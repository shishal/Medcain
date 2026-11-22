import {
  BROADCAST_TOPIC,
  NOTIFICATION_CHANNEL_ID,
  bearerToken,
  buildTokenMessage,
  buildTopicMessage,
  decidePush,
  deliverTokenMessages,
  isUnregisteredToken,
  readServiceAccount,
  secretsEqual,
  type PushRow,
} from './announcement_push.ts';

const row: PushRow = {
  id: '11111111-1111-4111-8111-111111111111',
  title: 'New paper',
  body: 'Medicine 2024 is in.',
  deep_link: '/upgrade',
  is_active: true,
  push_sent_at: null,
  audience: 'all',
};

Deno.test('accepts the webhook bearer and rejects a different secret', () => {
  if (!secretsEqual('same-secret', 'same-secret')) {
    throw new Error('expected equal secrets to match');
  }
  if (secretsEqual('same-secret', 'other-secret')) {
    throw new Error('expected a different secret to fail');
  }
  if (secretsEqual('short', 'much-longer-secret')) {
    throw new Error('expected a different length to fail');
  }
  if (bearerToken('Bearer topic-secret') !== 'topic-secret') {
    throw new Error('expected the bearer token');
  }
  if (bearerToken(null) !== null) {
    throw new Error('expected a missing header to be empty');
  }
});

Deno.test('sends only the first publish of a non-empty active row', () => {
  const send = decidePush(row);
  if (send.action !== 'send') throw new Error('expected a send');

  const inactive = decidePush({ ...row, is_active: false });
  if (inactive.action !== 'skip' || inactive.reason !== 'inactive') {
    throw new Error('expected an inactive row to skip');
  }

  const sent = decidePush({ ...row, push_sent_at: '2026-11-22T00:00:00Z' });
  if (sent.action !== 'skip' || sent.reason !== 'already_sent') {
    throw new Error('expected an already sent row to skip');
  }

  const empty = decidePush({ ...row, title: '   ' });
  if (empty.action !== 'skip' || empty.reason !== 'empty') {
    throw new Error('expected an empty title to skip');
  }

  if (decidePush(null).action !== 'skip') {
    throw new Error('expected a missing row to skip');
  }
});

Deno.test('topic message uses the inbox text and the broadcast topic', () => {
  const message = buildTopicMessage(row).message;
  if (message.topic !== BROADCAST_TOPIC) {
    throw new Error('expected the broadcast topic');
  }
  const notification = message.notification as { title: string; body: string };
  if (notification.title !== row.title || notification.body !== row.body) {
    throw new Error('expected the inbox title and body');
  }
  const data = message.data as Record<string, string>;
  if (data.deep_link !== '/upgrade' || data.announcement_id !== row.id) {
    throw new Error('expected the deep link and announcement id');
  }
  const android = message.android as {
    notification: { channel_id: string };
  };
  if (android.notification.channel_id !== NOTIFICATION_CHANNEL_ID) {
    throw new Error('expected the announcements channel');
  }

  const withoutLink = buildTopicMessage({ ...row, deep_link: '  ' }).message;
  const linkData = withoutLink.data as Record<string, string>;
  if ('deep_link' in linkData) {
    throw new Error('expected a blank deep link to be omitted');
  }
});

Deno.test('token message addresses one phone and keeps the inbox text', () => {
  const message = buildTokenMessage(row, 'device-token').message;
  if ('topic' in message) throw new Error('expected no topic');
  if (message.token !== 'device-token') {
    throw new Error('expected the device token');
  }
  const notification = message.notification as { title: string; body: string };
  if (notification.title !== row.title || notification.body !== row.body) {
    throw new Error('expected the inbox title and body');
  }
  const data = message.data as Record<string, string>;
  if (data.announcement_id !== row.id || data.deep_link !== '/upgrade') {
    throw new Error('expected the announcement id and deep link');
  }
});

Deno.test('unregistered tokens are the ones Firebase dropped', () => {
  const unregistered = {
    error: { details: [{ errorCode: 'UNREGISTERED' }] },
  };
  if (!isUnregisteredToken(404, unregistered)) {
    throw new Error('expected an UNREGISTERED code to be dropped');
  }
  if (!isUnregisteredToken(404, {})) {
    throw new Error('expected a bare 404 to be dropped');
  }
  const invalid = {
    error: { details: [{ errorCode: 'INVALID_ARGUMENT' }] },
  };
  if (isUnregisteredToken(400, invalid)) {
    throw new Error('expected a bad payload to stay');
  }
  if (isUnregisteredToken(500, {})) {
    throw new Error('expected a server error to stay');
  }
});

Deno.test('delivers each token once and splits success from dead tokens', async () => {
  const seen: string[] = [];
  const delivery = await deliverTokenMessages(
    ['a', 'b', 'c', 'a', ' '],
    async (token) => {
      seen.push(token);
      if (token === 'b') return { ok: false, unregistered: true };
      if (token === 'c') throw new Error('network');
      return { ok: true, unregistered: false };
    },
    2,
  );
  if (seen.length !== 3 || seen.slice().sort().join(',') !== 'a,b,c') {
    throw new Error('expected each non-blank token once');
  }
  if (delivery.sent !== 1 || delivery.failed !== 1) {
    throw new Error('expected one success and one failure');
  }
  if (delivery.removed.length !== 1 || delivery.removed[0] !== 'b') {
    throw new Error('expected the dead token to be removed');
  }
});

Deno.test('reads a service account and rejects a file without a key', () => {
  const account = readServiceAccount(JSON.stringify({
    project_id: 'medico-push',
    client_email: 'push@medico-push.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n',
  }));
  if (account.projectId !== 'medico-push') {
    throw new Error('expected the project id');
  }

  let rejected = false;
  try {
    readServiceAccount('{"project_id":"x"}');
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('expected a keyless account to fail');
});
