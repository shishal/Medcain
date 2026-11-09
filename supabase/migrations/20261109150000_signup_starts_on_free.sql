-- New accounts start on Free. Questions with required_plan = 'free' stay
-- visible; Pro and Elite questions stay behind current_plan().
-- Paid rows are left alone: a payment, or a Pro window longer than the old
-- 4-day signup grant, is not a trial.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, plan, phone)
  values (new.id, 'free', new.phone);
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Creates a Free profile for a new auth user and copies the confirmed phone.';

update public.profiles as p
set
  plan = 'free',
  plan_started_at = null,
  plan_expires_at = null
where p.plan = 'pro'
  and p.plan_started_at is not null
  and p.plan_expires_at is not null
  and p.plan_expires_at <= p.plan_started_at + interval '5 days'
  and not exists (
    select 1
    from public.payments as pay
    where pay.user_id = p.id
  );
