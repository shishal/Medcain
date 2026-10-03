-- Discount and referral codes for Razorpay checkout.
--
-- The browser may send a code. It never sends an amount. checkout_quote()
-- (signed-in students) and apply_razorpay_payment() (webhook only) both
-- price the order from paid_plan_terms() plus the code's percent_off.
--
-- Issue a code in the SQL editor (service_role / postgres), for example:
--   select public.issue_discount_code(
--     p_percent_off => 20,
--     p_owner_user_id => '<profile uuid>',  -- null = promo anyone can enter
--     p_code => 'CAMPUS20'                   -- null = generate a code
--   );
-- The owner sees the code on Profile and shares it. They cannot use it on
-- their own payment. Deactivate with:
--   update public.discount_codes set active = false where code = 'CAMPUS20';
-- Do not change percent_off after issue — an in-flight payment is checked
-- against the percent stored on the row.

-- ---------------------------------------------------------------------------
-- Catalog. scripts/validate_phase7_3_webhook.py reads this if/elsif block.
-- ---------------------------------------------------------------------------

create or replace function public.paid_plan_terms(p_plan public.plan_tier)
returns table (amount_paise integer, duration_days integer)
language plpgsql
immutable
as $$
declare
  v_amount_paise integer;
  v_duration_days integer;
begin
  if p_plan = 'pro' then
    v_amount_paise := 149900;
    v_duration_days := 180;
  elsif p_plan = 'elite' then
    v_amount_paise := 299900;
    v_duration_days := 365;
  else
    return;
  end if;

  amount_paise := v_amount_paise;
  duration_days := v_duration_days;
  return next;
end;
$$;

revoke all on function public.paid_plan_terms(public.plan_tier) from public;
revoke all on function public.paid_plan_terms(public.plan_tier) from anon, authenticated;

-- Half-up to the nearest paise. Razorpay's minimum charge is 100 paise.
create or replace function public.discounted_amount_paise(
  p_list_paise integer,
  p_percent_off integer
) returns integer
language sql
immutable
as $$
  select ((p_list_paise * (100 - p_percent_off)) + 50) / 100;
$$;

revoke all on function public.discounted_amount_paise(integer, integer) from public;
revoke all on function public.discounted_amount_paise(integer, integer) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Codes. Students can read only a code issued to them (the one they share).
-- ---------------------------------------------------------------------------

create table if not exists public.discount_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  percent_off integer not null,
  owner_user_id uuid references public.profiles (id) on delete cascade,
  max_redemptions integer,
  redemption_count integer not null default 0,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint discount_codes_code_format check (code ~ '^[A-Z0-9]{4,16}$'),
  constraint discount_codes_percent check (percent_off between 1 and 99),
  constraint discount_codes_max check (max_redemptions is null or max_redemptions >= 1),
  constraint discount_codes_count check (redemption_count >= 0)
);

create unique index if not exists discount_codes_code_key
  on public.discount_codes (code);

create index if not exists discount_codes_owner_active
  on public.discount_codes (owner_user_id)
  where active and owner_user_id is not null;

alter table public.discount_codes enable row level security;

grant select on table public.discount_codes to authenticated;
grant all on table public.discount_codes to service_role;

drop policy if exists discount_codes_select_own on public.discount_codes;
create policy discount_codes_select_own
  on public.discount_codes
  for select
  to authenticated
  using (owner_user_id = auth.uid());

comment on table public.discount_codes is
  'Checkout percent-off codes. owner_user_id set = referral (owner shares it, cannot redeem it). Null owner = promo anyone signed in can enter.';

-- The payment function can exist without this table if an earlier migration
-- was recorded by hand. Create it before adding discount columns.
create table if not exists public.payments (
  razorpay_payment_id text primary key,
  razorpay_order_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  plan public.plan_tier not null,
  amount_paise integer not null,
  currency text not null,
  applied_at timestamptz not null default now(),
  constraint payments_plan_paid check (plan in ('pro', 'elite')),
  constraint payments_currency_inr check (currency = 'INR')
);

create index if not exists idx_payments_user on public.payments (user_id);

alter table public.payments enable row level security;

grant all on table public.payments to service_role;

alter table public.payments
  add column if not exists discount_code text,
  add column if not exists list_amount_paise integer,
  add column if not exists percent_off integer;

alter table public.payments
  drop constraint if exists payments_discount_percent;

alter table public.payments
  add constraint payments_discount_percent
  check (percent_off is null or percent_off between 1 and 99);

-- ---------------------------------------------------------------------------
-- Normalize "campus-20" → CAMPUS20. Empty / too short / too long → null.
-- ---------------------------------------------------------------------------

create or replace function public.normalize_discount_code(p_code text)
returns text
language sql
immutable
as $$
  select case
    when upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
      ~ '^[A-Z0-9]{4,16}$'
    then upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
    else null
  end;
$$;

revoke all on function public.normalize_discount_code(text) from public;
revoke all on function public.normalize_discount_code(text) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Price a plan for the signed-in student. Optional code.
-- ---------------------------------------------------------------------------

create or replace function public.checkout_quote(
  p_plan text,
  p_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan public.plan_tier;
  v_list integer;
  v_duration integer;
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

  select amount_paise, duration_days
    into v_list, v_duration
  from public.paid_plan_terms(v_plan);

  if v_list is null then
    raise exception 'Choose Pro or Elite.';
  end if;

  v_code := public.normalize_discount_code(p_code);
  if p_code is null or length(trim(p_code)) = 0 then
    return jsonb_build_object(
      'plan', v_plan,
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
    'code', v_code,
    'percent_off', v_percent,
    'list_amount_paise', v_list,
    'amount_paise', v_amount,
    'currency', 'INR'
  );
end;
$$;

comment on function public.checkout_quote(text, text) is
  'List price or discounted price for the signed-in student. Does not create a charge.';

revoke all on function public.checkout_quote(text, text) from public;
revoke all on function public.checkout_quote(text, text) from anon;
grant execute on function public.checkout_quote(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Issue a referral (owner set) or a shared promo (owner null).
-- A new code for the same owner deactivates their previous one.
-- ---------------------------------------------------------------------------

create or replace function public.issue_discount_code(
  p_percent_off integer,
  p_owner_user_id uuid default null,
  p_code text default null,
  p_max_redemptions integer default null,
  p_expires_at timestamptz default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_try integer := 0;
begin
  if p_percent_off is null or p_percent_off < 1 or p_percent_off > 99 then
    raise exception 'percent off must be between 1 and 99';
  end if;
  if p_max_redemptions is not null and p_max_redemptions < 1 then
    raise exception 'max redemptions must be at least 1';
  end if;

  if p_owner_user_id is not null then
    perform 1 from public.profiles where id = p_owner_user_id;
    if not found then
      raise exception 'user not found';
    end if;
    update public.discount_codes
    set active = false
    where owner_user_id = p_owner_user_id
      and active = true;
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    loop
      v_try := v_try + 1;
      v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      exit when not exists (
        select 1 from public.discount_codes where code = v_code
      );
      if v_try > 5 then
        raise exception 'could not generate a code';
      end if;
    end loop;
  else
    v_code := public.normalize_discount_code(p_code);
    if v_code is null then
      raise exception 'code must be 4-16 letters or digits';
    end if;
    if exists (select 1 from public.discount_codes where code = v_code) then
      raise exception 'That code is already issued.';
    end if;
  end if;

  insert into public.discount_codes (
    code,
    percent_off,
    owner_user_id,
    max_redemptions,
    expires_at
  ) values (
    v_code,
    p_percent_off,
    p_owner_user_id,
    p_max_redemptions,
    p_expires_at
  );

  return v_code;
end;
$$;

comment on function public.issue_discount_code(integer, uuid, text, integer, timestamptz) is
  'Create a percent-off code. Owner set = referral they share. Not for clients.';

revoke all on function public.issue_discount_code(integer, uuid, text, integer, timestamptz) from public;
revoke all on function public.issue_discount_code(integer, uuid, text, integer, timestamptz) from anon, authenticated;
grant execute on function public.issue_discount_code(integer, uuid, text, integer, timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- Webhook grant. Same signature as before, plus an optional code. A missing
-- code must still match the list price. A code must match the discounted
-- price stored for that code, even if the code was deactivated after the
-- order was created (the student already paid that amount).
-- ---------------------------------------------------------------------------

drop function if exists public.apply_razorpay_payment(
  text, text, uuid, public.plan_tier, integer, text
);

create or replace function public.apply_razorpay_payment(
  p_payment_id text,
  p_order_id text,
  p_user_id uuid,
  p_plan public.plan_tier,
  p_amount_paise integer,
  p_currency text,
  p_discount_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount_paise integer;
  v_duration_days integer;
  v_expected integer;
  v_code text;
  v_percent integer;
  v_inserted text;
  v_expires_at timestamptz;
  v_plan public.plan_tier;
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

  select amount_paise, duration_days
    into v_amount_paise, v_duration_days
  from public.paid_plan_terms(p_plan);

  if v_amount_paise is null then
    raise exception 'unsupported plan';
  end if;

  v_code := public.normalize_discount_code(p_discount_code);
  if p_discount_code is null or length(trim(p_discount_code)) = 0 then
    v_code := null;
    v_expected := v_amount_paise;
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
    v_expected := public.discounted_amount_paise(v_amount_paise, v_percent);
  end if;

  if p_amount_paise is distinct from v_expected then
    raise exception 'amount does not match catalog';
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
    percent_off
  ) values (
    p_payment_id,
    p_order_id,
    p_user_id,
    p_plan,
    p_amount_paise,
    p_currency,
    v_code,
    v_amount_paise,
    v_percent
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
      + (v_duration_days * interval '1 day')
  where id = p_user_id
  returning plan, plan_expires_at into v_plan, v_expires_at;

  if v_plan is null then
    raise exception 'profile not found';
  end if;

  return jsonb_build_object(
    'applied', true,
    'duplicate', false,
    'plan', v_plan,
    'plan_expires_at', v_expires_at
  );
end;
$$;

comment on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text) is
  'Idempotent plan grant after a verified Razorpay payment.captured webhook. Optional discount code must match the stored percent. Stacks onto remaining time. Not for clients.';

revoke all on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text) from public;
revoke all on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text) from anon, authenticated;
grant execute on function public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text) to service_role;
