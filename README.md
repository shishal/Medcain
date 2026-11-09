# MEDCAIN

Flutter app for **MBBS university exams**: previous-year theory questions
(with optional sample answers and textbook page citations), lesson-scoped MCQ
practice.

Planning docs: `docs/00_PRODUCT.md` (read first), then `docs/01`–`03`.

NEET-PG catalog tests are hidden from the home screen; the MCQ player remains
for practice sessions only.

## Apply the UG schema

```bash
# against your Supabase project
supabase db push
# or paste supabase/migrations/20260830140000_ug_university_pivot.sql
```

Questions, catalog, users, announcements, prices, and coupons are edited
in the website admin at `/admin/`.

Replace the WhatsApp number in `lib/core/support.dart` before a public listing.
