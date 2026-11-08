#!/usr/bin/env python3
"""Preview or apply the one-file Questions CSV through Supabase RPC."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = ROOT / "content" / "google_sheet" / "tabs" / "Questions.csv"
# Preferred editor column order for Questions.csv (extras may follow).
LEAN_TEMPLATE_COLUMNS = (
    "course",
    "state",
    "university_alias",
    "university_name",
    "college_alias",
    "college_name",
    "exam_type",
    "year",
    "month",
    "paper_number",
    "subject_name",
    "chapter_name",
    "topic_name",
    "question_type",
    "marks",
    "question_id",
    "question_text",
    "option_a",
    "option_b",
    "option_c",
    "option_d",
    "correct_option",
    "answers",
    "exp_1",
    "exp_2",
)
REQUIRED_HEADERS = {
    "university_alias",
    "university_name",
    "exam_type",
    "year",
    "month",
    "subject_name",
    "question_type",
    "question_text",
}
ALLOWED_COLUMNS = {
    *LEAN_TEMPLATE_COLUMNS,
    "textbook_title", "textbook_authors", "textbook_edition",
    "page", "section_heading", "difficulty", "required_plan", "is_active",
    "resource_title", "resource_url", "resource_source_label", "resource_is_free",
}


def load_env() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for raw in env_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError("CSV has no header row")
        headers = {
            header.strip().lower().replace(" ", "_").replace("-", "_")
            for header in reader.fieldnames
        }
        missing = REQUIRED_HEADERS - headers
        if missing:
            raise ValueError(f"CSV is missing required column(s): {', '.join(sorted(missing))}")
        unsupported = headers - ALLOWED_COLUMNS
        if unsupported:
            raise ValueError(
                f"CSV has unsupported column(s): {', '.join(sorted(unsupported))}. "
                "Use the current Questions.csv template."
            )
        rows: list[dict[str, str]] = []
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                raise ValueError(f"CSV row {row_number} has more values than the header")
            normalized = {
                key.strip().lower().replace(" ", "_").replace("-", "_"): (value or "").strip()
                for key, value in row.items()
                if (value or "").strip()
            }
            if any(normalized.values()):
                normalized["_row_number"] = str(row_number)
                rows.append(normalized)
        return rows


def call_sync(rows: list[dict[str, str]], *, apply: bool) -> dict:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env")

    request = urllib.request.Request(
        f"{url}/rest/v1/rpc/sync_content_csv",
        data=json.dumps({"p_rows": rows, "p_apply": apply}).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        raise RuntimeError(f"Supabase RPC failed ({error.code}): {body}") from error


def write_question_ids(path: Path, result: dict) -> int:
    """Fill blank or unpadded question_id cells from an applied sync."""
    assigned = {
        int(item["row_number"]): str(item["question_id"])
        for item in result.get("question_ids", [])
        if item.get("row_number") and item.get("question_id")
    }
    if not assigned:
        return 0
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)
    key = "question_id"
    normalized = [name.strip().lower().replace(" ", "_").replace("-", "_") for name in fieldnames]
    if key not in normalized:
        fieldnames.append(key)
        normalized.append(key)
    column = fieldnames[normalized.index(key)]
    written = 0
    for row in rows:
        for name in fieldnames:
            if row.get(name) is None:
                row[name] = ""
    for row_number, row in enumerate(rows, start=2):
        code = assigned.get(row_number)
        if not code:
            continue
        if (row.get(column) or "").strip() != code:
            row[column] = code
            written += 1
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return written


def print_result(result: dict) -> None:
    for error in result.get("errors", []):
        print(f"ERROR: {error}", file=sys.stderr)
    for warning in result.get("warnings", []):
        print(f"WARNING: {warning}")
    counts = result.get("counts", {})
    print(
        "Questions: "
        f"{counts.get('insert', 0)} insert, "
        f"{counts.get('update', 0)} update, "
        f"{counts.get('delete', 0)} DELETE"
    )
    print(f"Complete attempts to DELETE: {counts.get('attempt_delete', 0)}")
    print(f"Dependent history to DELETE: {counts.get('dependent_delete', 0)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", nargs="?", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--apply", action="store_true", help="Apply after a successful preview")
    parser.add_argument("--yes", action="store_true", help="Confirm destructive apply non-interactively")
    args = parser.parse_args()

    load_env()
    try:
        rows = read_rows(args.csv_path)
        print(f"Loaded {len(rows)} row(s) from {args.csv_path}")
        preview = call_sync(rows, apply=False)
        print_result(preview)
        if not preview.get("ok"):
            return 1
        if not args.apply:
            print("Preview only. Re-run with --apply to write.")
            return 0

        if not args.yes:
            answer = input("Apply this complete snapshot? Type APPLY to continue: ")
            if answer != "APPLY":
                print("Cancelled.")
                return 0

        result = call_sync(rows, apply=True)
        print_result(result)
        if result.get("ok") and result.get("applied"):
            written = write_question_ids(args.csv_path, result)
            if written:
                print(f"Wrote {written} question_id value(s) back to {args.csv_path}")
            return 0
        return 1
    except (OSError, ValueError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
