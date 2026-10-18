#!/usr/bin/env python3
"""Validate the one-file Questions CSV migration and optional live sync."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

from sync_content_csv import DEFAULT_CSV, read_rows


ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"


def load_env() -> None:
    if not ENV_PATH.exists():
        sys.exit(f"Missing {ENV_PATH}. Copy .env.example and fill in DATABASE_URL.")
    for raw in ENV_PATH.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def ensure_psycopg() -> None:
    try:
        import psycopg  # noqa: F401

        return
    except ImportError:
        pass
    venv_dir = ROOT / "scripts" / ".venv"
    py = venv_dir / "bin" / "python"
    if not py.exists():
        subprocess.check_call([sys.executable, "-m", "venv", str(venv_dir)])
    subprocess.check_call([str(py), "-m", "pip", "install", "--quiet", "psycopg[binary]"])
    os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])


def generated_id(row: dict[str, str]) -> str:
    kind = row.get("question_type", "").strip().lower()
    normalized = "|".join((
        " ".join(row["subject_name"].lower().split()),
        kind,
        " ".join(row["question_text"].lower().split()),
    ))
    return "CSV-" + hashlib.md5(normalized.encode()).hexdigest()[:24].upper()  # noqa: S324


def check_migration(conn) -> list[str]:
    errors: list[str] = []
    column = conn.execute(
        """
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'questions'
          and column_name = 'content_sync_source'
        """
    ).fetchone()
    if not column:
        errors.append("questions.content_sync_source is missing")
    function = conn.execute(
        "select to_regprocedure('public.sync_content_csv(jsonb,boolean)')"
    ).fetchone()[0]
    if function is None:
        errors.append("sync_content_csv(jsonb, boolean) is missing")
    return errors


def check_sample_csv() -> tuple[list[dict[str, str]], list[str]]:
    try:
        rows = read_rows(DEFAULT_CSV)
    except (OSError, ValueError) as error:
        return [], [str(error)]
    errors: list[str] = []
    if not rows:
        errors.append("Questions.csv has no content rows")
    if not any(row.get("question_type") == "pyq_theory" for row in rows):
        errors.append("Questions.csv needs a theory example")
    if not any(row.get("question_type") == "mcq" and row.get("correct_option") for row in rows):
        errors.append("Questions.csv needs an MCQ example")
    for index, row in enumerate(rows, start=2):
        missing = [
            name for name in ("university_alias", "university_name", "exam_type", "year", "month", "subject_name", "question_type", "question_text")
            if not row.get(name)
        ]
        if missing:
            errors.append(
                f"Questions.csv row {index}: missing {', '.join(missing)}"
            )
    return rows, errors


def check_synced_content(conn, rows: list[dict[str, str]]) -> list[str]:
    ids = [generated_id(row) for row in rows]
    found = {
        row[0]
        for row in conn.execute(
            "select external_id from public.questions where external_id = any(%s)",
            (ids,),
        ).fetchall()
    }
    return [f"synced question missing: {external_id}" for external_id in ids if external_id not in found]


def rpc(conn, rows: list[dict[str, str]], apply: bool) -> dict:
    return conn.execute(
        "select public.sync_content_csv(%s::jsonb, %s)",
        (json.dumps(rows), apply),
    ).fetchone()[0]


def exercise_sync(conn) -> list[str]:
    """Exercise apply inside a transaction that is always rolled back."""
    errors: list[str] = []
    suffix = uuid.uuid4().hex[:8]
    uni = conn.execute(
        """
        select code, name, state
        from public.universities
        where lower(code) = 'kuhs'
        """
    ).fetchone()
    subjects = conn.execute(
        """
        select name from public.subjects
        where lower(name) in ('anatomy', 'physiology')
        order by lower(name)
        """
    ).fetchall()
    if uni is None or len(subjects) < 2:
        return ["exercise needs KUHS plus Anatomy and Physiology subjects"]
    anatomy, physiology = subjects[0][0], subjects[1][0]
    chapter = f"Shared topic {suffix}"

    def sitting(subject: str, stem: str, **extra: str) -> dict[str, str]:
        row = {
            "state": uni[2],
            "university_alias": uni[0],
            "university_name": uni[1],
            "exam_type": "PROF",
            "year": "2021",
            "month": "October",
            "paper_number": "Paper I",
            "subject_name": subject,
            "question_type": "pyq_theory",
            "question_text": stem,
        }
        row.update(extra)
        return row

    valid = [
        sitting(anatomy, f"Minimal theory {suffix}"),
        sitting(
            anatomy,
            f"Complete MCQ {suffix}",
            question_type="mcq",
            option_a="A", option_b="B", option_c="C", option_d="D",
            correct_option="A",
            chapter_name=chapter,
        ),
        sitting(
            physiology,
            f"Same-named chapter in another subject {suffix}",
            chapter_name=chapter,
        ),
    ]
    invalid_cases = [
        ([sitting(anatomy, "Partial MCQ", question_type="mcq", option_a="A")], "option_b"),
        ([sitting(anatomy, "No month", month="")], "month is required"),
        ([sitting("Not A Real Subject", "Unknown subject")], "is not in subjects"),
        ([sitting(anatomy, "Topic without chapter", topic_name="Lesson")], "chapter_name"),
        ([sitting(anatomy, "Bad exam", exam_type="university")], "exam_type must be"),
        ([sitting(anatomy, "Partial book", textbook_title="Book")], "page"),
    ]

    try:
        preview = rpc(conn, valid, False)
        if not preview.get("ok") or preview.get("applied"):
            errors.append("valid preview did not succeed without writes")

        for rows, expected in invalid_cases:
            result = rpc(conn, rows, False)
            messages = " ".join(result.get("errors", []))
            if result.get("ok") or expected not in messages:
                errors.append(f"invalid case did not report {expected}")

        marker = f"VALIDATOR-{suffix}"
        conn.execute(
            """
            insert into public.questions
              (external_id, kind, question_text, difficulty, required_plan, is_active)
            values (%s, 'pyq_theory', 'Non CSV control', 'should', 'free', true)
            """,
            (marker,),
        )
        result = rpc(conn, valid, True)
        if not result.get("ok") or not result.get("applied"):
            errors.append("valid apply failed")

        if not conn.execute(
            "select 1 from public.questions where external_id = %s", (marker,)
        ).fetchone():
            errors.append("snapshot deleted a non-CSV control question")

        topics = conn.execute(
            """
            select s.name, t.name
            from public.topics t join public.subjects s on s.id = t.subject_id
            where s.name in (%s, %s) and t.name = %s
            """,
            (anatomy, physiology, chapter),
        ).fetchall()
        if len(topics) != 2:
            errors.append("same topic name did not resolve independently per subject")

        second = rpc(conn, valid, False)
        if second.get("counts", {}).get("insert") != 0 or second.get("counts", {}).get("delete") != 0:
            errors.append("unchanged second sync is not idempotent")

        reduced = valid[:1]
        removal = rpc(conn, reduced, False)
        if removal.get("counts", {}).get("delete", 0) < 2:
            errors.append("snapshot preview did not report removed managed questions")
    finally:
        conn.rollback()
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-synced", action="store_true")
    parser.add_argument(
        "--exercise-sync",
        action="store_true",
        help="Run transactional importer tests against DATABASE_URL, then roll everything back",
    )
    args = parser.parse_args()

    rows, csv_errors = check_sample_csv()
    if csv_errors:
        for error in csv_errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Questions.csv: {len(rows)} valid sample row(s)")

    load_env()
    ensure_psycopg()
    import psycopg

    database_url = os.environ.get("DATABASE_URL", "")
    if not database_url:
        sys.exit("DATABASE_URL not set in .env")

    with psycopg.connect(database_url) as conn:
        errors = check_migration(conn)
        if args.expect_synced and not errors:
            errors.extend(check_synced_content(conn, rows))
        if args.exercise_sync and not errors:
            print("Exercising sync in a rollback-only transaction...")
            errors.extend(exercise_sync(conn))
        if errors:
            for error in errors:
                print(f"ERROR: {error}")
            return 1

    print("CSV sync validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
