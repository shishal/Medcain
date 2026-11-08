-- User-initiated WhatsApp sign-in.
-- The student sends a message to the business number (free inbound).
-- A service-role Edge Function matches it and mints a Supabase session.
-- authenticated has no access to these rows or to the lookup function.

-- ---------------------------------------------------------------------------
-- Challenges. The secret is stored only as a hash. The raw secret stays on
-- the device that started the request and is what may pick up the session.
-- ---------------------------------------------------------------------------

create table public.whatsapp_auth_challenges (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  code text not null,
  secret_hash text not null,
  status text not null default 'pending',
  user_id uuid references auth.users (id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  consumed_at timestamptz,
  whatsapp_message_id text,
  constraint whatsapp_auth_challenges_status check (
    status in ('pending', 'verified', 'consumed', 'blocked')
  ),
  constraint whatsapp_auth_challenges_phone check (
    phone ~ '^\+[1-9][0-9]{7,14}$'
  ),
  constraint whatsapp_auth_challenges_code check (
    code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$'
  ),
  constraint whatsapp_auth_challenges_secret_hash check (
    secret_hash ~ '^[0-9a-f]{64}$'
  )
);

create unique index whatsapp_auth_challenges_code_pending
  on public.whatsapp_auth_challenges (code)
  where status = 'pending';

create unique index whatsapp_auth_challenges_message
  on public.whatsapp_auth_challenges (whatsapp_message_id)
  where whatsapp_message_id is not null;

create index whatsapp_auth_challenges_phone_created
  on public.whatsapp_auth_challenges (phone, created_at desc);

alter table public.whatsapp_auth_challenges enable row level security;

revoke all on table public.whatsapp_auth_challenges from public, anon, authenticated;
grant select, insert, update, delete on table public.whatsapp_auth_challenges to service_role;

comment on table public.whatsapp_auth_challenges is
  'One WhatsApp sign-in attempt. The device holds the raw secret; the webhook sets verified when that phone messages the matching code.';

-- ---------------------------------------------------------------------------
-- Find an existing account for this WhatsApp number (auth phone, profile
-- phone, or the internal mailbox we create for new WhatsApp users).
-- ---------------------------------------------------------------------------

create or replace function public.lookup_whatsapp_account(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_row jsonb;
begin
  if char_length(v_digits) < 8 then
    return null;
  end if;

  select jsonb_build_object(
    'user_id', u.id,
    'email', u.email,
    'blocked', p.blocked_at is not null
  )
  into v_row
  from auth.users u
  left join public.profiles p on p.id = u.id
  where regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') = v_digits
     or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') = v_digits
     or lower(coalesce(u.email, '')) =
        'wa.' || v_digits || '@auth.medico.internal'
  order by
    case
      when regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') = v_digits
        then 0
      else 1
    end,
    u.created_at
  limit 1;

  return v_row;
end;
$$;

comment on function public.lookup_whatsapp_account(text) is
  'Service-role lookup of the Supabase user for a WhatsApp number. Null when none exists.';

revoke all on function public.lookup_whatsapp_account(text) from public, anon, authenticated;
grant execute on function public.lookup_whatsapp_account(text) to service_role;

-- New WhatsApp users carry the confirmed phone onto the profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, plan, plan_started_at, plan_expires_at, phone)
  values (new.id, 'pro', now(), now() + interval '4 days', new.phone);
  return new;
end;
$$;

-- Hide the internal mailbox from the admin console. Search still matches phone.
create or replace function public.admin_user_json(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'email', case
      when u.email ilike '%@auth.medico.internal' then null
      else u.email
    end,
    'full_name', p.full_name,
    'phone', coalesce(p.phone, u.phone),
    'plan', p.plan,
    'plan_expires_at', p.plan_expires_at,
    'plan_suspended_at', p.plan_suspended_at,
    'blocked_at', p.blocked_at,
    'blocked_reason', p.blocked_reason,
    'university_id', p.university_id,
    'university_name', uni.name,
    'college_id', p.college_id,
    'college_name', col.name,
    'batch_year', p.batch_year,
    'mbbs_phase_id', p.mbbs_phase_id,
    'is_admin', p.is_admin,
    'created_at', p.created_at
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.universities uni on uni.id = p.university_id
  left join public.colleges col on col.id = p.college_id
  where p.id = p_user_id;
$$;

create or replace function public.admin_search_users(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
begin
  perform public.assert_admin();

  if v_query is not null then
    v_query := replace(replace(v_query, '%', ''), '_', '');
  end if;

  return coalesce((
    select jsonb_agg(public.admin_user_json(p.id) order by p.created_at desc)
    from (
      select p.id, p.created_at
      from public.profiles p
      join auth.users u on u.id = p.id
      where v_query is null
        or u.email ilike '%' || v_query || '%'
        or u.phone ilike '%' || v_query || '%'
        or p.full_name ilike '%' || v_query || '%'
        or p.phone ilike '%' || v_query || '%'
      order by p.created_at desc
      limit 40
    ) p
  ), '[]'::jsonb);
end;
$$;
