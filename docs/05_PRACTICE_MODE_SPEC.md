# Practice Mode Spec (MCQ only)

> Practice Mode is the UG app’s **rapid-fire MCQ** tool, scoped to a lesson or
> topic. It does not apply to theory PYQs (those use the PYQ reader). Generator
> must only attach `questions.kind = 'mcq'`.


Read `04_TEST_ENGINE_SPEC.md` first — this file only documents what's *different* for Practice Mode. Everything not mentioned here (autosave, offline resilience, the anti-cheat wall-clock timer rule, server-side scoring) applies identically, because a practice session is just an ephemeral `tests` row running through the same engine — see `02_DATABASE_SCHEMA.md` §7 for how that's generated.

## 1. The Practice Builder screen

A form the student fills in before starting a session, which calls `create_practice_session()` (schema doc §7.6) and gets back a `test_id` to start an attempt against exactly like any catalog test.

| Field | Type | Notes |
|---|---|---|
| Subjects/Topics | Multi-select, topics filtered by chosen subjects | Required to pick at least one; default to "all" if none chosen |
| Tags | Multi-select (`#PYQ`, `#HighYield`, `#RecentUpdate`, `#OneLiner`, `#ClinicalVignette`, etc.) | **Disabled/hidden** if the user's plan's `allow_tag_filter` is false — don't just grey it out silently, show a small "Upgrade to filter by tags" hint so free users understand what they're missing |
| Priority | Hidden in Practice (Practice is Upcoming). PYQ lists show **Must / Should / Could** — the `questions.difficulty` column now stores those words. It is optional and blank imports as `should`, so the UI shows a chip only for `must` and `could`. |
| Question source | Single-select: **Unattempted**, **Previously Incorrect**, **Bookmarked**, **All** | This is the single most-used filter in every competitor app researched — give it visual priority in the UI, don't bury it |
| Question count | Slider or stepper | Cap it live in the UI to the plan's `max_practice_session_questions` as the user drags it — don't let them select 80 and then get silently clamped to 50 server-side without explanation; show the cap and why |
| Mode | **Tutor Mode** (see answer + explanation right after each question), **Exam Mode** (see everything at the end), or **Reading Mode** (scroll questions with the answer already open — no attempt) | Tutor and Exam use the names students already know from other QBanks. Reading is not an exam: no timer, no scoring, no option lock |
| Explanation level | Two-option toggle: **Answer only** vs **Full explanation** | Hidden/forced to "Answer only" if `allow_full_explanation` is false for the plan |
| Timer | On/off toggle, with minutes field if on | Hidden/forced on if `allow_timer_toggle` is false |
| Negative marking | On/off toggle | Off by default — practice is for learning, not exam pressure, unless the student deliberately wants realism |

On submit: call `create_practice_session()`, then navigate straight into the question player using the returned `test_id`. If the server clamped anything (fewer questions than requested, explanation downgraded), show a brief, honest toast ("Showing 10 questions — your plan's practice limit") rather than pretending the request was fully honored.

## 2. Feedback timing behavior

**Exam Mode (`feedback_timing = 'on_submit'`)**: identical to the Test Engine spec's palette states and behavior in every respect. No reveal until the session is submitted.

**Reading Mode (`feedback_timing = 'reading'`)**: no attempt, no timer, no score. `create_practice_session` still picks the MCQs and counts them against the daily quota, then the app opens a scroll. Each card shows the stem, the options, and the correct option marked. Explanation text follows `show_explanation_level` (`full` shows it). Timer and negative-marking controls are hidden, and the generator forces both off. Opening `/play` for this session redirects to the reader and does not start an attempt.

**Tutor Mode (`feedback_timing = 'immediate'`)**: this is the behavior that's actually new.

- The moment the student selects an option, **lock that question** (no changing the answer — this matches the standard tutor-mode convention in every app researched; it keeps the feedback loop honest rather than letting someone select randomly until they hit the right one).
- Immediately show: which option was correct, whether the student's choice was right or wrong, and the explanation content per the session's `show_explanation_level` (see §3 below).
- "Mark for Review" remains available even after the answer is locked — it's for flagging a question to revisit later (e.g. via a follow-up practice session filtered to "Bookmarked"/marked questions), not for changing the answer itself.
- Palette states differ from Exam Mode once a question is revealed:

| State | Meaning | Visual |
|---|---|---|
| Not Visited | Never opened | Grey |
| Skipped | Visited, no option ever selected | Red outline |
| Correct | Answered correctly | Solid green |
| Incorrect | Answered incorrectly | Solid red |
| (any of the above) + Marked for Review | Flagged for later | Add a purple border/dot on top of the correct/incorrect fill |

- Because feedback is immediate, there's no "review screen" at the end in the same sense as Exam Mode — ending a Tutor Mode session goes straight to the results summary (score/accuracy/time), since the student has already seen every explanation along the way.

## 3. Explanation levels

| Level | What's shown |
|---|---|
| `none` | Just marks the question correct/incorrect. Rare, but available for students who want pure self-testing without any hint — expose it, don't force everyone through explanation text they don't want |
| `answer_only` | Correct option highlighted, no explanation text/video | The free-tier default — enough to self-check, not enough to replace the paid explanation content |
| `full` | Correct option highlighted + `explanation_text` (+ `explanation_video_url` if present) | Paid tiers |

This reuses the exact same `questions` RLS policy already in place (schema doc §5) — explanation content is part of the same gated row, so there's no separate access-control logic to write here. The `show_explanation_level` on the practice session just controls what the *UI chooses to render* from data it's already allowed to fetch; it is a UX setting, not a security boundary. (The security boundary is still "can this user see this question at all," enforced the same way it already is for catalog tests.)

## 4. Timer-off behavior

When `timer_enabled = false`: no countdown UI, no auto-submit. The student submits manually via an explicit "Finish Session" action. Still silently track `time_spent_seconds` per question in the background (same autosave mechanism as timed sessions) — useful for the student's own analytics later ("you average 90 seconds per pharmacology question") even though they didn't feel time pressure while practicing.

## 5. Negative marking toggle

When off: `correct_marks = 1`, `incorrect_marks = 0`, `unattempted_marks = 0` (set this way by the generator function) — the results screen shows this as a clean accuracy percentage rather than a NEET-style score, which is the more useful framing for pure practice. When on: real `+4/-1` marking, for students who want to simulate exam pressure even outside a formal test.

## 6. Regenerating / retaking

Unlike catalog tests (which are typically solve-once, matching how the researched competitor apps treat their curated Test Series), **practice sessions are meant to be regenerated freely** — each Practice Builder submission creates a brand-new ephemeral session, subject only to the plan's daily quota. Store the filters used (`practice_filter_criteria`, already on the `tests` row) so the results screen can offer a one-tap **"Practice Similar Again"** button that re-opens the builder pre-filled with the same filters — small feature, disproportionately useful for someone drilling a weak topic repeatedly.

## 7. Validation checklist

- [ ] As a free-tier user, request a 999-question session — confirm you actually receive the plan's `max_practice_session_questions` (per schema doc §7.6's validation note), and that the UI explains why, rather than silently truncating with no message
- [ ] As a free-tier user, request `full` explanation level — confirm it's silently downgraded to `answer_only` server-side, and the UI reflects what was actually granted, not what was requested
- [ ] Exhaust the free tier's daily quota, confirm the next request either returns a shortened session or a clear "come back tomorrow" message — not a raw error
- [ ] In Tutor Mode, answer a question, confirm the option is locked and can't be changed afterward
- [ ] In Tutor Mode, confirm the palette shows correct/incorrect (not just generic green "answered") once a question is revealed
- [ ] In Exam Mode, confirm no explanation or correctness is visible anywhere until the session is submitted — this is the same guarantee as a catalog test, don't let Tutor Mode's reveal logic leak into Exam Mode sessions by accident
- [ ] Filter by "Previously Incorrect", answer everything correctly this time, start a new "Previously Incorrect" session immediately after — confirm questions you just got right are excluded (the filter is live against `attempt_answers`, not a stale snapshot)
- [ ] Turn the timer off, complete a session, confirm `time_spent_seconds` was still tracked per question even though nothing was shown to the user
- [ ] Tap "Practice Similar Again" from a results screen, confirm the builder opens pre-filled with the original session's filters
