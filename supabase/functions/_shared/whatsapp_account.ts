// Turns a verified WhatsApp number into a Supabase user and a session.
//
// GoTrue's magic-link API needs an email. New accounts get a mailbox under
// auth.medico.internal that is never delivered and never shown in the app.
// Existing accounts keep their real email and gain a confirmed phone.

import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2';

import { syntheticEmail } from './whatsapp_auth.ts';

export type ResolvedAccount =
  | { ok: true; userId: string }
  | { ok: false; blocked: true }
  | { ok: false; blocked: false };

export function createServiceClient(): SupabaseClient | null {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) return null;
  return createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

type LookupRow = {
  user_id?: string;
  email?: string | null;
  blocked?: boolean | null;
};

export async function resolveOrCreateWhatsAppUser(
  service: SupabaseClient,
  phone: string,
): Promise<ResolvedAccount> {
  const existing = await lookup(service, phone);
  if (existing?.blocked === true) return { ok: false, blocked: true };
  if (typeof existing?.user_id === 'string') {
    await attachPhone(service, existing.user_id, phone);
    return { ok: true, userId: existing.user_id };
  }

  const { data, error } = await service.auth.admin.createUser({
    email: syntheticEmail(phone),
    email_confirm: true,
    phone,
    phone_confirm: true,
    user_metadata: { auth_method: 'whatsapp' },
  });
  if (!error && data.user) {
    return { ok: true, userId: data.user.id };
  }

  console.error('createUser failed', error?.message);
  const again = await lookup(service, phone);
  if (again?.blocked === true) return { ok: false, blocked: true };
  if (typeof again?.user_id === 'string') {
    await attachPhone(service, again.user_id, phone);
    return { ok: true, userId: again.user_id };
  }
  return { ok: false, blocked: false };
}

export type MintedSession = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
};

export async function mintWhatsAppSession(
  service: SupabaseClient,
  userId: string,
): Promise<MintedSession | 'banned' | null> {
  const { data: userData, error: userError } = await service.auth.admin
    .getUserById(userId);
  if (userError || userData.user == null) {
    console.error('getUserById', userError?.message);
    return null;
  }

  const user = userData.user;
  if (isBanned(user.banned_until)) return 'banned';

  let email = user.email ?? '';
  if (email.length === 0) {
    if (!user.phone) return null;
    email = syntheticEmail(user.phone);
    const { error } = await service.auth.admin.updateUserById(userId, {
      email,
      email_confirm: true,
    });
    if (error) {
      console.error('set synthetic email', error.message);
      return null;
    }
  }

  // generateLink does not send the email. We verify the hash here and hand
  // the resulting refresh token to the device that holds the challenge secret.
  const { data: link, error: linkError } = await service.auth.admin
    .generateLink({
      type: 'magiclink',
      email,
    });
  const hashed = link?.properties?.hashed_token;
  if (linkError || hashed == null || hashed.length === 0) {
    console.error('generateLink', linkError?.message);
    return null;
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) return null;
  const anon = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: verified, error: verifyError } = await anon.auth.verifyOtp({
    token_hash: hashed,
    type: 'magiclink',
  });
  const session = verified.session;
  if (verifyError || session == null) {
    console.error('verifyOtp', verifyError?.message);
    return null;
  }

  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresIn: session.expires_in ?? 3600,
  };
}

export function sessionStillValid(expiresAt: string): boolean {
  const ms = Date.parse(expiresAt);
  return Number.isFinite(ms) && ms > Date.now();
}

async function lookup(
  service: SupabaseClient,
  phone: string,
): Promise<LookupRow | null> {
  const { data, error } = await service.rpc('lookup_whatsapp_account', {
    p_phone: phone,
  });
  if (error) {
    console.error('lookup_whatsapp_account', error.message);
    return null;
  }
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    return null;
  }
  return data as LookupRow;
}

async function attachPhone(
  service: SupabaseClient,
  userId: string,
  phone: string,
): Promise<void> {
  const { error: authError } = await service.auth.admin.updateUserById(
    userId,
    { phone, phone_confirm: true },
  );
  if (authError) console.error('confirm phone', authError.message);
  const { error: profileError } = await service
    .from('profiles')
    .update({ phone })
    .eq('id', userId);
  if (profileError) console.error('profile phone', profileError.message);
}

function isBanned(bannedUntil: string | null | undefined): boolean {
  if (bannedUntil == null || bannedUntil.length === 0) return false;
  const until = Date.parse(bannedUntil);
  return Number.isFinite(until) && until > Date.now();
}
