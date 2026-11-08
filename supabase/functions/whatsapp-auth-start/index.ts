// Starts a user-initiated WhatsApp sign-in. Returns a wa.me link.
// The student sends the message; we do not send an OTP template.
// verify_jwt is false because the caller is not signed in yet.
// The unguessable secret in the response is what may later collect the session.

import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import { createServiceClient } from '../_shared/whatsapp_account.ts';
import {
  buildWaUrl,
  generateCode,
  generateSecret,
  loginMessage,
  normalizePhone,
  sha256Hex,
} from '../_shared/whatsapp_auth.ts';

const TTL_MS = 10 * 60 * 1000;
const MAX_STARTS_PER_HOUR = 5;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let phoneRaw = '';
  try {
    const body = await req.json();
    phoneRaw = typeof body?.phone === 'string' ? body.phone : '';
  } catch {
    return jsonResponse({ error: 'Send JSON with a phone field.' }, 400);
  }

  const phone = normalizePhone(phoneRaw);
  if (phone == null) {
    return jsonResponse({
      error:
        'Enter a 10-digit Indian mobile number, or a full international number starting with +.',
    }, 400);
  }

  const business = Deno.env.get('WHATSAPP_BUSINESS_NUMBER') ?? '';
  if (buildWaUrl(business, 'MEDCAIN login ABCDEFGH') == null) {
    console.error('WHATSAPP_BUSINESS_NUMBER is missing or invalid');
    return jsonResponse({ error: 'WhatsApp sign-in is not set up yet.' }, 500);
  }

  const service = createServiceClient();
  if (service == null) {
    return jsonResponse({ error: 'Server is missing Supabase config.' }, 500);
  }

  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count, error: countError } = await service
    .from('whatsapp_auth_challenges')
    .select('id', { count: 'exact', head: true })
    .eq('phone', phone)
    .gte('created_at', hourAgo);
  if (countError) {
    console.error('rate limit', countError.message);
    return jsonResponse({
      error: 'Could not start WhatsApp sign-in. Please try again.',
    }, 500);
  }
  if ((count ?? 0) >= MAX_STARTS_PER_HOUR) {
    return jsonResponse({
      error: 'Too many attempts. Wait a few minutes and try again.',
    }, 429);
  }

  const { error: deleteError } = await service
    .from('whatsapp_auth_challenges')
    .delete()
    .lt('expires_at', new Date().toISOString());
  if (deleteError) console.error('delete expired', deleteError.message);

  const secret = generateSecret();
  const secretHash = await sha256Hex(secret);
  const expiresAt = new Date(Date.now() + TTL_MS).toISOString();

  let code = '';
  let inserted = false;
  for (let attempt = 0; attempt < 3 && !inserted; attempt++) {
    code = generateCode();
    const { error } = await service.from('whatsapp_auth_challenges').insert({
      phone,
      code,
      secret_hash: secretHash,
      expires_at: expiresAt,
    });
    if (!error) {
      inserted = true;
      break;
    }
    if (error.code !== '23505') {
      console.error('insert challenge', error.message);
      return jsonResponse({
        error: 'Could not start WhatsApp sign-in. Please try again.',
      }, 500);
    }
  }
  if (!inserted) {
    return jsonResponse({
      error: 'Could not start WhatsApp sign-in. Please try again.',
    }, 500);
  }

  const message = loginMessage(code);
  const waUrl = buildWaUrl(business, message);
  if (waUrl == null) {
    return jsonResponse({ error: 'WhatsApp sign-in is not set up yet.' }, 500);
  }

  const { data: row, error: idError } = await service
    .from('whatsapp_auth_challenges')
    .select('id')
    .eq('code', code)
    .eq('status', 'pending')
    .maybeSingle();
  if (idError || row == null) {
    console.error('read challenge', idError?.message);
    return jsonResponse({
      error: 'Could not start WhatsApp sign-in. Please try again.',
    }, 500);
  }

  return jsonResponse({
    challenge_id: row.id,
    secret,
    wa_url: waUrl,
    message,
    phone,
    expires_at: expiresAt,
  });
});
