-- Listing chips need to know whether a written answer or explanation exists
-- without shipping the text. Sample-answer bodies stay Pro-gated; this flag
-- is only a boolean on the question row the student can already read.

alter table public.questions
  add column if not exists has_explanation boolean
  generated always as (
    nullif(btrim(coalesce(explanation_text, '')), '') is not null
    or nullif(btrim(coalesce(explanation_deep, '')), '') is not null
  ) stored;

alter table public.questions
  add column if not exists has_direct_answer boolean not null default false;

comment on column public.questions.has_explanation is
  'True when explanation_text or explanation_deep has non-blank text. No body.';

comment on column public.questions.has_direct_answer is
  'True when question_sample_answers has a non-blank body. Not the answer itself.';

update public.questions q
set has_direct_answer = exists (
  select 1
  from public.question_sample_answers a
  where a.question_id = q.id
    and nullif(btrim(a.body), '') is not null
);

create or replace function public.sync_question_has_direct_answer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  qid uuid;
begin
  qid := coalesce(new.question_id, old.question_id);
  update public.questions
  set has_direct_answer = exists (
    select 1
    from public.question_sample_answers a
    where a.question_id = qid
      and nullif(btrim(a.body), '') is not null
  )
  where id = qid;
  return coalesce(new, old);
end;
$$;

drop trigger if exists question_sample_answers_sync_flag
  on public.question_sample_answers;

create trigger question_sample_answers_sync_flag
  after insert or update or delete on public.question_sample_answers
  for each row execute function public.sync_question_has_direct_answer();

revoke all on function public.sync_question_has_direct_answer()
  from public, anon, authenticated;

drop view if exists public.pyq_teasers;

create view public.pyq_teasers
with (security_invoker = true) as
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
  q.has_explanation
from public.questions q
where q.is_active;

comment on view public.pyq_teasers is
  'Theory + MCQ stems + frequency + difficulty + content flags. '
  'No sample-answer text, no explanation text, no MCQ keys.';

grant select on public.pyq_teasers to authenticated, service_role;
