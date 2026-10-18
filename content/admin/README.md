# Admin catalog seeds (not routine content sync)

These files are the affiliating-university + college catalog used at onboarding
(state → university → college). They are **not** read by `sync_content_csv` /
the Questions Google Sheet.

| File | Role |
|---|---|
| `MBBS_Colleges_by_State.xlsx` | Source workbook (State, University name, University short form, College name, College short form) |
| `Universities.csv` | Generated → `universities` (`code`, `name`, `state`, `slug`) |
| `Colleges.csv` | Generated → `colleges` (`university_code`, `name`, `short_form`) |

There is no separate `states` table — state is the `universities.state` column.

## Apply / refresh

```bash
# Rewrite CSVs from the Excel (dry-run; no DB writes)
python3 scripts/seed_universities_colleges.py

# Also replace the catalog in Supabase (needs DATABASE_URL in .env)
python3 scripts/seed_universities_colleges.py --apply
```

`--apply` clears every `profiles.college_id` (college rows are replaced, so
old ids would dangle), clears `profiles.university_id` when that university
code is not in the new list, deletes all colleges, and deletes universities
absent from the seed. Sample `exam_papers` on a university that is leaving
the catalog are deleted with them (appearances follow). Questions that then
have no paper left are deleted when nothing in an attempt still points at
them. Universities whose `code` is still in the sheet are updated in place,
so their papers stay attached. Colleges are inserted again with `short_form`.

Known legacy renames (exam papers / profiles stay attached):
- `IPU` → `GGSIPU`

Each university also gets an `Other / not listed` college (short form `Other`)
so students can finish onboarding when their campus is missing from the sheet.

Colliding short forms (same code, different state/name) are disambiguated to
`{CODE}-{state-slug}` so `universities.code` stays unique — see script output.

MBBS year for each subject is **not** in this catalog. It comes from
`subject_phase_defaults` in Postgres (Anatomy → year1, etc.).
