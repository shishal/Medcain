// Meta Cloud API webhook for user-initiated WhatsApp sign-in.
//
// Secrets (supabase secrets set, never in the app):
//   WHATSAPP_VERIFY_TOKEN       any private string you type into the Meta callback setup
//   WHATSAPP_APP_SECRET         App Secret from the Meta app dashboard
//   WHATSAPP_BUSINESS_NUMBER    digits only, the number students message (wa.me)
//   WHATSAPP_ACCESS_TOKEN       optional; sends the free "you're confirmed" text reply
//   WHATSAPP_PHONE_NUMBER_ID    optional; used when the webhook omits metadata
//
// Callback URL (anon key is public, same one the app ships):
//   https://<ref>.supabase.co/functions/v1/whatsapp-webhook?apikey=<anon key>
// Subscribe to the messages field. verify_jwt is false: Meta does not send a
// Supabase JWT. The App Secret signature is the authentication.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  createServiceClient,
  resolveOrCreateWhatsAppUser,
} from '../_shared/whatsapp_account.ts';
import {
  blockedReply,
  confirmationReply,
  extractInboundMessages,
  isValidMetaSignature,
  parseLoginCode,
  samePhone,
  timingSafeEqual,
  type InboundWhatsAppMessage,
} from '../_shared/whatsapp_auth.ts';

const GRAPH_VERSION = 'v22.0';

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    return verifySubscription(url);
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const appSecret = Deno.env.get('WHATSAPP_APP_SECRET') ?? '';
  if (appSecret.length === 0) {
    console.error('WHATSAPP_APP_SECRET is not set');
    return json({ error: 'Webhook is not configured' }, 500);
  }

  const rawBody = await req.text();
  const valid = await isValidMetaSignature(
    rawBody,
    req.headers.get('X-Hub-Signature-256'),
    appSecret,
  );
  if (!valid) return json({ error: 'Invalid signature' }, 401);

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const service = createServiceClient();
  if (service == null) {
    return json({ error: 'Server is missing Supabase config.' }, 500);
  }

  const expectedNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID') ?? '';
  for (const message of extractInboundMessages(payload)) {
    if (
      expectedNumberId.length > 0 &&
      message.phoneNumberId != null &&
      message.phoneNumberId !== expectedNumberId
    ) {
      continue;
    }
    const outcome = await verifyMessage(service, message);
    if (outcome === 'retry') {
      return json({ error: 'Could not verify that message.' }, 500);
    }
  }

  return json({ ok: true });
});

function verifySubscription(url: URL): Response {
  const verifyToken = Deno.env.get('WHATSAPP_VERIFY_TOKEN') ?? '';
  if (verifyToken.length === 0) {
    console.error('WHATSAPP_VERIFY_TOKEN is not set');
    return new Response('Webhook is not configured', { status: 500 });
  }

  const mode = url.searchParams.get('hub.mode');
  const provided = url.searchParams.get('hub.verify_token');
  const challenge = url.searchParams.get('hub.challenge') ?? '';
  if (
    mode !== 'subscribe' ||
    !timingSafeEqual(provided ?? '', verifyToken) ||
    challenge.length === 0 ||
    challenge.length > 256
  ) {
    return new Response('Forbidden', { status: 403 });
  }

  return new Response(challenge, {
    status: 200,
    headers: { 'Content-Type': 'text/plain' },
  });
}

type VerifyOutcome = 'ok' | 'retry';

async function verifyMessage(
  service: SupabaseClient,
  message: InboundWhatsAppMessage,
): Promise<VerifyOutcome> {
  const code = parseLoginCode(message.body);
  if (code == null) return 'ok';

  const { data: seen, error: seenError } = await service
    .from('whatsapp_auth_challenges')
    .select('id')
    .eq('whatsapp_message_id', message.messageId)
    .maybeSingle();
  if (seenError) {
    console.error('message lookup', seenError.message);
    return 'retry';
  }
  if (seen != null) return 'ok';

  const { data: challenge, error: challengeError } = await service
    .from('whatsapp_auth_challenges')
    .select('id, phone')
    .eq('code', code)
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .maybeSingle();
  if (challengeError) {
    console.error('challenge lookup', challengeError.message);
    return 'retry';
  }
  if (challenge == null || !samePhone(challenge.phone, message.from)) {
    return 'ok';
  }

  const resolved = await resolveOrCreateWhatsAppUser(service, challenge.phone);
  if (!resolved.ok && !resolved.blocked) return 'retry';

  const phoneNumberId = message.phoneNumberId ??
    Deno.env.get('WHATSAPP_PHONE_NUMBER_ID') ??
    '';

  if (!resolved.ok) {
    const { error } = await service
      .from('whatsapp_auth_challenges')
      .update({
        status: 'blocked',
        whatsapp_message_id: message.messageId,
        verified_at: new Date().toISOString(),
      })
      .eq('id', challenge.id)
      .eq('status', 'pending');
    if (error) {
      console.error('mark blocked', error.message);
      return 'retry';
    }
    await sendReply(phoneNumberId, blockedReply(message.from));
    return 'ok';
  }

  const { data: updated, error: updateError } = await service
    .from('whatsapp_auth_challenges')
    .update({
      status: 'verified',
      user_id: resolved.userId,
      whatsapp_message_id: message.messageId,
      verified_at: new Date().toISOString(),
    })
    .eq('id', challenge.id)
    .eq('status', 'pending')
    .select('id')
    .maybeSingle();
  if (updateError) {
    console.error('mark verified', updateError.message);
    return 'retry';
  }
  if (updated == null) return 'ok';

  await sendReply(phoneNumberId, confirmationReply(message.from));
  return 'ok';
}

async function sendReply(
  phoneNumberId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const token = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? '';
  if (token.length === 0 || phoneNumberId.length === 0) return;

  const response = await fetch(
    `https://graph.facebook.com/${GRAPH_VERSION}/${phoneNumberId}/messages`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    },
  );
  if (!response.ok) {
    console.error('WhatsApp reply failed', response.status, await response.text());
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
