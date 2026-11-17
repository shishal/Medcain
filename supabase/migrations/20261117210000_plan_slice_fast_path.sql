-- Plan slice without a per-question paper walk.
--
-- preview (preview_only): in slice means is_preview.
-- open (filtered, every university, every MBBS phase, every paper year,
--   every exam type, untagged included): in slice means is_preview or the
--   kind is allowed. Pro and Elite are this shape.
-- narrow (anything else): papers that match the plan are resolved once.
--   latest is max(exam_year) per subject on that set, not inside each question.
--
-- Preview questions stay in every slice, including when the kind is outside
-- the plan. question_listings stays security_barrier = false so a topic or
-- id filter still runs before the check.

create index if not exists idx_exam_papers_subject_year
  on public.exam_papers (subject_id, exam_year);

create or replace function private.plan_slice_mode(
  p_access_mode text,
  p_university_scope text,
  p_mbbs_year_scope text,
  p_exam_year_scope text,
  p_include_untagged boolean,
  p_allowed_exam_types text[]
) returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_access_mode = 'preview_only' then 'preview'
    when p_access_mode = 'filtered'
      and p_university_scope = 'all'
      and p_mbbs_year_scope = 'all'
      and p_exam_year_scope = 'all'
      and p_include_untagged
      and p_allowed_exam_types @> array['prof', 'supply', 'pre_prof', 'internal']::text[]
    then 'open'
    else 'narrow'
  end;
$$;

comment on function private.plan_slice_mode(text, text, text, text, boolean, text[]) is
  'preview, open, or narrow. Open is the full bank: every scope, every exam type, untagged included. Keep in step with question_listings and plan_allows_question.';

revoke all on function private.plan_slice_mode(text, text, text, text, boolean, text[]) from public, anon;
grant execute on function private.plan_slice_mode(text, text, text, text, boolean, text[]) to authenticated, service_role;

-- p_slice_mode other than narrow returns no rows and does not read papers.
-- Called once per listing from a materialized CTE, and once per practice
-- session. Single-question checks call it only on the narrow branch.
create or replace function private.allowed_paper_ids(
  p_slice_mode text,
  p_university uuid,
  p_exam_types text[],
  p_university_scope text,
  p_mbbs_year_scope text,
  p_mbbs_years text[],
  p_exam_year_scope text,
  p_exam_years integer[]
) returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_slice_mode is distinct from 'narrow' then
    return;
  end if;

  return query
  with papers as (
    select
      ep.id,
      ep.exam_year,
      max(ep.exam_year) over (partition by ep.subject_id) as latest_year
    from public.exam_papers ep
    join public.subjects s on s.id = ep.subject_id
    left join public.mbbs_phases ph on ph.id = s.mbbs_phase_id
    where ep.exam_type = any (p_exam_types)
      and (
        p_university_scope = 'all'
        or ep.university_id = p_university
      )
      and (
        p_mbbs_year_scope = 'all'
        or ph.code::text = any (p_mbbs_years)
      )
  )
  select papers.id
  from papers
  where p_exam_year_scope = 'all'
     or (
       p_exam_year_scope = 'selected'
       and papers.exam_year = any (p_exam_years)
     )
     or (
       p_exam_year_scope = 'latest'
       and papers.exam_year = papers.latest_year
     );
end;
$$;

comment on function private.allowed_paper_ids(text, uuid, text[], text, text, text[], text, integer[]) is
  'Paper ids inside a narrow plan slice. Empty unless p_slice_mode is narrow. latest is the newest exam_year per subject after the other paper filters.';

revoke all on function private.allowed_paper_ids(text, uuid, text[], text, text, text[], text, integer[]) from public, anon;
grant execute on function private.allowed_paper_ids(text, uuid, text[], text, text, text[], text, integer[]) to authenticated, service_role;

create or replace function public.plan_allows_question(
  p_plan_id uuid,
  p_question_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select
      q.is_active
      and case private.plan_slice_mode(
        pl.access_mode,
        pl.university_scope,
        pl.mbbs_year_scope,
        pl.exam_year_scope,
        pl.include_untagged,
        pl.allowed_exam_types
      )
        when 'preview' then q.is_preview
        when 'open' then
          q.is_preview
          or q.kind::text = any (pl.allowed_kinds)
        else
          q.is_preview
          or (
            q.kind::text = any (pl.allowed_kinds)
            and (
              (
                pl.include_untagged
                and not exists (
                  select 1
                  from public.question_appearances qa
                  where qa.question_id = q.id
                )
              )
              or exists (
                select 1
                from public.question_appearances qa
                where qa.question_id = q.id
                  and qa.exam_paper_id in (
                    select private.allowed_paper_ids(
                      'narrow',
                      pr.university_id,
                      pl.allowed_exam_types,
                      pl.university_scope,
                      pl.mbbs_year_scope,
                      pl.mbbs_years,
                      pl.exam_year_scope,
                      pl.exam_years
                    )
                  )
              )
            )
          )
      end
    from public.plans pl
    cross join public.questions q
    left join public.profiles pr on pr.id = p_user_id
    where pl.id = p_plan_id
      and q.id = p_question_id
  ), false);
$$;

comment on function public.plan_allows_question(uuid, uuid, uuid) is
  'True when the question is active and in the plan slice. Preview and open plans do not read papers. A narrow plan matches a preview, an untagged question when the plan includes those, or any sitting on private.allowed_paper_ids.';

revoke all on function public.plan_allows_question(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.plan_allows_question(uuid, uuid, uuid) to service_role;

-- Same slice as plan_allows_question. The paper set is one materialized CTE
-- so a subject listing does not recompute it per question. CASE skips that
-- set for preview and open.
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
    (pr.blocked_at is not null) as is_blocked,
    private.plan_slice_mode(
      pl.access_mode,
      pl.university_scope,
      pl.mbbs_year_scope,
      pl.exam_year_scope,
      pl.include_untagged,
      pl.allowed_exam_types
    ) as slice_mode
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
),
allowed_papers as materialized (
  select ids.paper_id
  from viewer v
  cross join lateral private.allowed_paper_ids(
    case when v.is_blocked then 'open' else v.slice_mode end,
    v.university_id,
    v.allowed_exam_types,
    v.university_scope,
    v.mbbs_year_scope,
    v.mbbs_years,
    v.exam_year_scope,
    v.exam_years
  ) as ids(paper_id)
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
  select case v.slice_mode
    when 'preview' then q.is_preview
    when 'open' then
      q.is_preview
      or q.kind::text = any (v.allowed_kinds)
    else
      q.is_preview
      or (
        q.kind::text = any (v.allowed_kinds)
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
            where qa.question_id = q.id
              and qa.exam_paper_id in (select ap.paper_id from allowed_papers ap)
          )
        )
      )
  end as in_slice
) gate on true
left join public.question_sample_answers sa on sa.question_id = q.id
where q.is_active
  and (gate.in_slice or v.tease);

comment on view public.question_listings is
  'Active question cards for the signed-in plan. Preview and open plans match on columns only. A narrow plan semi-joins to one paper set. Out-of-slice rows are omitted unless the plan teases them, and then the stem, key, explanation, and sample answer are null. Not security_barrier, so a topic filter runs before the plan check.';

-- Practice picks MCQs with the same three modes. Open and preview do not
-- build a paper list. Narrow compares appearances to that list once.
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
  v_slice_mode text;
  v_paper_ids uuid[];
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

  v_slice_mode := private.plan_slice_mode(
    v_plan.access_mode,
    v_plan.university_scope,
    v_plan.mbbs_year_scope,
    v_plan.exam_year_scope,
    v_plan.include_untagged,
    v_plan.allowed_exam_types
  );

  if v_slice_mode = 'narrow' then
    select coalesce(array_agg(ids.paper_id), '{}')
      into v_paper_ids
    from private.allowed_paper_ids(
      'narrow',
      v_university_id,
      v_plan.allowed_exam_types,
      v_plan.university_scope,
      v_plan.mbbs_year_scope,
      v_plan.mbbs_years,
      v_plan.exam_year_scope,
      v_plan.exam_years
    ) as ids(paper_id);
  else
    v_paper_ids := '{}';
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
    and case v_slice_mode
      when 'preview' then q.is_preview
      when 'open' then
        q.is_preview
        or 'mcq' = any (v_plan.allowed_kinds)
      else
        q.is_preview
        or (
          'mcq' = any (v_plan.allowed_kinds)
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
              where qa.question_id = q.id
                and qa.exam_paper_id = any (v_paper_ids)
            )
          )
        )
    end
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

comment on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) is
  'Creates an ephemeral MCQ practice test. feedback_timing may be immediate, on_submit, or reading. Reading forces the timer and negative marking off and does not start an attempt. Clamps to the caller''s plan row. Preview and open plans skip papers. A narrow plan keeps questions that sit on private.allowed_paper_ids.';

revoke all on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) from public, anon;
grant execute on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) to authenticated;
