import {
  confirmationReply,
  extractInboundMessages,
  generateCode,
  hmacSha256Hex,
  isSyntheticEmail,
  isValidMetaSignature,
  loginMessage,
  normalizePhone,
  parseLoginCode,
  samePhone,
  syntheticEmail,
} from './whatsapp_auth.ts';

Deno.test('normalizes Indian mobiles and explicit country codes', () => {
  if (normalizePhone('9876543210') !== '+919876543210') {
    throw new Error('10 digit');
  }
  if (normalizePhone(' 098765 43210 ') !== '+919876543210') {
    throw new Error('trunk prefix');
  }
  if (normalizePhone('+91 98765 43210') !== '+919876543210') {
    throw new Error('spaced +91');
  }
  if (normalizePhone('919876543210') !== '+919876543210') {
    throw new Error('91 prefix');
  }
  if (normalizePhone('+1 (415) 555-2671') !== '+14155552671') {
    throw new Error('international');
  }
  if (normalizePhone('00919876543210') !== '+919876543210') {
    throw new Error('00 prefix');
  }
  if (normalizePhone('5876543210') !== null) throw new Error('bad indian');
  if (normalizePhone('+915876543210') !== null) throw new Error('bad +91');
  if (normalizePhone('123') !== null) throw new Error('too short');
  if (normalizePhone('call me') !== null) throw new Error('letters');
});

Deno.test('login code is the whole message', () => {
  const code = 'AB2CD3EF';
  if (parseLoginCode(loginMessage(code)) !== code) {
    throw new Error('exact message');
  }
  if (parseLoginCode(`  medcain   login   ${code.toLowerCase()}  `) !== code) {
    throw new Error('case and space');
  }
  if (parseLoginCode(`${loginMessage(code)} thanks`) !== null) {
    throw new Error('extra words must not match');
  }
  if (parseLoginCode('MEDCAIN login AB2CD3E0') !== null) {
    throw new Error('ambiguous digit');
  }
});

Deno.test('generated codes use the unambiguous alphabet', () => {
  const code = generateCode();
  if (!/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/.test(code)) {
    throw new Error(code);
  }
});

Deno.test('synthetic mailbox is not a real domain students see', () => {
  const email = syntheticEmail('+919876543210');
  if (email !== 'wa.919876543210@auth.medico.internal') {
    throw new Error(email);
  }
  if (!isSyntheticEmail(email)) throw new Error('expected synthetic');
  if (isSyntheticEmail('student@college.edu')) {
    throw new Error('real email');
  }
});

Deno.test('accepts Meta sha256 signature over the raw body', async () => {
  const body = '{"object":"whatsapp_business_account"}';
  const secret = 'app-secret';
  const signature = await hmacSha256Hex(secret, body);
  const ok = await isValidMetaSignature(body, `sha256=${signature}`, secret);
  if (!ok) throw new Error('expected valid');
  const upper = await isValidMetaSignature(
    body,
    `sha256=${signature.toUpperCase()}`,
    secret,
  );
  if (!upper) throw new Error('expected uppercase hex');
  const bad = await isValidMetaSignature(body, `sha256=${signature}`, 'nope');
  if (bad) throw new Error('expected reject');
  const missing = await isValidMetaSignature(body, null, secret);
  if (missing) throw new Error('expected missing header to fail');
});

Deno.test('reads text messages and ignores status webhooks', () => {
  const messages = extractInboundMessages({
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        value: {
          messaging_product: 'whatsapp',
          metadata: { phone_number_id: 'PHONE_ID' },
          messages: [{
            from: '919876543210',
            id: 'wamid.1',
            type: 'text',
            text: { body: 'MEDCAIN login AB2CD3EF' },
          }, {
            from: '919876543210',
            id: 'wamid.2',
            type: 'image',
          }],
        },
      }],
    }],
  });
  if (messages.length !== 1) throw new Error('expected one text message');
  if (messages[0].from !== '919876543210') throw new Error('from');
  if (messages[0].phoneNumberId !== 'PHONE_ID') throw new Error('phone id');
  if (!samePhone('+919876543210', messages[0].from)) {
    throw new Error('phone match');
  }
  if (samePhone('+14155552671', messages[0].from)) {
    throw new Error('different phone');
  }
  if (extractInboundMessages({ object: 'whatsapp_business_account', entry: [] }).length !== 0) {
    throw new Error('empty');
  }
});

Deno.test('confirmation reply is a free text message, not a template', () => {
  const payload = confirmationReply('919876543210');
  if (payload.type !== 'text') throw new Error('type');
  if (JSON.stringify(payload).includes('template')) {
    throw new Error('must not be a template');
  }
});
