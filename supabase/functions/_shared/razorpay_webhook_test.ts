import {
  hmacSha256Hex,
  isValidRazorpaySignature,
  parseWebhookEvent,
} from './razorpay_webhook.ts';

const SECRET = 'test_webhook_secret';

const capturedBody = JSON.stringify({
  entity: 'event',
  event: 'payment.captured',
  payload: {
    payment: {
      entity: {
        id: 'pay_test123',
        entity: 'payment',
        amount: 149900,
        currency: 'INR',
        status: 'captured',
        order_id: 'order_test123',
        notes: {
          user_id: '11111111-1111-1111-1111-111111111111',
          plan_id: '22222222-2222-2222-2222-222222222222',
          email: 'a@b.c',
        },
      },
    },
  },
});

Deno.test('accepts a matching HMAC-SHA256 signature', async () => {
  const signature = await hmacSha256Hex(SECRET, capturedBody);
  const ok = await isValidRazorpaySignature(capturedBody, signature, SECRET);
  if (!ok) throw new Error('expected valid signature');
});

Deno.test('accepts the same signature in uppercase', async () => {
  const signature = (await hmacSha256Hex(SECRET, capturedBody)).toUpperCase();
  const ok = await isValidRazorpaySignature(capturedBody, signature, SECRET);
  if (!ok) throw new Error('expected uppercase signature to match');
});

Deno.test('rejects a missing signature', async () => {
  const ok = await isValidRazorpaySignature(capturedBody, null, SECRET);
  if (ok) throw new Error('missing signature must fail');
});

Deno.test('rejects a wrong signature', async () => {
  const ok = await isValidRazorpaySignature(
    capturedBody,
    '0'.repeat(64),
    SECRET,
  );
  if (ok) throw new Error('wrong signature must fail');
});

Deno.test('rejects a signature for a different body', async () => {
  const signature = await hmacSha256Hex(SECRET, capturedBody);
  const ok = await isValidRazorpaySignature(
    capturedBody + ' ',
    signature,
    SECRET,
  );
  if (ok) throw new Error('tampered body must fail');
});

Deno.test('parses payment.captured and forwards the amount', () => {
  const parsed = parseWebhookEvent(JSON.parse(capturedBody));
  if (parsed.kind !== 'captured') {
    throw new Error(`expected captured, got ${JSON.stringify(parsed)}`);
  }
  if (
    parsed.payment.planId !== '22222222-2222-2222-2222-222222222222' ||
    parsed.payment.amountPaise !== 149900
  ) {
    throw new Error('plan payment fields did not match');
  }
  if (parsed.payment.discountCode !== null) {
    throw new Error('list-price payment must not carry a discount code');
  }
});

Deno.test('forwards an amount with no code for the database to check', () => {
  const body = JSON.parse(capturedBody);
  body.payload.payment.entity.amount = 119920;
  const parsed = parseWebhookEvent(body);
  if (parsed.kind !== 'captured' || parsed.payment.discountCode !== null) {
    throw new Error('a missing code is forwarded; Postgres rejects a mismatched amount');
  }
  if (parsed.payment.amountPaise !== 119920) {
    throw new Error('amount must be forwarded to apply_razorpay_payment');
  }
});

Deno.test('accepts a discounted amount when notes include a code', () => {
  const body = JSON.parse(capturedBody);
  body.payload.payment.entity.amount = 119920;
  body.payload.payment.entity.notes.discount_code = 'campus-20';
  const parsed = parseWebhookEvent(body);
  if (parsed.kind !== 'captured') {
    throw new Error(`expected captured, got ${JSON.stringify(parsed)}`);
  }
  if (parsed.payment.discountCode !== 'CAMPUS20' || parsed.payment.amountPaise !== 119920) {
    throw new Error('normalized code or amount did not match');
  }
});

Deno.test('ignores order.paid so the same payment is not applied twice', () => {
  const parsed = parseWebhookEvent({ event: 'order.paid' });
  if (parsed.kind !== 'ignored' || parsed.event !== 'order.paid') {
    throw new Error(`expected ignored order.paid, got ${JSON.stringify(parsed)}`);
  }
});

Deno.test('forwards any positive amount for a plan id', () => {
  // The plan row is the price check. This parser must not reject a paise
  // value just because it differs from a seed price.
  const body = JSON.parse(capturedBody);
  body.payload.payment.entity.amount = 1;
  const parsed = parseWebhookEvent(body);
  if (parsed.kind !== 'captured' || parsed.payment.planId !==
    '22222222-2222-2222-2222-222222222222') {
    throw new Error(`expected captured plan, got ${JSON.stringify(parsed)}`);
  }
  if (parsed.payment.amountPaise !== 1) {
    throw new Error('amount must be forwarded to apply_razorpay_payment');
  }
});

Deno.test('rejects a non-uuid user_id', () => {
  const body = JSON.parse(capturedBody);
  body.payload.payment.entity.notes.user_id = 'not-a-uuid';
  const parsed = parseWebhookEvent(body);
  if (parsed.kind !== 'invalid') {
    throw new Error('non-uuid user_id must be invalid');
  }
});

Deno.test('rejects a missing plan id', () => {
  const body = JSON.parse(capturedBody);
  delete body.payload.payment.entity.notes.plan_id;
  const parsed = parseWebhookEvent(body);
  if (parsed.kind !== 'invalid') {
    throw new Error('missing plan_id must be invalid');
  }
});
