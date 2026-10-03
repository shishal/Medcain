#!/usr/bin/env python3
"""Phase 7.2 — display prices on the checkout page must match the Edge Function."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TS = ROOT / "supabase" / "functions" / "_shared" / "paid_plans.ts"
JS = ROOT / "checkout" / "paid_plans.js"
# Public site serves copies. Prices and checkout behavior must stay identical.
SITE_COPIES = (
    (
        ROOT / "checkout" / "paid_plans.js",
        ROOT / "website" / "public" / "checkout" / "paid_plans.js",
    ),
    (
        ROOT / "checkout" / "app.js",
        ROOT / "website" / "public" / "checkout" / "app.js",
    ),
)
FIELDS = ("amountPaise", "durationDays", "periodLabel")


def block(text: str, plan: str) -> str:
    match = re.search(rf"{plan}:\s*\{{(.*?)\n  \}}", text, re.S)
    if not match:
        sys.exit(f"Could not find `{plan}` in catalog")
    return match.group(1)


def fields(text: str, plan: str) -> dict[str, str]:
    body = block(text, plan)
    out: dict[str, str] = {}
    for key in FIELDS:
        match = re.search(rf"{key}:\s*(.+?),", body)
        if not match:
            sys.exit(f"Missing {key} on {plan}")
        out[key] = match.group(1).strip().strip("'").strip('"')
    return out


def main() -> int:
    ts = TS.read_text()
    js = JS.read_text()
    for plan in ("pro", "elite"):
        left = fields(ts, plan)
        right = fields(js, plan)
        if left != right:
            sys.exit(f"{plan} mismatch:\n  function {left}\n  page     {right}")
        print(f"ok {plan} amountPaise={left['amountPaise']} {left['periodLabel']}")
    for source, copy in SITE_COPIES:
        if source.read_text() != copy.read_text():
            sys.exit(f"{copy.relative_to(ROOT)} drifted from {source.relative_to(ROOT)}")
        print(f"ok copy {copy.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
