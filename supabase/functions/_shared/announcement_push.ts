// One FCM topic message for a newly published announcement.
// BROADCAST_TOPIC must match announcementBroadcastTopic in the Flutter app.

export const BROADCAST_TOPIC = 'broadcast';
export const NOTIFICATION_CHANNEL_ID = 'announcements';

const TITLE_LIMIT = 200;
const BODY_LIMIT = 3500;

export type PushRow = {
  id: string;
  title: string;
  body: string;
  deep_link: string | null;
  is_active: boolean;
  push_sent_at: string | null;
};

export type PushDecision =
  | { action: 'skip'; reason: 'not_found' | 'inactive' | 'already_sent' | 'empty' }
  | { action: 'send' };

export function secretsEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < leftBytes.length; i++) {
    diff |= leftBytes[i] ^ rightBytes[i];
  }
  return diff === 0;
}

export function bearerToken(authorization: string | null): string | null {
  if (!authorization) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(authorization);
  return match?.[1] ?? null;
}

export function decidePush(row: PushRow | null): PushDecision {
  if (row == null) return { action: 'skip', reason: 'not_found' };
  if (!row.is_active) return { action: 'skip', reason: 'inactive' };
  if (row.push_sent_at) return { action: 'skip', reason: 'already_sent' };
  if (row.title.trim() === '' || row.body.trim() === '') {
    return { action: 'skip', reason: 'empty' };
  }
  return { action: 'send' };
}

/// Notification payload. Title and body match the inbox row unless they
/// would exceed FCM's message size, in which case the tray text is clipped.
/// The inbox still has the full text.
export function buildTopicMessage(row: PushRow): { message: Record<string, unknown> } {
  const data: Record<string, string> = {
    announcement_id: row.id,
  };
  const deepLink = row.deep_link?.trim();
  if (deepLink) data.deep_link = deepLink;

  return {
    message: {
      topic: BROADCAST_TOPIC,
      notification: {
        title: clip(row.title.trim(), TITLE_LIMIT),
        body: clip(row.body.trim(), BODY_LIMIT),
      },
      data,
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: NOTIFICATION_CHANNEL_ID,
        },
      },
    },
  };
}

export type ServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

export function readServiceAccount(raw: string): ServiceAccount {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('FCM service account is not JSON.');
  }
  if (parsed == null || typeof parsed !== 'object') {
    throw new Error('FCM service account is not JSON.');
  }
  const record = parsed as Record<string, unknown>;
  const projectId = record.project_id;
  const clientEmail = record.client_email;
  const privateKey = record.private_key;
  if (typeof projectId !== 'string' || projectId === '') {
    throw new Error('FCM service account is missing project_id.');
  }
  if (typeof clientEmail !== 'string' || clientEmail === '') {
    throw new Error('FCM service account is missing client_email.');
  }
  if (typeof privateKey !== 'string' || !privateKey.includes('PRIVATE KEY')) {
    throw new Error('FCM service account is missing private_key.');
  }
  return { projectId, clientEmail, privateKey };
}

export async function fcmAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: 'RS256', typ: 'JWT' });
  const payload = base64UrlJson({
    iss: account.clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  });
  const unsigned = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(account.privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const body = await response.json().catch(() => null);
  const token = body && typeof body === 'object'
    ? (body as { access_token?: unknown }).access_token
    : null;
  if (!response.ok || typeof token !== 'string' || token === '') {
    throw new Error('Could not authorize with FCM.');
  }
  return token;
}

export async function sendTopicMessage(
  account: ServiceAccount,
  accessToken: string,
  message: { message: Record<string, unknown> },
): Promise<void> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    },
  );
  if (!response.ok) {
    throw new Error('FCM did not accept the announcement.');
  }
}

function clip(value: string, limit: number): string {
  if (value.length <= limit) return value;
  return `${value.slice(0, limit - 1)}…`;
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
