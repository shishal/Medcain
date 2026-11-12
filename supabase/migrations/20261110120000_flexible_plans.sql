-- Plans are rows an admin creates, not the free/pro/elite enum.
--
-- profiles.plan_id is the subscription. profiles.plan stays as a mirror for
-- the three seeded codes (a custom plan is stored as 'pro') so older reads
-- do not break. Access checks use current_plan_id() and the plan row.
-- questions.is_preview replaces per-question ranks. required_plan = free
-- still means preview; the trigger keeps the two in step.

-- ---------------------------------------------------------------------------
-- Plan catalog
-- ---------------------------------------------------------------------------

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  tagline text,
  benefits text[] not null default '{}',
  amount_paise integer not null default 0,
  duration_months integer,
  duration_label text,
  max_registered_devices integer not null default 1,
  promo_headline text,
  promo_detail text,
  featured_discount_code text references public.discount_codes (code) on delete set null,
  is_public boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  content_depth text not null default 'explanation',
  access_mode text not null default 'filtered',
  allowed_kinds text[] not null default array['mcq', 'pyq_theory']::text[],
  university_scope text not null default 'all',
  allowed_exam_types text[] not null default array['prof', 'supply', 'pre_prof', 'internal']::text[],
  mbbs_year_scope text not null default 'all',
  mbbs_years text[] not null default '{}',
  exam_year_scope text not null default 'all',
  exam_years integer[] not null default '{}',
  include_untagged boolean not null default false,
  tease_locked_questions boolean not null default false,
  allow_practice boolean not null default true,
  allow_tutor_mode boolean not null default true,
  allow_exam_mode boolean not null default true,
  max_practice_session_questions integer,
  daily_practice_question_quota integer,
  allow_timer_toggle boolean not null default true,
  allow_tag_filter boolean not null default true,
  allow_difficulty_filter boolean not null default true,
  allow_negative_marking_toggle boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plans_code_slug check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  constraint plans_amount check (amount_paise >= 0),
  constraint plans_sellable check (
    amount_paise = 0
    or (amount_paise >= 100 and duration_months is not null and duration_months >= 1)
  ),
  constraint plans_duration check (duration_months is null or duration_months >= 1),
  constraint plans_devices check (max_registered_devices between 1 and 10),
  constraint plans_depth check (content_depth in ('stem', 'answer', 'explanation')),
  constraint plans_access check (access_mode in ('preview_only', 'filtered')),
  constraint plans_university check (university_scope in ('own', 'all')),
  constraint plans_mbbs_scope check (mbbs_year_scope in ('all', 'selected')),
  constraint plans_exam_year_scope check (exam_year_scope in ('all', 'latest', 'selected')),
  constraint plans_kinds check (
    allowed_kinds <@ array['mcq', 'pyq_theory']::text[]
    and cardinality(allowed_kinds) >= 1
  ),
  constraint plans_exam_types check (
    allowed_exam_types <@ array['prof', 'supply', 'pre_prof', 'internal']::text[]
    and cardinality(allowed_exam_types) >= 1
  ),
  constraint plans_session_cap check (
    max_practice_session_questions is null or max_practice_session_questions >= 1
  ),
  constraint plans_daily_cap check (
    daily_practice_question_quota is null or daily_practice_question_quota >= 1
  )
);

comment on table public.plans is
  'Sellable and free plans. Entitlements, price, duration, and device cap live on the row. Students may read public rows and their own plan.';

insert into public.plans (
  code, name, tagline, benefits, amount_paise, duration_months, duration_label,
  max_registered_devices, is_public, is_active, sort_order,
  content_depth, access_mode, university_scope,
  mbbs_year_scope, exam_year_scope, include_untagged, tease_locked_questions,
  allow_practice, allow_tutor_mode, allow_exam_mode,
  max_practice_session_questions, daily_practice_question_quota,
  allow_timer_toggle, allow_tag_filter, allow_difficulty_filter,
  allow_negative_marking_toggle
) values
  (
    'free', 'Free', 'Questions marked as a free preview',
    array[
      'Free preview questions',
      'Locked cards for the rest of the bank',
      '1 registered device'
    ]::text[],
    0, null, null,
    1, true, true, 0,
    'explanation', 'preview_only', 'all',
    'all', 'all', false, true,
    true, true, true,
    10, 20,
    false, false, true,
    false
  ),
  (
    'pro', 'Pro', 'The full bank on one phone',
    array[
      'All questions, all years, all subjects',
      'Answers and explanations',
      '1 registered device'
    ]::text[],
    149900, 12, '1 year',
    1, true, true, 1,
    'explanation', 'filtered', 'all',
    'all', 'all', true, false,
    true, true, true,
    50, null,
    true, true, true,
    true
  ),
  (
    'elite', 'Elite', 'The same bank on two phones',
    array[
      'All questions, all years, all subjects',
      'Answers and explanations',
      '2 registered devices'
    ]::text[],
    299900, 12, '1 year',
    2, true, true, 2,
    'explanation', 'filtered', 'all',
    'all', 'all', true, false,
    true, true, true,
    50, null,
    true, true, true,
    true
  );

-- ---------------------------------------------------------------------------
-- Profile points at a plan. The enum column mirrors seeded codes.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists plan_id uuid references public.plans (id);

update public.profiles as p
set plan_id = pl.id
from public.plans as pl
where pl.code = p.plan::text
  and p.plan_id is null;

create or replace function public.profiles_sync_plan_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if new.plan_id is null then
    select id into new.plan_id
    from public.plans
    where code = coalesce(new.plan::text, 'free');
  end if;

  select code into v_code from public.plans where id = new.plan_id;
  if v_code is null then
    raise exception 'That plan does not exist.';
  end if;

  new.plan := case
    when v_code in ('free', 'pro', 'elite') then v_code::public.plan_tier
    else 'pro'::public.plan_tier
  end;
  return new;
end;
$$;

drop trigger if exists profiles_sync_plan_id on public.profiles;
create trigger profiles_sync_plan_id
  before insert or update of plan_id, plan on public.profiles
  for each row execute function public.profiles_sync_plan_id();

alter table public.profiles
  alter column plan_id set not null;

create index if not exists profiles_plan_id_idx on public.profiles (plan_id);

comment on column public.profiles.plan_id is
  'Subscription plan. Expired or suspended accounts are treated as the free plan by current_plan_id().';

-- ---------------------------------------------------------------------------
-- Preview flag. required_plan = free remains the stored mirror.
-- ---------------------------------------------------------------------------

alter table public.questions
  add column if not exists is_preview boolean not null default false;

update public.questions
set is_preview = (required_plan = 'free'::public.plan_tier)
where is_preview is distinct from (required_plan = 'free'::public.plan_tier);

create or replace function public.questions_sync_preview()
returns trigger
language plpgsql
as $$
begin
  new.is_preview := new.required_plan = 'free'::public.plan_tier;
  return new;
end;
$$;

drop trigger if exists questions_sync_preview on public.questions;
create trigger questions_sync_preview
  before insert or update of required_plan, is_preview on public.questions
  for each row execute function public.questions_sync_preview();

comment on column public.questions.is_preview is
  'Visible to every plan, including preview-only. Depth still follows the plan. Kept equal to required_plan = free.';

-- ---------------------------------------------------------------------------
-- Effective plan
-- ---------------------------------------------------------------------------

create or replace function public.current_plan_id(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.plan_suspended_at is not null then free_plan.id
    when p.plan_expires_at is not null and p.plan_expires_at < now() then free_plan.id
    else p.plan_id
  end
  from public.profiles p
  cross join lateral (
    select id from public.plans where code = 'free'
  ) free_plan
  where p.id = p_user_id;
$$;

comment on function public.current_plan_id(uuid) is
  'Plan that gates this account. The free plan when suspended or past plan_expires_at.';

revoke all on function public.current_plan_id(uuid) from public, anon;
grant execute on function public.current_plan_id(uuid) to authenticated, service_role;

create or replace function public.current_plan_detail()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(pl)
  from public.plans pl
  where pl.id = public.current_plan_id(auth.uid());
$$;

comment on function public.current_plan_detail() is
  'The signed-in student''s effective plan row, including entitlements.';

revoke all on function public.current_plan_detail() from public, anon;
grant execute on function public.current_plan_detail() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- One predicate for "is this question inside the plan's slice?"
-- Preview questions are always inside. preview_only plans see nothing else.
-- ---------------------------------------------------------------------------

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
  with plan as (
    select * from public.plans where id = p_plan_id
  ),
  q as (
    select id, kind, is_preview, is_active
    from public.questions
    where id = p_question_id
  ),
  viewer as (
    select university_id
    from public.profiles
    where id = p_user_id
  )
  select coalesce((
    select
      q.is_active
      and (
        q.is_preview
        or (
          plan.access_mode = 'filtered'
          and q.kind::text = any (plan.allowed_kinds)
          and (
            (
              not exists (
                select 1
                from public.question_appearances qa
                where qa.question_id = q.id
              )
              and plan.include_untagged
            )
            or exists (
              select 1
              from public.question_appearances qa
              join public.exam_papers ep on ep.id = qa.exam_paper_id
              join public.subjects s on s.id = ep.subject_id
              left join public.mbbs_phases ph on ph.id = s.mbbs_phase_id
              where qa.question_id = q.id
                and ep.exam_type = any (plan.allowed_exam_types)
                and (
                  plan.university_scope = 'all'
                  or ep.university_id = (select university_id from viewer)
                )
                and (
                  plan.mbbs_year_scope = 'all'
                  or ph.code::text = any (plan.mbbs_years)
                )
                and (
                  plan.exam_year_scope = 'all'
                  or (
                    plan.exam_year_scope = 'selected'
                    and ep.exam_year = any (plan.exam_years)
                  )
                  or (
                    plan.exam_year_scope = 'latest'
                    and ep.exam_year = (
                      select max(ep2.exam_year)
                      from public.exam_papers ep2
                      join public.subjects s2 on s2.id = ep2.subject_id
                      left join public.mbbs_phases ph2 on ph2.id = s2.mbbs_phase_id
                      where ep2.subject_id = ep.subject_id
                        and ep2.exam_type = any (plan.allowed_exam_types)
                        and (
                          plan.university_scope = 'all'
                          or ep2.university_id = (select university_id from viewer)
                        )
                        and (
                          plan.mbbs_year_scope = 'all'
                          or ph2.code::text = any (plan.mbbs_years)
                        )
                    )
                  )
                )
            )
          )
        )
      )
    from plan, q
  ), false);
$$;

comment on function public.plan_allows_question(uuid, uuid, uuid) is
  'True when the question is a preview or matches the plan slice (kind, university, exam type, MBBS year, paper year).';

revoke all on function public.plan_allows_question(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.plan_allows_question(uuid, uuid, uuid) to service_role;

create or replace function public.plan_allows_lesson(
  p_plan_id uuid,
  p_lesson_id uuid,
  p_user_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when pl.access_mode = 'preview_only' then exists (
        select 1
        from public.questions q
        where q.lesson_id = p_lesson_id
          and q.is_active
          and q.is_preview
      )
      else exists (
        select 1
        from public.lessons l
        join public.topics t on t.id = l.topic_id
        join public.subjects s on s.id = t.subject_id
        left join public.mbbs_phases ph on ph.id = s.mbbs_phase_id
        where l.id = p_lesson_id
          and (
            pl.mbbs_year_scope = 'all'
            or ph.code::text = any (pl.mbbs_years)
          )
      )
    end
    from public.plans pl
    where pl.id = p_plan_id
  ), false);
$$;

comment on function public.plan_allows_lesson(uuid, uuid, uuid) is
  'A lesson opens when its subject year is inside a filtered plan, or it contains a preview question on a preview-only plan.';

revoke all on function public.plan_allows_lesson(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.plan_allows_lesson(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Listings redact the stem, key, explanation, and sample answer.
-- Students no longer select questions or question_sample_answers directly.
-- ---------------------------------------------------------------------------

drop policy if exists "questions plan-gated select" on public.questions;
create policy "questions no direct select" on public.questions
  for select using (false);

revoke select on table public.questions from authenticated, anon;

drop policy if exists "sample answers pro" on public.question_sample_answers;
create policy "sample answers no direct select" on public.question_sample_answers
  for select using (false);

revoke select on table public.question_sample_answers from authenticated, anon;

create or replace view public.question_listings
with (security_invoker = false, security_barrier = true) as
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
    public.plan_allows_question(pl.id, q.id, auth.uid()) as in_slice,
    pl.tease_locked_questions as tease,
    pl.content_depth as depth
  from public.plans pl
  where pl.id = public.current_plan_id(auth.uid())
) gate on true
left join public.question_sample_answers sa on sa.question_id = q.id
where q.is_active
  and (gate.in_slice or gate.tease);

comment on view public.question_listings is
  'Active question cards for the signed-in plan. Out-of-slice rows are omitted unless the plan teases them, and then the stem, key, explanation, and sample answer are null.';

revoke all on table public.question_listings from public, anon;
grant select on table public.question_listings to authenticated, service_role;

-- pyq_teasers used to read questions directly. Students can no longer do that.
-- Replace in place so catalog search keeps working until it is rewritten below.
create or replace view public.pyq_teasers
with (security_invoker = true, security_barrier = true) as
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
  q.has_explanation,
  q.public_code,
  q.is_locked
from public.question_listings q;

comment on view public.pyq_teasers is
  'Listing cards from question_listings, plus how many papers a question appeared on. No answer key.';

revoke all on table public.pyq_teasers from public, anon;
grant select on table public.pyq_teasers to authenticated, service_role;

create or replace view public.lesson_access
with (security_invoker = false, security_barrier = true) as
select
  l.id as lesson_id,
  public.plan_allows_lesson(
    public.current_plan_id(auth.uid()),
    l.id,
    auth.uid()
  ) as is_open
from public.lessons l;

comment on view public.lesson_access is
  'Whether the signed-in plan may open each lesson.';

revoke all on table public.lesson_access from public, anon;
grant select on table public.lesson_access to authenticated, service_role;

drop policy if exists "lesson resources select" on public.lesson_resources;
create policy "lesson resources select" on public.lesson_resources
  for select using (
    is_free
    or public.plan_allows_lesson(
      public.current_plan_id(auth.uid()),
      lesson_id,
      auth.uid()
    )
  );

drop policy if exists "question resources select" on public.question_resources;
create policy "question resources select" on public.question_resources
  for select using (
    is_free
    or public.plan_allows_question(
      public.current_plan_id(auth.uid()),
      question_id,
      auth.uid()
    )
  );

drop policy if exists "tests select" on public.tests;
create policy "tests select" on public.tests
  for select using (
    owner_user_id = auth.uid()
    or (
      is_active
      and (
        required_plan = 'free'::public.plan_tier
        or exists (
          select 1
          from public.plans pl
          where pl.id = public.current_plan_id(auth.uid())
            and pl.access_mode = 'filtered'
        )
      )
    )
  );

drop policy if exists "test_questions select" on public.test_questions;
create policy "test_questions select" on public.test_questions
  for select using (
    exists (
      select 1
      from public.tests t
      where t.id = test_questions.test_id
        and (
          t.owner_user_id = auth.uid()
          or (
            t.is_active
            and (
              t.required_plan = 'free'::public.plan_tier
              or exists (
                select 1
                from public.plans pl
                where pl.id = public.current_plan_id(auth.uid())
                  and pl.access_mode = 'filtered'
              )
            )
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Device cap reads the plan row. A per-user raise still only raises.
-- ---------------------------------------------------------------------------

drop function if exists public.registered_device_limit(uuid, public.plan_tier);

create or replace function public.registered_device_limit(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    1,
    coalesce((
      select pl.max_registered_devices
      from public.plans pl
      where pl.id = public.current_plan_id(p_user_id)
    ), 1),
    coalesce((
      select pr.max_registered_devices
      from public.profiles pr
      where pr.id = p_user_id
    ), 0)
  );
$$;

comment on function public.registered_device_limit(uuid) is
  'Phone slots for one account: the higher of the effective plan and profiles.max_registered_devices.';

revoke all on function public.registered_device_limit(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Practice generator reads the plan row and the same question predicate.
-- ---------------------------------------------------------------------------

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

  v_plan_id := public.current_plan_id(auth.uid());
  select * into v_plan from public.plans where id = v_plan_id;
  if not found then
    raise exception 'PLAN_LIMITS_MISSING';
  end if;

  if not v_plan.allow_practice or v_plan.content_depth = 'stem' then
    raise exception 'PRACTICE_NOT_ON_PLAN';
  end if;

  if p_feedback_timing = 'immediate' and not v_plan.allow_tutor_mode then
    raise exception 'TUTOR_MODE_NOT_ON_PLAN';
  end if;

  if p_feedback_timing = 'on_submit' and not v_plan.allow_exam_mode then
    raise exception 'EXAM_MODE_NOT_ON_PLAN';
  end if;

  select p.university_id into v_university_id
  from public.profiles p
  where p.id = auth.uid();

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

  if v_plan.daily_practice_question_quota is not null then
    select coalesce(questions_used, 0) into v_used_today
    from public.daily_practice_usage
    where user_id = auth.uid() and usage_date = current_date;

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
    and public.plan_allows_question(v_plan_id, q.id, auth.uid())
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

comment on function public.create_practice_session(
  uuid[], uuid[], public.question_difficulty[], text, int, text, text, int, boolean, uuid[], uuid[]
) is
  'Creates an ephemeral MCQ practice test. Clamps to the caller''s plan row and only picks questions plan_allows_question accepts.';

-- ---------------------------------------------------------------------------
-- Search uses the listing view so stems stay redacted.
-- ---------------------------------------------------------------------------

create or replace function public.search_catalog(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text := '%' || coalesce(trim(p_query), '') || '%';
  v_plan_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if char_length(trim(coalesce(p_query, ''))) < 2 then
    return jsonb_build_object(
      'subjects', '[]'::jsonb,
      'lessons', '[]'::jsonb,
      'questions', '[]'::jsonb
    );
  end if;

  v_plan_id := public.current_plan_id(auth.uid());

  return jsonb_build_object(
    'subjects', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name))
      from public.subjects s
      where s.name ilike v_q
    ), '[]'::jsonb),
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'name', l.name, 'required_plan', l.required_plan
      ))
      from public.lessons l
      where l.is_active
        and l.name ilike v_q
        and public.plan_allows_lesson(v_plan_id, l.id, auth.uid())
      limit 20
    ), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'question_text', t.question_text,
        'lesson_id', t.lesson_id,
        'required_plan', t.required_plan,
        'is_locked', t.is_locked
      ))
      from public.question_listings t
      where t.question_text ilike v_q
      limit 20
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Plans are readable when public, or when this account is on that row.
-- ---------------------------------------------------------------------------

alter table public.plans enable row level security;

drop policy if exists "plans readable" on public.plans;
create policy "plans readable" on public.plans
  for select using (
    (is_public and is_active)
    or id = (
      select p.plan_id from public.profiles p where p.id = auth.uid()
    )
    or id = public.current_plan_id(auth.uid())
  );

grant select on table public.plans to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Signup still inserts plan = free. The profile trigger fills plan_id.
-- ---------------------------------------------------------------------------

comment on function public.handle_new_user() is
  'Creates a Free profile for a new auth user. profiles_sync_plan_id sets plan_id.';

-- ---------------------------------------------------------------------------
-- Admin: accept is_preview on question save and return it.
-- ---------------------------------------------------------------------------

do $patch$
declare
  v_def text;
  v_old text := $old$  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;$old$;
  v_new text := $new$  if p_body ? 'is_preview' then
    v_plan := case
      when coalesce((p_body->>'is_preview')::boolean, false) then 'free'
      else 'pro'
    end;
  end if;

  if v_plan not in ('free', 'pro', 'elite') then
    raise exception 'Pick a plan of free, pro, or elite.';
  end if;$new$;
begin
  v_def := pg_get_functiondef('public.admin_save_question(jsonb)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'admin_save_question plan check was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

do $patch$
declare
  v_def text;
  v_old text := $old$'required_plan', q.required_plan,$old$;
  v_new text := $new$'required_plan', q.required_plan,
    'is_preview', q.is_preview,$new$;
begin
  v_def := pg_get_functiondef('public.admin_get_question(uuid)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'admin_get_question required_plan field was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end
$patch$;

-- ---------------------------------------------------------------------------
-- Admin plan editor
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_plans()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(pl) order by pl.sort_order, pl.name)
    from public.plans pl
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_plans() from public, anon, authenticated;
grant execute on function public.admin_list_plans() to authenticated, service_role;

create or replace function public.admin_save_plan(p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := nullif(p_body->>'id', '')::uuid;
  v_code text := lower(btrim(coalesce(p_body->>'code', '')));
  v_name text := nullif(btrim(coalesce(p_body->>'name', '')), '');
  v_tagline text := nullif(btrim(coalesce(p_body->>'tagline', '')), '');
  v_benefits text[] := '{}';
  v_amount integer;
  v_months integer;
  v_label text := nullif(btrim(coalesce(p_body->>'duration_label', '')), '');
  v_devices integer;
  v_promo_headline text := nullif(btrim(coalesce(p_body->>'promo_headline', '')), '');
  v_promo_detail text := nullif(btrim(coalesce(p_body->>'promo_detail', '')), '');
  v_promo_code text;
  v_public boolean := coalesce((p_body->>'is_public')::boolean, false);
  v_active boolean := coalesce((p_body->>'is_active')::boolean, true);
  v_sort integer := coalesce((p_body->>'sort_order')::integer, 0);
  v_depth text := lower(btrim(coalesce(p_body->>'content_depth', 'explanation')));
  v_access text := lower(btrim(coalesce(p_body->>'access_mode', 'filtered')));
  v_kinds text[];
  v_university text := lower(btrim(coalesce(p_body->>'university_scope', 'all')));
  v_exam_types text[];
  v_mbbs_scope text := lower(btrim(coalesce(p_body->>'mbbs_year_scope', 'all')));
  v_mbbs_years text[];
  v_year_scope text := lower(btrim(coalesce(p_body->>'exam_year_scope', 'all')));
  v_exam_years integer[] := '{}';
  v_untagged boolean;
  v_tease boolean := coalesce((p_body->>'tease_locked_questions')::boolean, false);
  v_practice boolean := coalesce((p_body->>'allow_practice')::boolean, false);
  v_tutor boolean := coalesce((p_body->>'allow_tutor_mode')::boolean, false);
  v_exam boolean := coalesce((p_body->>'allow_exam_mode')::boolean, false);
  v_session integer;
  v_daily integer;
  v_existing_code text;
  v_item jsonb;
  v_year text;
begin
  perform public.assert_admin();

  if v_name is null then
    raise exception 'Name is required.';
  end if;
  if v_code !~ '^[a-z][a-z0-9_]{1,40}$' then
    raise exception 'Code must be a short lowercase slug.';
  end if;

  if v_id is not null then
    select code into v_existing_code from public.plans where id = v_id;
    if v_existing_code is null then
      raise exception 'Plan not found.';
    end if;
    if v_existing_code = 'free' and v_code <> 'free' then
      raise exception 'The free plan code cannot change.';
    end if;
  end if;

  if exists (
    select 1 from public.plans
    where code = v_code
      and id is distinct from v_id
  ) then
    raise exception 'That code is already used.';
  end if;

  select coalesce(array_agg(btrim(item)), '{}')
  into v_benefits
  from jsonb_array_elements_text(coalesce(p_body->'benefits', '[]'::jsonb)) as item
  where btrim(item) <> '';
  if cardinality(v_benefits) > 20 then
    raise exception 'Use at most 20 benefit lines.';
  end if;

  begin
    v_amount := coalesce((p_body->>'amount_paise')::integer, 0);
  exception
    when others then
      raise exception 'Price must be a whole number of paise.';
  end;
  if v_amount < 0 then
    raise exception 'Price cannot be negative.';
  end if;

  if nullif(btrim(coalesce(p_body->>'duration_months', '')), '') is null then
    v_months := null;
  else
    begin
      v_months := (p_body->>'duration_months')::integer;
    exception
      when others then
        raise exception 'Duration must be a number of months.';
    end;
  end if;

  if v_amount = 0 then
    v_months := null;
  elsif v_amount < 100 or v_months is null or v_months < 1 then
    raise exception 'A paid plan needs a price of at least ₹1 and a duration of at least 1 month.';
  end if;

  begin
    v_devices := coalesce((p_body->>'max_registered_devices')::integer, 1);
  exception
    when others then
      raise exception 'Device limit must be a number from 1 to 10.';
  end;
  if v_devices < 1 or v_devices > 10 then
    raise exception 'Device limit must be a number from 1 to 10.';
  end if;

  v_promo_code := public.normalize_discount_code(p_body->>'featured_discount_code');
  if nullif(btrim(coalesce(p_body->>'featured_discount_code', '')), '') is null then
    v_promo_code := null;
  elsif v_promo_code is null then
    raise exception 'That promo code is not valid.';
  elsif not exists (
    select 1
    from public.discount_codes d
    where d.code = v_promo_code
      and d.active
      and d.owner_user_id is null
      and (d.expires_at is null or d.expires_at > now())
  ) then
    raise exception 'Promo code must be an active public discount code.';
  end if;

  if v_depth not in ('stem', 'answer', 'explanation') then
    raise exception 'Content depth must be stem, answer, or explanation.';
  end if;
  if v_access not in ('preview_only', 'filtered') then
    raise exception 'Access must be preview only or a filtered bank.';
  end if;
  if v_university not in ('own', 'all') then
    raise exception 'University scope must be own or all.';
  end if;
  if v_mbbs_scope not in ('all', 'selected') then
    raise exception 'MBBS year scope must be all or selected.';
  end if;
  if v_year_scope not in ('all', 'latest', 'selected') then
    raise exception 'Paper year scope must be all, latest, or selected.';
  end if;

  select coalesce(array_agg(distinct lower(btrim(item))), '{}')
  into v_kinds
  from jsonb_array_elements_text(coalesce(p_body->'allowed_kinds', '[]'::jsonb)) as item;
  if v_kinds is null or cardinality(v_kinds) = 0
     or not v_kinds <@ array['mcq', 'pyq_theory']::text[] then
    raise exception 'Pick MCQ, theory, or both.';
  end if;

  select coalesce(array_agg(distinct lower(btrim(item))), '{}')
  into v_exam_types
  from jsonb_array_elements_text(coalesce(p_body->'allowed_exam_types', '[]'::jsonb)) as item;
  if v_exam_types is null or cardinality(v_exam_types) = 0
     or not v_exam_types <@ array['prof', 'supply', 'pre_prof', 'internal']::text[] then
    raise exception 'Pick at least one exam type.';
  end if;

  select coalesce(array_agg(distinct lower(btrim(item))), '{}')
  into v_mbbs_years
  from jsonb_array_elements_text(coalesce(p_body->'mbbs_years', '[]'::jsonb)) as item;
  if v_mbbs_scope = 'selected' then
    if v_mbbs_years is null or cardinality(v_mbbs_years) = 0
       or not v_mbbs_years <@ array['year1', 'year2', 'year3', 'year4']::text[] then
      raise exception 'Pick at least one MBBS year.';
    end if;
  else
    v_mbbs_years := '{}';
  end if;

  if v_year_scope = 'selected' then
    for v_item in select * from jsonb_array_elements(coalesce(p_body->'exam_years', '[]'::jsonb))
    loop
      begin
        v_year := v_item#>>'{}';
        if v_year::integer < 1990 or v_year::integer > 2100 then
          raise exception 'Paper years must be between 1990 and 2100.';
        end if;
        v_exam_years := v_exam_years || v_year::integer;
      exception
        when others then
          raise exception 'Paper years must be numbers.';
      end;
    end loop;
    if cardinality(v_exam_years) = 0 then
      raise exception 'Enter at least one paper year.';
    end if;
  end if;

  if p_body ? 'include_untagged' then
    v_untagged := coalesce((p_body->>'include_untagged')::boolean, false);
  else
    v_untagged := v_mbbs_scope = 'all' and v_year_scope = 'all';
  end if;

  if nullif(btrim(coalesce(p_body->>'max_practice_session_questions', '')), '') is null then
    v_session := null;
  else
    v_session := (p_body->>'max_practice_session_questions')::integer;
    if v_session < 1 then
      raise exception 'Practice session size must be at least 1, or empty for no cap.';
    end if;
  end if;

  if nullif(btrim(coalesce(p_body->>'daily_practice_question_quota', '')), '') is null then
    v_daily := null;
  else
    v_daily := (p_body->>'daily_practice_question_quota')::integer;
    if v_daily < 1 then
      raise exception 'Daily practice cap must be at least 1, or empty for no cap.';
    end if;
  end if;

  if v_practice and not v_tutor and not v_exam then
    raise exception 'Practice needs tutor mode, exam mode, or both.';
  end if;

  if v_id is null then
    insert into public.plans (
      code, name, tagline, benefits, amount_paise, duration_months, duration_label,
      max_registered_devices, promo_headline, promo_detail, featured_discount_code,
      is_public, is_active, sort_order, content_depth, access_mode, allowed_kinds,
      university_scope, allowed_exam_types, mbbs_year_scope, mbbs_years,
      exam_year_scope, exam_years, include_untagged, tease_locked_questions,
      allow_practice, allow_tutor_mode, allow_exam_mode,
      max_practice_session_questions, daily_practice_question_quota,
      allow_timer_toggle, allow_tag_filter, allow_difficulty_filter,
      allow_negative_marking_toggle, updated_at
    ) values (
      v_code, v_name, v_tagline, coalesce(v_benefits, '{}'), v_amount, v_months, v_label,
      v_devices, v_promo_headline, v_promo_detail, v_promo_code,
      v_public, v_active, v_sort, v_depth, v_access, v_kinds,
      v_university, v_exam_types, v_mbbs_scope, coalesce(v_mbbs_years, '{}'),
      v_year_scope, coalesce(v_exam_years, '{}'), v_untagged, v_tease,
      v_practice, v_tutor, v_exam,
      v_session, v_daily,
      coalesce((p_body->>'allow_timer_toggle')::boolean, false),
      coalesce((p_body->>'allow_tag_filter')::boolean, false),
      coalesce((p_body->>'allow_difficulty_filter')::boolean, false),
      coalesce((p_body->>'allow_negative_marking_toggle')::boolean, false),
      now()
    )
    returning id into v_id;
  else
    update public.plans
    set
      code = v_code,
      name = v_name,
      tagline = v_tagline,
      benefits = coalesce(v_benefits, '{}'),
      amount_paise = v_amount,
      duration_months = v_months,
      duration_label = v_label,
      max_registered_devices = v_devices,
      promo_headline = v_promo_headline,
      promo_detail = v_promo_detail,
      featured_discount_code = v_promo_code,
      is_public = v_public,
      is_active = v_active,
      sort_order = v_sort,
      content_depth = v_depth,
      access_mode = v_access,
      allowed_kinds = v_kinds,
      university_scope = v_university,
      allowed_exam_types = v_exam_types,
      mbbs_year_scope = v_mbbs_scope,
      mbbs_years = coalesce(v_mbbs_years, '{}'),
      exam_year_scope = v_year_scope,
      exam_years = coalesce(v_exam_years, '{}'),
      include_untagged = v_untagged,
      tease_locked_questions = v_tease,
      allow_practice = v_practice,
      allow_tutor_mode = v_tutor,
      allow_exam_mode = v_exam,
      max_practice_session_questions = v_session,
      daily_practice_question_quota = v_daily,
      allow_timer_toggle = coalesce((p_body->>'allow_timer_toggle')::boolean, false),
      allow_tag_filter = coalesce((p_body->>'allow_tag_filter')::boolean, false),
      allow_difficulty_filter = coalesce((p_body->>'allow_difficulty_filter')::boolean, false),
      allow_negative_marking_toggle = coalesce((p_body->>'allow_negative_marking_toggle')::boolean, false),
      updated_at = now()
    where id = v_id;
  end if;

  perform public.admin_log_action(
    'save_plan',
    null,
    jsonb_build_object('plan_id', v_id, 'code', v_code)
  );

  return (select to_jsonb(pl) from public.plans pl where pl.id = v_id);
end;
$$;

revoke all on function public.admin_save_plan(jsonb) from public, anon, authenticated;
grant execute on function public.admin_save_plan(jsonb) to authenticated, service_role;

comment on function public.admin_save_plan(jsonb) is
  'Creates or updates a plan. Price, duration, and entitlements are stored here. The client does not grant access.';

create or replace function public.admin_archive_plan(p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  perform public.assert_admin();

  select code into v_code from public.plans where id = p_plan_id;
  if v_code is null then
    raise exception 'Plan not found.';
  end if;
  if v_code = 'free' then
    raise exception 'The free plan cannot be archived.';
  end if;

  update public.plans
  set is_active = false,
      is_public = false,
      updated_at = now()
  where id = p_plan_id;

  perform public.admin_log_action(
    'archive_plan',
    null,
    jsonb_build_object('plan_id', p_plan_id, 'code', v_code)
  );

  return (select to_jsonb(pl) from public.plans pl where pl.id = p_plan_id);
end;
$$;

revoke all on function public.admin_archive_plan(uuid) from public, anon, authenticated;
grant execute on function public.admin_archive_plan(uuid) to authenticated, service_role;

comment on function public.admin_archive_plan(uuid) is
  'Hides a plan from new purchases. Accounts already on it keep it until expiry.';

-- ---------------------------------------------------------------------------
-- Assign any active plan. Replaces admin_set_plan(uuid, text, timestamptz).
-- ---------------------------------------------------------------------------

drop function if exists public.admin_set_plan(uuid, text, timestamptz);

create or replace function public.admin_set_plan(
  p_user_id uuid,
  p_plan_id uuid,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_active boolean;
begin
  perform public.assert_admin();

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'User not found.';
  end if;

  select code, is_active into v_code, v_active
  from public.plans
  where id = p_plan_id;

  if v_code is null then
    raise exception 'Pick an active plan.';
  end if;
  -- An archived plan cannot be newly assigned. Saving the plan someone
  -- already has still updates the expiry.
  if v_active is not true and p_plan_id is distinct from (
    select plan_id from public.profiles where id = p_user_id
  ) then
    raise exception 'Pick an active plan.';
  end if;

  update public.profiles
  set
    plan_id = p_plan_id,
    plan_started_at = now(),
    plan_expires_at = p_expires_at
  where id = p_user_id;

  perform public.release_extra_device_slots(
    p_user_id,
    public.registered_device_limit(p_user_id)
  );

  perform public.admin_log_action(
    'set_plan',
    p_user_id,
    jsonb_build_object(
      'plan_id', p_plan_id,
      'code', v_code,
      'plan_expires_at', p_expires_at
    )
  );

  return public.admin_user_json(p_user_id);
end;
$$;

revoke all on function public.admin_set_plan(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.admin_set_plan(uuid, uuid, timestamptz) to authenticated, service_role;

create or replace function public.admin_user_json(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'email', case
      when u.email ilike '%@auth.medico.internal' then null
      else u.email
    end,
    'full_name', p.full_name,
    'phone', coalesce(p.phone, u.phone),
    'plan', p.plan,
    'plan_id', p.plan_id,
    'plan_code', pl.code,
    'plan_name', pl.name,
    'plan_expires_at', p.plan_expires_at,
    'plan_suspended_at', p.plan_suspended_at,
    'blocked_at', p.blocked_at,
    'blocked_reason', p.blocked_reason,
    'university_id', p.university_id,
    'university_name', uni.name,
    'college_id', p.college_id,
    'college_name', col.name,
    'batch_year', p.batch_year,
    'mbbs_phase_id', p.mbbs_phase_id,
    'is_admin', p.is_admin,
    'created_at', p.created_at,
    'plan_device_limit', pl.max_registered_devices,
    'device_limit_override', p.max_registered_devices,
    'device_limit', public.registered_device_limit(p.id),
    'registered_device_count', (
      select count(*)::int
      from public.device_claims d
      where d.user_id = p.id
        and d.registered_at is not null
    ),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'device_id', listed.device_id,
        'last_seen_at', listed.last_seen_at,
        'registered_at', listed.registered_at
      ) order by listed.ord)
      from (
        select
          d.device_id,
          d.last_seen_at,
          d.registered_at,
          row_number() over (
            order by d.registered_at desc nulls last, d.last_seen_at desc
          ) as ord
        from public.device_claims d
        where d.user_id = p.id
        order by d.registered_at desc nulls last, d.last_seen_at desc
        limit 20
      ) listed
    ), '[]'::jsonb)
  )
  from public.profiles p
  join auth.users u on u.id = p.id
  join public.plans pl on pl.id = p.plan_id
  left join public.universities uni on uni.id = p.university_id
  left join public.colleges col on col.id = p.college_id
  where p.id = p_user_id;
$$;

create or replace function public.admin_set_device_limit(
  p_user_id uuid,
  p_max integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan_limit integer;
  v_plan_name text;
  v_stored integer;
begin
  perform public.assert_admin();

  select pl.max_registered_devices, pl.name
  into v_plan_limit, v_plan_name
  from public.profiles p
  join public.plans pl on pl.id = p.plan_id
  where p.id = p_user_id;

  if v_plan_name is null then
    raise exception 'User not found.';
  end if;

  if v_plan_limit is null or v_plan_limit < 1 then
    v_plan_limit := 1;
  end if;

  if p_max is not null and p_max > 10 then
    raise exception 'Device limit cannot be more than 10.';
  end if;

  if p_max is not null and p_max < v_plan_limit then
    raise exception '% already allows % phones. Enter % or more, or leave the box empty.',
      v_plan_name, v_plan_limit, v_plan_limit;
  end if;

  v_stored := case
    when p_max is null or p_max <= v_plan_limit then null::integer
    else p_max
  end;

  update public.profiles
  set max_registered_devices = v_stored
  where id = p_user_id;

  perform public.release_extra_device_slots(
    p_user_id,
    public.registered_device_limit(p_user_id)
  );

  perform public.admin_log_action(
    'set_device_limit',
    p_user_id,
    jsonb_build_object('max_registered_devices', v_stored)
  );

  return public.admin_user_json(p_user_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Checkout prices a plan row. Periods are gone.
-- ---------------------------------------------------------------------------

alter table public.payments
  add column if not exists plan_id uuid references public.plans (id);

drop function if exists public.checkout_quote(text, text, text);

create or replace function public.checkout_quote(
  p_plan_id uuid,
  p_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan public.plans%rowtype;
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

  select * into v_plan
  from public.plans
  where id = p_plan_id
    and is_active
    and is_public
    and amount_paise >= 100
    and duration_months is not null;

  if v_plan.id is null then
    raise exception 'Choose a plan.';
  end if;

  if p_code is null or length(trim(p_code)) = 0 then
    return jsonb_build_object(
      'plan_id', v_plan.id,
      'code', v_plan.code,
      'name', v_plan.name,
      'duration_months', v_plan.duration_months,
      'duration_label', v_plan.duration_label,
      'discount_code', null,
      'percent_off', null,
      'list_amount_paise', v_plan.amount_paise,
      'amount_paise', v_plan.amount_paise,
      'currency', 'INR'
    );
  end if;

  v_code := public.normalize_discount_code(p_code);
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

  v_amount := public.discounted_amount_paise(v_plan.amount_paise, v_percent);
  if v_amount < 100 or v_amount >= v_plan.amount_paise then
    raise exception 'That discount is too large for this plan.';
  end if;

  return jsonb_build_object(
    'plan_id', v_plan.id,
    'code', v_plan.code,
    'name', v_plan.name,
    'duration_months', v_plan.duration_months,
    'duration_label', v_plan.duration_label,
    'discount_code', v_code,
    'percent_off', v_percent,
    'list_amount_paise', v_plan.amount_paise,
    'amount_paise', v_amount,
    'currency', 'INR'
  );
end;
$$;

comment on function public.checkout_quote(uuid, text) is
  'List or discounted price for one plan. Does not create a charge.';

revoke all on function public.checkout_quote(uuid, text) from public, anon;
grant execute on function public.checkout_quote(uuid, text) to authenticated;

drop function if exists public.apply_razorpay_payment(text, text, uuid, public.plan_tier, integer, text, text, text);

create or replace function public.apply_razorpay_payment(
  p_payment_id text,
  p_order_id text,
  p_user_id uuid,
  p_plan_id uuid,
  p_amount_paise integer,
  p_currency text,
  p_discount_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.plans%rowtype;
  v_expected integer;
  v_code text;
  v_percent integer;
  v_tier public.plan_tier;
  v_inserted text;
  v_expires_at timestamptz;
  v_plan_id uuid;
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

  select * into v_plan
  from public.plans
  where id = p_plan_id
    and is_active
    and amount_paise >= 100
    and duration_months is not null;

  if v_plan.id is null then
    raise exception 'unsupported plan';
  end if;

  v_code := public.normalize_discount_code(p_discount_code);
  if p_discount_code is null or length(trim(p_discount_code)) = 0 then
    v_code := null;
    v_percent := null;
    v_expected := v_plan.amount_paise;
  else
    if v_code is null then
      raise exception 'amount does not match catalog';
    end if;
    select percent_off into v_percent
    from public.discount_codes
    where code = v_code;
    if v_percent is null then
      raise exception 'amount does not match catalog';
    end if;
    v_expected := public.discounted_amount_paise(v_plan.amount_paise, v_percent);
  end if;

  if p_amount_paise is distinct from v_expected then
    raise exception 'amount does not match catalog';
  end if;
  if p_currency is distinct from 'INR' then
    raise exception 'currency does not match catalog';
  end if;

  v_tier := case
    when v_plan.code in ('pro', 'elite') then v_plan.code::public.plan_tier
    else 'pro'::public.plan_tier
  end;

  insert into public.payments (
    razorpay_payment_id,
    razorpay_order_id,
    user_id,
    plan,
    plan_id,
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
    v_tier,
    v_plan.id,
    p_amount_paise,
    p_currency,
    v_code,
    v_plan.amount_paise,
    v_percent,
    null
  )
  on conflict (razorpay_payment_id) do nothing
  returning razorpay_payment_id into v_inserted;

  if v_inserted is null then
    select pr.plan_id, pr.plan_expires_at
      into v_plan_id, v_expires_at
    from public.payments pay
    join public.profiles pr on pr.id = pay.user_id
    where pay.razorpay_payment_id = p_payment_id;

    return jsonb_build_object(
      'applied', false,
      'duplicate', true,
      'plan_id', v_plan_id,
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
    plan_id = v_plan.id,
    plan_started_at = now(),
    plan_expires_at = greatest(now(), coalesce(plan_expires_at, now()))
      + make_interval(months => v_plan.duration_months)
  where id = p_user_id
  returning plan_id, plan_expires_at into v_plan_id, v_expires_at;

  if v_plan_id is null then
    raise exception 'profile not found';
  end if;

  perform public.release_extra_device_slots(
    p_user_id,
    public.registered_device_limit(p_user_id)
  );

  return jsonb_build_object(
    'applied', true,
    'duplicate', false,
    'plan_id', v_plan_id,
    'plan_expires_at', v_expires_at
  );
end;
$$;

comment on function public.apply_razorpay_payment(text, text, uuid, uuid, integer, text, text) is
  'Idempotent plan grant after a verified payment.captured webhook. Amount and months come from the plan row.';

revoke all on function public.apply_razorpay_payment(text, text, uuid, uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.apply_razorpay_payment(text, text, uuid, uuid, integer, text, text) to service_role;
