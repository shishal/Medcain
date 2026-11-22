import {
  BROADCAST_TOPIC,
  NOTIFICATION_CHANNEL_ID,
  bearerToken,
  buildTopicMessage,
  decidePush,
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
