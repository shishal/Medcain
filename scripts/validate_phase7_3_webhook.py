#!/usr/bin/env python3
"""
Phase 7.3 — Razorpay webhook → plan update.

Checks:
  1. Price/duration catalog matches across paid_plans.ts, paid_plans.js, and
     apply_razorpay_payment() SQL (never trust a client-sent amount).
  2. The RPC grants a plan, is idempotent, and rejects a wrong amount.
  3. authenticated cannot UPDATE profiles.plan or EXECUTE the RPC.
  4. POST without X-Razorpay-Signature is rejected (400).

Requires in .env: DATABASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY.
Optional: RAZORPAY_WEBHOOK_SECRET — if set, also POSTs a signed payload for a
temp user and checks the profile row.

Apply the migration first:
  npx supabase db push
  npx supabase secrets set RAZORPAY_WEBHOOK_SECRET=...
  npx supabase functions deploy razorpay-webhook
"""

from __future__ import annotations

import hmac
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db_url import normalize_database_url  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
TS = ROOT / "supabase" / "functions" / "_shared" / "paid_plans.ts"
JS = ROOT / "checkout" / "paid_plans.js"
SQL = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260930210000_discount_codes.sql"
)
FIELDS = ("amountPaise", "durationDays")


def load_env() -> None:
    if not ENV_PATH.exists():
        sys.exit(f"Missing {ENV_PATH}. Copy .env.example and fill in keys.")
    for line in ENV_PATH.read_text().splitlines():
        line = line.strip()
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
    subprocess.check_call(
        [str(py), "-m", "pip", "install", "--quiet", "psycopg[binary]"],
    )
    os.execv(str(py), [str(py), str(Path(__file__).resolve()), *sys.argv[1:]])


def block(text: str, plan: str) -> str:
    match = re.search(rf"{plan}:\s*\{{(.*?)\n  \}}", text, re.S)
    if not match:
        sys.exit(f"Could not find `{plan}` in catalog")
    return match.group(1)


def ts_js_fields(text: str, plan: str) -> dict[str, str]:
    body = block(text, plan)
    out: dict[str, str] = {}
    for key in FIELDS:
        match = re.search(rf"{key}:\s*(.+?),", body)
        if not match:
            sys.exit(f"Missing {key} on {plan}")
        out[key] = match.group(1).strip().strip("'").strip('"')
    return out


def sql_fields(sql: str, plan: str) -> dict[str, str]:
    pattern = (
        rf"if p_plan = '{plan}' then\s*"
        rf"v_amount_paise := (\d+);\s*"
        rf"v_duration_days := (\d+);"
    )
    match = re.search(pattern, sql)
    if not match:
        sys.exit(f"Could not find `{plan}` catalog in {SQL.name}")
    return {"amountPaise": match.group(1), "durationDays": match.group(2)}


def check_catalog() -> dict[str, dict[str, str]]:
    ts = TS.read_text()
    js = JS.read_text()
    sql = SQL.read_text()
    catalog: dict[str, dict[str, str]] = {}
    for plan in ("pro", "elite"):
        left = ts_js_fields(ts, plan)
        page = ts_js_fields(js, plan)
        db = sql_fields(sql, plan)
        if left != page or left != db:
            sys.exit(
                f"{plan} mismatch:\n  function {left}\n  page     {page}\n  sql      {db}"
            )
        catalog[plan] = left
        print(
            f"  catalog {plan}: amountPaise={left['amountPaise']} "
            f"durationDays={left['durationDays']}"
        )
    return catalog


def insert_auth_user(conn, user_id: str, email: str) -> None:
    conn.execute(
        """
        insert into auth.users (
          id, instance_id, aud, role, email,
          encrypted_password, email_confirmed_at,
          raw_app_meta_data, raw_user_meta_data,
          created_at, updated_at,
          confirmation_token, email_change,
          email_change_token_new, recovery_token
        ) values (
          %s::uuid,
          '00000000-0000-0000-0000-000000000000',
          'authenticated',
          'authenticated',
          %s,
          '$2a$06$placeholderplaceholderplaceholderpl.aceholderplaceho',
          now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          '{}'::jsonb,
          now(),
          now(),
          '',
          '',
          '',
          ''
        )
        """,
        (user_id, email),
    )
    conn.execute(
        """
        insert into public.profiles (id, plan)
        values (%s::uuid, 'free')
        on conflict (id) do update set plan = 'free',
          plan_started_at = null,
          plan_expires_at = null
        """,
        (user_id,),
    )


def as_obj(value: object) -> dict:
    if isinstance(value, str):
        return json.loads(value)
    if isinstance(value, dict):
        return value
    raise TypeError(f"expected jsonb object, got {type(value)}")


def post_webhook(url: str, anon: str, body: bytes, signature: str | None) -> tuple[int, str]:
    headers = {
        "Content-Type": "application/json",
        "apikey": anon,
        "Authorization": f"Bearer {anon}",
    }
    if signature is not None:
        headers["X-Razorpay-Signature"] = signature
    req = Request(url, data=body, headers=headers, method="POST")
    try:
        with urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode()
    except HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace")


def main() -> int:
    load_env()
    print("Phase 7.3 — payment webhook → plan update")

    print("1. Catalog (TS / checkout JS / SQL) must match")
    catalog = check_catalog()
    print("  catalog: OK")

    database_url = os.environ.get("DATABASE_URL", "")
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    anon = os.environ.get("SUPABASE_ANON_KEY", "")
    webhook_secret = os.environ.get("RAZORPAY_WEBHOOK_SECRET", "")

    if not database_url or "YOUR_" in database_url:
        sys.exit("DATABASE_URL is missing or still a placeholder in .env")
    if not supabase_url or "YOUR_" in supabase_url:
        sys.exit("SUPABASE_URL is missing or still a placeholder in .env")
    if not anon or anon.startswith("your_"):
        sys.exit("SUPABASE_ANON_KEY is missing or still a placeholder in .env")

    try:
        database_url = normalize_database_url(database_url)
    except ValueError as exc:
        sys.exit(f"DATABASE_URL: {exc}")

    ensure_psycopg()
    import psycopg

    user_id = str(uuid.uuid4())
    email = f"phase7_3_{user_id[:8]}@medico.test"
    payment_id = f"pay_phase73_{user_id[:8]}"
    created_user = False

    print("2. apply_razorpay_payment() RPC")
    with psycopg.connect(database_url) as conn:
        conn.execute("set search_path to public")

        fn = conn.execute(
            """
            select 1 from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'apply_razorpay_payment'
            """
        ).fetchone()
        if not fn:
            print("FAIL: apply_razorpay_payment() missing — run npx supabase db push")
            return 1

        can_exec = conn.execute(
            """
            select has_function_privilege('authenticated', p.oid, 'execute')
            from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'apply_razorpay_payment'
            """
        ).fetchone()[0]
        if can_exec:
            print("FAIL: authenticated can execute apply_razorpay_payment")
            return 1
        print("  authenticated cannot execute RPC: OK")

        can_update_plan = conn.execute(
            """
            select has_column_privilege(
              'authenticated', 'public.profiles', 'plan', 'update'
            )
            """
        ).fetchone()[0]
        if can_update_plan:
            print("FAIL: authenticated can UPDATE profiles.plan")
            return 1
        print("  authenticated cannot UPDATE profiles.plan: OK")

        for col in ("plan_started_at", "plan_expires_at"):
            can_update = conn.execute(
                """
                select has_column_privilege(
                  'authenticated', 'public.profiles', %s, 'update'
                )
                """,
                (col,),
            ).fetchone()[0]
            if can_update:
                print(f"FAIL: authenticated can UPDATE profiles.{col}")
                return 1
        print("  authenticated cannot UPDATE plan timestamps: OK")

        try:
            insert_auth_user(conn, user_id, email)
            created_user = True
            conn.commit()

            try:
                conn.execute(
                    """
                    select apply_razorpay_payment(
                      %s, 'order_wrong', %s::uuid, 'pro', 1, 'INR'
                    )
                    """,
                    (payment_id + "_bad", user_id),
                )
                print("FAIL: wrong amount was accepted")
                return 1
            except psycopg.Error as exc:
                conn.rollback()
                if "amount does not match catalog" not in str(exc):
                    print(f"FAIL: expected amount mismatch, got: {exc}")
                    return 1
                print("  wrong amount rejected: OK")

            first = as_obj(
                conn.execute(
                    """
                    select apply_razorpay_payment(
                      %s, 'order_ok', %s::uuid, 'pro', %s, 'INR'
                    )
                    """,
                    (payment_id, user_id, int(catalog["pro"]["amountPaise"])),
                ).fetchone()[0]
            )
            conn.commit()

            if first.get("applied") is not True or first.get("duplicate") is not False:
                print(f"FAIL: first apply: {first}")
                return 1

            row = conn.execute(
                """
                select plan, plan_expires_at > now() as future,
                       current_plan(id) as effective
                from public.profiles where id = %s::uuid
                """,
                (user_id,),
            ).fetchone()
            plan, future, effective = row
            if plan != "pro" or not future or effective != "pro":
                print(f"FAIL: profile after apply: plan={plan} future={future} effective={effective}")
                return 1
            print(f"  first apply granted pro, current_plan={effective}: OK")

            expires_before = conn.execute(
                "select plan_expires_at from public.profiles where id = %s::uuid",
                (user_id,),
            ).fetchone()[0]

            second = as_obj(
                conn.execute(
                    """
                    select apply_razorpay_payment(
                      %s, 'order_ok', %s::uuid, 'pro', %s, 'INR'
                    )
                    """,
                    (payment_id, user_id, int(catalog["pro"]["amountPaise"])),
                ).fetchone()[0]
            )
            conn.commit()

            if second.get("duplicate") is not True or second.get("applied") is not False:
                print(f"FAIL: retry should be duplicate: {second}")
                return 1

            expires_after = conn.execute(
                "select plan_expires_at from public.profiles where id = %s::uuid",
                (user_id,),
            ).fetchone()[0]
            if expires_after != expires_before:
                print("FAIL: retry extended plan_expires_at")
                return 1
            print("  retry is idempotent (no extra days): OK")
        except Exception:
            conn.rollback()
            raise
        finally:
            if created_user:
                try:
                    conn.execute(
                        "delete from auth.users where id = %s::uuid",
                        (user_id,),
                    )
                    conn.commit()
                    print("  cleaned up RPC temp user")
                except Exception as cleanup_err:
                    conn.rollback()
                    print(f"  RPC cleanup failed: {cleanup_err}")

    print("3. Unsigned webhook POST is rejected")
    webhook_url = f"{supabase_url}/functions/v1/razorpay-webhook"
    unsigned_body = b'{"event":"payment.captured"}'
    try:
        status, text = post_webhook(webhook_url, anon, unsigned_body, signature=None)
    except URLError as exc:
        print(f"FAIL: could not reach {webhook_url}: {exc}")
        print("  Deploy with: npx supabase functions deploy razorpay-webhook")
        return 1

    if status != 400:
        print(f"FAIL: unsigned webhook returned {status} {text}")
        print("  Expected 400 Invalid signature")
        return 1
    print(f"  unsigned POST → {status}: OK")

    if not webhook_secret or webhook_secret.startswith("your_"):
        print("4. Signed POST skipped (set RAZORPAY_WEBHOOK_SECRET in .env to run it)")
        print("PASS: catalog + RPC + unsigned rejection")
        return 0

    print("4. Signed webhook POST updates the profile")
    http_user = str(uuid.uuid4())
    http_email = f"phase7_3http_{http_user[:8]}@medico.test"
    http_pay = f"pay_wh_{http_user[:8]}"

    with psycopg.connect(database_url) as conn:
        try:
            insert_auth_user(conn, http_user, http_email)
            conn.commit()
        except Exception:
            conn.rollback()
            raise

        payload = {
            "entity": "event",
            "event": "payment.captured",
            "payload": {
                "payment": {
                    "entity": {
                        "id": http_pay,
                        "entity": "payment",
                        "amount": int(catalog["pro"]["amountPaise"]),
                        "currency": "INR",
                        "status": "captured",
                        "order_id": f"order_wh_{http_user[:8]}",
                        "notes": {
                            "user_id": http_user,
                            "plan": "pro",
                            "email": http_email,
                        },
                    }
                }
            },
        }
        raw = json.dumps(payload, separators=(",", ":")).encode()
        signature = hmac.new(
            webhook_secret.encode(), raw, hashlib.sha256
        ).hexdigest()

        try:
            status, text = post_webhook(webhook_url, anon, raw, signature)
        except URLError as exc:
            print(f"FAIL: signed POST could not reach webhook: {exc}")
            return 1
        finally:
            # Read profile before deleting the user.
            row = conn.execute(
                """
                select plan, current_plan(id) as effective
                from public.profiles where id = %s::uuid
                """,
                (http_user,),
            ).fetchone()
            try:
                conn.execute(
                    "delete from auth.users where id = %s::uuid",
                    (http_user,),
                )
                conn.commit()
                print("  cleaned up signed-POST temp user")
            except Exception as cleanup_err:
                conn.rollback()
                print(f"  signed-POST cleanup failed: {cleanup_err}")

    if status != 200:
        print(f"FAIL: signed webhook returned {status} {text}")
        print("  Secret on the function must match RAZORPAY_WEBHOOK_SECRET")
        return 1
    if row is None or row[0] != "pro" or row[1] != "pro":
        print(f"FAIL: profile after signed webhook: {row}")
        return 1
    print(f"  signed POST → {status}, profile.plan=pro: OK")
    print("PASS: webhook verifies signature and updates plan")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
