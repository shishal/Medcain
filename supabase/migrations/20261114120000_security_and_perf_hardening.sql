-- Security hardening & SQL performance optimizations:
-- 1. Authoritative payment_orders table so Razorpay webhook never trusts
--    client-overridable payment.entity.notes on Standard Checkout.
-- 2. Prevent synthetic email/unverified profile.phone pre-account collisions.
-- 3. Enforce profiles.blocked_at across assert_admin, assert_active_device,
--    current_plan_id, and current_plan so banned JWTs lose access immediately.
-- 4. Lock down cross-user current_plan_id(uuid) probing and revoke PUBLIC/anon
--    on internal functions.
-- 5. Tighten attempts RLS + submit_attempt entitlement check against locked
--    catalog tests, reading-mode sessions, and other users' practice tests.
-- 6. Prevent TOCTOU races in claim_active_device and create_practice_session
--    via per-user row locks, and enforce allow_tutor_mode on reading mode.
-- 7. Inline plan slice checks inside question_listings, pyq_teasers, and
--    search_catalog (avoiding per-row SECURITY DEFINER overhead) and add
--    missing hot-path indexes + single-query get_study_progress.

-- ---------------------------------------------------------------------------
-- 1. Authoritative Razorpay Order Binding (payment_orders)
-- ---------------------------------------------------------------------------

create table if not exists public.payment_orders (
  razorpay_order_id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null references public.plans (id) on delete restrict,
  amount_paise integer not null check (amount_paise >= 100),
  list_amount_paise integer not null check (list_amount_paise >= 100),
  currency text not null default 'INR' check (currency = 'INR'),
  discount_code text,
  percent_off integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_payment_orders_user_created
  on public.payment_orders (user_id, created_at desc);

alter table public.payment_orders enable row level security;

revoke all on table public.payment_orders from public, anon, authenticated;
grant select, insert, update, delete on table public.payment_orders to service_role;

comment on table public.payment_orders is
  'Server-recorded Razorpay Orders created by create-razorpay-order. apply_razorpay_payment trusts this row over client-editable payment notes.';

-- ---------------------------------------------------------------------------
-- 2. Account Collision & Blocked-User Enforcement
-- ---------------------------------------------------------------------------

-- Students sign in with WhatsApp; phone is verified by the inbound message,
-- never self-edited from the client.
revoke update on table public.profiles from authenticated;
grant update (
  full_name,
  university_id,
  college_id,
  batch_year,
  mbbs_phase_id,
  onboarding_completed_at
) on table public.profiles to authenticated;

create or replace function public.lookup_whatsapp_account(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_synth text;
  v_row jsonb;
begin
  if char_length(v_digits) < 8 then
    return null;
  end if;

  v_synth := 'wa.' || v_digits || '@auth.medico.internal';

  -- Match confirmed auth.users.phone or our own synthetic WhatsApp mailbox,
  -- using indexed equality checks first before falling back to digit-normalized
  -- auth.users.phone. Unverified profiles.phone is excluded so a user cannot
  -- claim an unregistered phone number ahead of its owner.
  select jsonb_build_object(
    'user_id', matched.id,
    'email', matched.email,
    'blocked', p.blocked_at is not null
  )
  into v_row
  from (
    select u.id, u.email, 0 as prio, u.created_at
    from auth.users u
    where u.phone in ('+' || v_digits, v_digits)
    union all
    select u.id, u.email, 1 as prio, u.created_at
    from auth.users u
    where lower(u.email) = v_synth
    union all
    select u.id, u.email, 2 as prio, u.created_at
    from auth.users u
    where u.phone is not null
      and u.phone not in ('+' || v_digits, v_digits)
      and regexp_replace(u.phone, '\D', '', 'g') = v_digits
  ) matched
  left join public.profiles p on p.id = matched.id
  order by matched.prio, matched.created_at
  limit 1;

  return v_row;
end;
$$;

revoke all on function public.lookup_whatsapp_account(text) from public, anon, authenticated;
grant execute on function public.lookup_whatsapp_account(text) to service_role;

-- Blocked operators immediately lose admin RPC access even before JWT expiry.
create or replace function public.assert_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue.';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_admin
      and blocked_at is null
  ) then
    raise exception 'Admin only.';
  end if;
end;
$$;

revoke all on function public.assert_admin() from public, anon;
grant execute on function public.assert_admin() to authenticated;

-- Effective plan helpers: blocked accounts drop to Free (and blocked checks
-- below block session creation / active device assertions).
create or replace function public.current_plan(p_user_id uuid)
returns public.plan_tier
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.blocked_at is not null then 'free'::public.plan_tier
    when p.plan_suspended_at is not null then 'free'::public.plan_tier
    when p.plan_expires_at is not null and p.plan_expires_at < now() then 'free'::public.plan_tier
    else p.plan
  end
  from public.profiles p
  where p.id = p_user_id
    and (auth.role() = 'service_role' or p_user_id = auth.uid());
$$;

revoke all on function public.current_plan(uuid) from public, anon;
grant execute on function public.current_plan(uuid) to authenticated, service_role;

create or replace function public.current_plan_id(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.blocked_at is not null then free_plan.id
    when p.plan_suspended_at is not null then free_plan.id
    when p.plan_expires_at is not null and p.plan_expires_at < now() then free_plan.id
    else p.plan_id
  end
  from public.profiles p
  cross join lateral (
    select id from public.plans where code = 'free'
  ) free_plan
  where p.id = p_user_id;
$$;

-- Prevent cross-user plan probing: students call current_plan_detail() or
-- private.my_current_plan_id() pinned to auth.uid().
revoke all on function public.current_plan_id(uuid) from public, anon, authenticated;
grant execute on function public.current_plan_id(uuid) to service_role;

create or replace function private.my_current_plan_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.current_plan_id(auth.uid());
$$;

revoke all on function private.my_current_plan_id() from public, anon;
grant execute on function private.my_current_plan_id() to authenticated, service_role;

create or replace function public.current_plan_detail()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(pl)
  from public.plans pl
  where pl.id = private.my_current_plan_id();
$$;

revoke all on function public.current_plan_detail() from public, anon;
grant execute on function public.current_plan_detail() to authenticated, service_role;

-- Update plans RLS policy to use private.my_current_plan_id() instead of
-- calling revoked current_plan_id(uuid) directly as authenticated.
drop policy if exists "plans readable" on public.plans;
create policy "plans readable" on public.plans
  for select using (
    (is_public and is_active)
    or id = (
      select p.plan_id from public.profiles p where p.id = auth.uid()
    )
    or id = private.my_current_plan_id()
  );

drop policy if exists "tests select" on public.tests;
create policy "tests select" on public.tests
  for select using (
    owner_user_id = auth.uid()
    or (
      is_active
      and (
        required_plan = 'free'::public.plan_tier
        or exists (
          select 1
          from public.plans pl
          where pl.id = private.my_current_plan_id()
            and pl.access_mode = 'filtered'
        )
      )
    )
  );

drop policy if exists "test_questions select" on public.test_questions;
create policy "test_questions select" on public.test_questions
  for select using (
    exists (
      select 1
      from public.tests t
      where t.id = test_questions.test_id
        and (
          t.owner_user_id = auth.uid()
          or (
            t.is_active
            and (
              t.required_plan = 'free'::public.plan_tier
              or exists (
                select 1
                from public.plans pl
                where pl.id = private.my_current_plan_id()
                  and pl.access_mode = 'filtered'
              )
            )
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Device Registration Lock & Blocked-Account Guard
-- ---------------------------------------------------------------------------

create or replace function public.claim_active_device(p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := nullif(btrim(p_device_id), '');
  v_max int;
  v_registered boolean;
  v_count int;
  v_suspended boolean;
  v_is_admin boolean;
  v_blocked boolean;
  v_session_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if v_device is null or char_length(v_device) > 128 then
    raise exception 'INVALID_DEVICE_ID';
  end if;

  -- Serialize concurrent device claims for the same user (prevents TOCTOU
  -- slot-count bypass across simultaneous logins).
  select p.is_admin, (p.blocked_at is not null), (p.plan_suspended_at is not null)
    into v_is_admin, v_blocked, v_suspended
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_blocked, false) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;

  if coalesce(v_is_admin, false) then
    return jsonb_build_object(
      'ok', true,
      'device_limit', false,
      'max_devices', 0,
      'suspended', false,
      'just_suspended', false,
      'distinct_device_count', 0
    );
  end if;

  v_max := public.registered_device_limit(v_uid);
  if v_max is null or v_max < 1 then
    v_max := 1;
  end if;

  insert into public.device_claims (
    user_id, device_id, first_seen_at, last_seen_at
  ) values (
    v_uid, v_device, now(), now()
  )
  on conflict (user_id, device_id) do update
  set last_seen_at = now();

  select registered_at is not null
    into v_registered
  from public.device_claims
  where user_id = v_uid
    and device_id = v_device;

  begin
    v_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception
    when others then
      v_session_id := null;
  end;

  if not coalesce(v_registered, false) then
    select count(*)::int
      into v_count
    from public.device_claims
    where user_id = v_uid
      and registered_at is not null;

    if v_count >= v_max then
      if v_session_id is not null then
        delete from auth.sessions
        where user_id = v_uid
          and id = v_session_id;
      end if;

      return jsonb_build_object(
        'ok', false,
        'device_limit', true,
        'max_devices', v_max,
        'suspended', false,
        'just_suspended', false,
        'distinct_device_count', v_count
      );
    end if;

    update public.device_claims
    set registered_at = now(),
        session_id = v_session_id
    where user_id = v_uid
      and device_id = v_device;
  else
    update public.device_claims
    set session_id = v_session_id
    where user_id = v_uid
      and device_id = v_device;
  end if;

  update public.profiles
  set
    active_device_id = v_device,
    active_device_claimed_at = now()
  where id = v_uid;

  if v_max <= 1 and v_session_id is not null then
    delete from auth.sessions
    where user_id = v_uid
      and id is distinct from v_session_id;
  end if;

  select count(*)::int
    into v_count
  from public.device_claims
  where user_id = v_uid
    and registered_at is not null;

  return jsonb_build_object(
    'ok', true,
    'device_limit', false,
    'max_devices', v_max,
    'suspended', coalesce(v_suspended, false),
    'just_suspended', false,
    'distinct_device_count', v_count
  );
end;
$$;

revoke all on function public.claim_active_device(text) from public, anon;
grant execute on function public.claim_active_device(text) to authenticated;

create or replace function public.assert_active_device(p_device_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := nullif(btrim(p_device_id), '');
  v_is_admin boolean;
  v_blocked boolean;
begin
  if v_uid is null then
    return false;
  end if;

  select p.is_admin, (p.blocked_at is not null)
    into v_is_admin, v_blocked
  from public.profiles p
  where p.id = v_uid;

  if coalesce(v_blocked, false) then
    return false;
  end if;

  if coalesce(v_is_admin, false) then
    return true;
  end if;

  if v_device is null or char_length(v_device) > 128 then
    return false;
  end if;

  if exists (
    select 1
    from public.device_claims
    where user_id = v_uid
      and device_id = v_device
      and registered_at is not null
  ) then
    return true;
  end if;

  if not exists (
    select 1
    from public.device_claims
    where user_id = v_uid
      and registered_at is not null
  ) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.assert_active_device(text) from public, anon;
grant execute on function public.assert_active_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Attempts & Scoring Entitlement Hardening + Single-Scan Percentile
-- ---------------------------------------------------------------------------

drop policy if exists "own attempts insert" on public.attempts;
create policy "own attempts insert" on public.attempts
  for insert
  with check (
    auth.uid() = user_id
    and status = 'in_progress'
    and exists (
      select 1
      from public.tests t
      where t.id = attempts.test_id
        and t.feedback_timing in ('immediate', 'on_submit')
        and (
          t.owner_user_id = auth.uid()
          or (
            t.owner_user_id is null
            and t.is_active
            and (
              t.required_plan = 'free'::public.plan_tier
              or exists (
                select 1
                from public.plans pl
                where pl.id = private.my_current_plan_id()
                  and pl.access_mode = 'filtered'
                  and pl.content_depth in ('answer', 'explanation')
              )
            )
          )
        )
    )
  );

create or replace function public.calculate_percentile(
  p_test_id uuid,
  p_score numeric
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select round(
    100.0 * count(*) filter (where total_score <= p_score)
    / nullif(count(*), 0)
  , 1)
  from public.attempts
  where test_id = p_test_id
    and status = 'submitted';
$$;

revoke all on function public.calculate_percentile(uuid, numeric) from public, anon, authenticated;

create or replace function public.submit_attempt(
  p_attempt_id uuid,
  p_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_test public.tests%rowtype;
  v_correct_marks numeric;
  v_incorrect_marks numeric;
  v_unattempted_marks numeric;
  v_correct int;
  v_incorrect int;
  v_unattempted int;
  v_total numeric;
  v_percentile numeric;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if exists (
    select 1 from public.profiles where id = auth.uid() and blocked_at is not null
  ) then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_attempt_id is null then
    raise exception 'ATTEMPT_NOT_FOUND';
  end if;

  select *
    into v_attempt
  from public.attempts
  where id = p_attempt_id
  for update;

  if not found then
    raise exception 'ATTEMPT_NOT_FOUND';
  end if;

  if v_attempt.user_id is distinct from auth.uid() then
    raise exception 'ATTEMPT_NOT_OWNED';
  end if;

  if v_attempt.status = 'submitted' then
    return jsonb_build_object(
      'id', v_attempt.id,
      'test_id', v_attempt.test_id,
      'status', v_attempt.status,
      'total_score', v_attempt.total_score,
      'correct_count', v_attempt.correct_count,
      'incorrect_count', v_attempt.incorrect_count,
      'unattempted_count', v_attempt.unattempted_count,
      'percentile', v_attempt.percentile,
      'submitted_at', v_attempt.submitted_at
    );
  end if;

  if v_attempt.status is distinct from 'in_progress' then
    raise exception 'ATTEMPT_NOT_IN_PROGRESS';
  end if;

  -- Verify the test belongs to this user or is an active allowed catalog test,
  -- and is not a reading-mode scroll session.
  select *
    into v_test
  from public.tests
  where id = v_attempt.test_id;

  if not found
     or v_test.feedback_timing not in ('immediate', 'on_submit')
     or (v_test.owner_user_id is not null and v_test.owner_user_id is distinct from auth.uid())
     or (
       v_test.owner_user_id is null
       and (
         not v_test.is_active
         or (
           v_test.required_plan <> 'free'::public.plan_tier
           and not exists (
             select 1
             from public.plans pl
             where pl.id = public.current_plan_id(auth.uid())
               and pl.access_mode = 'filtered'
               and pl.content_depth in ('answer', 'explanation')
           )
         )
       )
     )
  then
    raise exception 'ATTEMPT_NOT_OWNED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) elem
    where nullif(btrim(elem->>'selected_option'), '') is not null
      and btrim(elem->>'selected_option') not in ('A', 'B', 'C', 'D')
  ) then
    raise exception 'INVALID_SELECTED_OPTION';
  end if;

  insert into public.attempt_answers (
    attempt_id,
    question_id,
    selected_option,
    is_marked_for_review,
    time_spent_seconds,
    answered_at
  )
  select
    p_attempt_id,
    tq.question_id,
    nullif(btrim(elem->>'selected_option'), '')::char(1),
    coalesce((elem->>'is_marked_for_review')::boolean, false),
    greatest(coalesce((elem->>'time_spent_seconds')::int, 0), 0),
    case
      when nullif(btrim(elem->>'selected_option'), '') is not null then now()
      else null
    end
  from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) elem
  join public.test_questions tq
    on tq.test_id = v_attempt.test_id
   and tq.question_id = (elem->>'question_id')::uuid
  on conflict (attempt_id, question_id) do update
    set selected_option = excluded.selected_option,
        is_marked_for_review = excluded.is_marked_for_review,
        time_spent_seconds = excluded.time_spent_seconds,
        answered_at = excluded.answered_at;

  select
    t.correct_marks,
    t.incorrect_marks,
    t.unattempted_marks,
    count(*) filter (
      where aa.selected_option is not null
        and aa.selected_option = q.correct_option
    )::int,
    count(*) filter (
      where aa.selected_option is not null
        and aa.selected_option is distinct from q.correct_option
    )::int,
    count(*) filter (
      where aa.selected_option is null
    )::int
  into
    v_correct_marks,
    v_incorrect_marks,
    v_unattempted_marks,
    v_correct,
    v_incorrect,
    v_unattempted
  from public.tests t
  join public.test_questions tq on tq.test_id = t.id
  join public.questions q on q.id = tq.question_id
  left join public.attempt_answers aa
    on aa.attempt_id = p_attempt_id
   and aa.question_id = tq.question_id
  where t.id = v_attempt.test_id
  group by t.correct_marks, t.incorrect_marks, t.unattempted_marks;

  v_correct := coalesce(v_correct, 0);
  v_incorrect := coalesce(v_incorrect, 0);
  v_unattempted := coalesce(v_unattempted, 0);
  v_total :=
    (v_correct * coalesce(v_correct_marks, 0))
    + (v_incorrect * coalesce(v_incorrect_marks, 0))
    + (v_unattempted * coalesce(v_unattempted_marks, 0));

  update public.attempts
     set status = 'submitted',
         submitted_at = now(),
         total_score = v_total,
         correct_count = v_correct,
         incorrect_count = v_incorrect,
         unattempted_count = v_unattempted
   where id = p_attempt_id;

  v_percentile := public.calculate_percentile(v_attempt.test_id, v_total);

  update public.attempts
     set percentile = v_percentile
   where id = p_attempt_id
  returning * into v_attempt;

  return jsonb_build_object(
    'id', v_attempt.id,
    'test_id', v_attempt.test_id,
    'status', v_attempt.status,
    'total_score', v_attempt.total_score,
    'correct_count', v_attempt.correct_count,
    'incorrect_count', v_attempt.incorrect_count,
    'unattempted_count', v_attempt.unattempted_count,
    'percentile', v_attempt.percentile,
    'submitted_at', v_attempt.submitted_at
  );
end;
$$;

revoke all on function public.submit_attempt(uuid, jsonb) from public, anon;
grant execute on function public.submit_attempt(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Hardened apply_razorpay_payment Using Authoritative payment_orders
-- ---------------------------------------------------------------------------

create or replace function public.apply_razorpay_payment(
  p_payment_id text,
  p_order_id text,
  p_user_id uuid,
  p_plan_id uuid,
  p_amount_paise integer,
  p_currency text,
  p_discount_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.payment_orders%rowtype;
  v_has_order boolean := false;
  v_effective_user_id uuid;
  v_effective_plan_id uuid;
  v_plan public.plans%rowtype;
  v_expected integer;
  v_code text;
  v_percent integer;
  v_owner uuid;
  v_max integer;
  v_count integer;
  v_expires timestamptz;
  v_active boolean;
  v_tier public.plan_tier;
  v_inserted text;
  v_expires_at timestamptz;
  v_plan_id uuid;
begin
  if p_payment_id is null or length(trim(p_payment_id)) = 0 then
    raise exception 'payment id required';
  end if;
  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'order id required';
  end if;

  -- Idempotency check first before locking discount codes.
  select pr.plan_id, pr.plan_expires_at
    into v_plan_id, v_expires_at
  from public.payments pay
  join public.profiles pr on pr.id = pay.user_id
  where pay.razorpay_payment_id = p_payment_id;

  if found then
    return jsonb_build_object(
      'applied', false,
      'duplicate', true,
      'plan_id', v_plan_id,
      'plan_expires_at', v_expires_at
    );
  end if;

  -- Prefer the server-stored order row created by create-razorpay-order so
  -- client-supplied checkout.js notes cannot swap user_id, plan_id, or code.
  select *
    into v_order
  from public.payment_orders
  where razorpay_order_id = p_order_id;

  v_has_order := found;

  if v_has_order then
    v_effective_user_id := v_order.user_id;
    v_effective_plan_id := v_order.plan_id;
    v_code := v_order.discount_code;
    v_percent := v_order.percent_off;
    v_expected := v_order.amount_paise;

    select * into v_plan
    from public.plans
    where id = v_effective_plan_id
      and amount_paise >= 100
      and duration_months is not null;

    if v_plan.id is null then
      raise exception 'unsupported plan';
    end if;
  else
    -- Legacy fallback for orders created right before this migration deployed.
    if p_user_id is null then
      raise exception 'user id required';
    end if;
    v_effective_user_id := p_user_id;
    v_effective_plan_id := p_plan_id;

    select * into v_plan
    from public.plans
    where id = v_effective_plan_id
      and is_active
      and is_public
      and amount_paise >= 100
      and duration_months is not null;

    if v_plan.id is null then
      raise exception 'unsupported plan';
    end if;

    v_code := public.normalize_discount_code(p_discount_code);
    if p_discount_code is null or length(trim(p_discount_code)) = 0 then
      v_code := null;
      v_percent := null;
      v_expected := v_plan.amount_paise;
    else
      if v_code is null then
        raise exception 'amount does not match catalog';
      end if;
      select percent_off, owner_user_id, max_redemptions, redemption_count,
             expires_at, active
        into v_percent, v_owner, v_max, v_count, v_expires, v_active
      from public.discount_codes
      where code = v_code
      for update;

      if v_percent is null
         or v_active is not true
         or (v_expires is not null and v_expires <= now())
         or (v_max is not null and v_count >= v_max)
         or (v_owner is not null and v_owner = v_effective_user_id)
      then
        raise exception 'amount does not match catalog';
      end if;

      v_expected := public.discounted_amount_paise(v_plan.amount_paise, v_percent);
    end if;
  end if;

  if p_amount_paise is distinct from v_expected then
    raise exception 'amount does not match catalog';
  end if;
  if p_currency is distinct from 'INR' then
    raise exception 'currency does not match catalog';
  end if;

  v_tier := case
    when v_plan.code in ('pro', 'elite') then v_plan.code::public.plan_tier
    else 'pro'::public.plan_tier
  end;

  insert into public.payments (
    razorpay_payment_id,
    razorpay_order_id,
    user_id,
    plan,
    plan_id,
    amount_paise,
    currency,
    discount_code,
    list_amount_paise,
    percent_off,
    billing_period
  ) values (
    p_payment_id,
    p_order_id,
    v_effective_user_id,
    v_tier,
    v_plan.id,
    p_amount_paise,
    p_currency,
    v_code,
    case when v_has_order then v_order.list_amount_paise else v_plan.amount_paise end,
    v_percent,
    null
  )
  on conflict (razorpay_payment_id) do nothing
  returning razorpay_payment_id into v_inserted;

  if v_inserted is null then
    select pr.plan_id, pr.plan_expires_at
      into v_plan_id, v_expires_at
    from public.payments pay
    join public.profiles pr on pr.id = pay.user_id
    where pay.razorpay_payment_id = p_payment_id;

    return jsonb_build_object(
      'applied', false,
      'duplicate', true,
      'plan_id', v_plan_id,
      'plan_expires_at', v_expires_at
    );
  end if;

  if v_code is not null then
    update public.discount_codes
    set redemption_count = redemption_count + 1
    where code = v_code;
  end if;

  update public.profiles
  set
    plan_id = v_plan.id,
    plan_started_at = now(),
    plan_expires_at = greatest(now(), coalesce(plan_expires_at, now()))
      + make_interval(months => v_plan.duration_months)
  where id = v_effective_user_id
  returning plan_id, plan_expires_at into v_plan_id, v_expires_at;

  if v_plan_id is null then
    raise exception 'profile not found';
  end if;

  perform public.release_extra_device_slots(
    v_effective_user_id,
    public.registered_device_limit(v_effective_user_id)
  );

  return jsonb_build_object(
    'applied', true,
    'duplicate', false,
    'plan_id', v_plan_id,
    'plan_expires_at', v_expires_at
  );
end;
$$;

revoke all on function public.apply_razorpay_payment(text, text, uuid, uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.apply_razorpay_payment(text, text, uuid, uuid, integer, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Inline Plan Slice in question_listings & pyq_teasers + Fast Practice/Search
-- ---------------------------------------------------------------------------

-- Inlines the plan slice directly inside question_listings (which runs as
-- view owner, security_invoker = false) so PostgreSQL evaluates the caller's
-- plan and profile ONCE per query instead of invoking a non-inlineable
-- SECURITY DEFINER function on every question row.
create or replace view public.question_listings
with (security_invoker = false, security_barrier = false) as
with viewer as (
  select
    pl.id as plan_id,
    pl.access_mode,
    pl.content_depth as depth,
    pl.tease_locked_questions as tease,
    pl.allowed_kinds,
    pl.university_scope,
    pl.allowed_exam_types,
    pl.mbbs_year_scope,
    pl.mbbs_years,
    pl.exam_year_scope,
    pl.exam_years,
    pl.include_untagged,
    pr.university_id,
    (pr.blocked_at is not null) as is_blocked
  from public.profiles pr
  join public.plans pl on pl.id = (
    case
      when pr.blocked_at is not null then (select id from public.plans where code = 'free')
      when pr.plan_suspended_at is not null then (select id from public.plans where code = 'free')
      when pr.plan_expires_at is not null and pr.plan_expires_at < now() then (select id from public.plans where code = 'free')
      else pr.plan_id
    end
  )
  where pr.id = auth.uid()
)
select
  q.id,
  q.lesson_id,
  q.topic_id,
  case when gate.in_slice then q.question_text end as question_text,
  q.marks,
  q.required_plan,
  q.is_active,
  q.kind,
  q.difficulty,
  q.has_direct_answer,
  q.has_explanation,
  q.public_code,
  case when gate.in_slice then q.option_a end as option_a,
  case when gate.in_slice then q.option_b end as option_b,
  case when gate.in_slice then q.option_c end as option_c,
  case when gate.in_slice then q.option_d end as option_d,
  case
    when gate.in_slice and v.depth in ('answer', 'explanation') then q.correct_option
  end as correct_option,
  case
    when gate.in_slice and v.depth = 'explanation' then q.explanation_text
  end as explanation_text,
  case
    when gate.in_slice and v.depth = 'explanation' then q.explanation_deep
  end as explanation_deep,
  case
    when gate.in_slice and v.depth = 'explanation' then q.explanation_video_url
  end as explanation_video_url,
  case when gate.in_slice then q.image_url end as image_url,
  case
    when gate.in_slice and v.depth in ('answer', 'explanation') then nullif(btrim(sa.body), '')
  end as sample_answer,
  (not gate.in_slice) as is_locked,
  q.is_preview,
  (gate.in_slice and v.depth in ('answer', 'explanation')) as answers_visible,
  (gate.in_slice and v.depth = 'explanation') as explanation_visible
from public.questions q
join viewer v on not v.is_blocked
join lateral (
  select (
    q.is_preview
    or (
      v.access_mode = 'filtered'
      and q.kind::text = any (v.allowed_kinds)
      and (
        (
          v.include_untagged
          and not exists (
            select 1
            from public.question_appearances qa
            where qa.question_id = q.id
          )
        )
        or exists (
          select 1
          from public.question_appearances qa
          join public.exam_papers ep on ep.id = qa.exam_paper_id
          join public.subjects s on s.id = ep.subject_id
          left join public.mbbs_phases ph on ph.id = s.mbbs_phase_id
          where qa.question_id = q.id
            and ep.exam_type = any (v.allowed_exam_types)
            and (
              v.university_scope = 'all'
              or ep.university_id = v.university_id
            )
            and (
              v.mbbs_year_scope = 'all'
              or ph.code::text = any (v.mbbs_years)
            )
            and (
              v.exam_year_scope = 'all'
              or (
                v.exam_year_scope = 'selected'
                and ep.exam_year = any (v.exam_years)
              )
              or (
                v.exam_year_scope = 'latest'
                and ep.exam_year = (
                  select max(ep2.exam_year)
                  from public.exam_papers ep2
                  join public.subjects s2 on s2.id = ep2.subject_id
                  left join public.mbbs_phases ph2 on ph2.id = s2.mbbs_phase_id
                  where ep2.subject_id = ep.subject_id
                    and ep2.exam_type = any (v.allowed_exam_types)
                    and (
                      v.university_scope = 'all'
                      or ep2.university_id = v.university_id
                    )
                    and (
                      v.mbbs_year_scope = 'all'
                      or ph2.code::text = any (v.mbbs_years)
                    )
                )
              )
            )
        )
      )
    )
  ) as in_slice
) gate on true
left join public.question_sample_answers sa on sa.question_id = q.id
where q.is_active
  and (gate.in_slice or v.tease);

-- Drop security_barrier on pyq_teasers so id/lesson filters push down cleanly.
create or replace view public.pyq_teasers
with (security_invoker = true, security_barrier = false) as
select
  q.id,
  q.lesson_id,
  q.topic_id,
  q.question_text,
  q.marks,
  q.required_plan,
  q.is_active,
  (
    select count(*)::int
    from public.question_appearances a
    where a.question_id = q.id
  ) as appearance_count,
  q.kind,
  q.difficulty,
  q.has_direct_answer,
  q.has_explanation,
  q.public_code,
  q.is_locked
from public.question_listings q;

-- Practice session generator: row-locks caller profile (prevents daily quota
-- TOCTOU bypass), blocks banned users, enforces allow_tutor_mode on reading
-- mode, and evaluates plan slice inline instead of per-row SECURITY DEFINER.
create or replace function public.create_practice_session(
  p_topic_ids uuid[],
  p_tag_ids uuid[],
  p_difficulties public.question_difficulty[],
  p_source_filter text,
  p_question_count int,
  p_feedback_timing text,
  p_explanation_level text,
  p_timer_minutes int,
  p_negative_marking boolean,
  p_lesson_ids uuid[] default null,
  p_subject_ids uuid[] default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_plan public.plans%rowtype;
  v_plan_id uuid;
  v_test_id uuid;
  v_effective_count int;
  v_effective_explanation text;
  v_used_today int;
  v_topic_ids uuid[];
  v_lesson_ids uuid[];
  v_subject_ids uuid[];
  v_tag_ids uuid[];
  v_difficulties public.question_difficulty[];
  v_timer_minutes int;
  v_negative_marking boolean;
  v_actual_count int;
  v_university_id uuid;
  v_blocked boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_source_filter is null
     or p_source_filter not in ('unattempted', 'incorrect', 'bookmarked', 'all') then
    raise exception 'INVALID_SOURCE_FILTER';
  end if;

  if p_feedback_timing is null
     or p_feedback_timing not in ('immediate', 'on_submit', 'reading') then
    raise exception 'INVALID_FEEDBACK_TIMING';
  end if;

  if p_explanation_level is null
     or p_explanation_level not in ('none', 'answer_only', 'full') then
    raise exception 'INVALID_EXPLANATION_LEVEL';
  end if;

  if p_question_count is null or p_question_count < 1 then
    raise exception 'INVALID_QUESTION_COUNT';
  end if;

  -- Serialize concurrent practice creation per user so daily quota checks
  -- cannot race.
  select p.university_id, (p.blocked_at is not null)
    into v_university_id, v_blocked
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_blocked, false) then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  v_plan_id := public.current_plan_id(v_uid);
  select * into v_plan from public.plans where id = v_plan_id;
  if not found then
    raise exception 'PLAN_LIMITS_MISSING';
  end if;

  if not v_plan.allow_practice or v_plan.content_depth = 'stem' then
    raise exception 'PRACTICE_NOT_ON_PLAN';
  end if;

  if p_feedback_timing in ('immediate', 'reading') and not v_plan.allow_tutor_mode then
    raise exception 'TUTOR_MODE_NOT_ON_PLAN';
  end if;

  if p_feedback_timing = 'on_submit' and not v_plan.allow_exam_mode then
    raise exception 'EXAM_MODE_NOT_ON_PLAN';
  end if;

  if v_plan.max_practice_session_questions is null then
    v_effective_count := p_question_count;
  else
    v_effective_count := least(p_question_count, v_plan.max_practice_session_questions);
  end if;

  v_effective_explanation := case
    when p_explanation_level = 'full' and v_plan.content_depth <> 'explanation' then
      case when v_plan.content_depth = 'answer' then 'answer_only' else 'none' end
    when p_explanation_level = 'answer_only' and v_plan.content_depth = 'stem' then 'none'
    else p_explanation_level
  end;

  v_topic_ids := case
    when p_topic_ids is null or cardinality(p_topic_ids) = 0 then null
    else p_topic_ids
  end;

  v_lesson_ids := case
    when p_lesson_ids is null or cardinality(p_lesson_ids) = 0 then null
    else p_lesson_ids
  end;

  v_subject_ids := case
    when p_subject_ids is null or cardinality(p_subject_ids) = 0 then null
    else p_subject_ids
  end;

  if v_topic_ids is not null then
    v_subject_ids := null;
  end if;

  if v_plan.allow_tag_filter then
    v_tag_ids := case
      when p_tag_ids is null or cardinality(p_tag_ids) = 0 then null
      else p_tag_ids
    end;
  else
    v_tag_ids := null;
  end if;

  if v_plan.allow_difficulty_filter then
    v_difficulties := case
      when p_difficulties is null or cardinality(p_difficulties) = 0 then null
      else p_difficulties
    end;
  else
    v_difficulties := null;
  end if;

  if v_plan.allow_timer_toggle then
    v_timer_minutes := p_timer_minutes;
  else
    v_timer_minutes := coalesce(p_timer_minutes, v_effective_count);
  end if;

  if v_plan.allow_negative_marking_toggle then
    v_negative_marking := coalesce(p_negative_marking, false);
  else
    v_negative_marking := false;
  end if;

  if p_feedback_timing = 'reading' then
    v_timer_minutes := null;
    v_negative_marking := false;
  end if;

  if v_plan.daily_practice_question_quota is not null then
    select coalesce(questions_used, 0) into v_used_today
    from public.daily_practice_usage
    where user_id = v_uid and usage_date = current_date;

    if coalesce(v_used_today, 0) + v_effective_count > v_plan.daily_practice_question_quota then
      v_effective_count := greatest(
        v_plan.daily_practice_question_quota - coalesce(v_used_today, 0),
        0
      );
    end if;

    if v_effective_count <= 0 then
      raise exception 'DAILY_PRACTICE_QUOTA_EXCEEDED';
    end if;
  end if;

  insert into public.tests (
    title, test_type, required_plan, total_duration_minutes, total_questions,
    correct_marks, incorrect_marks, unattempted_marks, is_active,
    owner_user_id, is_ephemeral_practice, feedback_timing, show_explanation_level,
    timer_enabled, practice_filter_criteria
  ) values (
    'Practice Session', 'mini', 'free',
    coalesce(v_timer_minutes, 0), v_effective_count,
    case when v_negative_marking then 4 else 1 end,
    case when v_negative_marking then -1 else 0 end,
    0, false,
    v_uid, true, p_feedback_timing, v_effective_explanation,
    v_timer_minutes is not null,
    jsonb_build_object(
      'topic_ids', to_jsonb(v_topic_ids),
      'lesson_ids', to_jsonb(v_lesson_ids),
      'subject_ids', to_jsonb(v_subject_ids),
      'tag_ids', to_jsonb(v_tag_ids),
      'difficulties', to_jsonb(v_difficulties),
      'source_filter', p_source_filter,
      'requested_question_count', p_question_count,
      'requested_explanation_level', p_explanation_level,
      'negative_marking', v_negative_marking,
      'timer_minutes', v_timer_minutes,
      'university_id', v_university_id
    )
  ) returning id into v_test_id;

  insert into public.test_questions (test_id, question_id, section_number, order_index)
  select v_test_id, q.id, 1, row_number() over (order by random())
  from public.questions q
  where q.is_active
    and q.kind = 'mcq'
    and (
      q.is_preview
      or (
        v_plan.access_mode = 'filtered'
        and 'mcq' = any (v_plan.allowed_kinds)
        and (
          (
            v_plan.include_untagged
            and not exists (
              select 1
              from public.question_appearances qa
              where qa.question_id = q.id
            )
          )
          or exists (
            select 1
            from public.question_appearances qa
            join public.exam_papers ep on ep.id = qa.exam_paper_id
            join public.subjects s on s.id = ep.subject_id
            left join public.mbbs_phases ph on ph.id = s.mbbs_phase_id
            where qa.question_id = q.id
              and ep.exam_type = any (v_plan.allowed_exam_types)
              and (
                v_plan.university_scope = 'all'
                or ep.university_id = v_university_id
              )
              and (
                v_plan.mbbs_year_scope = 'all'
                or ph.code::text = any (v_plan.mbbs_years)
              )
              and (
                v_plan.exam_year_scope = 'all'
                or (
                  v_plan.exam_year_scope = 'selected'
                  and ep.exam_year = any (v_plan.exam_years)
                )
                or (
                  v_plan.exam_year_scope = 'latest'
                  and ep.exam_year = (
                    select max(ep2.exam_year)
                    from public.exam_papers ep2
                    join public.subjects s2 on s2.id = ep2.subject_id
                    left join public.mbbs_phases ph2 on ph2.id = s2.mbbs_phase_id
                    where ep2.subject_id = ep.subject_id
                      and ep2.exam_type = any (v_plan.allowed_exam_types)
                      and (
                        v_plan.university_scope = 'all'
                        or ep2.university_id = v_university_id
                      )
                      and (
                        v_plan.mbbs_year_scope = 'all'
                        or ph2.code::text = any (v_plan.mbbs_years)
                      )
                  )
                )
              )
          )
        )
      )
    )
    and (
      case
        when v_topic_ids is not null then
          q.topic_id = any(v_topic_ids)
          or exists (
            select 1 from public.lessons l
            where l.id = q.lesson_id
              and l.topic_id = any(v_topic_ids)
          )
        when v_subject_ids is not null then
          exists (
            select 1 from public.topics tp
            where tp.id = q.topic_id
              and tp.subject_id = any(v_subject_ids)
          )
          or exists (
            select 1
            from public.lessons l
            join public.topics tp on tp.id = l.topic_id
            where l.id = q.lesson_id
              and tp.subject_id = any(v_subject_ids)
          )
          or exists (
            select 1
            from public.question_appearances qa
            join public.exam_papers ep on ep.id = qa.exam_paper_id
            where qa.question_id = q.id
              and ep.subject_id = any(v_subject_ids)
          )
        else true
      end
    )
    and (v_lesson_ids is null or q.lesson_id = any(v_lesson_ids))
    and (v_difficulties is null or q.difficulty = any(v_difficulties))
    and (v_tag_ids is null or exists (
          select 1 from public.question_tags qt
          where qt.question_id = q.id and qt.tag_id = any(v_tag_ids)))
    and (
      p_source_filter = 'all'
      or (p_source_filter = 'bookmarked' and exists (
            select 1 from public.bookmarks b
            where b.question_id = q.id and b.user_id = v_uid))
      or (p_source_filter = 'incorrect' and exists (
            select 1 from public.attempt_answers aa
            join public.attempts a on a.id = aa.attempt_id
            where a.user_id = v_uid
              and aa.question_id = q.id
              and aa.selected_option is distinct from q.correct_option))
      or (p_source_filter = 'unattempted' and not exists (
            select 1 from public.attempt_answers aa
            join public.attempts a on a.id = aa.attempt_id
            where a.user_id = v_uid
              and aa.question_id = q.id
              and aa.selected_option is not null))
    )
  order by random()
  limit v_effective_count;

  get diagnostics v_actual_count = row_count;

  if v_actual_count = 0 then
    delete from public.tests where id = v_test_id;
    raise exception 'NO_QUESTIONS_MATCH_FILTERS';
  end if;

  if v_actual_count <> v_effective_count then
    update public.tests
    set total_questions = v_actual_count
    where id = v_test_id;
  end if;

  insert into public.daily_practice_usage (user_id, usage_date, questions_used)
  values (v_uid, current_date, v_actual_count)
  on conflict (user_id, usage_date) do update
    set questions_used = public.daily_practice_usage.questions_used + v_actual_count;

  return v_test_id;
end;
$$;

revoke all on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) from public, anon;
grant execute on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) to authenticated;

-- Escape ILIKE wildcards and filter stem text BEFORE running plan slice checks.
create or replace function public.search_catalog(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw text := trim(coalesce(p_query, ''));
  v_escaped text;
  v_q text;
  v_plan_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if char_length(v_raw) < 2 then
    return jsonb_build_object(
      'subjects', '[]'::jsonb,
      'lessons', '[]'::jsonb,
      'questions', '[]'::jsonb
    );
  end if;

  v_escaped := replace(replace(replace(v_raw, '\', '\\'), '%', '\%'), '_', '\_');
  v_q := '%' || v_escaped || '%';
  v_plan_id := public.current_plan_id(auth.uid());

  return jsonb_build_object(
    'subjects', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name))
      from public.subjects s
      where s.name ilike v_q escape '\'
    ), '[]'::jsonb),
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'required_plan', m.required_plan
      ))
      from (
        select l.id, l.name, l.required_plan
        from public.lessons l
        where l.is_active
          and l.name ilike v_q escape '\'
          and public.plan_allows_lesson(v_plan_id, l.id, auth.uid())
        order by l.name
        limit 20
      ) m
    ), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mq.id,
        'question_text', mq.question_text,
        'lesson_id', mq.lesson_id,
        'required_plan', mq.required_plan,
        'is_locked', false
      ))
      from (
        select q.id, q.question_text, q.lesson_id, q.required_plan
        from public.questions q
        where q.is_active
          and q.question_text ilike v_q escape '\'
          and public.plan_allows_question(v_plan_id, q.id, auth.uid())
        limit 20
      ) mq
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.search_catalog(text) from public, anon;
grant execute on function public.search_catalog(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Single-Query get_study_progress & University Coverage RPC
-- ---------------------------------------------------------------------------

create or replace function public.get_study_progress()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phase uuid;
  v_university uuid;
  v_streak int := 0;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select mbbs_phase_id, university_id
    into v_phase, v_university
  from public.profiles
  where id = v_uid;

  -- Compute consecutive streak days in one index-friendly query instead of an
  -- N+1 per-day PL/pgSQL loop.
  with active_days as (
    select distinct (e.created_at at time zone 'UTC')::date as d
    from public.study_events e
    where e.user_id = v_uid
      and e.created_at <= now() + interval '1 day'
  ),
  anchor as (
    select case
      when exists (select 1 from active_days where d = current_date) then current_date
      when exists (select 1 from active_days where d = current_date - 1) then current_date - 1
      else null::date
    end as start_day
  ),
  numbered as (
    select
      ad.d,
      (a.start_day - ad.d) as diff,
      row_number() over (order by ad.d desc) - 1 as rn
    from active_days ad
    join anchor a on a.start_day is not null and ad.d <= a.start_day
  )
  select count(*)::int
    into v_streak
  from numbered
  where diff = rn;

  return jsonb_build_object(
    'streak', coalesce(v_streak, 0),
    'days7', coalesce((
      with counts as (
        select (e.created_at)::date as d, count(*)::int as c
        from public.study_events e
        where e.user_id = v_uid
          and e.created_at >= (current_date - 6)::timestamptz
        group by (e.created_at)::date
      )
      select jsonb_agg(jsonb_build_object('date', gs::date::text, 'count', coalesce(counts.c, 0)) order by gs)
      from generate_series(current_date - 6, current_date, interval '1 day') gs
      left join counts on counts.d = gs::date
    ), '[]'::jsonb),
    'days30', coalesce((
      with counts as (
        select (e.created_at)::date as d, count(*)::int as c
        from public.study_events e
        where e.user_id = v_uid
          and e.created_at >= (current_date - 29)::timestamptz
        group by (e.created_at)::date
      )
      select jsonb_agg(jsonb_build_object('date', gs::date::text, 'count', coalesce(counts.c, 0)) order by gs)
      from generate_series(current_date - 29, current_date, interval '1 day') gs
      left join counts on counts.d = gs::date
    ), '[]'::jsonb),
    'subjects', coalesce((
      with pyq_counts as (
        select ep.subject_id, count(distinct q.id)::int as total_pyqs
        from public.exam_papers ep
        join public.question_appearances qa on qa.exam_paper_id = ep.id
        join public.questions q on q.id = qa.question_id and q.is_active
        group by ep.subject_id
      ),
      uni_lessons as (
        select distinct tp.subject_id, l.id as lesson_id
        from public.lessons l
        join public.topics tp on tp.id = l.topic_id
        where l.is_active
          and v_university is not null
          and exists (
            select 1
            from public.questions q
            join public.question_appearances qa on qa.question_id = q.id
            join public.exam_papers ep on ep.id = qa.exam_paper_id
            where q.lesson_id = l.id
              and ep.university_id = v_university
          )
      ),
      lesson_stats as (
        select
          ul.subject_id,
          count(*)::int as total_lessons,
          count(lp.lesson_id)::int as learnt_lessons
        from uni_lessons ul
        left join public.lesson_progress lp
          on lp.lesson_id = ul.lesson_id
         and lp.user_id = v_uid
         and lp.learnt_at is not null
        group by ul.subject_id
      )
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'learnt_lessons', coalesce(ls.learnt_lessons, 0),
        'total_lessons', coalesce(ls.total_lessons, 0),
        'total_pyqs', coalesce(pc.total_pyqs, 0)
      ) order by s.display_order)
      from public.subjects s
      left join pyq_counts pc on pc.subject_id = s.id
      left join lesson_stats ls on ls.subject_id = s.id
      where v_phase is null or s.mbbs_phase_id = v_phase
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_study_progress() from public, anon;
grant execute on function public.get_study_progress() to authenticated;

-- Validate announcement deep_link format on admin save.
create or replace function public.admin_upsert_announcement(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_title text := nullif(btrim(coalesce(p_body->>'title', '')), '');
  v_body text := nullif(btrim(coalesce(p_body->>'body', '')), '');
  v_category text := lower(btrim(coalesce(p_body->>'category', 'general')));
  v_deep_link text := nullif(btrim(coalesce(p_body->>'deep_link', '')), '');
  v_active boolean := coalesce((p_body->>'is_active')::boolean, false);
  v_expires timestamptz := nullif(p_body->>'expires_at', '')::timestamptz;
  v_was_active boolean;
begin
  perform public.assert_admin();

  if v_title is null then
    raise exception 'Title is required.';
  end if;
  if v_body is null then
    raise exception 'Body is required.';
  end if;
  if v_category not in ('general', 'version', 'offer', 'payment') then
    raise exception 'Category must be general, version, offer, or payment.';
  end if;
  if v_deep_link is not null and (
    v_deep_link !~ '^/[A-Za-z0-9/_?=&%-]*$'
    or v_deep_link ~ '^//'
    or v_deep_link ~ '^/admin(/|$)'
  ) then
    raise exception 'Deep link must be an in-app student path starting with /.';
  end if;

  if v_id is null then
    insert into public.announcements (
      title, body, category, deep_link, is_active, published_at, expires_at
    ) values (
      v_title, v_body, v_category, v_deep_link, v_active, now(), v_expires
    )
    returning id into v_id;
  else
    select is_active into v_was_active
    from public.announcements
    where id = v_id;

    if v_was_active is null then
      raise exception 'Announcement not found.';
    end if;

    update public.announcements
    set
      title = v_title,
      body = v_body,
      category = v_category,
      deep_link = v_deep_link,
      is_active = v_active,
      expires_at = v_expires,
      published_at = case
        when v_active and not v_was_active then now()
        else published_at
      end
    where id = v_id;
  end if;

  perform public.admin_log_action(
    'upsert_announcement',
    v_id,
    jsonb_build_object('is_active', v_active, 'category', v_category)
  );

  return (
    select jsonb_build_object(
      'id', a.id,
      'title', a.title,
      'body', a.body,
      'category', a.category,
      'deep_link', a.deep_link,
      'is_active', a.is_active,
      'published_at', a.published_at,
      'expires_at', a.expires_at,
      'created_at', a.created_at
    )
    from public.announcements a
    where a.id = v_id
  );
end;
$$;

revoke all on function public.admin_upsert_announcement(jsonb) from public, anon;
grant execute on function public.admin_upsert_announcement(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Function search_path, Privilege Revocations & Missing Hot-Path Indexes
-- ---------------------------------------------------------------------------

create or replace function public.questions_sync_preview()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.is_preview := new.required_plan = 'free'::public.plan_tier;
  return new;
end;
$$;

create or replace function public.plan_rank(p public.plan_tier)
returns int
language sql
immutable
set search_path = public
as $$
  select case p
    when 'free' then 0
    when 'pro' then 1
    when 'elite' then 1
  end;
$$;

create or replace function public.server_now()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select now();
$$;

revoke all on function public.plan_rank(public.plan_tier) from public, anon;
grant execute on function public.plan_rank(public.plan_tier) to authenticated, service_role;

revoke all on function public.server_now() from public, anon;
grant execute on function public.server_now() to authenticated, service_role;

revoke all on function public.mark_lesson_learnt(uuid) from public, anon;
grant execute on function public.mark_lesson_learnt(uuid) to authenticated;

revoke all on function public.mark_question_learnt(uuid) from public, anon;
grant execute on function public.mark_question_learnt(uuid) to authenticated;

revoke all on function public.record_study_event(public.study_event_kind, uuid, uuid) from public, anon;
grant execute on function public.record_study_event(public.study_event_kind, uuid, uuid) to authenticated;

revoke all on function public.get_attempt_results(uuid) from public, anon;
grant execute on function public.get_attempt_results(uuid) to authenticated;

-- Indexes on hot RLS, practice filter, percentile, and cleanup paths.
create index if not exists idx_tests_owner_user
  on public.tests (owner_user_id)
  where owner_user_id is not null;

create index if not exists idx_attempt_answers_question
  on public.attempt_answers (question_id);

create index if not exists idx_test_questions_question
  on public.test_questions (question_id);

create index if not exists idx_attempts_test_submitted_score
  on public.attempts (test_id, total_score)
  where status = 'submitted';

create index if not exists idx_whatsapp_challenges_pending_expires
  on public.whatsapp_auth_challenges (expires_at)
  where status = 'pending';

create index if not exists idx_questions_created_at
  on public.questions (created_at desc);

create extension if not exists pg_trgm with schema extensions;

create index if not exists idx_questions_stem_trgm
  on public.questions
  using gin (question_text extensions.gin_trgm_ops)
  where is_active;
