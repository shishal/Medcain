-- question_listings calls plan_allows_question while a signed-in student
-- selects the view. Postgres checks EXECUTE as that student, even though the
-- view is security definer. The three-argument function is revoked from
-- authenticated, so the subject query failed with
-- "permission denied for function plan_allows_question" and the app showed
-- "Could not load PYQs."
--
-- These wrappers pin the check to auth.uid() and the caller's own plan.
-- Students may execute them. They still cannot pass another user id, and
-- they still cannot select questions. The functions live outside public so
-- PostgREST does not expose them as RPCs.

create schema if not exists private;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create or replace function private.my_plan_allows_question(p_question_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.plan_allows_question(
    public.current_plan_id(auth.uid()),
    p_question_id,
    auth.uid()
  );
$$;

comment on function private.my_plan_allows_question(uuid) is
  'Whether the signed-in plan includes this question. Executable by students because question_listings calls it.';

revoke all on function private.my_plan_allows_question(uuid) from public, anon;
grant execute on function private.my_plan_allows_question(uuid) to authenticated, service_role;

create or replace function private.my_plan_allows_lesson(p_lesson_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.plan_allows_lesson(
    public.current_plan_id(auth.uid()),
    p_lesson_id,
    auth.uid()
  );
$$;

comment on function private.my_plan_allows_lesson(uuid) is
  'Whether the signed-in plan opens this lesson. Executable by students because lesson_access calls it.';

revoke all on function private.my_plan_allows_lesson(uuid) from public, anon;
grant execute on function private.my_plan_allows_lesson(uuid) to authenticated, service_role;

create or replace view public.question_listings
with (security_invoker = false, security_barrier = false) as
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
    when gate.in_slice and gate.depth in ('answer', 'explanation') then q.correct_option
  end as correct_option,
  case
    when gate.in_slice and gate.depth = 'explanation' then q.explanation_text
  end as explanation_text,
  case
    when gate.in_slice and gate.depth = 'explanation' then q.explanation_deep
  end as explanation_deep,
  case
    when gate.in_slice and gate.depth = 'explanation' then q.explanation_video_url
  end as explanation_video_url,
  case when gate.in_slice then q.image_url end as image_url,
  case
    when gate.in_slice and gate.depth in ('answer', 'explanation') then nullif(btrim(sa.body), '')
  end as sample_answer,
  (not gate.in_slice) as is_locked,
  q.is_preview,
  (gate.in_slice and gate.depth in ('answer', 'explanation')) as answers_visible,
  (gate.in_slice and gate.depth = 'explanation') as explanation_visible
from public.questions q
join lateral (
  select
    private.my_plan_allows_question(q.id) as in_slice,
    pl.tease_locked_questions as tease,
    pl.content_depth as depth
  from public.plans pl
  where pl.id = public.current_plan_id(auth.uid())
) gate on true
left join public.question_sample_answers sa on sa.question_id = q.id
where q.is_active
  and (gate.in_slice or gate.tease);

comment on view public.question_listings is
  'Active question cards for the signed-in plan. Out-of-slice rows are omitted unless the plan teases them, and then the stem, key, explanation, and sample answer are null. Not security_barrier, so a topic filter runs before the plan check.';

create or replace view public.lesson_access
with (security_invoker = false, security_barrier = true) as
select
  l.id as lesson_id,
  private.my_plan_allows_lesson(l.id) as is_open
from public.lessons l;

drop policy if exists "lesson resources select" on public.lesson_resources;
create policy "lesson resources select" on public.lesson_resources
  for select using (
    is_free
    or private.my_plan_allows_lesson(lesson_id)
  );

drop policy if exists "question resources select" on public.question_resources;
create policy "question resources select" on public.question_resources
  for select using (
    is_free
    or private.my_plan_allows_question(question_id)
  );
