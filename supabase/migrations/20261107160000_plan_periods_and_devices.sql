-- Pro and Elite unlock the same question bank (answers included).
-- They differ by registered-device slots: Pro 1, Elite 2.
-- Checkout sells a period (y1–y4). Longer periods add free months.
-- The client never sends an amount. paid_plan_catalog is the list price.

-- ---------------------------------------------------------------------------
-- Content rank: paid plans are equal. Device slots are not a content gate.
-- ---------------------------------------------------------------------------

create or replace function public.plan_rank(p public.plan_tier)
returns int
language sql
immutable
as $$
  select case p
    when 'free' then 0
    when 'pro' then 1
    when 'elite' then 1
  end;
$$;

comment on function public.plan_rank(public.plan_tier) is
  'Content access: free 0, Pro and Elite both 1. Elite is extra device slots, not extra questions.';

-- ---------------------------------------------------------------------------
-- Practice limits match between Pro and Elite. Slots live on this row.
-- ---------------------------------------------------------------------------

alter table public.plan_limits
  add column if not exists max_registered_devices integer not null default 1;

update public.plan_limits
set max_registered_devices = 2
where plan = 'elite';

update public.plan_limits
set
  max_practice_session_questions = (
    select p.max_practice_session_questions
    from public.plan_limits p
    where p.plan = 'pro'
  ),
  daily_practice_question_quota = (
    select p.daily_practice_question_quota
    from public.plan_limits p
    where p.plan = 'pro'
  ),
  allow_full_explanation = true,
  allow_timer_toggle = true,
  allow_tag_filter = true,
  allow_difficulty_filter = true,
  allow_negative_marking_toggle = true
where plan = 'elite';

comment on column public.plan_limits.max_registered_devices is
  'How many installs may use this plan at once. Pro 1, Elite 2, Free 1.';

-- ---------------------------------------------------------------------------
-- Registered slots. A row with registered_at set occupies one slot.
-- Lifetime first_seen stays for support. Exceeding the cap does not suspend.
-- ---------------------------------------------------------------------------

alter table public.device_claims
  add column if not exists registered_at timestamptz,
  add column if not exists session_id uuid;

comment on column public.device_claims.registered_at is
  'Set while this install occupies one of the plan''s device slots.';

with ranked as (
  select
    user_id,
    device_id,
    last_seen_at,
    row_number() over (
      partition by user_id
      order by last_seen_at desc
    ) as rn
  from public.device_claims
),
caps as (
  select
    p.id as user_id,
    coalesce(
      (
        select l.max_registered_devices
        from public.plan_limits l
        where l.plan = public.current_plan(p.id)
      ),
      1
    ) as max_devices
  from public.profiles p
)
update public.device_claims d
set registered_at = r.last_seen_at
from ranked r
join caps c on c.user_id = r.user_id
where d.user_id = r.user_id
  and d.device_id = r.device_id
  and r.rn <= c.max_devices
  and d.registered_at is null;

-- ---------------------------------------------------------------------------
-- claim / assert: fill a free slot, or refuse this install.
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
  v_session_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if v_device is null or char_length(v_device) > 128 then
    raise exception 'INVALID_DEVICE_ID';
  end if;

  if exists (
    select 1 from public.profiles where id = v_uid and is_admin
  ) then
    return jsonb_build_object(
      'ok', true,
      'device_limit', false,
      'max_devices', 0,
      'suspended', false,
      'just_suspended', false,
      'distinct_device_count', 0
    );
  end if;

  select coalesce(l.max_registered_devices, 1)
  into v_max
  from public.plan_limits l
  where l.plan = public.current_plan(v_uid);

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
      -- This install does not get a slot. Drop its session so the
      -- registered phones keep working.
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

  -- Pro (and Free) are one device: end every other session.
  -- Elite keeps the other registered phone signed in.
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

  select plan_suspended_at is not null
  into v_suspended
  from public.profiles
  where id = v_uid;

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

comment on function public.claim_active_device(text) is
  'Registers this install if the plan has a free device slot. Pro 1, Elite 2. Does not suspend the plan.';

create or replace function public.assert_active_device(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := nullif(btrim(p_device_id), '');
begin
  if v_uid is null then
    return false;
  end if;

  if exists (
    select 1 from public.profiles where id = v_uid and is_admin
  ) then
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

  -- No slot has been taken yet (legacy session before the first claim).
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

comment on function public.assert_active_device(text) is
  'True when this install occupies a registered slot, or no slot is taken yet.';

-- ---------------------------------------------------------------------------
-- Catalog: one list price per plan and period.
-- y1 = 12 months, y2 = 25, y3 = 38, y4 = 51.
-- Seed: 1-year price times the year count. Extra months are not charged.
-- Drop callers first so the column change is allowed.
-- ---------------------------------------------------------------------------

drop function if exists public.checkout_quote(text, text);
drop function if exists public.apply_razorpay_payment(
  text, text, uuid, public.plan_tier, integer, text, text
);
drop function if exists public.paid_plan_terms(public.plan_tier);

alter table public.paid_plan_catalog
  add column if not exists period text,
  add column if not exists duration_months integer;

delete from public.paid_plan_catalog;

alter table public.paid_plan_catalog
  drop constraint if exists paid_plan_catalog_pkey;

alter table public.paid_plan_catalog
  drop constraint if exists paid_plan_catalog_duration;

alter table public.paid_plan_catalog
  drop column if exists duration_days;

alter table public.paid_plan_catalog
  alter column period set not null,
  alter column duration_months set not null;

alter table public.paid_plan_catalog
  add constraint paid_plan_catalog_pkey primary key (plan, period);

alter table public.paid_plan_catalog
  drop constraint if exists paid_plan_catalog_period;

alter table public.paid_plan_catalog
  add constraint paid_plan_catalog_period
  check (period in ('y1', 'y2', 'y3', 'y4'));

alter table public.paid_plan_catalog
  drop constraint if exists paid_plan_catalog_months;

alter table public.paid_plan_catalog
  add constraint paid_plan_catalog_months
  check (duration_months >= 1);

comment on table public.paid_plan_catalog is
  'List price for Pro or Elite and a billing period. amount_paise is rupees times 100. Students can read; only the SQL editor / service role can change a row.';

comment on column public.paid_plan_catalog.duration_months is
  'Months added to plan_expires_at. y2/y3/y4 include the free extra months.';

insert into public.paid_plan_catalog (plan, period, amount_paise, duration_months) values
  ('pro', 'y1', 149900, 12),
  ('pro', 'y2', 299800, 25),
  ('pro', 'y3', 449700, 38),
  ('pro', 'y4', 599600, 51),
  ('elite', 'y1', 299900, 12),
  ('elite', 'y2', 599800, 25),
  ('elite', 'y3', 899700, 38),
  ('elite', 'y4', 1199600, 51);

create function public.paid_plan_terms(
  p_plan public.plan_tier,
  p_period text
)
returns table (amount_paise integer, duration_months integer)
language sql
stable
set search_path = public
as $$
  select c.amount_paise, c.duration_months
  from public.paid_plan_catalog c
  where c.plan = p_plan
    and c.period = p_period
    and c.plan in ('pro'::public.plan_tier, 'elite'::public.plan_tier)
    and c.period in ('y1', 'y2', 'y3', 'y4');
$$;

revoke all on function public.paid_plan_terms(public.plan_tier, text) from public;
revoke all on function public.paid_plan_terms(public.plan_tier, text) from anon, authenticated;

comment on function public.paid_plan_terms(public.plan_tier, text) is
  'List price and month count for one plan and period, from paid_plan_catalog.';

-- ---------------------------------------------------------------------------
-- Quote. Students may ask for a price. They cannot set one.
-- ---------------------------------------------------------------------------

create function public.checkout_quote(
  p_plan text,
  p_code text default null,
  p_period text default 'y1'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan public.plan_tier;
  v_period text;
  v_list integer;
  v_months integer;
  v_code text;
  v_percent integer;
  v_owner uuid;
  v_max integer;
  v_count integer;
  v_expires timestamptz;
  v_active boolean;
  v_amount integer;
begin
  if v_user_id is null then
    raise exception 'Sign in to continue.';
  end if;

  if p_plan is null or p_plan not in ('pro', 'elite') then
    raise exception 'Choose Pro or Elite.';
  end if;
  v_plan := p_plan::public.plan_tier;

  v_period := lower(btrim(coalesce(p_period, 'y1')));
  if v_period not in ('y1', 'y2', 'y3', 'y4') then
    raise exception 'Choose 1, 2, 3, or 4 years.';
  end if;

  select amount_paise, duration_months
    into v_list, v_months
  from public.paid_plan_terms(v_plan, v_period);

  if v_list is null then
    raise exception 'Choose Pro or Elite.';
  end if;

  v_code := public.normalize_discount_code(p_code);
  if p_code is null or length(trim(p_code)) = 0 then
    return jsonb_build_object(
      'plan', v_plan,
      'period', v_period,
      'duration_months', v_months,
      'code', null,
      'percent_off', null,
      'list_amount_paise', v_list,
      'amount_paise', v_list,
      'currency', 'INR'
    );
  end if;

  if v_code is null then
    raise exception 'That code is not valid.';
  end if;

  select percent_off, owner_user_id, max_redemptions, redemption_count,
         expires_at, active
    into v_percent, v_owner, v_max, v_count, v_expires, v_active
  from public.discount_codes
  where code = v_code;

  if v_percent is null or v_active is not true then
    raise exception 'That code is not valid.';
  end if;
  if v_expires is not null and v_expires <= now() then
    raise exception 'That code has expired.';
  end if;
  if v_max is not null and v_count >= v_max then
    raise exception 'That code has been used up.';
  end if;
  if v_owner is not null and v_owner = v_user_id then
    raise exception 'Referral codes cannot be used on your own payment.';
  end if;

  if exists (
    select 1
    from public.payments
    where user_id = v_user_id
      and discount_code = v_code
  ) then
    raise exception 'You already used this code.';
  end if;

  v_amount := public.discounted_amount_paise(v_list, v_percent);
  if v_amount < 100 or v_amount >= v_list then
    raise exception 'That discount is too large for this plan.';
  end if;

  return jsonb_build_object(
    'plan', v_plan,
    'period', v_period,
    'duration_months', v_months,
    'code', v_code,
    'percent_off', v_percent,
    'list_amount_paise', v_list,
    'amount_paise', v_amount,
    'currency', 'INR'
  );
end;
$$;

comment on function public.checkout_quote(text, text, text) is
  'List or discounted price for one plan and period. Does not create a charge.';

revoke all on function public.checkout_quote(text, text, text) from public;
revoke all on function public.checkout_quote(text, text, text) from anon;
grant execute on function public.checkout_quote(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Grant. Period in the notes picks the row. A missing period matches the
-- unique catalog row whose (discounted) paise equal the captured amount.
-- ---------------------------------------------------------------------------

alter table public.payments
  add column if not exists billing_period text;

alter table public.payments
  drop constraint if exists payments_billing_period;

alter table public.payments
  add constraint payments_billing_period
  check (
    billing_period is null
    or billing_period in ('y1', 'y2', 'y3', 'y4')
  );

create function public.apply_razorpay_payment(
  p_payment_id text,
  p_order_id text,
  p_user_id uuid,
  p_plan public.plan_tier,
  p_amount_paise integer,
  p_currency text,
  p_discount_code text default null,
  p_period text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount_paise integer;
  v_duration_months integer;
  v_expected integer;
  v_code text;
  v_percent integer;
  v_period text;
  v_matches integer := 0;
  v_inserted text;
  v_expires_at timestamptz;
  v_plan public.plan_tier;
  r record;
begin
  if p_payment_id is null or length(trim(p_payment_id)) = 0 then
    raise exception 'payment id required';
  end if;
  if p_order_id is null or length(trim(p_order_id)) = 0 then
    raise exception 'order id required';
  end if;
  if p_user_id is null then
    raise exception 'user id required';
  end if;
  if p_plan is null or p_plan not in ('pro', 'elite') then
    raise exception 'unsupported plan';
  end if;

  v_period := nullif(lower(btrim(coalesce(p_period, ''))), '');
  if v_period is not null and v_period not in ('y1', 'y2', 'y3', 'y4') then
    raise exception 'amount does not match catalog';
  end if;

  v_code := public.normalize_discount_code(p_discount_code);
  if p_discount_code is null or length(trim(p_discount_code)) = 0 then
    v_code := null;
    v_percent := null;
  else
    if v_code is null then
      raise exception 'amount does not match catalog';
    end if;
    select percent_off
      into v_percent
    from public.discount_codes
    where code = v_code;
    if v_percent is null then
      raise exception 'amount does not match catalog';
    end if;
  end if;

  if v_period is not null then
    select amount_paise, duration_months
      into v_amount_paise, v_duration_months
    from public.paid_plan_terms(p_plan, v_period);

    if v_amount_paise is null then
      raise exception 'unsupported plan';
    end if;

    if v_percent is null then
      v_expected := v_amount_paise;
    else
      v_expected := public.discounted_amount_paise(v_amount_paise, v_percent);
    end if;

    if p_amount_paise is distinct from v_expected then
      raise exception 'amount does not match catalog';
    end if;
  else
    for r in
      select c.period, c.amount_paise, c.duration_months
      from public.paid_plan_catalog c
      where c.plan = p_plan
    loop
      if v_percent is null then
        v_expected := r.amount_paise;
      else
        v_expected := public.discounted_amount_paise(r.amount_paise, v_percent);
      end if;

      if p_amount_paise = v_expected then
        v_matches := v_matches + 1;
        v_period := r.period;
        v_amount_paise := r.amount_paise;
        v_duration_months := r.duration_months;
      end if;
    end loop;

    if v_matches <> 1 then
      raise exception 'amount does not match catalog';
    end if;
  end if;

  if p_currency is distinct from 'INR' then
    raise exception 'currency does not match catalog';
  end if;

  insert into public.payments (
    razorpay_payment_id,
    razorpay_order_id,
    user_id,
    plan,
    amount_paise,
    currency,
    discount_code,
    list_amount_paise,
    percent_off,
    billing_period
  ) values (
    p_payment_id,
    p_order_id,
    p_user_id,
    p_plan,
    p_amount_paise,
    p_currency,
    v_code,
    v_amount_paise,
    v_percent,
    v_period
  )
  on conflict (razorpay_payment_id) do nothing
  returning razorpay_payment_id into v_inserted;

  if v_inserted is null then
    select pr.plan, pr.plan_expires_at
      into v_plan, v_expires_at
    from public.payments pay
    join public.profiles pr on pr.id = pay.user_id
    where pay.razorpay_payment_id = p_payment_id;

    return jsonb_build_object(
      'applied', false,
      'duplicate', true,
      'plan', v_plan,
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
    plan = p_plan,
    plan_started_at = now(),
    plan_expires_at = greatest(now(), coalesce(plan_expires_at, now()))
      + make_interval(months => v_duration_months)
  where id = p_user_id
  returning plan, plan_expires_at into v_plan, v_expires_at;

  if v_plan is null then
    raise exception 'profile not found';
  end if;

  -- A shorter device cap (Elite → Pro) drops the oldest extra slots.
  with ranked as (
    select
      device_id,
      row_number() over (order by last_seen_at desc) as rn
    from public.device_claims
    where user_id = p_user_id
      and registered_at is not null
  ),
  cap as (
    select max_registered_devices as n
    from public.plan_limits
    where plan = p_plan
  )
  update public.device_claims d
  set registered_at = null,
      session_id = null
  from ranked r, cap
  where d.user_id = p_user_id
    and d.device_id = r.device_id
    and r.rn > cap.n;

  return jsonb_build_object(
    'applied', true,
    'duplicate', false,
    'plan', v_plan,
    'plan_expires_at', v_expires_at,
    'period', v_period
  );
end;
$$;

comment on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text) is
  'Idempotent plan grant after a verified payment.captured webhook. Period and percent come from the catalog and the code row, never from the client amount. Stacks months onto time still left.';

revoke all on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text) from public;
revoke all on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text) from anon, authenticated;
grant execute on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text) to service_role;
