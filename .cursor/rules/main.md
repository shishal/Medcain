# MEDCAIN — Cursor rules

Project instructions live in **AGENTS.md** at the repo root — read it first. It is the single source of truth for rules, docs index, stack decisions, and working style.

Full planning docs are in `docs/`:
- `docs/00_PRODUCT.md` — what the app is (read always)
- `docs/01_PROJECT_FOUNDATION.md` — tech stack, architecture, conventions (read always)
- `docs/02_DATABASE_SCHEMA.md` — Supabase schema, RLS, practice generator
- `docs/03_BUILD_PLAN.md` — phased tasks with acceptance criteria
- `docs/04_TEST_ENGINE_SPEC.md` — historical NEET-PG test engine
- `docs/05_PRACTICE_MODE_SPEC.md` — practice mode behavior
- `docs/10_INDIA_MBBS_EXAMS.md` — how Indian MBBS university papers work

All substantive rules live in `AGENTS.md` and `docs/` so Cursor and Claude Code share the same context. Don't add Cursor-only rules here that would make the two tools diverge.
