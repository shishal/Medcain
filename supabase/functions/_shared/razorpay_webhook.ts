/// Parse + authenticate a Razorpay webhook body.
///
/// Signature check uses the *raw* POST body (not re-serialized JSON). Razorpay
/// signs with HMAC-SHA256; the hex digest is `X-Razorpay-Signature`.

import { getPaidPlan, type PaidPlanId } from './paid_plans.ts';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type CapturedPayment = {
  paymentId: string;
  orderId: string;
  userId: string;
  plan: PaidPlanId;
  amountPaise: number;
  currency: string;
  /** Null when the student paid the list price. */
  discountCode: string | null;
};

export type ParseResult =
  | { kind: 'ignored'; event: string }
  | { kind: 'invalid'; reason: string }
  | { kind: 'captured'; payment: CapturedPayment };

export async function hmacSha256Hex(
  secret: string,
  body: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
  return [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Constant-time compare for equal-length hex strings. */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

export async function isValidRazorpaySignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
): Promise<boolean> {
  if (signatureHeader == null || signatureHeader.length === 0) {
    return false;
  }
  const expected = await hmacSha256Hex(secret, rawBody);
  return timingSafeEqual(expected, signatureHeader.trim().toLowerCase());
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function asAmount(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    return Number(value);
  }
  return null;
}

export function parseWebhookEvent(body: unknown): ParseResult {
  const root = asRecord(body);
  if (root == null) {
    return { kind: 'invalid', reason: 'body is not an object' };
  }

  const event = asString(root.event);
  if (event == null) {
    return { kind: 'invalid', reason: 'missing event' };
  }

  // Only payment.captured grants a plan. order.paid is signed+acked so
  // Razorpay does not retry, but applying both would double-count without
  // the payments unique key (and we still only want one code path).
  if (event !== 'payment.captured') {
    return { kind: 'ignored', event };
  }

  const payload = asRecord(root.payload);
  const paymentWrap = payload == null ? null : asRecord(payload.payment);
  const entity = paymentWrap == null ? null : asRecord(paymentWrap.entity);
  if (entity == null) {
    return { kind: 'invalid', reason: 'missing payment entity' };
  }

  const status = asString(entity.status);
  if (status !== 'captured') {
    return { kind: 'invalid', reason: 'payment is not captured' };
  }

  const paymentId = asString(entity.id);
  const orderId = asString(entity.order_id);
  if (paymentId == null || orderId == null) {
    return { kind: 'invalid', reason: 'missing payment or order id' };
  }

  const notes = asRecord(entity.notes) ?? {};
  const userId = asString(notes.user_id);
  const planName = asString(notes.plan)?.trim().toLowerCase() ?? '';
  if (userId == null || !UUID_RE.test(userId)) {
    return { kind: 'invalid', reason: 'notes.user_id is not a uuid' };
  }

  const catalog = getPaidPlan(planName);
  if (catalog == null) {
    return { kind: 'invalid', reason: 'notes.plan is not a paid plan' };
  }

  const amountPaise = asAmount(entity.amount);
  const currency = asString(entity.currency);
  if (amountPaise == null || currency == null) {
    return { kind: 'invalid', reason: 'missing amount or currency' };
  }
  if (currency !== catalog.currency) {
    return { kind: 'invalid', reason: 'amount does not match catalog' };
  }

  // The exact paise (list price, or list price minus a code's percent) is
  // checked in apply_razorpay_payment(), which reads paid_plan_catalog.
  // This layer only rejects a code that could not have come from our notes.
  // Comparing the amount here would ignore a price changed in the database.
  const rawCode = asString(notes.discount_code);
  let discountCode: string | null = null;
  if (rawCode != null) {
    discountCode = rawCode.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (!/^[A-Z0-9]{4,16}$/.test(discountCode)) {
      return { kind: 'invalid', reason: 'notes.discount_code is not a code' };
    }
  }

  return {
    kind: 'captured',
    payment: {
      paymentId,
      orderId,
      userId,
      plan: planName as PaidPlanId,
      amountPaise,
      currency,
      discountCode,
    },
  };
}
