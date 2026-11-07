-- Paper and lesson lists need every active question, including ones above
-- the caller's plan, so the app can show a Free / Pro tag and a mask.
-- questions RLS stays as it is: explanations, options, and keys never leave
-- that table. This view returns the stem only when current_plan() covers
-- required_plan, and null otherwise.
--
-- security_invoker = false so the owner can read questions, then the CASE
-- redacts. An invoker view would drop Pro rows before the CASE runs.
-- security_barrier stops a caller's WHERE from seeing the raw stem.

create or replace view public.question_listings
with (security_invoker = false, security_barrier = true) as
select
  q.id,
  q.lesson_id,
  q.topic_id,
  case
    when public.plan_rank(public.current_plan(auth.uid()))
         >= public.plan_rank(q.required_plan)
    then q.question_text
    else null
  end as question_text,
  q.marks,
  q.required_plan,
  q.is_active,
  q.kind,
  q.difficulty,
  q.has_direct_answer,
  q.has_explanation
from public.questions q
where q.is_active;

comment on view public.question_listings is
  'Active question cards. question_text is null when current_plan() is below required_plan. No explanation, options, or answer key.';

revoke all on table public.question_listings from public, anon;
grant select on table public.question_listings to authenticated, service_role;
