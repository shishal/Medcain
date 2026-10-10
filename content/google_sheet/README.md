# Google Sheet content CMS

Routine content entry uses **one file/tab**: `tabs/Questions.csv` → `Questions`.
Apps Script and `scripts/sync_content_csv.py` both call the same Supabase RPC.

Editors fill names only — never UUIDs. MBBS year (year1–year4) comes from
`subject_phase_defaults` in Postgres, not from the CSV.

Admin catalogs (universities / colleges) live in [`content/admin/`](../admin/)
and are seeded by migration, not by content sync.

## Create the Sheet (one-time)

1. Open [Google Sheets](https://sheets.google.com) → blank spreadsheet.
2. Import `tabs/Questions.csv` and name the tab exactly `Questions`.
3. Optional: add a non-synced ReadMe tab with the editor rules below.

## Lean `Questions` columns

Editor-facing order (first nine, then MCQ/optional extras):

| Column | Required | Notes |
|---|---|---|
| `subject_name` | yes | Must match `subject_phase_defaults` exactly: Anatomy, Physiology, Biochemistry (1st); Pathology, Pharmacology, Microbiology (2nd); FMT, PSM, Ophthalmology, ENT (3rd); Medicine, Surgery, OBGYN, Pediatrics (4th). |
| `question_text` | yes | Stem. |
| `sample_answer_text` | no | DA (Pro-gated table). |
| `explanation_text` | no | EX. |
| `university_code` + `exam_year` + `paper_name` | no | Fill all three or none. Code must exist in `universities` (e.g. KUHS). |
| `topic_name` | no | Syllabus tag; created on sync. |
| `lesson_name` | no | Needs `topic_name` if filled. |
| `option_a` … `option_d` | if MCQ | Blank on theory. Any option/key cell ⇒ MCQ. |
| `correct_option` | if MCQ | `A` / `B` / `C` / `D`. |
| `marks` | no | Theory format: ≥10 essay, 4–9 short, ≤3 VSA. |
| `textbook_title` + `page` | no | Fill both or neither. |
| `resource_title` + `resource_url` | no | Fill both or neither; `https` only. |

Optional advanced columns (allowed by sync, omitted from the lean template):
`kind`, `exam_type`, `textbook_authors`, `textbook_edition`,
`section_heading`, `difficulty`, `required_plan`, `is_active`,
`resource_source_label`, `resource_is_free`.

`difficulty` is revision priority, not an easy/medium/hard scale: `must`,
`should` or `could`. Leave it blank unless the question really is a must-know
or a nice-to-have — blank imports as `should`, and the app only shows a chip
for `must` and `could`, so a sheet full of `should` looks the same as an
untagged one.

## Defaults

| Blank cell | Sync uses |
|---|---|
| kind | theory if no MCQ cells; else MCQ |
| exam_type | university |
| difficulty | should |
| required_plan | free |
| is_active | TRUE |
| resource_is_free | TRUE |

There is **no default university**. Paper-linked rows must set `university_code`
explicitly.

## Editor rules

1. Only edit `Questions`. Never invent IDs.
2. Repeat the same subject + stem for another paper/page/resource.
3. Theory: leave options blank. MCQ: fill all four options + key.
4. Bank MCQs can omit paper fields (they will not appear in year browsing).
5. Preview shows destructive removals; type `APPLY` to confirm.

## Sync

See [`apps_script/README.md`](apps_script/README.md).

```bash
python3 scripts/sync_content_csv.py             # preview
python3 scripts/sync_content_csv.py --apply     # type APPLY to write
```

Apply migrations through
`supabase/migrations/20261010130000_mbbs_subject_catalog.sql`
before the first sync.
