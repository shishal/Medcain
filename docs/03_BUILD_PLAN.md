# Build Plan — Phased Tasks

Work top to bottom. Don't start a phase until the previous phase's validation steps all pass. Load one phase's section into the AI at a time.

Each task has: **Description**, **Expected Outcome** (what "done" means, testable), **Validation** (how you personally confirm it — not the AI's claim, your own check), and **Notes**.

**Current work is UG-F / Phase 10 (GeckoMed UX alignment).** UG-A–E and
Phases 0–9 are complete or historical. Do not start new NEET-PG catalog tasks.
Mini / Subject / Mock / Grand list IA is retired.

---

## UG-A — Product docs & university lock

**UG-A.1 — Product identity**
- Description: `docs/00_PRODUCT.md` is the source of truth: KUHS, dual question kinds, sample answers, reference links, 4-day trial. Syllabus tags are Year→Subject→Topic→Lesson; the exam unit is a university paper (see `docs/10_INDIA_MBBS_EXAMS.md`).
- Expected Outcome: AGENTS.md and foundation docs point at the UG product. NEET-PG specs are marked historical.
- Validation: a new session reading AGENTS.md would not build a Grand Test as the home screen.

**UG-A.2 — Schema + sheet docs**
- Description: Document additive UG tables in `docs/02_DATABASE_SCHEMA.md` §10 and the Google Sheet tabs in `content/google_sheet/`.
- Expected Outcome: An implementer can apply one migration and sync the new tabs without guessing column names.

---

## UG-B — Database (additive)

**UG-B.1 — Apply `ug_university_pivot` migration**
- Description: Run `supabase/migrations/20260830140000_ug_university_pivot.sql`.
- Expected Outcome: universities, colleges, phases, lessons, appearances, textbook refs, sample-answer table, resources, progress, RPCs, 4-day trial on new profiles.
- Validation: Table Editor lists the new tables; `select * from universities;` returns KUHS; signup as a test user yields `plan = pro` with `plan_expires_at` ~4 days out.

**UG-B.2 — Practice generator is MCQ-only**
- Description: `create_practice_session` only attaches `kind = 'mcq'` and accepts optional `p_lesson_ids`.
- Validation: a lesson with only theory PYQs returns `NO_QUESTIONS_MATCH_FILTERS`.

---

## UG-C — Content pipeline

**UG-C.1 — Sheet tabs**
- Description: One lean Questions CSV/tab. Subject + stem are required;
  topic/lesson/paper/marks/textbook/page/resources are optional, and MCQ
  options/key are conditionally required. MBBS year comes from
  `subject_phase_defaults` in Postgres. Universities/colleges are admin
  seeds (`content/admin/` + migration), not routine sync tabs.
- Validation: fill the sample CSV rows, run Apps Script validation against a missing `correct_option` on a theory row — it must pass. An MCQ row missing options must fail.

**UG-C.2 — Sync script**
- Description: Apps Script and Python call one service-role-only transactional
  RPC to preview/apply the complete Questions CSV snapshot. Sample answers go
  to `question_sample_answers`; resource URLs must be https.
- Validation: sync twice unchanged with no duplicates; removed managed rows
  preview destructive counts and require confirmation before deletion.

---

## UG-D — App information architecture

**UG-D.1 — Onboarding**
- Description: After signup, stepped form: theme, name, MBBS year, **state picker**, **university picker** (only universities in that state), college search for that university, batch year. Writes `profiles` academic columns + `onboarding_completed_at`. Profile can change the same fields later. State is not stored on the profile — it is read from `universities.state`.
- Validation: a profile with null `onboarding_completed_at` cannot reach Home; completing the form lands on Home with that year’s subjects. Picking a university with no papers still reaches Home (empty PYQs until papers are added).

**UG-D.2 — Catalog browse**
- Description: Home lists subjects for the student’s phase. **Opening a subject shows that subject’s PYQs** (paper / year / format / chapter filters). Topic → lesson remains under **Chapters** for grouping and mark-learnt. See `docs/10_INDIA_MBBS_EXAMS.md`.
- Validation: a Paper II stem and a Paper I stem appear together on the subject screen; filtering Paper II hides Paper I. Chapters still opens the topic list.

**UG-D.3 — PYQ reader**
- Description: Stem, marks, appearance years, textbook page citations, collapsed sample answer (text / Pro lock / “No sample answer yet”), “More on this topic” links, bookmark, mark as learnt.
- Validation: as free user, sample-answer body is not in the network payload. Tapping a free `is_free` resource opens the URL. Tapping a locked resource goes to upgrade.

**UG-D.4 — Lesson-scoped MCQ practice**
- Description: From a lesson, start a practice session filtered to that lesson’s MCQs (existing player).
- Validation: questions in the session all belong to that lesson and `kind = mcq`.

**UG-D.5 — Search, learnt, bookmarks**
- Description: Search subjects, lessons, PYQ stems. Lesson bookmarks use `lesson_bookmarks`. Mark-learnt writes progress + a `study_events` row via repository (RPC for streak reads).
- Validation: bookmark a lesson, force-quit, reopen — still bookmarked.

**UG-D.6 — Trackers (retired)**
- Description: Removed. Bottom tab, Dart feature, and SQL (`trackers` /
  `tracker_items` / `user_tracker_item_done` / `tracker_completion`) are gone.
  No CSV cleanup — trackers were never a sheet tab. Drop leftover DB objects
  with `supabase/migrations/20260912120000_drop_trackers.sql`.

**UG-D.7 — Progress**
- Description: Home strip + progress screen: 7-day / 30-day activity, streak, subject coverage from `get_study_progress` RPC.
- Validation: two study events on consecutive days show streak 2; skipping a day resets unless “yesterday” still counts as continuing (standard streak: last event today or yesterday).

**UG-D.8 — Hide NEET-PG catalog**
- Description: Home does not offer “Browse tests.” Test-player routes remain for practice.
- Validation: walk every tab on Home — no Mini/Mock/Grand list.

---

## UG-E — Growth (after real PYQs exist)

**UG-E.1 — KUHS SEO pages** on the existing static site (`/kuhs/`, `/kuhs/anatomy/`, important-questions).
**UG-E.2 — WhatsApp support** link in the app profile and site header (number is an operator setting, not hardcoded to a competitor).
**UG-E.3 — Ambassadors page** explaining campus contribution (papers / dates). Do not build a CRM in v1.

---

## UG-F / Phase 10 — GeckoMed UX alignment

Work top to bottom. One task at a time.

**10.1 — Visual system**
- Description: Coral-orange primary, charcoal dark canvas, indigo-purple chrome, gold Pro. Persist System/Light/Dark; Light is default. Keep Docci.
- Expected Outcome: Light default on first launch; Profile 3-way theme selector survives force-quit; light mode is clean white/gray, not comic paper.
- Validation: toggle System and confirm it follows the emulator OS theme.

**10.2 — Retire catalog tests**
- Description: Remove Mini/Subject/Mock/Grand list UI, Tests.csv / TestQuestions.csv, and NEET seed scripts. Keep `tests`/`attempts` for Practice.
- Expected Outcome: `/tests` list route is gone; Practice player still starts from a lesson or the Practice tab.
- Validation: grep the app IA for Mini/Mock/Grand list — none. Start a 10-question practice session.

**10.3 — Denormalized sheet + university-scoped PYQs**
- Description: Wide Questions tab; sync writes normalized tables. Teasers include `kind`. Filter PYQs by selected university; empty lists stay empty.
- Expected Outcome: A content person can add a PYQ as one spreadsheet row (names, not UUIDs). A university with no papers sees empty PYQs until rows are added.
- Validation: upsert two rows with the same `external_id` and different papers — one question, two appearances.

**10.4 — Onboarding + Profile university picker**
- Description: Stepped onboarding (state before university); Profile shows and edits name, state, university, college, year, batch. Changing state clears university/college; changing university clears college.
- Validation: pick Kerala — only KUHS (and other Kerala rows) appear; change university on Profile; college that does not belong to the new university is cleared; Home follows the new id.

**10.5 — Home dashboard**
- Description: Docci + name + year + university; honest coverage banner (PYQ and paper counts for the selected university).
- Validation: KUHS profile shows KUHS counts; a university with zero papers shows 0 PYQs, not another university’s bank.

**10.6 — PYQ list chips + cards**
- Description: All / Essay / Short / VSA / MCQ chips; high-yield when appearance_count ≥ 2; textbook line; bookmark.
- Validation: filter to MCQ on a lesson that has both kinds — only MCQ stems. Theory cards never show option keys.

**10.7 — PYQ reader (theory + MCQ)**
- Description: Theory sample answer + MCQ show-answer; preferred textbook picker (local). Never invent sample text.
- Validation: MCQ teaser has no correct option; opening it and tapping Show answer reveals the key + explanation.

**10.8 — Community links**
- Description: Profile WhatsApp + Telegram via `SupportLinks` placeholders until real URLs exist.
- Validation: both tiles open an external URL (placeholders are fine).

**10.9 — Year-first paper outline**
- Description: Subject opens exam years (Filters: chapters / paper / Must-Should-Could). A year opens a text outline with pinned LAQ / Short notes / MCQ tabs (Paper I+II merged). PYQ reader uses **EX** (`explanation_text` + textbooks/links) and **DA** (`sample_answer_text`; MCQ also shows the key). Scanned paper image is not shown. Onboarding unchanged.
- Expected Outcome: Home → subject → years → tabbed outline → reader. No flat subject PYQ dump. EX/DA work for theory and MCQ. Practice tab is **Upcoming**.
- Validation: open 2024, switch tabs without scrolling to find a section; DA shows sample (Pro lock if free); EX shows explanation + textbook line. No Question paper Image tile.

---

## Historical — NEET-PG Phases 0–9 (complete)

The original QBank phases follow. Do not extend them. Kept so migrations and old PRs still make sense.

---

## Phase 0 — Environment & Project Init

**0.1 — Set up accounts and tooling**
- Description: Complete the environment checklist in `01_PROJECT_FOUNDATION.md`.
- Expected Outcome: `flutter doctor` clean for Android; Supabase project created; GitHub repo created and pushed; Codemagic connected to it; Apple Developer + Play Console enrollment *submitted* (approval can lag, don't block on it).
- Validation: run `flutter doctor -v`, all Android-related checks green.

**0.2 — Scaffold the Flutter project**
- Description: `flutter create` the project, add the locked dependencies from `01_PROJECT_FOUNDATION.md` (`flutter_riverpod`, `riverpod_annotation`, `go_router`, `supabase_flutter`, `path_provider`), set up the folder structure exactly as specified there.
- Expected Outcome: App builds and runs on an Android emulator showing a blank "Hello" screen; folder structure matches the spec; no unused starter counter-app code left behind.
- Validation: run the app, confirm it launches without errors; open the folder tree and compare against the spec by eye.
- Notes: cheap model is fine for this — it's boilerplate.

---

## Phase 1 — Backend Foundation

**1.1 — Run the database schema**
- Description: Execute all SQL blocks in `02_DATABASE_SCHEMA.md` sections 1–5 against your Supabase project, in order.
- Expected Outcome: All tables, enums, functions, triggers, and RLS policies exist with no errors.
- Validation: in Supabase's Table Editor, confirm every table listed in the schema doc exists; in the SQL editor run `select * from pg_policies where schemaname = 'public';` and confirm a policy exists for every table.

**1.2 — Test the plan-expiry function**
- Description: Run the specific validation described in schema doc section 4 (set a test profile's `plan_expires_at` to the past, confirm `current_plan()` correctly falls back to `'free'`).
- Expected Outcome: Confirmed working as described.
- Validation: this *is* the validation — don't skip it, it's the single highest-value test in the whole backend.

**1.3 — Build the seed data script**
- Description: Write a script (Python or Dart, your choice — doesn't need to be in the Flutter app) implementing the seed strategy at the bottom of `02_DATABASE_SCHEMA.md`, using the Supabase service_role key.
- Expected Outcome: Running the script populates subjects, topics, ~200 questions across plan tiers, and 4 tests (one per type, including a proper 5-section/36-question grand test matching the real NEET-PG shape).
- Validation: query `select plan, count(*) from questions group by plan;` — confirm a realistic free/pro/elite split, not all-free or all-paid.
- Notes: **keep the service_role key out of the Flutter repo entirely** — this script lives separately or in a `scripts/` folder with its own gitignored `.env`.

**1.4 — Verify RLS end-to-end**
- Description: Using the Supabase client library from a scratch script (not the Flutter app yet), authenticate as a free-tier test user and query `questions`.
- Expected Outcome: Only `free`-tier questions come back, even though pro/elite questions exist in the table.
- Validation: count returned rows vs. `select count(*) from questions where required_plan = 'free';` — they should match exactly.

---

## Phase 2 — Content Pipeline (Google Sheet → Supabase)

**2.1 — Design the Google Sheet structure**
- Description: Create a Google Sheet with one tab per content type: `Subjects`, `Topics`, `Questions`, `Tests`, `TestQuestions`. Columns mirror the database schema field names exactly (e.g. the `Questions` tab has columns `topic_name`, `question_text`, `option_a`...`option_d`, `correct_option`, `explanation_text`, `difficulty`, `required_plan`) so the sync script's mapping logic stays simple.
- Expected Outcome: A sheet a non-technical content person could fill in without needing to understand the database.
- Validation: fill in 2–3 sample rows per tab by hand and eyeball that every required DB field has a corresponding column.

**2.2 — Write the Apps Script sync**
- Description: A Google Apps Script (bound to the Sheet) triggered by a custom menu button ("Sync to App") that reads each tab, validates rows, and upserts into Supabase via its REST API using the service_role key (stored in Script Properties, never hardcoded).
- Expected Outcome: Clicking "Sync to App" pushes new/changed rows into the corresponding Supabase tables; running it twice with unchanged data doesn't create duplicates (upsert on a natural key, not blind insert).
- Validation rules the script must enforce *before* writing anything:
  - `correct_option` is exactly one of A/B/C/D
  - `topic_name` (for Questions) matches an existing topic — script should look up the topic's UUID by name, and **fail loudly with a row number** if no match, not silently skip
  - `required_plan` is one of free/pro/elite
  - all four options are non-empty
- Expected Outcome (cont.): on validation failure, the script shows a popup listing every bad row and why, and writes nothing to Supabase for that run (all-or-nothing per sync, not partial).
- Validation: intentionally put a typo in one row's `correct_option` (e.g. "E") and confirm the script catches it and syncs nothing, rather than silently corrupting that question.
- Notes: use a stronger model for this task — a sync script with a subtle bug (e.g. matching topics by name case-sensitively when your content team sometimes capitalizes differently) causes silent data corruption that's genuinely hard to notice until a student reports a wrong answer.

---

## Phase 3 — App Foundation

**3.1 — Theme and navigation shell**
- Description: Implement `ThemeData` (light + dark) per the design direction in `01_PROJECT_FOUNDATION.md`; set up `go_router` with placeholder routes for: splash, login, signup, home, test list, test player, results, profile.
- Expected Outcome: App launches to a splash screen, navigates to login if unauthenticated, to home if authenticated; dark mode toggle (can be a temporary debug button for now) actually changes the theme.
- Validation: manually navigate every placeholder route; toggle system dark mode on the emulator and confirm the app follows it.

**3.2 — Supabase client + auth screens**
- Description: Initialize the Supabase client in `core/supabase/`. Build login and signup screens (email/password) wired to Supabase Auth through an `auth` feature repository (per the layering rule in `01_PROJECT_FOUNDATION.md`).
- Expected Outcome: A new user can sign up, gets a `profiles` row auto-created (via the Phase 1 trigger) with `plan = 'free'`, can log out and log back in.
- Validation: sign up a real test account, check Supabase's Table Editor to confirm the `profiles` row exists with the right default; force-quit and reopen the app, confirm the session persists (don't require re-login every launch).
- Edge cases to explicitly handle: wrong password error message is user-readable (not a raw Postgrest error string), duplicate signup email shows a clear message, empty-field submission is blocked client-side before hitting the network.

**3.3 — Current-plan provider**
- Description: A Riverpod provider that exposes the logged-in user's current plan (calling the `current_plan()` function or just reading the profile row and doing the expiry check client-side too, as a defense-in-depth display concern — the *real* enforcement is RLS, this provider is just for UI decisions like showing/hiding a lock icon).
- Expected Outcome: Any screen can read "what can this user see" without duplicating the expiry logic.
- Validation: manually expire a test profile's plan in Supabase, confirm the app's UI reflects `'free'` on next data refresh without a code change needed elsewhere.

---

## Phase 4 — Test Discovery (historical)

Retired from the student-facing IA in UG-F / 10.2. Practice still uses the
player routes. Do not rebuild Mini / Subject / Mock / Grand as Home.

**4.1 — Test list screen**
- Description: Tabbed or filtered list of tests by type (Mini / Subject / Mock / Grand), pulling from Supabase (RLS already filters to what the user's plan allows — but see 4.2).
- Expected Outcome: Tests render with title, question count, duration, and type badge.
- Validation: with a free-tier test account, confirm pro/elite-only tests simply don't appear (RLS hides them at the query level) — cross-check against Phase 1.4's expectations, this should feel like a natural continuation of that same guarantee.

**4.2 — "Locked" content teaser**
- Description: Product requirement, not just a technical one — free users should see *that* pro/elite tests exist (as a locked card with an upgrade prompt), not just have them invisible. This means you need a way to show test *titles* without exposing question content. Add a narrow, separate RLS policy or a Postgres view exposing only non-sensitive test metadata (title, type, question count) to all authenticated users regardless of plan, while the full `test_questions`/`questions` join stays gated.
- Expected Outcome: Free user sees "NEET-PG Grand Test 3 🔒 Upgrade to Pro" as a disabled card; tapping it goes to an upgrade prompt, not the test player.
- Validation: confirm a free user can see the locked test's title/metadata but a direct API query for that test's questions still returns nothing (this is exactly the kind of policy you need to get right per the warning in schema doc section 5 — narrow and deliberate, not a loosened blanket rule).

**4.3 — Test detail / instructions screen**
- Description: Before entering the test player, show duration, question count, marking scheme (from the test row's `correct_marks`/`incorrect_marks`), and for sectional tests, an explicit warning about the section-lock behavior (see `04_TEST_ENGINE_SPEC.md`).
- Expected Outcome: User can't accidentally stumble into a timed test without seeing the rules first.
- Validation: read it yourself as if you were a first-time user — is it obvious you can't go back once a section's time is up?

---

## Phase 4B — Practice Mode

Full spec is in `05_PRACTICE_MODE_SPEC.md`, which itself builds on `04_TEST_ENGINE_SPEC.md` — read both before starting. Do this phase *after* Phase 5/6 (Test Engine Core + Submission/Scoring) if you'd rather build the simpler, better-understood exam flow first and reuse it once it's solid — the practice session generator specifically depends on the `attempts`/`attempt_answers` machinery from Phase 5/6 already working. Listed here in build order relative to Test Discovery for planning purposes only; feel free to actually build it after Phase 6.

**4B.1 — Practice session generator (backend)**
- Description: Implement `create_practice_session()` from `02_DATABASE_SCHEMA.md` §7.6, plus the `tags`/`question_tags`/`plan_limits`/`daily_practice_usage` tables and the updated `tests`/`test_questions` RLS policies it depends on.
- Expected Outcome: Calling the function with a set of filters returns a valid `test_id` whose `test_questions` match the filters and respect the calling user's plan.
- Validation: run the exact validation described in schema doc §7.6 — request 999 questions and `full` explanations as a free-tier user, confirm both are clamped server-side. This is the practice-mode equivalent of the RLS check in Phase 1.4 — don't skip it for the same reasons.
- Notes: strong model, careful review — this function is a plan-gating enforcement point, same risk category as the RLS policies themselves.

**4B.2 — Practice Builder screen**
- Expected Outcome: Matches the field list and tier-gating behavior in `05_PRACTICE_MODE_SPEC.md` §1 exactly — including showing (not hiding without explanation) which options are locked by the user's current plan.
- Validation: switch between a free-tier and pro-tier test account, confirm the builder's available options visibly change (disabled tag/timer/explanation controls with an upgrade hint for free, fully open for pro).

**4B.3 — Tutor Mode question player behavior**
- Description: Extend the question player built in Phase 5.2 to branch on `feedback_timing`: immediate reveal + answer-locking + correct/incorrect palette states per `05_PRACTICE_MODE_SPEC.md` §2, vs. the existing Exam Mode behavior untouched.
- Expected Outcome: Both modes work from the same underlying widget without duplicated screens — this should be a behavioral branch, not a second question-player implementation.
- Validation: go through both Tutor Mode and Exam Mode validation checklist items in the practice spec; specifically confirm Exam Mode's "no reveal until submit" guarantee still holds after this change — the most likely regression here is Tutor Mode's reveal logic accidentally leaking into Exam Mode sessions.

**4B.4 — "Practice Similar Again"**
- Expected Outcome: From a practice results screen, one tap reopens the builder pre-filled from `practice_filter_criteria` on that session's `tests` row.
- Validation: confirm the pre-filled builder still re-clamps against current plan limits at generation time (a user's plan may have changed since the original session) rather than blindly trusting the stored filter JSON.

---

## Phase 5 — Test Engine Core

Full behavioral spec is in `04_TEST_ENGINE_SPEC.md` — read that file in full before starting this phase, it's the most detail-dense part of the whole plan. Build this phase for Exam Mode / catalog tests first; Phase 4B extends the same question player for Practice Mode afterward, so get this solid before branching it.

**5.1 — Attempt creation and local state**
- Expected Outcome: Starting a test creates an `attempts` row (`status = 'in_progress'`), downloads the test's questions, and initializes local answer state per the spec.
- Validation: kill the app mid-test (force stop, not graceful close), reopen, confirm you're offered a "resume" path with previous answers intact — per the autosave requirements in the spec.

**5.2 — Question player UI**
- Expected Outcome: Matches the palette states, navigation, and marking-for-review behavior defined in `04_TEST_ENGINE_SPEC.md` exactly.
- Validation: run through every palette state transition listed in the spec by hand, confirm the UI matches.
- Notes: build this with Phase 4B.3 in mind — structure it so feedback timing can be branched in later without a rewrite (e.g. don't hardcode "never reveal answer" deep in the widget tree).

**5.3 — Timer and sectional lock**
- Expected Outcome: Matches the timer and section-transition behavior in the spec exactly, including auto-submit at zero.
- Validation: this is the highest-risk task in the whole app for subtle bugs (see spec for the specific edge cases to test) — go through the spec's validation checklist item by item, don't spot-check.
- Notes: strong model, careful human review. A timer bug that costs a student their test attempt is the single worst possible bug in this app.

---

## Phase 6 — Submission, Scoring & Results

**6.1 — Submit logic**
- Expected Outcome: On submit (manual or auto), all local answers sync to `attempt_answers`, the attempt's `status` becomes `submitted`, `total_score`/`correct_count`/`incorrect_count`/`unattempted_count` are computed server-side (implement this as a Postgres function/RPC, the same pattern as `calculate_percentile()` and `create_practice_session()` — pure data manipulation inside the database, no external calls needed, so no Edge Function required here) using the test's actual `correct_marks`/`incorrect_marks`/`unattempted_marks`, and `calculate_percentile()` is called and stored.
- Validation: manually submit a test with a known mix of right/wrong/skipped answers, hand-calculate the expected score using the test's marking scheme, confirm it matches exactly. Do this for both a non-sectional test and the sectional grand test.
- Notes: **scoring must happen server-side.** This is worth restating because it's the single most common shortcut an AI agent will try to take (compute the score in Dart, then just write it to Supabase) — that's trivially exploitable by anyone who inspects network traffic.

**6.2 — Results summary screen**
- Expected Outcome: Score, accuracy %, percentile, subject-wise breakdown (correct/incorrect/unattempted per subject), time spent.
- Validation: cross-check the subject-wise numbers sum to the overall totals.

**6.3 — Solution review screen**
- Expected Outcome: Per-question view showing the student's answer, correct answer, and explanation text; plan-gated (this respects the same `questions` RLS policy already in place — no new gating logic needed, just don't accidentally fetch explanation text through a different, ungated path). For sessions created via Phase 4B, respect the session's `show_explanation_level` (`none`/`answer_only`/`full`) when deciding what to render — this is a UI setting read off the `tests` row, not a separate access-control check (see `05_PRACTICE_MODE_SPEC.md` §3).
- Validation: as a free-tier user who somehow attempted a pro-tier question (shouldn't be possible per 4.1/4.2, but test the failure mode anyway) — confirm the review screen fails gracefully rather than crashing. Separately, confirm a practice session generated with `answer_only` never renders explanation text even though the underlying question row technically contains it.

**6.4 — Bookmarking from review**
- Expected Outcome: Tap-to-bookmark on any question in the review screen; a separate "My Bookmarks" screen lists them for later practice.
- Validation: bookmark a question, force-close the app, reopen, confirm it's still bookmarked (data round-trips through Supabase, not just local state).

---

## Phase 7 — Plan Gating UI & Payments

**7.1 — Upgrade/paywall screen**
- Expected Outcome: Shows plan comparison (Free/Pro/Elite feature differences), with a button that opens your external web checkout page in the device browser (`url_launcher`) — **not** an in-app purchase flow.
- Validation: confirm there is no purchase button, price display with a "Buy" action, or payment form rendered *inside* the Flutter app itself — the app only ever links out. This is the compliance boundary discussed earlier: no in-app purchase mechanism means no IAP requirement, but that only holds if the purchase genuinely happens outside the app.

**7.2 — External web checkout (separate small project)**
- Description: A simple web page (can be a basic static site or a tiny Next.js/plain HTML+JS page) with Razorpay Checkout integrated, where a logged-in-by-email user selects a plan and pays.
- Expected Outcome: Successful payment triggers a webhook.
- Validation: complete a real test payment in Razorpay's test mode end-to-end.

**7.3 — Payment webhook → plan update**
- Description: A Supabase Edge Function that receives Razorpay's webhook, verifies its signature (critical — an unverified webhook endpoint is a free way for anyone to grant themselves a paid plan), and updates the matching `profiles` row's `plan` and `plan_expires_at`.
- Expected Outcome: Within seconds of a successful test payment, the corresponding Supabase user's plan updates; the Flutter app reflects it on next data refresh without needing a rebuild or manual sync.
- Validation: complete a test payment, watch the `profiles` row update in real time in Supabase's Table Editor; then separately, send a fake unsigned webhook payload and confirm it's rejected.
- Notes: strong model + careful review, this is a real money/security boundary. Production cutover (Live keys, HTTPS checkout, store `.env`) is in `docs/06_PAYMENTS_PRODUCTION.md` — do that when you take real money, not as part of 7.3 Test Mode.

---

## Phase 8 — Security Hardening

**8.1 — Screenshot/recording prevention**
- Expected Outcome: `no_screenshot` (or equivalent, verify current pub.dev health first) integrated on the question player and solution review screens specifically — not the entire app, since blocking screenshots on your own marketing/onboarding screens serves no purpose and just annoys users.
- Validation: on a physical Android device, attempt a screenshot on the test player — confirm it's blocked. On iOS, confirm the app is notified of a screenshot attempt and can react (even though it can't be prevented) — decide and implement what "react" means (e.g. a one-time warning toast, or logging the event server-side against that user's account for repeat-offender tracking).

**8.2 — Dynamic watermark**
- Expected Outcome: A faint, semi-transparent overlay showing the logged-in user's name/phone/email tiled across content screens — traceability for the iOS case where blocking isn't possible.
- Validation: visually confirm the watermark is legible enough to trace but not so intrusive it hurts readability of the actual question text — this is a judgment call, get a second opinion from an actual test user if you can.
- Update: answer screens (PYQ reader, solution review) pass `watermark: false` to `ContentCaptureGuard` and show no overlay. Capture blocking and logging still apply there; the test player keeps the watermark.

---

## Phase 9 — Polish & Store Submission

**9.1 — Error/empty/loading states audit**
- Expected Outcome: every screen that fetches data has an explicit loading state, empty state, and error state — no screen that just shows a blank white page on failure.
- Validation: turn on airplane mode mid-session and click through the whole app; nothing should crash, everything should show a sensible "you're offline" message where relevant.

**9.2 — App icon, splash screen, store listing assets**
- Expected Outcome: Real icon (not the Flutter default), splash screen matching your theme, screenshots and description drafted for both store listings.

**9.3 — Codemagic build pipeline**
- Expected Outcome: One-click (or one-command) builds for both Android and iOS producing signed, installable binaries.
- Validation: install a Codemagic-built binary on a real device for each platform before submitting to either store — don't submit an untested build.

**9.4 — Store submission**
- Expected Outcome: Both apps submitted for review.
- Validation: n/a — budget for at least one rejection round; read the specific rejection reason carefully, first-time EdTech app submissions commonly get flagged for unclear subscription/refund terms even when you're not using IAP, since you still need a visible way for users to manage/cancel and a clear privacy policy.
