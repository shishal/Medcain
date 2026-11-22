// Sends the one broadcast for an announcement that just became active.
// pg_net calls this with PUSH_WEBHOOK_SECRET. The Firebase service account
// stays in FCM_SERVICE_ACCOUNT_JSON. The app cannot send.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  bearerToken,
  buildTopicMessage,
  decidePush,
  fcmAccessToken,
  readServiceAccount,
  secretsEqual,
  sendTopicMessage,
  type PushRow,
} from '../_shared/announcement_push.ts';
import { jsonResponse } from '../_shared/cors.ts';

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const expected = Deno.env.get('PUSH_WEBHOOK_SECRET') ?? '';
  const presented = bearerToken(req.headers.get('Authorization'));
  if (
    expected === '' ||
    presented == null ||
    !secretsEqual(presented, expected)
  ) {
    return jsonResponse({ error: 'Not allowed.' }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Send JSON.' }, 400);
  }
  const announcementId = body && typeof body === 'object'
    ? (body as { announcement_id?: unknown }).announcement_id
    : null;
  if (typeof announcementId !== 'string' || !uuidPattern.test(announcementId)) {
    return jsonResponse({ error: 'Announcement not found.' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const serviceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!supabaseUrl || !serviceKey || !serviceAccountRaw) {
    return jsonResponse({ error: 'Push is not configured.' }, 500);
  }

  let account;
  try {
    account = readServiceAccount(serviceAccountRaw);
  } catch {
    return jsonResponse({ error: 'Push is not configured.' }, 500);
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await service
    .from('announcements')
    .select('id, title, body, deep_link, is_active, push_sent_at')
    .eq('id', announcementId)
    .maybeSingle();

  if (error) {
    return jsonResponse({ error: 'Could not load that announcement.' }, 500);
  }

  const row = asPushRow(data);
  const decision = decidePush(row);
  if (decision.action === 'skip') {
    return jsonResponse({ skipped: true, reason: decision.reason });
  }
  if (row == null) {
    return jsonResponse({ skipped: true, reason: 'not_found' });
  }

  // Claim before the network call so a second delivery does not send twice.
  // Cleared again if FCM rejects the message, which leaves a retry possible.
  const { data: claimed, error: claimError } = await service
    .from('announcements')
    .update({ push_sent_at: new Date().toISOString() })
    .eq('id', row.id)
    .is('push_sent_at', null)
    .eq('is_active', true)
    .select('push_sent_at')
    .maybeSingle();

  if (claimError) {
    return jsonResponse({ error: 'Could not record the alert.' }, 500);
  }
  const claimedAt = claimed && typeof claimed === 'object'
    ? (claimed as { push_sent_at?: unknown }).push_sent_at
    : null;
  if (typeof claimedAt !== 'string') {
    return jsonResponse({ skipped: true, reason: 'already_sent' });
  }

  try {
    const accessToken = await fcmAccessToken(account);
    await sendTopicMessage(account, accessToken, buildTopicMessage(row));
  } catch {
    await service
      .from('announcements')
      .update({ push_sent_at: null })
      .eq('id', row.id)
      .eq('push_sent_at', claimedAt);
    return jsonResponse({ error: 'Push was not accepted.' }, 502);
  }

  return jsonResponse({ sent: true });
});

function asPushRow(data: unknown): PushRow | null {
  if (data == null || typeof data !== 'object') return null;
  const record = data as Record<string, unknown>;
  if (
    typeof record.id !== 'string' ||
    typeof record.title !== 'string' ||
    typeof record.body !== 'string' ||
    typeof record.is_active !== 'boolean'
  ) {
    return null;
  }
  const deepLink = record.deep_link;
  const sentAt = record.push_sent_at;
  return {
    id: record.id,
    title: record.title,
    body: record.body,
    deep_link: typeof deepLink === 'string' ? deepLink : null,
    is_active: record.is_active,
    push_sent_at: typeof sentAt === 'string' ? sentAt : null,
  };
}
