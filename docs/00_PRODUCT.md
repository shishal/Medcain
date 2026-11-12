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
  The plan’s content depth decides whether the answer is included.
  Missing content shows “No direct answer yet”
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

Signup starts on the **Free** plan. A plan is a row an admin creates on the
website (`/admin/plans/`). Postgres decides what that row can open. The app
shows the row and never sends a price, a duration, or a content decision.

Each plan has one price and one duration. “Pro for 1 year” and “Pro for 2
years” are two plans. The editor can duplicate a plan so the access block
does not have to be retyped. Seeded sellable plans use the old 1-year prices
only: Pro ₹1,499 / 12 months / 1 phone, Elite ₹2,999 / 12 months / 2 phones.
A price of ₹0 is not for sale and does not expire.

What a plan includes:

- **Depth:** question text only, text plus the answer, or the answer plus the explanation. Reading and practice share that depth.
- **Slice:** preview questions only, or a filter on kind (MCQ, theory), exam type, the student’s university or every university, MBBS course years, and past-paper years (all, latest per subject, or a list). A question with several sittings is included when any sitting matches.
- **Tease:** Free shows a locked card with empty text for everything else. A narrow plan leaves those rows out.
- **Practice:** tutor mode, exam mode, questions per session, and questions per day. Empty caps mean no cap.

`questions.is_preview` marks a free preview. `profiles.plan_id` is the subscription. `plan_expires_at` stays on the profile. An inactive plan cannot be bought, and people already on it keep it until it expires.

| Seeded plan | Library | Practice | Devices |
|---|---|---|---|
| Free | Preview questions, with explanations | 10 per session, 20 per day | 1 |
| Pro | Every question, every university, answers and explanations | 50 per session, no daily cap | 1 |
| Elite | Same as Pro | Same as Pro | 2 |

A phone that is not registered is refused. It does not suspend the plan.
On the website user page, an admin can free a phone or raise that account's
phone count (up to 10). The raise only goes above the plan’s device cap.
`profiles.max_registered_devices` stores the raise.

Purchase, in the app, picks one public plan and an optional percent-off
coupon, then opens the **website** to pay. The app does not charge a card.
Checkout reads `amount_paise` and `duration_months` from the plan. A featured
promo on the card is display only; the percent still comes from
`discount_codes`. Paying replaces `plan_id` and adds the plan’s months onto
the later of now and the current expiry.

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
