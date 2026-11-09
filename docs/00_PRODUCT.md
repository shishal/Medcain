# Product — university-exam MBBS companion

MEDCAIN (“Drug of Choice for Exam Pain”) is an **India-focused MBBS university-exam** app: previous-year theory
questions (PYQs), textbook page citations, optional sample answers, topic
reference links, and MCQ practice.

It is **not** a NEET-PG mock-test product. The timed sectional engine still
exists in the codebase for MCQ practice sessions only. Mini / Subject / Mock /
Grand catalog tests are **retired** from the student-facing IA (not merely
hidden). Practice sessions still create `tests` / `attempts` rows internally.

## Universities

Students pick their **state**, then **affiliating university** at onboarding
(university list is filtered to that state) and can change the same fields
on Profile (state, university, college, MBBS year, batch).

**v1 content bank** is **Kerala University of Health Sciences (KUHS)** —
code `KUHS`. Other universities are listed so the picker is real. If that
university has no tagged papers yet, PYQ lists for it stay empty until
questions are added in the website admin. Adding another university later
is new catalog and question rows, not a schema rewrite.

Curriculum (year → subject → topic → lesson) is **shared** across universities
and is how we **tag** questions for revision. PYQs are
**university-owned** via `exam_papers.university_id` → appearances. A real
university paper mixes many topics in one sitting — see
`docs/10_INDIA_MBBS_EXAMS.md`.

## Content hierarchy

- **Exam unit (what the student sits):** university + subject + year + paper
  (Paper I / Paper II / …) → questions in that paper, several chapters.
- **Syllabus tags (shared):** Year (MBBS phase) → Subject → Topic → Lesson.
  A lesson is a syllabus unit, not a PYQ count. Used to group questions.
- **Question kinds** on a lesson or paper: theory PYQ and/or MCQ.

## Question kinds

| Kind | What it is | Player |
|---|---|---|
| `pyq_theory` | University / internal written stem (essay / short note / VSA by marks) | PYQ reader — not scored |
| `mcq` | Four-option recall item | PYQ reader **DA** / **EX**, **or** the existing tutor/exam practice player |

## Sample answers and reference links

- **Direct answer (DA)** is `sample_answer_text` for theory or MCQ. The PYQ
  reader opens with **DA** already expanded (tap again to collapse).
  Pro-gated (separate table). Missing content shows “No direct answer yet”
  — never invent text in the client. MCQ DA also shows the correct option.
- **Explanation (EX)** is `explanation_text` plus textbook citations and
  “More on this topic” links, for either kind. Collapsed until **EX**. Do not
  put the MCQ key on teasers.
- **Textbook refs** are citations (book + edition + page). Never store PDFs.
- **Lesson resources** are https “read more” links. `is_free` links are
  visible without Pro.

## UX direction

Visual language is MEDCAIN’s blue-on-black brand (black canvas, cyan/blue
CTAs, cooler indigo chrome, gold Pro chips) while keeping **Docci**. Theme is **System / Light / Dark**, persisted, **Light default**.

Home is a PYQ dashboard (coverage banner, year + university, subject cards).
Opening a subject starts with **exam years**, then that year’s paper outline
(LAQ / Short notes / MCQ tabs). Chapter and Paper I/II live in Filters.
Topic → lesson is for grouping, not the first tap.

## Monetization

Signup starts on **Free**. Free sees questions marked `required_plan = 'free'`.
`current_plan()` is what the database uses for that gate.

**Pro** and **Elite** both include every question, every year, and every
subject, with answers. The only difference is registered devices:

| Plan | Library | Registered devices |
|---|---|---|
| Free | Questions marked free | 1 |
| Pro | All questions, years, subjects, and answers | 1 |
| Elite | Same as Pro | 2 |

A phone that is not registered is refused. It does not suspend the plan.
On the website user page, an admin can free a phone or raise that account's
phone count (up to 10). The plan counts above stay the default for everyone
else. `profiles.max_registered_devices` stores the raise.

Purchase, in the app, asks for a prepaid period and an optional percent-off
coupon, then opens the **website** to pay. The app does not charge a card.

| Period | Access |
|---|---|
| 1 year | 12 months |
| 2 years + 1 month extra | 25 months |
| 3 years + 2 months extra | 38 months |
| 4 years + 3 months extra | 51 months |

The 1-year list price is charged once per year. The extra months are free.
Seed prices are Pro ₹1,499 / year and Elite ₹2,999 / year (longer periods
are that price × the number of years). Change a live price in
`paid_plan_catalog` — see `docs/06_PAYMENTS_PRODUCTION.md`. The coupon
percent is applied on the website from `discount_codes`, never from a number
the app sends.

## Accounts

Students sign in with **user-initiated WhatsApp**. They enter their mobile
number, then send one WhatsApp message to the MEDCAIN business number. That
inbound message proves they control the number. MEDCAIN does not send a
WhatsApp authentication template (those are paid). A new number creates the
account; a known number signs in. Checkout uses the same check.

## Out of v1

In-app notes / charts / viva / drug cards, offline packs, campus-ambassador
CRM, SMS OTP, Internship/PG stages, group-discount checkout, NEET-PG mode
in the UI.
