// Sends the one broadcast for an announcement that just became active.
// pg_net calls this with PUSH_WEBHOOK_SECRET. The Firebase service account
// stays in FCM_SERVICE_ACCOUNT_JSON. The app cannot send.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  bearerToken,
  buildTokenMessage,
  buildTopicMessage,
  decidePush,
  deliverTokenMessages,
  fcmAccessToken,
  isUnregisteredToken,
  postFcmMessage,
  readServiceAccount,
  secretsEqual,
  sendTopicMessage,
  TOKEN_SEND_CONCURRENCY,
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
    .select('id, title, body, deep_link, is_active, push_sent_at, audience, created_by')
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

  const actorId = createdByOf(data);

  try {
    if (row.audience === 'selected') {
      const tokens = await loadTokens(service, row.id);
      if (tokens.length === 0) {
        await recordPushAudit(service, actorId, row.id, {
          audience: 'selected',
          tokens: 0,
          sent: 0,
          removed: 0,
          failed: 0,
        });
        return jsonResponse({
          sent: true,
          tokens: 0,
          pushes: 0,
          removed: 0,
          failed: 0,
        });
      }

      const accessToken = await fcmAccessToken(account);
      const delivery = await deliverTokenMessages(
        tokens,
        async (token) => {
          const posted = await postFcmMessage(
            account,
            accessToken,
            buildTokenMessage(row, token),
          );
          return {
            ok: posted.ok,
            unregistered: !posted.ok && isUnregisteredToken(posted.status, posted.body),
          };
        },
        TOKEN_SEND_CONCURRENCY,
      );
      if (delivery.removed.length > 0) {
        try {
          await deleteTokens(service, delivery.removed);
        } catch {
          // Alerts already went out. Leave the claim set so they are not repeated.
        }
      }
      // Nobody was alerted and Firebase still might accept a retry.
      // Dead tokens are already gone, so a retry would not repeat them.
      if (delivery.sent === 0 && delivery.failed > 0) {
        await recordPushAudit(service, actorId, row.id, {
          audience: 'selected',
          tokens: tokens.length,
          sent: 0,
          removed: delivery.removed.length,
          failed: delivery.failed,
          retryable: true,
        });
        await clearClaim(service, row.id, claimedAt);
        return jsonResponse({ error: 'Push was not accepted.' }, 502);
      }
      await recordPushAudit(service, actorId, row.id, {
        audience: 'selected',
        tokens: tokens.length,
        sent: delivery.sent,
        removed: delivery.removed.length,
        failed: delivery.failed,
      });
      return jsonResponse({
        sent: true,
        tokens: tokens.length,
        pushes: delivery.sent,
        removed: delivery.removed.length,
        failed: delivery.failed,
      });
    }

    const accessToken = await fcmAccessToken(account);
    await sendTopicMessage(account, accessToken, buildTopicMessage(row));
  } catch {
    await clearClaim(service, row.id, claimedAt);
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
  if (record.audience !== 'all' && record.audience !== 'selected') return null;
  const deepLink = record.deep_link;
  const sentAt = record.push_sent_at;
  return {
    id: record.id,
    title: record.title,
    body: record.body,
    deep_link: typeof deepLink === 'string' ? deepLink : null,
    is_active: record.is_active,
    push_sent_at: typeof sentAt === 'string' ? sentAt : null,
    audience: record.audience,
  };
}

function createdByOf(data: unknown): string | null {
  if (data == null || typeof data !== 'object') return null;
  const createdBy = (data as { created_by?: unknown }).created_by;
  return typeof createdBy === 'string' && uuidPattern.test(createdBy) ? createdBy : null;
}

// Supabase's client generics are not generated in this function. The helpers
// only call rpc, from().delete/update/insert.
// deno-lint-ignore no-explicit-any
type ServiceClient = any;

async function loadTokens(
  service: ServiceClient,
  announcementId: string,
): Promise<string[]> {
  const { data, error } = await service.rpc('announcement_push_tokens', {
    p_announcement_id: announcementId,
  });
  if (error) throw new Error('Could not load notification tokens.');
  if (!Array.isArray(data)) return [];
  const tokens: string[] = [];
  for (const item of data) {
    if (item == null || typeof item !== 'object') continue;
    const token = (item as { token?: unknown }).token;
    if (typeof token === 'string' && token !== '') tokens.push(token);
  }
  return tokens;
}

async function deleteTokens(
  service: ServiceClient,
  tokens: string[],
): Promise<void> {
  for (let index = 0; index < tokens.length; index += 100) {
    const batch = tokens.slice(index, index + 100);
    const { error } = await service.from('push_tokens').delete().in('token', batch);
    if (error) throw new Error('Could not drop old notification tokens.');
  }
}

async function clearClaim(
  service: ServiceClient,
  announcementId: string,
  claimedAt: string,
): Promise<void> {
  await service
    .from('announcements')
    .update({ push_sent_at: null })
    .eq('id', announcementId)
    .eq('push_sent_at', claimedAt);
}

async function recordPushAudit(
  service: ServiceClient,
  actorId: string | null,
  announcementId: string,
  detail: Record<string, unknown>,
): Promise<void> {
  if (actorId == null) return;
  const { error } = await service.from('admin_audit_log').insert({
    actor_id: actorId,
    action: 'announcement_push',
    target_id: announcementId,
    detail,
  });
  // The inbox row and any alerts already happened. A missing audit row
  // must not clear the claim and send the alert again.
  if (error) console.warn('Could not record the push audit.');
}
