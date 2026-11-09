// User-initiated WhatsApp sign-in.
//
// The student sends the message, so it arrives inside a service conversation.
// Do not switch this to an authentication template: those are the paid OTPs
// this flow exists to avoid. Replies, when sent, are plain text in that
// same window (type "text", never type "template").
//
// Phone rules are mirrored in lib/features/auth/domain/whatsapp_phone.dart.

export const SYNTHETIC_EMAIL_DOMAIN = 'auth.medico.internal';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const LOGIN_CODE_RE =
  /^MEDCAIN\s+LOGIN\s+([ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8})$/;

export function syntheticEmail(phoneE164: string): string {
  const digits = phoneE164.replace(/\D/g, '');
  return `wa.${digits}@${SYNTHETIC_EMAIL_DOMAIN}`;
}

export function isSyntheticEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  return email.toLowerCase().endsWith(`@${SYNTHETIC_EMAIL_DOMAIN}`);
}

/// E.164, or null when [raw] is not a usable mobile number.
/// A 10-digit Indian mobile (starts 6–9) gets +91. Anything else must
/// already include a + country code.
export function normalizePhone(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > 32) return null;
  if (/[a-z]/i.test(trimmed)) return null;

  const digits = trimmed.replace(/\D/g, '');
  if (trimmed.startsWith('+')) return toE164(digits);
  if (/^[6-9]\d{9}$/.test(digits)) return toE164(`91${digits}`);
  if (/^0[6-9]\d{9}$/.test(digits)) return toE164(`91${digits.slice(1)}`);
  if (/^91[6-9]\d{9}$/.test(digits)) return toE164(digits);
  if (digits.startsWith('00') && digits.length > 4) {
    return toE164(digits.slice(2));
  }
  return null;
}

function toE164(digits: string): string | null {
  if (!/^[1-9]\d{7,14}$/.test(digits)) return null;
  if (digits.startsWith('91') && !/^91[6-9]\d{9}$/.test(digits)) return null;
  return `+${digits}`;
}

export function phoneDigits(phone: string): string {
  return phone.replace(/\D/g, '');
}

export function samePhone(e164: string, whatsappFrom: string): boolean {
  const left = phoneDigits(e164);
  const right = phoneDigits(whatsappFrom);
  return left.length >= 8 && left === right;
}

export function loginMessage(code: string): string {
  return `MEDCAIN login ${code}`;
}

export function parseLoginCode(body: string): string | null {
  const match = body.trim().toUpperCase().match(LOGIN_CODE_RE);
  return match ? match[1] : null;
}

export function buildWaUrl(
  businessNumber: string,
  message: string,
): string | null {
  const digits = businessNumber.replace(/\D/g, '');
  if (!/^[1-9]\d{7,14}$/.test(digits)) return null;
  return `https://wa.me/${digits}?text=${encodeURIComponent(message)}`;
}

export function generateCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return [...bytes].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join(
    '',
  );
}

export function generateSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

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

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/// Meta sends `X-Hub-Signature-256: sha256=<hex>` over the raw POST body.
export async function isValidMetaSignature(
  rawBody: string,
  header: string | null,
  appSecret: string,
): Promise<boolean> {
  if (header == null || appSecret.length === 0) return false;
  const trimmed = header.trim();
  const prefix = 'sha256=';
  if (!trimmed.toLowerCase().startsWith(prefix)) return false;
  const provided = trimmed.slice(prefix.length).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(provided)) return false;
  const expected = await hmacSha256Hex(appSecret, rawBody);
  return timingSafeEqual(expected, provided);
}

export type InboundWhatsAppMessage = {
  from: string;
  body: string;
  messageId: string;
  phoneNumberId: string | null;
};

export function extractInboundMessages(
  payload: unknown,
): InboundWhatsAppMessage[] {
  const root = asRecord(payload);
  if (root == null || root.object !== 'whatsapp_business_account') return [];
  const entries = asArray(root.entry);
  const out: InboundWhatsAppMessage[] = [];
  for (const entry of entries) {
    const changes = asArray(asRecord(entry)?.changes);
    for (const change of changes) {
      const value = asRecord(asRecord(change)?.value);
      if (value == null) continue;
      const phoneNumberId = asString(
        asRecord(value.metadata)?.phone_number_id,
      );
      for (const message of asArray(value.messages)) {
        const row = asRecord(message);
        if (row == null || row.type !== 'text') continue;
        const from = asString(row.from);
        const messageId = asString(row.id);
        const body = asString(asRecord(row.text)?.body);
        if (from == null || messageId == null || body == null) continue;
        if (!/^\d{8,15}$/.test(from)) continue;
        out.push({ from, body, messageId, phoneNumberId });
      }
    }
  }
  return out;
}

/// Session-window reply. `type` stays `text` so this is not a paid template.
export function confirmationReply(toDigits: string): Record<string, unknown> {
  return {
    messaging_product: 'whatsapp',
    to: toDigits,
    type: 'text',
    text: {
      body:
        'MEDCAIN confirmed this number. Return to the app to finish signing in.',
    },
  };
}

export function blockedReply(toDigits: string): Record<string, unknown> {
  return {
    messaging_product: 'whatsapp',
    to: toDigits,
    type: 'text',
    text: {
      body:
        'This MEDCAIN account is blocked. Email medcain@shishal.com if that is a mistake.',
    },
  };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}
