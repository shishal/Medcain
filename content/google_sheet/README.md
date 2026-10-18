# Google Sheet content CMS

Routine content entry uses **one file/tab**: `tabs/Questions.csv` → `Questions`.
Apps Script and `scripts/sync_content_csv.py` both call the same Supabase RPC.

Editors fill names only — never UUIDs. MBBS year comes from the subject
already in the database, not from this sheet.

Admin catalogs (universities / colleges) live in [`content/admin/`](../admin/)
and are seeded by migration, not by content sync.

## Create the Sheet (one-time)

1. Open [Google Sheets](https://sheets.google.com) → blank spreadsheet.
2. Import `tabs/Questions.csv` and name the tab exactly `Questions`.
3. Optional: add a non-synced ReadMe tab with the editor rules below.

## `Questions` columns

Same header as the Numbers question sheet. `course` may be present and is ignored.

| Column | Required | Notes |
|---|---|---|
| `university_alias` | yes | Existing `universities.code` (KUHS, GGSIPU). |
| `university_name` | yes | The name of that same university row. |
| `college_alias` | no | Existing `colleges.short_form` for that university, or blank. Fill together with `college_name`. |
| `college_name` | no | The name of that same college, or blank. Blank is allowed for PROF, SUPPLY, PRE PROF, and INTERNAL. |
| `exam_type` | yes | `PROF`, `SUPPLY`, `PRE PROF` (or `Pre Proff`), `INTERNAL`. |
| `year` | yes | Four-digit year the question was asked. |
| `month` | yes | Month name (`May`, `June`, …). |
| `paper_number` | no | Free text. Usual values: `Paper I`, `Paper II`. |
| `subject_name` | yes | Existing subject: Anatomy, Physiology, Biochemistry, Pathology, Pharmacology, Microbiology, FMT, PSM, Ophthalmology, ENT, Medicine, Surgery, OBGYN, Pediatrics. |
| `chapter_name` | no | Free text. Stored as a topic under the subject. |
| `topic_name` | no | Free text. Stored as a lesson under that chapter. Needs `chapter_name` when filled. |
| `question_type` | yes | `pyq_theory` or `mcq`. |
| `marks` | no | Numeric marks for this question. |
| `question_text` | yes | Stem. Markdown is fine. |
| `option_a` … `option_d` | mcq | Blank on theory. |
| `correct_option` | mcq | `A` / `B` / `C` / `D`. Blank on theory. |
| `answers` | no | Model answer. Pro-gated; not returned with the free stem. |
| `exp_1` | no | Short explanation. |
| `exp_2` | no | Longer explanation. |
| `state` | no | When filled, must match that university's state. |

Optional advanced columns (allowed by sync, omitted from the template):
`textbook_title`, `textbook_authors`, `textbook_edition`, `page`,
`section_heading`, `difficulty`, `required_plan`, `is_active`,
`resource_title`, `resource_url`, `resource_source_label`, `resource_is_free`.

`difficulty` is revision priority, not an easy/medium/hard scale: `must`,
`should` or `could`. Leave it blank unless the question really is a must-know
or a nice-to-have — blank imports as `should`, and the app only shows a chip
for `must` and `could`, so a sheet full of `should` looks the same as an
untagged one.

## Defaults

| Blank cell | Sync uses |
|---|---|
| difficulty | should |
| required_plan | free |
| is_active | TRUE |
| resource_is_free | TRUE |

There is **no default university, exam type, year, or month**. Every row is one
question on one sitting.

## Editor rules

1. Only edit `Questions`. Never invent IDs.
2. Repeat the same subject + question type + stem for another sitting, page, or resource.
3. Theory: `question_type` = `pyq_theory` and leave options blank. MCQ: `mcq`, all four options, and `correct_option`.
4. Leave `college_alias` and `college_name` both blank, or fill both with a college already in the catalog.
5. Preview shows destructive removals; type `APPLY` to confirm.

## Sync

See [`apps_script/README.md`](apps_script/README.md).

```bash
python3 scripts/sync_content_csv.py             # preview
python3 scripts/sync_content_csv.py --apply     # type APPLY to write
```

Apply migrations through
`supabase/migrations/20261018180000_question_sheet_columns.sql`
before the first sync.
