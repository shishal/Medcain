-- Live Pro / Elite price and access window.
--
-- checkout_quote() and apply_razorpay_payment() already call paid_plan_terms().
-- That function used to hardcode the paise. It now reads this table, so a price
-- change is an UPDATE in the SQL editor — not a new app build and not an edit
-- to the Edge Function.
--
--   update public.paid_plan_catalog
--   set amount_paise = 99900   -- rupees × 100
--   where plan = 'pro';
--
-- Do that when no checkout is in progress. An order already created keeps the
-- old paise, and the webhook rejects it if this row changed before capture.
-- Students may SELECT (the checkout page shows the price). They cannot write.

create table public.paid_plan_catalog (
  plan public.plan_tier primary key,
  amount_paise integer not null,
  duration_days integer not null,
  constraint paid_plan_catalog_paid_only check (plan in ('pro', 'elite')),
  constraint paid_plan_catalog_amount check (amount_paise >= 100),
  constraint paid_plan_catalog_duration check (duration_days >= 1)
);

comment on table public.paid_plan_catalog is
  'What we charge for Pro and Elite. amount_paise is rupees times 100. Signed-in students can read; only the SQL editor / service role can change a row.';

comment on column public.paid_plan_catalog.amount_paise is
  'List price in paise (₹1 = 100). Discount codes are applied on top of this.';

comment on column public.paid_plan_catalog.duration_days is
  'Days added to plan_expires_at when a payment at this price is applied.';

insert into public.paid_plan_catalog (plan, amount_paise, duration_days) values
  ('pro', 149900, 180),
  ('elite', 299900, 365);

alter table public.paid_plan_catalog enable row level security;

revoke all on table public.paid_plan_catalog from public;
revoke all on table public.paid_plan_catalog from anon, authenticated;
grant select on table public.paid_plan_catalog to authenticated;
grant all on table public.paid_plan_catalog to service_role;

create policy "paid_plan_catalog readable" on public.paid_plan_catalog
  for select using (auth.role() = 'authenticated');

-- Replaces the hardcoded if/elsif. STABLE because it reads a table.
-- Drop first so the language can change from plpgsql to sql.
-- Still not granted to students: checkout_quote and apply_razorpay_payment
-- are security definer and call it as the owner.
drop function if exists public.paid_plan_terms(public.plan_tier);

create function public.paid_plan_terms(p_plan public.plan_tier)
returns table (amount_paise integer, duration_days integer)
language sql
stable
set search_path = public
as $$
  select c.amount_paise, c.duration_days
  from public.paid_plan_catalog c
  where c.plan = p_plan
    and c.plan in ('pro'::public.plan_tier, 'elite'::public.plan_tier);
$$;

revoke all on function public.paid_plan_terms(public.plan_tier) from public;
revoke all on function public.paid_plan_terms(public.plan_tier) from anon, authenticated;

comment on function public.paid_plan_terms(public.plan_tier) is
  'List price and access window for a paid plan, from paid_plan_catalog.';
