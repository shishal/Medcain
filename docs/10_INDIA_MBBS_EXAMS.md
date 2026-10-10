# India MBBS exams — how they actually work

Reference for product and catalog decisions. The app’s job is to help a
student pass **affiliating-university professional exams** (and the college
internals that feed them), not NEET-PG.

**Status:** research note plus shipped year-first PYQ browse (see §6–7).

Sources (Aug 2023–2025, not a substitute for the current university
notification):

- NMC CBME / GMER 2023 and UGMEB FAQs (MCQ cap, two-paper pass rule)
- University blueprints and circulars: KUHS topic-division circular (crossover
  is inevitable); RGUHS UG preclinical QP blueprint (indicative Paper I / II
  split; overlap expected because questions are case-based)
- Real paper shape: KUHS Anatomy Paper II Oct 2024 (Q.P. 112001) — one sitting
  mixes thorax, abdomen, pelvis, lower limb, histology
- Competitor public copy (GeckoMed): open a subject → start with PYQs;
  chapters/lessons for grouping and custom trackers; papers listed by
  university + year + Paper I/II

Exact mark tables **vary by university and scheme year**. Always store what
was on *that* paper (`exam_papers` + `marks` on the question), never assume
one national template.

---

## 1. What the student actually sits

Two assessments, different shapes:

| Assessment | Who sets it | What it looks like |
|---|---|---|
| **College internals / IA** | The college | Often closer to the teaching timetable: one region or chapter at a time |
| **University professional exam** | Affiliating university (KUHS, RGUHS, TNMGRMU, …) | Whole **subject**, usually **two theory papers**, mixed chapters in one sitting |

MEDCAIN v1 is for the **university paper** (PYQs tagged to `exam_papers` with
`exam_type = 'university'`). Internals can be stored the same way
(`exam_type = 'internal'`) but are not the primary browse.

Students still *revise* chapter-wise before internals. That is why
chapters/lessons stay as tags even though the university paper is mixed.

---

## 2. Course shape (NMC CBME)

4.5 years of MBBS + internship. Students say 1st / 2nd / 3rd / final year.
The regulation names are phases:

| Student year | Regulation phase | Typical university-exam subjects |
|---|---|---|
| 1st | Phase I (~12 months) | Anatomy, Physiology, Biochemistry |
| 2nd | Phase II (~12 months) | Pathology, Pharmacology, Microbiology |
| 3rd | Phase III Part I (~12 months) | FMT, PSM, Ophthalmology, ENT |
| Final | Phase III Part II (~18 months) | Medicine, Surgery, OBGYN, Pediatrics |

Those fourteen names are the app catalog (`subject_phase_defaults`).
FMT is Forensic Medicine & Toxicology, PSM is Community Medicine, and
OBGYN is Obstetrics & Gynaecology. Allied subjects are not separate rows;
Orthopaedics, for example, is tagged inside a Surgery paper.

Curriculum competencies are **national**. The **question paper** is
**university-owned**. Same Anatomy chapter, different KUHS vs RGUHS stems.

---

## 3. University theory paper (the PYQ unit)

For most Phase I / II / III-Part-I subjects the professional exam is:

- **Two theory papers** (Paper I and Paper II), commonly 100 marks each,
  ~3 hours
- Separate **practical / clinical + viva**
- **FMT** is often **one** theory paper (check the current GMER table)
- Clinical subjects and “allied inside a paper” (e.g. Orthopaedics in KUHS
  Surgery Paper II) are university-specific — store `paper_name` as printed,
  do not hard-code “every subject has Paper I and II”

NMC (UGMEB FAQ, CBME 2023):

- MCQs in the annual theory exam: **at most 20 marks** (universities decide
  the exact MCQ count ≤ that cap)
- Rest of the paper is structured written work: long essay / LAQ, short
  essay, SAQ / short notes, VSA
- Passing is **not** “50% in each paper”. For two-paper subjects the learner
  needs about **40% of the combined theory papers**, plus the
  theory/practical split in the current GMER (50% aggregate with a 60:40 or
  40:60 floor). **No grace marks.** Confirm against the live notification
  when writing student-facing pass-rule copy.

A pattern many universities publish (illustrative, **not** a MEDCAIN constant):

| Type | Typical count × marks | ~Total |
|---|---|---|
| MCQ | 20 × 1 | 20 |
| Essay / LAQ | 2 × 10 | 20 |
| Short essay | 6 × 5 | 30 |
| Short answer / VSA | 10 × 3 | 30 |
| **Paper total** | | **100** |

MEDCAIN already maps theory marks → chips (`QuestionFormat`: essay ≥10, short
note 4–9, VSA ≤3, plus `kind = mcq`). Keep inferring from **this question’s
marks**, not from a frozen national grid.

Older schemes (pre-CBME / 2019 vs 2023) used different totals (e.g. 50-mark
papers). `exam_year` + `paper_name` + `marks` are the source of truth.

---

## 4. One paper mixes many topics — this is the load-bearing fact

Universities **do** publish a Paper I vs Paper II **blueprint** (which
regions belong on which paper). That split is **indicative**.

They also say, in writing:

- RGUHS UG preclinical blueprint: the I/II split is for assessment only;
  **strict division is not possible**; overlap is inevitable because
  questions are competency / case based.
- KUHS circular on topic division: **crossover between Paper I and II is
  inevitable**; follow the model paper on the university site.

**Inside one paper**, questions are not one chapter. Example: KUHS Anatomy
Paper II (Oct 2024) in a single 100-mark sitting asks coronary arteries,
femoral triangle, intercostal nerve, rectus sheath, perineal pouches,
prostate, liver histology, appendix, dorsalis pedis, portal anastomoses —
thorax + abdomen + pelvis + lower limb + histology together.

So a real previous-year PDF **cannot** be uploaded as “Upper Limb PYQs”.
The atomic exam object is:

**University + subject + year + paper name (Paper I / Paper II / …)**

Chapters are **tags on questions that live on that paper**.

```text
KUHS 2024 Anatomy Paper II
  Q. Essay — coronary arteries          → tagged Thorax / Heart
  Q. Essay — femoral triangle           → tagged Lower limb
  Q. Short essay — rectus sheath        → tagged Abdomen
  Q. VSA — appendix positions           → tagged Abdomen
  … more stems, several chapters …
```

The same stem can show up again in another year. That is
`question_appearances` (frequency / “high yield”), not a second question
row.

---

## 5. How students actually study (two views, both needed)

| View | Student intent | Matches |
|---|---|---|
| **Paper-wise** | “Write 2024 Paper I in exam order, timed” | University day; pattern, diagrams, time |
| **Chapter-wise** | “All Upper Limb PYQs across 5 years, then mark the chapter done” | Internals, last-month revision, high-yield repeats |

A PYQ app that **only** offers Subject → Topic → Lesson → questions hides
the paper. A student cannot reconstruct what KUHS actually asked in 2024.

A PYQ app that **only** offers full PDFs with no chapter tags makes
“finish Upper Limb before IA” and “this essay repeated three times”
painful.

GeckoMed-style apps (public copy, not a layout clone): **open a subject →
start with PYQs**; use chapters/lessons to group questions; also list papers
by year / Paper I / Paper II.

---

## 6. What that means for MEDCAIN

### Already true in data (do not flatten the database)

- Shared curriculum: year → subject → topic → lesson
- University-owned PYQs: `exam_papers` (`university_id`, `subject_id`,
  `exam_year`, `paper_name`, `exam_type`) → `question_appearances`
- One sheet row = one appearance (or extra textbook page). Repeat
  `external_id` for another paper. Topic/lesson names on that row **tag**
  the stem; they do not mean the paper is only that lesson.

### Currently true in the app (browse)

Home → subject → **exam years** → that year’s paper outline (pinned LAQ /
Short notes / MCQ tabs; Paper I and Paper II merged, labeled on each stem).
**Filters** (chapters / paper) sit on the year list. Topic → lesson remains
the syllabus index (and mark-learnt), not the first tap from Home.

### Student path (shipped)

1. Home → tap **subject** (Anatomy)
2. Land on **that subject’s exam years** (university-filtered; empty if that
   university has no papers yet)
3. Open a year to reconstruct the sitting:
   - Long answer / Short notes (includes VSA) / MCQ tabs
   - Paper I and Paper II stems together, labeled
   - Chapter / paper via Filters on the year list

Topic/lesson stay the syllabus index. Opening a subject no longer funnels
through them first. Exam order inside a paper is not stored yet (no
`order_index` on appearances); each tab sorts by paper name, then marks.

---

## 7. Product decision (confirmed)

The owner’s understanding is **correct** for India MBBS university exams:

> Open a subject → start with PYQs. Chapters/lessons group those questions.
> Real papers mix topics, so the paper is the upload unit and the chapter
> is a tag.

**Paper I / Paper II / year** are first-class. Year is the browse step;
paper is a filter plus a label on each stem.

**Shipped browse:** Home → subject → exam years → year outline tabs.
Chapter is a **Filters** tag, not a separate year-list button. Database is
unchanged (`exam_papers` + appearances + lesson/topic tags).
