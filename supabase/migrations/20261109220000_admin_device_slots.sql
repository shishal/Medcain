-- Website admin can free a student's phones and raise that account's
-- slot count above the plan default (Free 1, Pro 1, Elite 2).
-- The plan row stays the default for everyone else.
-- Students cannot write profiles.max_registered_devices: it is omitted
-- from the authenticated UPDATE column grant.

alter table public.profiles
  add column if not exists max_registered_devices integer;

alter table public.profiles
  drop constraint if exists profiles_max_registered_devices_range;

alter table public.profiles
  add constraint profiles_max_registered_devices_range
  check (
    max_registered_devices is null
    or max_registered_devices between 1 and 10
  );

comment on column public.profiles.max_registered_devices is
  'Optional raise of this account''s phone slots, 1 to 10. Null follows plan_limits. The effective cap is the higher of the two. Omitted from the authenticated UPDATE grant.';

-- ---------------------------------------------------------------------------
-- Effective slot count. A per-user raise never lowers the plan.
-- p_plan null uses current_plan (expired or suspended counts as free).
-- ---------------------------------------------------------------------------

create or replace function public.registered_device_limit(
  p_user_id uuid,
  p_plan public.plan_tier default null
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    1,
    coalesce((
      select l.max_registered_devices
      from public.plan_limits l
      where l.plan = coalesce(
        p_plan,
        public.current_plan(p_user_id),
        'free'::public.plan_tier
      )
    ), 1),
    coalesce((
      select pr.max_registered_devices
      from public.profiles pr
      where pr.id = p_user_id
    ), 0)
  );
$$;

comment on function public.registered_device_limit(uuid, public.plan_tier) is
  'Phone slots for one account: the higher of the plan limit and profiles.max_registered_devices.';

revoke all on function public.registered_device_limit(uuid, public.plan_tier) from public, anon, authenticated;

-- Drop the oldest registered installs past p_keep and end those sessions.
create or replace function public.release_extra_device_slots(
  p_user_id uuid,
  p_keep integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep integer := greatest(coalesce(p_keep, 0), 0);
begin
  if p_user_id is null then
    return;
  end if;

  delete from auth.sessions s
  using (
    select session_id
    from (
      select
        session_id,
        row_number() over (order by last_seen_at desc) as rn
      from public.device_claims
      where user_id = p_user_id
        and registered_at is not null
    ) ranked
    where rn > v_keep
      and session_id is not null
  ) dropped
  where s.user_id = p_user_id
    and s.id = dropped.session_id;

  update public.device_claims d
  set registered_at = null,
      session_id = null
  from (
    select device_id
    from (
      select
        device_id,
        row_number() over (order by last_seen_at desc) as rn
      from public.device_claims
      where user_id = p_user_id
        and registered_at is not null
    ) ranked
    where rn > v_keep
  ) extra
  where d.user_id = p_user_id
    and d.device_id = extra.device_id;

  update public.profiles p
  set active_device_id = null,
      active_device_claimed_at = null
  where p.id = p_user_id
    and p.active_device_id is not null
    and not exists (
      select 1
      from public.device_claims d
      where d.user_id = p_user_id
        and d.device_id = p.active_device_id
        and d.registered_at is not null
    );
end;
$$;

comment on function public.release_extra_device_slots(uuid, integer) is
  'Unregisters installs beyond p_keep, newest last_seen first, and ends those sessions.';

revoke all on function public.release_extra_device_slots(uuid, integer) from public, anon, authenticated;

-- claim_active_device: use the per-user cap. Body otherwise stays as shipped.
do $patch$
declare
  v_def text;
  v_old text := $old$  select coalesce(l.max_registered_devices, 1)
  into v_max
  from public.plan_limits l
  where l.plan = public.current_plan(v_uid);

  if v_max is null or v_max < 1 then
    v_max := 1;
  end if;$old$;
  v_new text := $new$  v_max := public.registered_device_limit(v_uid);$new$;
begin
  v_def := pg_get_functiondef('public.claim_active_device(text)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'claim_active_device device cap snippet was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

comment on function public.claim_active_device(text) is
  'Registers this install if the account has a free device slot. The slot count is the higher of the plan limit and profiles.max_registered_devices. Does not suspend the plan.';

-- A payment onto a shorter plan must keep an admin raise.
do $patch$
declare
  v_def text;
  v_old text := $old$    select max_registered_devices as n
    from public.plan_limits
    where plan = p_plan$old$;
  v_new text := $new$    select public.registered_device_limit(p_user_id, p_plan) as n$new$;
begin
  v_def := pg_get_functiondef(
    'public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text)'::regprocedure
  );
  if position(v_old in v_def) = 0 then
    raise exception 'apply_razorpay_payment device cap snippet was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

-- ---------------------------------------------------------------------------
-- Admin user payload includes the phones support needs to see.
-- ---------------------------------------------------------------------------

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
    'created_at', p.created_at,
    'plan_device_limit', (
      select l.max_registered_devices
      from public.plan_limits l
      where l.plan = p.plan
    ),
    'device_limit_override', p.max_registered_devices,
    'device_limit', public.registered_device_limit(p.id, p.plan),
    'registered_device_count', (
      select count(*)::int
      from public.device_claims d
      where d.user_id = p.id
        and d.registered_at is not null
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'device_id', listed.device_id,
        'last_seen_at', listed.last_seen_at,
        'registered_at', listed.registered_at
      ) order by listed.ord)
      from (
        select
          d.device_id,
          d.last_seen_at,
          d.registered_at,
          row_number() over (
            order by d.registered_at desc nulls last, d.last_seen_at desc
          ) as ord
        from public.device_claims d
        where d.user_id = p.id
        order by d.registered_at desc nulls last, d.last_seen_at desc
        limit 20
      ) listed
    ), '[]'::jsonb)
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.universities uni on uni.id = p.university_id
  left join public.colleges col on col.id = p.college_id
  where p.id = p_user_id;
$$;

-- Saving a lower plan drops phones the new cap does not cover.
-- An override above that plan is kept.
create or replace function public.admin_set_plan(
  p_user_id uuid,
  p_plan text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := lower(btrim(coalesce(p_plan, '')));
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;

  -- Direct write. Does not insert a payment row.
  update public.profiles
  set
    plan = v_plan::public.plan_tier,
    plan_started_at = now(),
    plan_expires_at = p_expires_at
  where id = p_user_id;

  perform public.release_extra_device_slots(
    p_user_id,
    public.registered_device_limit(p_user_id, v_plan::public.plan_tier)
  );

  perform public.admin_log_action(
    'set_plan',
    p_user_id,
    jsonb_build_object('plan', v_plan, 'plan_expires_at', p_expires_at)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

create or replace function public.admin_set_device_limit(
  p_user_id uuid,
  p_max integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.plan_tier;
  v_plan_limit integer;
  v_plan_name text;
  v_stored integer;
begin
  perform public.assert_admin();

  select plan
  into v_plan
  from public.profiles
  where id = p_user_id;

  if v_plan is null then
    raise exception 'User not found.';
  end if;

  select coalesce(l.max_registered_devices, 1)
  into v_plan_limit
  from public.plan_limits l
  where l.plan = v_plan;

  if v_plan_limit is null or v_plan_limit < 1 then
    v_plan_limit := 1;
  end if;

  v_plan_name := case v_plan
    when 'elite' then 'Elite'
    when 'pro' then 'Pro'
    else 'Free'
  end;

  if p_max is not null and p_max > 10 then
    raise exception 'Device limit cannot be more than 10.';
  end if;

  if p_max is not null and p_max < v_plan_limit then
    raise exception '% already allows % phones. Enter % or more, or leave the box empty.',
      v_plan_name, v_plan_limit, v_plan_limit;
  end if;

  -- Equal to the plan stores null, so a later plan change is not pinned.
  v_stored := case
    when p_max is null or p_max <= v_plan_limit then null::integer
    else p_max
  end;

  update public.profiles
  set max_registered_devices = v_stored
  where id = p_user_id;

  perform public.release_extra_device_slots(
    p_user_id,
    public.registered_device_limit(p_user_id, v_plan)
  );

  perform public.admin_log_action(
    'set_device_limit',
    p_user_id,
    jsonb_build_object('max_registered_devices', v_stored)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

comment on function public.admin_set_device_limit(uuid, integer) is
  'Raises one account''s phone slots above the plan, up to 10. Null or the plan count clears the raise.';

create or replace function public.admin_release_device(
  p_user_id uuid,
  p_device_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device text := nullif(btrim(coalesce(p_device_id, '')), '');
  v_session uuid;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  if v_device is null or char_length(v_device) > 128 then
    raise exception 'That phone is not on this account.';
  end if;

  select session_id
  into v_session
  from public.device_claims
  where user_id = p_user_id
    and device_id = v_device;

  if not found then
    raise exception 'That phone is not on this account.';
  end if;

  update public.device_claims
  set registered_at = null,
      session_id = null
  where user_id = p_user_id
    and device_id = v_device;

  if v_session is not null then
    delete from auth.sessions
    where user_id = p_user_id
      and id = v_session;
  end if;

  update public.profiles
  set active_device_id = null,
      active_device_claimed_at = null
  where id = p_user_id
    and active_device_id = v_device;

  perform public.admin_log_action(
    'release_device',
    p_user_id,
    jsonb_build_object('device_id', v_device)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

comment on function public.admin_release_device(uuid, text) is
  'Frees one phone slot and ends that phone''s session so another install can register.';

create or replace function public.admin_reset_devices(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cleared integer;
  v_keep_session uuid;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  -- Resetting your own account must not drop the website session you
  -- are using to click the button.
  if p_user_id = auth.uid() then
    begin
      v_keep_session := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    exception
      when others then
        v_keep_session := null;
    end;
  end if;

  select count(*)::int
  into v_cleared
  from public.device_claims
  where user_id = p_user_id
    and registered_at is not null;

  update public.device_claims
  set registered_at = null,
      session_id = null
  where user_id = p_user_id;

  update public.profiles
  set active_device_id = null,
      active_device_claimed_at = null
  where id = p_user_id;

  -- Every session, not only the ones stored on device_claims. A phone
  -- that is still signed in would claim the slot again on the next open.
  delete from auth.sessions
  where user_id = p_user_id
    and id is distinct from v_keep_session;

  perform public.admin_log_action(
    'reset_devices',
    p_user_id,
    jsonb_build_object('registered_cleared', v_cleared)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

comment on function public.admin_reset_devices(uuid) is
  'Frees every phone slot and signs the account out so the next sign-in can register.';

revoke all on function public.admin_set_device_limit(uuid, integer) from public, anon;
revoke all on function public.admin_release_device(uuid, text) from public, anon;
revoke all on function public.admin_reset_devices(uuid) from public, anon;

grant execute on function public.admin_set_device_limit(uuid, integer) to authenticated;
grant execute on function public.admin_release_device(uuid, text) to authenticated;
grant execute on function public.admin_reset_devices(uuid) to authenticated;
