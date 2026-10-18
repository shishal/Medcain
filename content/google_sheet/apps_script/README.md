# Phase 2.2 — Apps Script sync

Bound this project to a Sheet that has a single `Questions` tab. The **MEDCAIN**
menu previews one transactional import and requires typing `APPLY` before writes.

## Prerequisites

1. Import `../tabs/Questions.csv` as tab `Questions`.
2. Apply migrations through
   `supabase/migrations/20261018180000_question_sheet_columns.sql`.
3. Script properties: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.

## Install

Paste these files into Apps Script:

- `Code.gs`
- `SheetReader.gs`
- `SupabaseClient.gs`
- `Sync.gs`

## What Sync does

1. Reads `Questions` rows.
2. Calls `sync_content_csv(..., false)` for validation + counts.
3. Asks you to type `APPLY`.
4. Calls `sync_content_csv(..., true)` in one DB transaction.

Subjects must already exist. Unknown subject names fail validation.

## Validation

- Required: `university_alias`, `university_name`, `exam_type`, `year`, `month`, `subject_name`, `question_type`, `question_text`
- `exam_type`: PROF, SUPPLY, PRE PROF / Pre Proff, or INTERNAL
- MCQ: options A–D + `correct_option`
- Theory: `pyq_theory`, options and key blank
- College alias and name both blank, or both matching one college of that university
- `textbook_title` + `page` together; `resource_title` + `resource_url` together
- Resource URL must be `https://`

## Security

Never put the service_role key in the Flutter app or git.
