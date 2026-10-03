# Phase 7.2 / 7.3 — External web checkout + plan update

**Test Mode only.** When you are ready for real money, follow
[`docs/06_PAYMENTS_PRODUCTION.md`](../docs/06_PAYMENTS_PRODUCTION.md) (Live
keys, HTTPS hosting, Flutter `CHECKOUT_URL`, Live webhook). Do not put
`rzp_live_` keys in this local setup.

A small static site (not part of the Flutter app) where a student signs in
with their MEDCAIN email and pays through **Razorpay Checkout**. The app
only opens this page in the system browser.

A successful **Test Mode** payment makes Razorpay POST to the
`razorpay-webhook` Edge Function. That function verifies Razorpay's
signature and calls `apply_razorpay_payment()`, which sets `profiles.plan`
and `plan_expires_at`.

## What lives where

| Piece | Role |
|---|---|
| This folder | HTML/JS page: email login, plan pick, Razorpay modal |
| `supabase/functions/create-razorpay-order` | Creates the Razorpay **Order** (amount is chosen here, not in the browser) |
| `supabase/functions/razorpay-webhook` | Verifies `X-Razorpay-Signature`, then grants the plan |
| `apply_razorpay_payment()` (Postgres) | Amount check + idempotent `profiles` update |

## One-time setup

1. Create a [Razorpay](https://dashboard.razorpay.com/) account and switch the
   Dashboard to **Test Mode**.
2. **Account & Settings → API Keys** → generate Test keys (`rzp_test_…`).
3. Put them in the repo `.env` (never commit that file):

   ```
   RAZORPAY_KEY_ID=rzp_test_...
   RAZORPAY_KEY_SECRET=...
   RAZORPAY_WEBHOOK_SECRET=...
   CHECKOUT_URL=http://127.0.0.1:4173
   ```

   On an Android emulator, use `http://10.0.2.2:4173` so the device reaches
   your laptop.

4. Push the secrets and functions to the hosted project the Flutter app uses:

   ```bash
   npx supabase db push
   npx supabase secrets set \
     RAZORPAY_KEY_ID="$RAZORPAY_KEY_ID" \
     RAZORPAY_KEY_SECRET="$RAZORPAY_KEY_SECRET" \
     RAZORPAY_WEBHOOK_SECRET="$RAZORPAY_WEBHOOK_SECRET"
   npx supabase functions deploy create-razorpay-order
   npx supabase functions deploy razorpay-webhook
   ```

   `razorpay-webhook` must stay `verify_jwt = false` — Razorpay does not send
   a Supabase JWT. Auth is Razorpay's HMAC instead.

5. In Razorpay Dashboard → **Account & Settings → Webhooks** (Test Mode),
   add this URL:

   `https://<PROJECT_REF>.supabase.co/functions/v1/razorpay-webhook`

   Active event: **`payment.captured`** (required). `order.paid` is optional
   and ignored by the function.

   Secret: the same value as `RAZORPAY_WEBHOOK_SECRET`.

   Custom headers (Supabase's gateway still wants the public anon key even
   though JWT verification is off):

   | Header | Value |
   |---|---|
   | `apikey` | `SUPABASE_ANON_KEY` (same key as the Flutter app — it is public) |
   | `Authorization` | `Bearer <SUPABASE_ANON_KEY>` |

## Run the page locally

```bash
python3 checkout/serve.py
```

Open http://127.0.0.1:4173 (optional `?plan=elite&email=you@example.com`).

Sign in with a real MEDCAIN test account, pick Pro or Elite, pay.

## Test payment (no real money)

1. Choose **Card**.
2. Number `4111 1111 1111 1111` (Visa) or `5267 3181 8797 5449` (Mastercard).
3. Any future expiry, any CVV.
4. On the mock bank page, click **Success**.

Then:

- Razorpay Dashboard → **Transactions → Payments** should show **Captured**.
- Razorpay Dashboard → **Webhooks** should show a 200 delivery.
- Supabase Table Editor → `profiles` for that user: `plan` is `pro` or
  `elite`, `plan_expires_at` is in the future.
- In the Flutter app, open **Profile** and tap the refresh icon — the plan
  label updates without rebuilding the app.

### Unsigned webhook (must fail)

```bash
curl -i -X POST "$SUPABASE_URL/functions/v1/razorpay-webhook" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event":"payment.captured"}'
```

Expect **400** and `{"error":"Invalid signature"}`. A 200 here means the
endpoint would grant plans to anyone.

Or run:

```bash
python3 scripts/validate_phase7_3_webhook.py
```

Signature helper (no network):

```bash
npx deno test supabase/functions/_shared/razorpay_webhook_test.ts
```

## Prices

| Plan | Amount | Access window |
|---|---|---|
| Pro | ₹1,499 | 180 days |
| Elite | ₹2,999 | 365 days |

Change `checkout/paid_plans.js`, `supabase/functions/_shared/paid_plans.ts`,
**and** `paid_plan_terms()` in
`supabase/migrations/20260930210000_discount_codes.sql`, then run
`python3 scripts/validate_phase7_3_webhook.py`.

A discount code does not change those list prices. Issue one with
`issue_discount_code()` — see `docs/06_PAYMENTS_PRODUCTION.md`.
