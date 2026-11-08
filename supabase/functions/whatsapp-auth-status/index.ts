// Polled by the device that started sign-in. The challenge secret is the
// only credential. A matching verified row is exchanged for a Supabase
// session exactly once.
// verify_jwt is false because the caller is not signed in yet.

import { corsHeaders, jsonResponse } from '../_shared/cors.ts';
import {
  createServiceClient,
  mintWhatsAppSession,
  sessionStillValid,
} from '../_shared/whatsapp_account.ts';
import { sha256Hex, timingSafeEqual } from '../_shared/whatsapp_auth.ts';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EXPIRED = 'That sign-in request expired. Try again.';
const USED = 'That sign-in was already used. Try again.';
const FAILED = 'Could not finish sign-in. Please try again.';
const BLOCKED = 'This account is blocked.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let challengeId = '';
  let secret = '';
  try {
    const body = await req.json();
    challengeId = typeof body?.challenge_id === 'string'
      ? body.challenge_id.trim()
      : '';
    secret = typeof body?.secret === 'string' ? body.secret.trim() : '';
  } catch {
    return jsonResponse({ error: EXPIRED }, 400);
  }

  if (!UUID_RE.test(challengeId) || !/^[0-9a-f]{64}$/.test(secret)) {
    return jsonResponse({ error: EXPIRED }, 400);
  }

  const service = createServiceClient();
  if (service == null) {
    return jsonResponse({ error: 'Server is missing Supabase config.' }, 500);
  }

  const { data: row, error } = await service
    .from('whatsapp_auth_challenges')
    .select('id, status, expires_at, secret_hash, user_id')
    .eq('id', challengeId)
    .maybeSingle();
  if (error) {
    console.error('read challenge', error.message);
    return jsonResponse({ error: FAILED }, 500);
  }
  if (row == null) return jsonResponse({ error: EXPIRED }, 400);

  const secretHash = await sha256Hex(secret);
  const stored = typeof row.secret_hash === 'string' ? row.secret_hash : '';
  if (!timingSafeEqual(secretHash, stored)) {
    return jsonResponse({ error: EXPIRED }, 400);
  }

  const expiresAt = typeof row.expires_at === 'string' ? row.expires_at : '';
  const fresh = sessionStillValid(expiresAt);

  if (row.status === 'pending') {
    return fresh
      ? jsonResponse({ status: 'pending' })
      : jsonResponse({ error: EXPIRED }, 400);
  }
  if (row.status === 'blocked') {
    return jsonResponse({ error: BLOCKED }, 403);
  }
  if (row.status === 'consumed') {
    return jsonResponse({ error: USED }, 400);
  }
  if (row.status !== 'verified' || !fresh) {
    return jsonResponse({ error: EXPIRED }, 400);
  }

  const userId = typeof row.user_id === 'string' ? row.user_id : '';
  if (!UUID_RE.test(userId)) {
    return jsonResponse({ error: FAILED }, 500);
  }

  const { data: profile, error: profileError } = await service
    .from('profiles')
    .select('blocked_at')
    .eq('id', userId)
    .maybeSingle();
  if (profileError) {
    console.error('profile', profileError.message);
    return jsonResponse({ error: FAILED }, 500);
  }
  if (profile?.blocked_at != null) {
    await service
      .from('whatsapp_auth_challenges')
      .update({ status: 'blocked' })
      .eq('id', challengeId)
      .eq('status', 'verified');
    return jsonResponse({ error: BLOCKED }, 403);
  }

  const consumedAt = new Date().toISOString();
  const { data: consumed, error: consumeError } = await service
    .from('whatsapp_auth_challenges')
    .update({ status: 'consumed', consumed_at: consumedAt })
    .eq('id', challengeId)
    .eq('status', 'verified')
    .eq('secret_hash', secretHash)
    .select('user_id')
    .maybeSingle();
  if (consumeError) {
    console.error('consume', consumeError.message);
    return jsonResponse({ error: FAILED }, 500);
  }
  if (consumed == null) return jsonResponse({ error: USED }, 400);

  const session = await mintWhatsAppSession(service, userId);
  if (session === 'banned') {
    await service
      .from('whatsapp_auth_challenges')
      .update({ status: 'blocked' })
      .eq('id', challengeId)
      .eq('status', 'consumed');
    return jsonResponse({ error: BLOCKED }, 403);
  }
  if (session == null) {
    await service
      .from('whatsapp_auth_challenges')
      .update({ status: 'verified', consumed_at: null })
      .eq('id', challengeId)
      .eq('status', 'consumed');
    return jsonResponse({ error: FAILED }, 500);
  }

  return jsonResponse({
    status: 'ready',
    access_token: session.accessToken,
    refresh_token: session.refreshToken,
    expires_in: session.expiresIn,
  });
});
