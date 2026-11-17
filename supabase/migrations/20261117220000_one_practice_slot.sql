-- One practice tests row per student. Answered questions live in
-- user_question_attempts so Unattempted / Previously Incorrect still work
-- after that row (and its attempts) is replaced.

-- ---------------------------------------------------------------------------
-- 1. Ledger: one latest answer per student per question
-- ---------------------------------------------------------------------------

create table public.user_question_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  selected_option char(1) not null check (selected_option in ('A', 'B', 'C', 'D')),
  was_correct boolean not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

alter table public.user_question_attempts enable row level security;

revoke all on table public.user_question_attempts from public, anon, authenticated;
grant select on table public.user_question_attempts to authenticated;
grant select, insert, update, delete on table public.user_question_attempts to service_role;

create policy "own question attempts select"
  on public.user_question_attempts
  for select
  using (user_id = auth.uid());

comment on table public.user_question_attempts is
  'Latest selected option per student per question. Written only by submit_attempt and create_practice_session. Unattempted means no row. Previously Incorrect means was_correct is false.';

-- security definer so it can read questions.correct_option (students cannot
-- select that table). Not granted to authenticated — callers are other
-- definer functions.
create or replace function private.record_user_question_attempts(
  p_user_id uuid,
  p_answers jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null
     or p_answers is null
     or jsonb_typeof(p_answers) is distinct from 'array' then
    return;
  end if;

  insert into public.user_question_attempts (
    user_id, question_id, selected_option, was_correct, updated_at
  )
  select distinct on (q.id)
    p_user_id,
    q.id,
    s.selected_option::char(1),
    s.selected_option::char(1) is not distinct from q.correct_option,
    now()
  from (
    select
      lower(btrim(elem->>'question_id')) as question_id,
      btrim(elem->>'selected_option') as selected_option
    from jsonb_array_elements(p_answers) elem
  ) s
  join public.questions q on q.id::text = s.question_id
  where s.selected_option in ('A', 'B', 'C', 'D')
  order by q.id
  on conflict (user_id, question_id) do update
    set selected_option = excluded.selected_option,
        was_correct = excluded.was_correct,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function private.record_user_question_attempts(uuid, jsonb)
  from public, anon, authenticated;

comment on function private.record_user_question_attempts(uuid, jsonb) is
  'Upserts the latest selected option. was_correct is computed from questions.correct_option. Ignores blank or invalid options. Duplicate question ids in one payload collapse to one row.';

-- ---------------------------------------------------------------------------
-- 2. Backfill from answers already stored, then drop extra practice rows
-- ---------------------------------------------------------------------------

insert into public.user_question_attempts (
  user_id, question_id, selected_option, was_correct, updated_at
)
select distinct on (a.user_id, aa.question_id)
  a.user_id,
  aa.question_id,
  aa.selected_option,
  aa.selected_option is not distinct from q.correct_option,
  coalesce(aa.answered_at, a.submitted_at, a.created_at, now())
from public.attempt_answers aa
join public.attempts a on a.id = aa.attempt_id
join public.questions q on q.id = aa.question_id
where aa.selected_option is not null
order by
  a.user_id,
  aa.question_id,
  coalesce(aa.answered_at, a.submitted_at, a.created_at) desc;

-- Keep an in-progress practice test when the student has one, otherwise the
-- newest practice test. Snapshot the ids first: deleting attempts clears
-- in_progress, which would change the ranking. attempts.test_id is
-- ON DELETE RESTRICT, so attempts go before tests.
drop table if exists _drop_practice_tests;
create temporary table _drop_practice_tests as
select id
from (
  select
    t.id,
    row_number() over (
      partition by t.owner_user_id
      order by
        exists (
          select 1
          from public.attempts a
          where a.test_id = t.id
            and a.status = 'in_progress'
        ) desc,
        t.created_at desc
    ) as rn
  from public.tests t
  where t.is_ephemeral_practice
    and t.owner_user_id is not null
) ranked
where rn > 1;

delete from public.attempts
where test_id in (select id from _drop_practice_tests);

delete from public.tests
where id in (select id from _drop_practice_tests);

drop table _drop_practice_tests;

create unique index tests_one_practice_per_user
  on public.tests (owner_user_id)
  where is_ephemeral_practice;

comment on index public.tests_one_practice_per_user is
  'A student has one practice session. create_practice_session replaces it.';

-- ---------------------------------------------------------------------------
-- 3. submit_attempt also writes the ledger
-- ---------------------------------------------------------------------------

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

  perform private.record_user_question_attempts(
    v_attempt.user_id,
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'question_id', aa.question_id,
            'selected_option', aa.selected_option
          )
        ),
        '[]'::jsonb
      )
      from public.attempt_answers aa
      where aa.attempt_id = p_attempt_id
        and aa.selected_option is not null
    )
  );

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

comment on function public.submit_attempt(uuid, jsonb) is
  'Writes attempt_answers, scores from tests.correct/incorrect/unattempted_marks, stores percentile, and upserts user_question_attempts for each selected option. Client must not send a score.';

revoke all on function public.submit_attempt(uuid, jsonb) from public, anon;
grant execute on function public.submit_attempt(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. create_practice_session replaces the one practice row
-- ---------------------------------------------------------------------------

drop function if exists public.create_practice_session(
  uuid[],
  uuid[],
  public.question_difficulty[],
  text,
  int,
  text,
  text,
  int,
  boolean,
  uuid[],
  uuid[]
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
  p_subject_ids uuid[] default null,
  p_prior_answers jsonb default null
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
  v_old_ids uuid[];
  v_old_test_id uuid;
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
  -- cannot race, and so two calls cannot insert two practice rows.
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

  -- Replace the previous practice row inside this transaction. A later
  -- NO_QUESTIONS_MATCH_FILTERS rolls the delete back, so a failed start
  -- leaves the open session in place.
  if p_prior_answers is null
     or jsonb_typeof(p_prior_answers) is distinct from 'array' then
    p_prior_answers := '[]'::jsonb;
  end if;

  select coalesce(array_agg(t.id), '{}'::uuid[])
    into v_old_ids
  from public.tests t
  where t.owner_user_id = v_uid
    and t.is_ephemeral_practice;

  foreach v_old_test_id in array v_old_ids loop
    perform private.record_user_question_attempts(
      v_uid,
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'question_id', aa.question_id,
              'selected_option', aa.selected_option
            )
          ),
          '[]'::jsonb
        )
        from public.attempt_answers aa
        join public.attempts a on a.id = aa.attempt_id
        where a.test_id = v_old_test_id
          and a.user_id = v_uid
          and aa.selected_option is not null
      )
    );

    -- Phone answers win over the saved copy: an open session keeps its
    -- selections in local JSON until submit. Only questions on this test count.
    perform private.record_user_question_attempts(
      v_uid,
      (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'question_id', picked.question_id,
              'selected_option', picked.selected_option
            )
          ),
          '[]'::jsonb
        )
        from (
          select distinct on (tq.question_id)
            tq.question_id,
            btrim(elem->>'selected_option') as selected_option
          from jsonb_array_elements(p_prior_answers) elem
          join public.test_questions tq
            on tq.test_id = v_old_test_id
           and tq.question_id::text = lower(btrim(elem->>'question_id'))
          where btrim(elem->>'selected_option') in ('A', 'B', 'C', 'D')
          order by tq.question_id
        ) picked
      )
    );

    delete from public.attempts where test_id = v_old_test_id;
    delete from public.tests where id = v_old_test_id;
  end loop;

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
            select 1 from public.user_question_attempts uqa
            where uqa.user_id = v_uid
              and uqa.question_id = q.id
              and not uqa.was_correct))
      or (p_source_filter = 'unattempted' and not exists (
            select 1 from public.user_question_attempts uqa
            where uqa.user_id = v_uid
              and uqa.question_id = q.id))
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
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[], jsonb
) is
  'Replaces the caller''s single practice test. Records saved answers and p_prior_answers (only questions on the replaced test) into user_question_attempts before deleting it. Unattempted and Previously Incorrect read that ledger. feedback_timing may be immediate, on_submit, or reading. Reading forces the timer and negative marking off and does not start an attempt. Clamps to the caller''s plan row.';

revoke all on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[], jsonb
) from public, anon;
grant execute on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[], jsonb
) to authenticated;
