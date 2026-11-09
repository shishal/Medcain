-- Practice sessions follow the same question ownership as the PYQ reader.
--
-- A student's university comes from profiles, not from the client. An MCQ
-- with no exam appearance is the shared bank (every university). An MCQ that
-- appears on a paper belongs only to that paper's university.
--
-- Subject filters also match paper-tagged stems whose topic_id is empty,
-- and topic filters match a lesson when topic_id itself is empty.

drop function if exists public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[]
);

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
  v_plan public.plan_tier;
  v_limits public.plan_limits%rowtype;
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
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_source_filter is null
     or p_source_filter not in ('unattempted', 'incorrect', 'bookmarked', 'all') then
    raise exception 'INVALID_SOURCE_FILTER';
  end if;

  if p_feedback_timing is null
     or p_feedback_timing not in ('immediate', 'on_submit') then
    raise exception 'INVALID_FEEDBACK_TIMING';
  end if;

  if p_explanation_level is null
     or p_explanation_level not in ('none', 'answer_only', 'full') then
    raise exception 'INVALID_EXPLANATION_LEVEL';
  end if;

  if p_question_count is null or p_question_count < 1 then
    raise exception 'INVALID_QUESTION_COUNT';
  end if;

  v_plan := public.current_plan(auth.uid());
  select * into v_limits from public.plan_limits where plan = v_plan;
  if not found then
    raise exception 'PLAN_LIMITS_MISSING';
  end if;

  select p.university_id into v_university_id
  from public.profiles p
  where p.id = auth.uid();

  v_effective_count := least(p_question_count, v_limits.max_practice_session_questions);

  v_effective_explanation := case
    when p_explanation_level = 'full' and not v_limits.allow_full_explanation then 'answer_only'
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

  -- A chosen topic is already inside a subject. Don't AND the two.
  if v_topic_ids is not null then
    v_subject_ids := null;
  end if;

  if v_limits.allow_tag_filter then
    v_tag_ids := case
      when p_tag_ids is null or cardinality(p_tag_ids) = 0 then null
      else p_tag_ids
    end;
  else
    v_tag_ids := null;
  end if;

  if v_limits.allow_difficulty_filter then
    v_difficulties := case
      when p_difficulties is null or cardinality(p_difficulties) = 0 then null
      else p_difficulties
    end;
  else
    v_difficulties := null;
  end if;

  if v_limits.allow_timer_toggle then
    v_timer_minutes := p_timer_minutes;
  else
    v_timer_minutes := coalesce(p_timer_minutes, v_effective_count);
  end if;

  if v_limits.allow_negative_marking_toggle then
    v_negative_marking := coalesce(p_negative_marking, false);
  else
    v_negative_marking := false;
  end if;

  if v_limits.daily_practice_question_quota is not null then
    select coalesce(questions_used, 0) into v_used_today
    from public.daily_practice_usage
    where user_id = auth.uid() and usage_date = current_date;

    if coalesce(v_used_today, 0) + v_effective_count > v_limits.daily_practice_question_quota then
      v_effective_count := greatest(
        v_limits.daily_practice_question_quota - coalesce(v_used_today, 0),
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
    auth.uid(), true, p_feedback_timing, v_effective_explanation,
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
    and public.plan_rank(v_plan) >= public.plan_rank(q.required_plan)
    and (
      v_university_id is null
      or not exists (
        select 1 from public.question_appearances qa
        where qa.question_id = q.id
      )
      or exists (
        select 1
        from public.question_appearances qa
        join public.exam_papers ep on ep.id = qa.exam_paper_id
        where qa.question_id = q.id
          and ep.university_id = v_university_id
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
            where b.question_id = q.id and b.user_id = auth.uid()))
      or (p_source_filter = 'incorrect' and exists (
            select 1 from public.attempt_answers aa
            join public.attempts a on a.id = aa.attempt_id
            where a.user_id = auth.uid()
              and aa.question_id = q.id
              and aa.selected_option is distinct from q.correct_option))
      or (p_source_filter = 'unattempted' and not exists (
            select 1 from public.attempt_answers aa
            join public.attempts a on a.id = aa.attempt_id
            where a.user_id = auth.uid()
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
  values (auth.uid(), current_date, v_actual_count)
  on conflict (user_id, usage_date) do update
    set questions_used = public.daily_practice_usage.questions_used + v_actual_count;

  return v_test_id;
end;
$$;

revoke all on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) from public;

grant execute on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) to authenticated, service_role;

comment on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) is
  'Creates an ephemeral MCQ practice test for the caller. Clamps to plan_limits. Scopes paper MCQs to profiles.university_id; untagged MCQs stay in the shared bank.';
