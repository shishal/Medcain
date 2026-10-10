# Database Schema (Supabase / Postgres)

Run these in the Supabase SQL editor in order. Each block is idempotent-ish (uses `if not exists` where sensible) but review before running against a live project.

## 1. Enums

```sql
create type plan_tier as enum ('free', 'pro', 'elite');
create type test_type as enum ('mini', 'subject', 'mock', 'grand');
create type attempt_status as enum ('in_progress', 'submitted', 'abandoned');
-- Revision priority (MoSCoW), not a difficulty scale. The type name is
-- historical; `20260916120000_review_fixes.sql` renamed the values.
create type question_difficulty as enum ('could', 'should', 'must');
```

## 2. Core tables

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  plan plan_tier not null default 'free',
  plan_started_at timestamptz,
  plan_expires_at timestamptz,
  -- Single-device login + multi-device suspension (migration
  -- `20260919140000_single_device_login.sql`). Students cannot UPDATE these.
  active_device_id text,
  active_device_claimed_at timestamptz,
  plan_suspended_at timestamptz,
  plan_suspend_reason text,
  created_at timestamptz not null default now()
);

create table subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  display_order int not null default 0
);

create table topics (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references subjects(id) on delete cascade,
  name text not null,
  display_order int not null default 0,
  unique (subject_id, name)       -- Phase 2.2 sheet upsert key
);
create index idx_topics_subject on topics(subject_id);

create table questions (
  id uuid primary key default gen_random_uuid(),
  external_id text unique,        -- Phase 2.2 Google Sheet stable id (e.g. Q-MED-CARD-001)
  topic_id uuid not null references topics(id) on delete restrict,
  question_text text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option char(1) not null check (correct_option in ('A','B','C','D')),
  explanation_text text,
  explanation_video_url text,
  image_url text,
  difficulty question_difficulty not null default 'should',
  source text,                    -- e.g. 'PYQ 2024', 'Custom'
  required_plan plan_tier not null default 'free',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index idx_questions_topic on questions(topic_id);
create index idx_questions_active on questions(is_active) where is_active;

create table tests (
  id uuid primary key default gen_random_uuid(),
  title text not null,            -- catalog uniqueness is tests_catalog_title_key (partial); sheet upserts use sheet_key
  description text,
  test_type test_type not null,
  subject_id uuid references subjects(id),          -- null for mixed-subject tests
  required_plan plan_tier not null default 'free',
  is_sectional boolean not null default false,
  section_count int not null default 1,
  questions_per_section int,
  section_duration_minutes int,
  total_duration_minutes int not null,
  total_questions int not null,
  correct_marks numeric not null default 4,
  incorrect_marks numeric not null default -1,
  unattempted_marks numeric not null default 0,
  is_live boolean not null default false,             -- pan-India timed "live" test
  live_start_at timestamptz,
  live_end_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table test_questions (
  test_id uuid not null references tests(id) on delete cascade,
  question_id uuid not null references questions(id) on delete restrict,
  section_number int not null default 1,
  order_index int not null,
  primary key (test_id, question_id)
);
create index idx_test_questions_test on test_questions(test_id);

create table attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  test_id uuid not null references tests(id) on delete restrict,
  status attempt_status not null default 'in_progress',
  started_at timestamptz not null default now(),
  -- Phase 5.3: section_number → timestamptz. Timer remaining is always
  -- duration - (now - this timestamp), never a saved countdown.
  section_started_at jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  total_score numeric,
  correct_count int,
  incorrect_count int,
  unattempted_count int,
  percentile numeric,
  created_at timestamptz not null default now()
);
create index idx_attempts_user on attempts(user_id);
create index idx_attempts_test on attempts(test_id);
-- One in-progress attempt per user+test (Phase 5.1). Submitted rows are
-- excluded so a later retake can insert a new in_progress row.
create unique index idx_attempts_one_in_progress
  on attempts(user_id, test_id)
  where status = 'in_progress';

create table attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references attempts(id) on delete cascade,
  question_id uuid not null references questions(id) on delete restrict,
  selected_option char(1) check (selected_option in ('A','B','C','D')),
  is_marked_for_review boolean not null default false,
  time_spent_seconds int not null default 0,
  answered_at timestamptz,
  unique (attempt_id, question_id)
);
create index idx_attempt_answers_attempt on attempt_answers(attempt_id);

create table bookmarks (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, question_id)
);
```

## 3. New-user trigger (auto-create a profile row on signup)

```sql
create function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, plan)
  values (new.id, 'free');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();
```

## 4. Plan-comparison helper (used by RLS)

```sql
create function plan_rank(p plan_tier) returns int
language sql immutable as $$
  select case p when 'free' then 0 when 'pro' then 1 when 'elite' then 2 end;
$$;

-- Returns the user's *effective* plan, falling back to 'free' if their paid
-- plan expired OR if plan_suspended_at is set (multi-device sharing).
create function current_plan(p_user_id uuid) returns plan_tier
language sql stable as $$
  select case
    when plan_suspended_at is not null then 'free'::plan_tier
    when plan_expires_at is not null and plan_expires_at < now() then 'free'::plan_tier
    else plan
  end
  from profiles where id = p_user_id;
$$;

-- Phase 5.3: remaining time is duration - (server_now() - started_at).
-- The client uses this when the device clock disagrees by more than ~2 minutes.
create function server_now() returns timestamptz
language sql stable as $$ select now(); $$;
```

**Validation for this step**: after running, manually set a test profile's `plan_expires_at` to yesterday and confirm `select current_plan('<that-user-id>')` returns `'free'` even though the `plan` column still says `'pro'`. Also set `plan_suspended_at = now()` with a future `plan_expires_at` and confirm `current_plan` is `'free'`. This is the exact bug class that causes "I cancelled and I'm still being charged/still have access" support tickets — test it now, not after launch.

## 5. Row-Level Security

RLS policies decide *which rows* a role can see. Postgres also needs
**table GRANTs** so `authenticated` / `service_role` can touch the tables at
all — without them, PostgREST returns `permission denied` before any policy
runs. Apply the grants below (or the `phase1_4_grants` migration) after the
policies.

```sql
alter table profiles enable row level security;
alter table subjects enable row level security;
alter table topics enable row level security;
alter table questions enable row level security;
alter table tests enable row level security;
alter table test_questions enable row level security;
alter table attempts enable row level security;
alter table attempt_answers enable row level security;
alter table bookmarks enable row level security;

-- Privileges for API roles (RLS still filters rows)
grant usage on schema public to anon, authenticated, service_role;
grant select on table profiles to authenticated;
-- Phase 7.3: students cannot write plan / plan_expires_at — webhook RPC only.
grant update (full_name, phone) on table profiles to authenticated;
grant select on table subjects to authenticated;
grant select on table topics to authenticated;
grant select on table questions to authenticated;
grant select on table tests to authenticated;
grant select on table test_questions to authenticated;
-- attempts insert/update is column-restricted in Phase 6.1 so the client
-- cannot write total_score. See §6.1.
grant select, insert, update on table attempts to authenticated;
grant select, insert, update on table attempt_answers to authenticated;
grant select, insert, update, delete on table bookmarks to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function plan_rank(plan_tier) to authenticated, service_role;
grant execute on function current_plan(uuid) to authenticated, service_role;
grant execute on function server_now() to authenticated;
grant execute on function submit_attempt(uuid, jsonb) to authenticated;
grant execute on function get_attempt_results(uuid) to authenticated;
-- calculate_percentile is not granted to authenticated — see §6.1.
-- apply_razorpay_payment is not granted to authenticated — see §8.

-- profiles: users see/edit only their own row
create policy "own profile select" on profiles for select using (auth.uid() = id);
create policy "own profile update" on profiles for update using (auth.uid() = id);

-- subjects/topics/lessons: readable by any authenticated user, NOT plan-gated,
-- even though subjects and lessons carry a required_plan. This is deliberate:
-- the catalog reads these tables directly and renders Pro rows with a padlock
-- that routes to the upgrade screen, so gating the names would delete the
-- upgrade prompt. Paid content (stems, MCQ keys, explanations, sample answers)
-- is gated by the `questions` policy and question_sample_answers RLS.
create policy "subjects readable" on subjects for select using (auth.role() = 'authenticated');
create policy "topics readable" on topics for select using (auth.role() = 'authenticated');
create policy "lessons readable" on lessons for select using (auth.role() = 'authenticated');

-- questions: only visible if the user's current plan meets the question's required plan
create policy "questions plan-gated select" on questions for select using (
  is_active
  and plan_rank(current_plan(auth.uid())) >= plan_rank(required_plan)
);

-- tests: same pattern
create policy "tests plan-gated select" on tests for select using (
  is_active
  and plan_rank(current_plan(auth.uid())) >= plan_rank(required_plan)
);

-- test_questions: visible if the parent test is visible (join through)
create policy "test_questions via test" on test_questions for select using (
  exists (
    select 1 from tests t
    where t.id = test_questions.test_id
    and t.is_active
    and plan_rank(current_plan(auth.uid())) >= plan_rank(t.required_plan)
  )
);

-- attempts: users only see/create/update their own
create policy "own attempts select" on attempts for select using (auth.uid() = user_id);
create policy "own attempts insert" on attempts for insert with check (auth.uid() = user_id);
create policy "own attempts update" on attempts for update using (auth.uid() = user_id);

-- attempt_answers: users only touch answers belonging to their own attempts
create policy "own answers select" on attempt_answers for select using (
  exists (select 1 from attempts a where a.id = attempt_answers.attempt_id and a.user_id = auth.uid())
);
create policy "own answers insert" on attempt_answers for insert with check (
  exists (select 1 from attempts a where a.id = attempt_answers.attempt_id and a.user_id = auth.uid())
);
create policy "own answers update" on attempt_answers for update using (
  exists (select 1 from attempts a where a.id = attempt_answers.attempt_id and a.user_id = auth.uid())
);

-- bookmarks: fully own-user
create policy "own bookmarks all" on bookmarks for all using (auth.uid() = user_id);
```

**Important note for the AI agent doing this task**: `questions.explanation_text` and `explanation_video_url` are covered by the same plan-gated SELECT policy as the rest of the row — do not create a separate, looser policy for "just the explanation," even if a future task asks for a "preview the solution" feature. If you need a genuine free preview of a paid question, that should be a deliberate, separate `is_preview` boolean column with its own narrow policy, not a loosened blanket policy.

### 5.1 Catalog test teasers (Phase 4.2) — retired

Mini / Subject / Mock / Grand list is gone. Drop leftover view with
`supabase/migrations/20260913160000_drop_catalog_test_teasers.sql`.
Practice still uses `tests` / `test_questions` / `attempts`.

### 5.2 One in-progress attempt (Phase 5.1)

A student must not get a second `attempts` row for the same test while one is still `in_progress`. Retakes after submit are allowed — the index is partial.

```sql
create unique index if not exists idx_attempts_one_in_progress
  on public.attempts (user_id, test_id)
  where status = 'in_progress';
```

## 6. Percentile calculation (simple version for Phase 1)

```sql
create function calculate_percentile(p_test_id uuid, p_score numeric) returns numeric
language sql stable as $$
  select round(
    100.0 * (select count(*) from attempts
              where test_id = p_test_id and status = 'submitted' and total_score <= p_score)
    / nullif((select count(*) from attempts where test_id = p_test_id and status = 'submitted'), 0)
  , 1);
$$;
```

Call this right after an attempt is marked `submitted`, store the result on `attempts.percentile`. This is a live, keeps-shifting percentile (recalculating it for *everyone* who took the test as more people submit is a Phase 2 nice-to-have, not required for launch — the score users see the moment they finish is what matters most).

`calculate_percentile` must run as `security definer` (and must **not** be granted to `authenticated`). RLS on `attempts` is "own rows only" — if this ran as the student, their percentile would be computed against a 1-row set (themselves) and always come back as `100`. `submit_attempt` is the only caller.

### 6.1 Submit and score (Phase 6.1)

The client sends answers only. Scoring uses the test row's `correct_marks` / `incorrect_marks` / `unattempted_marks` and the spec in `04_TEST_ENGINE_SPEC.md` §5. Missing `attempt_answers` rows and `selected_option is null` both count as unattempted. A retry against an already-`submitted` attempt returns the stored scores and ignores new answers.

Column-level GRANTs on `attempts` block the client from writing `total_score` / counts / `percentile` / `status` after insert. Answer INSERT/UPDATE policies require `attempts.status = 'in_progress'` so scores cannot be changed after submit. `submit_attempt` is `security definer` so it can still write those rows.

```sql
create or replace function submit_attempt(p_attempt_id uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer
set search_path = public as $$
-- lock attempt; reject if not owned / not in_progress (unless already submitted)
-- upsert p_answers into attempt_answers (only question_ids on this test)
-- score every test_questions row; write status, counts, total_score, submitted_at
-- percentile := calculate_percentile(test_id, total_score); return the scored row
$$;
```

`p_answers` is a JSON array of `{question_id, selected_option, is_marked_for_review, time_spent_seconds}`. `selected_option` is `A`/`B`/`C`/`D` or null. The Flutter client must not send `total_score`.

### 6.2 Results summary (Phase 6.2)

The results screen reads stored `total_score` / counts / `percentile` — it does not re-score. Subject-wise correct/incorrect/unattempted uses the same classification as §5 of the test-engine spec. Time spent is wall-clock `submitted_at - started_at`.

Subject resolution walks `questions.topic_id → topics.subject_id`, falling back to the lesson's topic and then to the question's newest exam paper. `topic_id` became nullable in the UG pivot, so the original inner join to `topics` silently dropped untagged questions from the breakdown while they still counted in the stored totals. The fallbacks are **scalar subqueries, not joins**, so each question contributes exactly one row and the per-subject counts still sum to the stored attempt totals.

`get_attempt_results` is `security definer` so a student can still open their own submitted results if their plan later drops below a question's `required_plan` (a client-side join through `questions` would be blocked by that RLS policy).

```sql
create or replace function get_attempt_results(p_attempt_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public as $$
-- reject if not authenticated / not owned / not submitted
-- return stored score fields + test title/marking + duration_seconds
-- + subjects[] of {subject_id, subject_name, correct/incorrect/unattempted_count}
$$;
```

### 6.3 Solution review (Phase 6.3)

The review screen fetches `questions` (including `explanation_text`) through the same client-side RLS path as the test player. Do **not** return explanation content from `get_attempt_results` or any other `security definer` function — that would bypass plan gating.

`tests.show_explanation_level` (`none` / `answer_only` / `full`) is a UI filter on data the student is already allowed to read, not a second access-control check (see `05_PRACTICE_MODE_SPEC.md` §3). Catalog tests default to `full`. If a question row is hidden by RLS, the review screen shows a plan-locked placeholder rather than crashing.

## 7. Practice Mode additions

Practice Mode is **not** a separate system — a practice session is an ephemeral, personally-owned row in the existing `tests` table, generated on demand from a student's filters, then run through the exact same attempt/timer/scoring flow as a catalog test (with a few behavioral flags different — see `05_PRACTICE_MODE_SPEC.md`). This section adds what's needed to support that: a tagging system, per-plan limits stored as data, and a server-side generator function.

### 7.1 Tags

```sql
create table tags (
  id uuid primary key default gen_random_uuid(),
  name text not null unique          -- e.g. 'PYQ', 'HighYield', 'RecentUpdate', 'OneLiner', 'ClinicalVignette'
);

create table question_tags (
  question_id uuid not null references questions(id) on delete cascade,
  tag_id uuid not null references tags(id) on delete cascade,
  primary key (question_id, tag_id)
);
create index idx_question_tags_tag on question_tags(tag_id);
```

Add a `Tags` tab to the Google Sheet (comma-separated tag names per question row) so content entry can assign tags the same way it assigns subjects/topics — extend the Phase 2 sync script to handle this, creating any new tag by name automatically.

### 7.2 Plan limits (data-driven, not hardcoded)

```sql
create table plan_limits (
  plan plan_tier primary key,
  max_practice_session_questions int not null,
  daily_practice_question_quota int,              -- null = unlimited
  allow_full_explanation boolean not null default true,
  allow_timer_toggle boolean not null default true,
  allow_tag_filter boolean not null default true,
  allow_difficulty_filter boolean not null default true,
  allow_negative_marking_toggle boolean not null default true
);

-- Starting defaults — a product decision, not an engineering one. Change any time by
-- updating this table; no app rebuild needed since the generator function reads it live.
insert into plan_limits (plan, max_practice_session_questions, daily_practice_question_quota, allow_full_explanation, allow_timer_toggle, allow_tag_filter, allow_difficulty_filter, allow_negative_marking_toggle) values
  ('free',  10,  20,   false, false, false, true,  false),
  ('pro',   50,  null, true,  true,  true,  true,  true),
  ('elite', 100, null, true,  true,  true,  true,  true);
```

Suggested rationale for these defaults, adjust freely: free users get a small taste (10 questions/session, 20/day, answer-only feedback, no tag/timer control — enough to evaluate the product, not enough to fully self-study for free). Pro and Elite differ mainly in session size and daily ceiling, since the meaningful feature gate (full explanations, tag filtering) is the same for both — differentiate Elite further later with things like audio explanations or unlimited resets once you have those.

### 7.3 Daily usage tracking

```sql
create table daily_practice_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  questions_used int not null default 0,
  primary key (user_id, usage_date)
);
```

### 7.4 Extend `tests` for ephemeral practice sessions

```sql
alter table tests
  add column owner_user_id uuid references auth.users(id),      -- null for shared catalog tests
  add column is_ephemeral_practice boolean not null default false,
  add column feedback_timing text not null default 'on_submit' check (feedback_timing in ('immediate','on_submit')),
  add column show_explanation_level text not null default 'full' check (show_explanation_level in ('none','answer_only','full')),
  add column timer_enabled boolean not null default true,
  add column practice_filter_criteria jsonb;                    -- stores the filters used, for a "redo similar" feature later

-- Catalog titles stay unique among owner-less rows; practice sessions may
-- all be titled 'Practice Session'. PostgREST upserts cannot target a
-- partial unique index (error 42P10), so catalog sync uses sheet_key.
alter table tests drop constraint if exists tests_title_key;
create unique index tests_catalog_title_key
  on tests (title)
  where owner_user_id is null;
alter table tests add column sheet_key text unique;  -- NULL on practice rows
```

### 7.5 RLS updates (tests/test_questions must also allow the owner to see their own practice session)

```sql
drop policy "tests plan-gated select" on tests;
create policy "tests select" on tests for select using (
  (is_active and plan_rank(current_plan(auth.uid())) >= plan_rank(required_plan))
  or owner_user_id = auth.uid()
);

drop policy "test_questions via test" on test_questions;
create policy "test_questions select" on test_questions for select using (
  exists (
    select 1 from tests t
    where t.id = test_questions.test_id
    and (
      (t.is_active and plan_rank(current_plan(auth.uid())) >= plan_rank(t.required_plan))
      or t.owner_user_id = auth.uid()
    )
  )
);
```

Note there's deliberately no direct client INSERT policy on `tests`/`test_questions` for practice sessions — creation only happens through the function below, so tier limits can't be bypassed by a modified client sending its own rows.

### 7.6 Practice session generator function

This is the one piece of SQL in the whole schema worth a second, careful read before you trust it — it's the thing standing between a free user and unlimited paid content if it has a bug.

```sql
create or replace function create_practice_session(
  p_topic_ids uuid[],
  p_tag_ids uuid[],
  p_difficulties question_difficulty[],
  p_source_filter text,        -- 'unattempted' | 'incorrect' | 'bookmarked' | 'all'
  p_question_count int,
  p_feedback_timing text,      -- 'immediate' | 'on_submit'
  p_explanation_level text,    -- 'none' | 'answer_only' | 'full'
  p_timer_minutes int,         -- null if the student turned the timer off
  p_negative_marking boolean
) returns uuid
language plpgsql security definer as $$
declare
  v_plan plan_tier;
  v_limits plan_limits%rowtype;
  v_test_id uuid;
  v_effective_count int;
  v_effective_explanation text;
  v_used_today int;
begin
  v_plan := current_plan(auth.uid());
  select * into v_limits from plan_limits where plan = v_plan;

  v_effective_count := least(p_question_count, v_limits.max_practice_session_questions);

  v_effective_explanation := case
    when p_explanation_level = 'full' and not v_limits.allow_full_explanation then 'answer_only'
    else p_explanation_level
  end;

  if v_limits.daily_practice_question_quota is not null then
    select coalesce(questions_used, 0) into v_used_today
    from daily_practice_usage where user_id = auth.uid() and usage_date = current_date;

    if coalesce(v_used_today, 0) + v_effective_count > v_limits.daily_practice_question_quota then
      v_effective_count := greatest(v_limits.daily_practice_question_quota - coalesce(v_used_today, 0), 0);
    end if;

    if v_effective_count <= 0 then
      raise exception 'DAILY_PRACTICE_QUOTA_EXCEEDED';
    end if;
  end if;

  insert into tests (
    title, test_type, required_plan, total_duration_minutes, total_questions,
    correct_marks, incorrect_marks, unattempted_marks, is_active,
    owner_user_id, is_ephemeral_practice, feedback_timing, show_explanation_level,
    timer_enabled, practice_filter_criteria
  ) values (
    'Practice Session', 'mini', 'free',
    coalesce(p_timer_minutes, 0), v_effective_count,
    case when p_negative_marking then 4 else 1 end,
    case when p_negative_marking then -1 else 0 end,
    0, false,
    auth.uid(), true, p_feedback_timing, v_effective_explanation,
    p_timer_minutes is not null,
    jsonb_build_object('topic_ids', p_topic_ids, 'tag_ids', p_tag_ids, 'difficulties', p_difficulties, 'source_filter', p_source_filter)
  ) returning id into v_test_id;

  insert into test_questions (test_id, question_id, section_number, order_index)
  select v_test_id, q.id, 1, row_number() over (order by random())
  from questions q
  where q.is_active
    and plan_rank(v_plan) >= plan_rank(q.required_plan)          -- re-check plan gating manually: security definer bypasses RLS
    and (p_topic_ids is null or q.topic_id = any(p_topic_ids))
    and (p_difficulties is null or q.difficulty = any(p_difficulties))
    and (p_tag_ids is null or exists (
          select 1 from question_tags qt where qt.question_id = q.id and qt.tag_id = any(p_tag_ids)))
    and (
      p_source_filter = 'all'
      or (p_source_filter = 'bookmarked' and exists (
            select 1 from bookmarks b where b.question_id = q.id and b.user_id = auth.uid()))
      or (p_source_filter = 'incorrect' and exists (
            select 1 from attempt_answers aa join attempts a on a.id = aa.attempt_id
            where a.user_id = auth.uid() and aa.question_id = q.id
            and aa.selected_option is distinct from q.correct_option))
      or (p_source_filter = 'unattempted' and not exists (
            select 1 from attempt_answers aa join attempts a on a.id = aa.attempt_id
            where a.user_id = auth.uid() and aa.question_id = q.id and aa.selected_option is not null))
    )
  order by random()
  limit v_effective_count;

  insert into daily_practice_usage (user_id, usage_date, questions_used)
  values (auth.uid(), current_date, v_effective_count)
  on conflict (user_id, usage_date) do update
    set questions_used = daily_practice_usage.questions_used + v_effective_count;

  return v_test_id;
end;
$$;
```

**Validation for this function specifically**: as a free-tier test user, call it requesting `p_question_count = 999` and `p_explanation_level = 'full'` — confirm the returned session has at most 10 questions (the free-tier `max_practice_session_questions`) and that `show_explanation_level` was silently downgraded to `'answer_only'` on the created row, not honored as `'full'`. This is the single most important test in this whole addition: it's proving the limit can't be bypassed by just asking for more.

## 8. Payments (Phase 7.3)

Razorpay's webhook hits a Supabase Edge Function (`razorpay-webhook`). That function's only job is to verify `X-Razorpay-Signature` (HMAC-SHA256 of the **raw** body with `RAZORPAY_WEBHOOK_SECRET`). After a valid `payment.captured` event, it calls `apply_razorpay_payment()` — it does **not** write `profiles.plan` itself.

Amount and duration live in `paid_plan_catalog` (Pro and Elite rows). `paid_plan_terms()` reads that table. Change a live price with `UPDATE` in the SQL editor — see `docs/06_PAYMENTS_PRODUCTION.md`. Students can `SELECT` the catalog and cannot write it. A signed webhook that claims Elite but paid the Pro amount is rejected against the current row. A `discount_code` on the order is priced from `discount_codes.percent_off` inside `apply_razorpay_payment` — the client never sends an amount. Issue codes with `issue_discount_code()` (service role / SQL editor only). The code's owner can `SELECT` their own row; they cannot redeem it.

```sql
create table payments (
  razorpay_payment_id text primary key,
  razorpay_order_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan plan_tier not null,
  amount_paise int not null,
  currency text not null,
  applied_at timestamptz not null default now()
);

create function apply_razorpay_payment(
  p_payment_id text,
  p_order_id text,
  p_user_id uuid,
  p_plan plan_tier,
  p_amount_paise int,
  p_currency text
) returns jsonb
language plpgsql security definer
set search_path = public as $$
-- reject unknown plan / amount / currency (catalog: pro 149900/180d, elite 299900/365d)
-- insert payments; on unique payment id, return {applied:false, duplicate:true}
-- else set profiles.plan, plan_started_at,
--   plan_expires_at = greatest(now(), coalesce(plan_expires_at, now())) + duration
--   (stacks onto time the student already paid for; renewing early used to
--    reset the expiry and throw the remainder away)
$$;
```

`apply_razorpay_payment` is **not** granted to `authenticated` (same reason as `calculate_percentile`). The Flutter client never calls it. Students also cannot `UPDATE` `profiles.plan` / `plan_expires_at` — those columns are revoked from the `authenticated` role; only `full_name` and `phone` remain updatable.

Idempotency: Razorpay retries. The unique `razorpay_payment_id` means a second delivery returns `duplicate: true` and does not add more days.

**Validation**: complete a Test Mode payment, watch `profiles.plan` change in Table Editor, then `POST` the same Edge Function URL with no `X-Razorpay-Signature` header and confirm HTTP 400. Script: `python3 scripts/validate_phase7_3_webhook.py`.

## 9. Screenshot events (Phase 8.1)

iOS cannot prevent screenshots. The question player and solution review still detect the attempt, warn the student, and insert a row here so repeat capture can be reviewed. Android blocks the capture via `FLAG_SECURE` (`no_screenshot`); detected attempts are logged the same way.

```sql
create table screenshot_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  screen text not null,          -- 'test_player' | 'solution_review' | 'pyq_reader'
  event_type text not null check (event_type in ('screenshot', 'screen_recording')),
  created_at timestamptz not null default now()
);

alter table screenshot_events enable row level security;
create policy "own screenshot events insert" on screenshot_events
  for insert with check (auth.uid() = user_id);

grant insert on table screenshot_events to authenticated;
-- no SELECT/UPDATE/DELETE for authenticated — audit log only
```

The Flutter client never reads this table. Logging is best-effort: a failed insert must not interrupt the test.

## Seed data strategy (placeholder content for testing)

Since you don't have real content yet, write a one-off SQL script (or a small Dart/Python script) that:

1. Inserts 5–6 `subjects` (e.g. Medicine, Surgery, OBGYN, Pediatrics, Pharmacology, Pathology) matching real NEET-PG subject names — even placeholder tests should use real subject names so the UI you're building looks right.
2. Inserts 3–4 `topics` per subject.
3. Generates ~200 dummy `questions` with obviously-fake but structurally valid text (e.g. "Sample question 14 about Cardiology — option A", correct_option rotated deterministically) spread across topics and difficulty levels, ~80% `required_plan = 'free'` and the rest split pro/elite so you can actually test the plan-gating UI.
4. Creates one test of each `test_type`, including one `is_sectional = true` "grand test" with 5 sections × 36 questions (matching the real NEET-PG 2026 format: 180 questions, +4/-1 marking, 42-minute sections) so you're validating against the actual exam shape from day one, not an arbitrary placeholder shape.
5. Inserts a handful of `tags` (`PYQ`, `HighYield`, `RecentUpdate`, `OneLiner`, `ClinicalVignette`) and assigns 1–2 to each dummy question randomly, so Practice Mode's tag filter has something real to filter against.
6. Confirms `plan_limits` has its three seed rows from §7.2 — this table is populated by that section's `insert` statement directly, not by your seed script, but double-check it landed correctly before testing Practice Mode.

**Validation for this step**: after seeding, manually query as an anonymous/free-tier test user and confirm you get back only `free`-tier questions and tests — this is your first real end-to-end proof the RLS policies work, before any Flutter code exists.

---

## 10. UG university catalog (additive)

NEET-PG tables above stay. This section is the **current product schema**. Apply
`supabase/migrations/20260830140000_ug_university_pivot.sql` — do not re-run
sections 1–8 on a live project.

v1 **content** university: **KUHS**. The app lists other affiliating
universities for onboarding/Profile. Students pick **state** first
(`universities.state`), then only universities in that state. PYQ lists
filter by `exam_papers.university_id`. A university with zero papers shows
empty PYQs — it does not substitute another bank. See `docs/00_PRODUCT.md`.

### 9.1 Enums and catalog

```sql
create type question_kind as enum ('pyq_theory', 'mcq');
create type mbbs_phase_code as enum ('year1', 'year2', 'year3', 'year4');
create type study_event_kind as enum (
  'opened_lesson', 'opened_pyq', 'marked_learnt', 'answered_mcq', 'opened_resource'
);
```

Tables: `universities`, `mbbs_phases`, `colleges`, `lessons` (sheet `external_id`),
`textbooks`, `exam_papers`, `lesson_resources`, `question_resources`.
`subjects` gains `mbbs_phase_id` and `required_plan`.

### 9.2 Dual-kind questions

`questions.kind` (`pyq_theory` | `mcq`), `topic_id`, `lesson_id`, `marks`.
`topic_id` and `lesson_id` are optional syllabus tags — a PYQ can be uploaded
before the chapter is known. MCQ options stay required only when
`kind = 'mcq'` (nullable columns + a check constraint).

**Sample answers are not a column on `questions`** — a free SELECT on a free
PYQ would leak the model answer. They live in `question_sample_answers` with
RLS `plan_rank(current_plan()) >= plan_rank('pro')`.

Also: `question_appearances` (frequency = count), `question_textbook_refs`
(citation only — never PDF bytes).

Indexes on the PYQ read path (added in
`20260916120000_review_fixes.sql`) — every subject load filters `exam_papers`
by university + subject and then walks appearances in both directions:

```sql
create index idx_exam_papers_university on exam_papers(university_id);
create index idx_exam_papers_subject on exam_papers(subject_id);
create index idx_question_appearances_paper on question_appearances(exam_paper_id);
create index idx_questions_lesson on questions(lesson_id) where lesson_id is not null;
-- the (question_id, exam_paper_id) primary key already covers the other direction
```

View `pyq_teasers` (security_invoker = true so questions RLS still applies):
stem, marks, kind, difficulty, lesson_id, required_plan, appearance_count —
no sample answer, no MCQ keys. `difficulty` holds `must` / `should` / `could`
and is optional on import (blank ⇒ `should`); the app renders a chip only for
`must` and `could`, since `should` is just the default. Includes both
`pyq_theory` and `mcq` rows. University filter is applied in the client/RPC
via appearances → exam_papers.

`universities.slug` is `lower(code)` from sheet sync (not a sheet column).
`is_fallback` is retired — drop with
`supabase/migrations/20260913120000_drop_university_fallback.sql`.

### 9.2c One-file CSV sync

Apply migrations through
`supabase/migrations/20260915200000_content_admin_seed_and_cleanup.sql`.

Routine content entry uses only `content/google_sheet/tabs/Questions.csv`.
`subject_name` and `question_text` are unconditional; kind is inferred, and
MCQ options/key are conditionally required. Topic, lesson, marks,
textbook/page, and resource fields are optional. Paper linkage requires
`university_code` + `exam_year` + `paper_name` together (no default
university code).

**MBBS year is not a CSV column.** Table `subject_phase_defaults` maps
the university-exam subjects to `year1`–`year4`:

| Year | Subjects |
|---|---|
| 1st | Anatomy, Physiology, Biochemistry |
| 2nd | Pathology, Pharmacology, Microbiology |
| 3rd | FMT, PSM, Ophthalmology, ENT |
| 4th | Medicine, Surgery, OBGYN, Pediatrics |

FMT is Forensic Medicine & Toxicology. PSM is Community Medicine
(Preventive and Social Medicine). OBGYN is Obstetrics & Gynaecology.
Allied subjects are not separate catalog rows. Sync calls
`ensure_csv_subject()` so new subjects get `mbbs_phase_id` automatically.
Unknown subjects fail validation.

Admin seeds (universities, colleges) live under `content/admin/` and are
applied by the same migration — not by the Questions sync.

Both Google Apps Script and `scripts/sync_content_csv.py` call
`sync_content_csv(jsonb, boolean)`. Preview (`false`) validates and returns
insert/update/delete counts without writes. Apply (`true`) repeats validation
and normalizes the complete snapshot in one transaction. The function is
granted only to `service_role`.

Question identity is generated from normalized subject + kind + stem.
CSV-managed rows carry `questions.content_sync_source =
'questions_csv_v2'`. Rows absent from the next snapshot are deleted with
dependent history after the client shows preview counts and receives explicit
confirmation. Changing subject, kind, or stem therefore creates a new
identity; this destructive behavior is intentional for this pipeline.

### 9.2b Editor sheet vs database

The Google Sheet is **denormalized** for a non-technical editor: a wide
`Questions` tab (university, phase, subject, topic, lesson, stem, paper,
textbook page, sample answer on one row). Sync upserts the normalized
tables above. Editors do not invent UUIDs. See `content/google_sheet/README.md`.

### 9.3 Profile academic fields + 4-day trial

`profiles` gains `university_id`, `college_id`, `batch_year`, `mbbs_phase_id`,
`onboarding_completed_at`. `handle_new_user` inserts `plan = 'pro'` with
`plan_expires_at = now() + 4 days`. Authenticated GRANT update is limited to
name/phone/academic fields — never `plan` / `plan_expires_at` /
`plan_suspended_at` / `active_device_id`.

### 9.3b Single-device login + 3rd-device plan suspension

Migration: `supabase/migrations/20260919140000_single_device_login.sql`.

**Policy:** one active install at a time (new claim kicks the old Auth
session). Lifetime unique `device_id`s are stored in `device_claims`. The
**3rd distinct** install sets `plan_suspended_at` / `plan_suspend_reason =
'multi_device'`. `current_plan()` then returns `free` until support clears
suspension. `plan` / `plan_expires_at` are left intact so unsuspend restores
paid access if still unexpired.

```sql
create table device_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
-- No authenticated write policies — only claim_active_device() touches rows.

-- claim_active_device(p_device_id text) → jsonb { ok, suspended, just_suspended, distinct_device_count }
-- assert_active_device(p_device_id text) → boolean
```

**Support unsuspend** (SQL editor / service role only — no Flutter UI):

```sql
-- Restore plan access (and optionally drop stale installs so the student
-- can use a new phone without immediately re-hitting the cap).
update public.profiles
set plan_suspended_at = null,
    plan_suspend_reason = null
where id = '<user-uuid>';

-- Optional: keep only the current active install in history
delete from public.device_claims
where user_id = '<user-uuid>'
  and device_id is distinct from (
    select active_device_id from public.profiles where id = '<user-uuid>'
  );
```

**Validation**

- Device A then B → A kicked on resume/assert; `device_claims` count = 2; plan still paid
- Device C (3rd unique) → `plan_suspended_at` set; `current_plan` = `free`
- Clear `plan_suspended_at` → Pro returns if `plan_expires_at` is still future
- Authenticated role cannot `UPDATE` `active_device_id` / `plan_suspended_at`

### 9.4 Progress

`lesson_progress` / `question_progress` (learnt_at, last_viewed_at),
`lesson_bookmarks`, append-only `study_events`.

Trackers (`trackers`, `tracker_items`, `user_tracker_item_done`,
`tracker_kind`, `tracker_completion`) are **retired**. Drop them with
`supabase/migrations/20260912120000_drop_trackers.sql`. They were never a
Google Sheet / CSV tab.

### 9.5 RPCs (do not reimplement in Dart)

| RPC | Returns |
|---|---|
| `get_study_progress()` | streak, 7/30-day counts, subject coverage (`total_lessons` + `total_pyqs`) |
| `search_catalog(p_query)` | subjects, lessons, PYQ teasers |
| `create_practice_session(..., p_lesson_ids uuid[] default null)` | MCQ-only + optional lesson filter |
| `mark_lesson_learnt(p_lesson_id)` / `mark_question_learnt(p_question_id)` | progress + study_event |
| `claim_active_device(p_device_id)` | jsonb — sole active device + maybe suspend on 3rd install |
| `assert_active_device(p_device_id)` | boolean — this install still owns the account |

Lesson resources: visible if `is_free` OR the user's plan covers the parent
lesson's `required_plan`.

---

## 11. In-app announcements (inbox, no OS push)

Broadcast messages (new app version, offer, payment reminder, etc.) published
via **Supabase Table Editor**. Students see them in the app inbox when they
open the app — there is no FCM / lock-screen push in this step.

Migration: `supabase/migrations/20260919120000_announcements_inbox.sql`.

```sql
create table announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null default 'general'
    check (category in ('general', 'version', 'offer', 'payment')),
  deep_link text,                 -- optional app path, e.g. /upgrade
  is_active boolean not null default true,
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table announcement_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  announcement_id uuid not null references announcements(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

alter table announcements enable row level security;
alter table announcement_reads enable row level security;

create policy "active announcements select" on announcements
  for select to authenticated
  using (is_active and (expires_at is null or expires_at > now()));

create policy "own announcement reads select" on announcement_reads
  for select to authenticated using (auth.uid() = user_id);
create policy "own announcement reads insert" on announcement_reads
  for insert to authenticated with check (auth.uid() = user_id);

grant select on table announcements to authenticated;
grant select, insert on table announcement_reads to authenticated;
-- no INSERT/UPDATE/DELETE on announcements for authenticated — Table Editor / service_role only
```

**Ops (Table Editor):**

1. Draft: insert with `is_active = false` (hidden from the app).
2. Publish: set `is_active = true` (optional `expires_at`).
3. Next Home open / refresh shows the row as unread until the student opens or dismisses it.

See also `docs/11_ANNOUNCEMENTS_OPS.md`.
