// Admin password, email, and ban. The Flutter app never sees the service role.
// The caller must already be profiles.is_admin (assert_admin). GoTrue ban and
// password changes happen here; the blocked_at column is set by admin_set_blocked.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { corsHeaders, jsonResponse } from '../_shared/cors.ts';

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'Server is missing Supabase config.' }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || user == null) {
    return jsonResponse({ error: 'Sign in to continue.' }, 401);
  }

  const { error: adminError } = await userClient.rpc('assert_admin');
  if (adminError) {
    const denied = adminError.message.includes('Admin only');
    return jsonResponse(
      { error: denied ? 'Admin only.' : 'Sign in to continue.' },
      403,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Send JSON.' }, 400);
  }

  const action = body.action;
  const userId = typeof body.user_id === 'string' ? body.user_id.trim() : '';
  if (!uuidPattern.test(userId)) {
    return jsonResponse({ error: 'User not found.' }, 400);
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (action === 'set_password') {
    const password = typeof body.password === 'string' ? body.password : '';
    if (password.length < 6) {
      return jsonResponse(
        { error: 'Password must be at least 6 characters.' },
        400,
      );
    }

    const { error } = await service.auth.admin.updateUserById(userId, {
      password,
    });
    if (error) {
      return jsonResponse({ error: goTrueMessage(error.message) }, 400);
    }

    const logged = await logAction(userClient, 'set_password', userId, {});
    if (!logged) {
      return jsonResponse(
        { error: 'Password was reset, but the audit log failed.' },
        500,
      );
    }
    return jsonResponse({ ok: true });
  }

  if (action === 'set_email') {
    const email = typeof body.email === 'string' ? body.email.trim() : '';
    if (!email.includes('@') || email.length > 320) {
      return jsonResponse({ error: 'Please enter a valid email address.' }, 400);
    }

    const { error } = await service.auth.admin.updateUserById(userId, {
      email,
      email_confirm: true,
    });
    if (error) {
      return jsonResponse({ error: goTrueMessage(error.message) }, 400);
    }

    const logged = await logAction(userClient, 'set_email', userId, { email });
    if (!logged) {
      return jsonResponse(
        { error: 'Email was updated, but the audit log failed.' },
        500,
      );
    }
    return jsonResponse({ ok: true });
  }

  if (action === 'block' || action === 'unblock') {
    const blocked = action === 'block';
    const reason = typeof body.reason === 'string' ? body.reason.trim() : '';

    const { error: flagError } = await userClient.rpc('admin_set_blocked', {
      p_user_id: userId,
      p_blocked: blocked,
      p_reason: reason,
    });
    if (flagError) {
      return jsonResponse({ error: rpcMessage(flagError.message) }, 400);
    }

    const { error: banError } = await service.auth.admin.updateUserById(
      userId,
      { ban_duration: blocked ? '876000h' : 'none' },
    );
    if (banError) {
      await userClient.rpc('admin_set_blocked', {
        p_user_id: userId,
        p_blocked: !blocked,
        p_reason: reason,
      });
      return jsonResponse({ error: 'Could not update that account.' }, 400);
    }

    if (blocked) {
      const { error: revokeError } = await service.rpc(
        'admin_revoke_sessions',
        { p_user_id: userId },
      );
      if (revokeError) {
        return jsonResponse(
          {
            error:
              'The account is blocked, but an old session could not be cleared. Block them again if they are still signed in.',
          },
          500,
        );
      }
    }

    return jsonResponse({ ok: true });
  }

  return jsonResponse({ error: 'Unknown action.' }, 400);
});

function goTrueMessage(message: string): string {
  const lower = message.toLowerCase();
  if (lower.includes('already') && lower.includes('registered')) {
    return 'An account with this email already exists.';
  }
  if (lower.includes('password')) {
    return 'Password must be at least 6 characters.';
  }
  if (lower.includes('email')) {
    return 'Please enter a valid email address.';
  }
  if (lower.includes('not found')) {
    return 'User not found.';
  }
  return 'Could not update that account.';
}

function rpcMessage(message: string): string {
  const known = [
    'Admin only.',
    'Sign in to continue.',
    'User not found.',
    'You cannot block your own account.',
  ];
  return known.find((item) => message.includes(item)) ??
    'Could not update that account.';
}

async function logAction(
  userClient: SupabaseClient,
  action: string,
  userId: string,
  detail: Record<string, unknown>,
): Promise<boolean> {
  const { error } = await userClient.rpc('admin_log_action', {
    p_action: action,
    p_target_id: userId,
    p_detail: detail,
  });
  return error == null;
}
