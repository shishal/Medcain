# MEDCAIN — Claude Code instructions

Project instructions live in **AGENTS.md** (read it first — it is the single source of truth for rules, docs index, and working style). This file adds Claude Code–specific context on top of that.

## Claude Code conventions

- Task list: use `mcp__ccd_turn__update_plan` to track multi-step work; mark each step done as you finish it.
- One task from `docs/03_BUILD_PLAN.md` at a time. After finishing, stop and summarize — don't chain into the next task unasked.
- Prefer `Read` / `Edit` / `Write` tools over `Bash cat/sed/echo`; use `Bash` only for shell-only operations.
- For UI changes: start the dev server and verify the feature in a browser/emulator before reporting done.
- Commit attribution: end every commit message with `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.

## Switching between Cursor and Claude Code

Both tools read their own instruction files:
- **Cursor** reads `.cursor/rules/` (currently empty — rules live in docs instead)
- **Claude Code** reads `CLAUDE.md` (this file) and `AGENTS.md`

All substantive project rules live in `AGENTS.md` and `docs/` so either tool gets the same context.
