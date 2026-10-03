# Payments — production integration guide

Use this when you are ready to take **real money**. The app, checkout page, and
webhook are already built (Phases 7.1–7.3). This file is only the **Live**
switch: Razorpay Live keys, an HTTPS checkout URL, and the matching Supabase
secrets.

Local / Test Mode steps stay in [`checkout/README.md`](../checkout/README.md).
Do not mix those keys with the Live ones below.

---

## What is already built

You do **not** need to write a new payment flow. Going live is configuration.

| Piece | What it already does |
|---|---|
| Flutter **Plans** screen | Opens the system browser only (`url_launcher`). No card form, no IAP. |
| `checkout/` static page | Email login + Razorpay Checkout modal |
| `create-razorpay-order` Edge Function | Creates the Razorpay Order; **amount comes from the server catalog**, not the browser |
| `razorpay-webhook` Edge Function | Checks `X-Razorpay-Signature`, then grants the plan |
| `apply_razorpay_payment()` in Postgres | Checks amount/duration, updates `profiles.plan` / `plan_expires_at`, ignores duplicate webhooks |

Money never goes through the Flutter app. That is the App Store / Play
compliance boundary: the app only **links out**.

---

## How the Live path fits together

```
Student in MEDCAIN
  → browser opens CHECKOUT_URL?plan=pro&email=…
  → signs in (same Supabase Auth as the app)
  → Pay → create-razorpay-order (Live key) → Razorpay Checkout
  → student pays
  → Razorpay POST payment.captured → razorpay-webhook
  → apply_razorpay_payment() → profiles.plan
  → student returns to the app → Profile → refresh
```

One Edge Function has **one** Razorpay key pair and **one** webhook secret.
When you switch to Live, Test Mode deliveries to that URL will fail signature
checks. That is expected — delete or disable the Test webhook so it stops
retrying.

---

## Do this in order

### 1. Push the database and functions (if you have not already)

From the repo root, logged in and linked to the **same** Supabase project the
app uses:

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase functions deploy create-razorpay-order
npx supabase functions deploy razorpay-webhook
```

Confirm in the SQL editor:

```sql
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'apply_razorpay_payment';
```

`razorpay-webhook` must stay `verify_jwt = false` in `supabase/config.toml`
(Razorpay cannot send a Supabase JWT). Do not “fix” that.

### 2. Activate Razorpay Live

1. Open [Razorpay Dashboard](https://dashboard.razorpay.com/) → complete
   **business KYC** (Live is blocked until this is approved).
2. Fill **Website / app** details. Use the HTTPS checkout URL from step 3
   (you can come back and paste it after the page is hosted).
3. Flip the Dashboard toggle from **Test Mode** to **Live Mode**.
4. **Account & Settings → API Keys** → generate **Live** keys.
   - Key id starts with `rzp_live_` (never `rzp_test_`).
   - The key **secret** is shown once. Store it in a password manager, not git.

Keep the Test keys. You will still use Test Mode for development.

### 3. Serve checkout on the public site

Razorpay **Live** Checkout expects the page to be served over **https://**.
`python3 checkout/serve.py` is local-only.

The public site already serves checkout at
`https://medico.shishal.com/checkout` (`website/public/checkout/`). From the
repo root, rebuild so nginx and the page are current:

```bash
docker compose up --build -d
```

On startup the container writes `checkout/config.js` from `SUPABASE_URL` and
`SUPABASE_ANON_KEY` in the repo `.env` (the same public values as the Flutter
app). Never put `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, or
`SUPABASE_SERVICE_ROLE_KEY` in that container. The Razorpay **public** key is
returned at runtime by `create-razorpay-order`.

Open `https://medico.shishal.com/checkout`. You should see the sign-in form.
Paste that URL into Flutter `CHECKOUT_URL`, Razorpay website details, and
Supabase Auth redirect URLs.

### 4. Allow the checkout origin in Supabase Auth

Dashboard → **Authentication → URL configuration**:

- **Site URL**: can stay the app / marketing site.
- **Additional redirect URLs**: add `https://medico.shishal.com` (and
  `https://medico.shishal.com/**` if the UI offers a wildcard).

Checkout login uses email + password (no OAuth redirect today). This still
matters if you later add magic links or password reset from that page.

### 5. Point the Flutter app at the hosted page

In the **gitignored** `.env` that store / Codemagic builds use:

```
CHECKOUT_URL=https://medico.shishal.com/checkout
```

Rules:

- Must be `https://` (Android already allows the app to query `https` browsers).
- No trailing path required; the app adds `?plan=pro|elite` and `email=`.
- `.env` is bundled as a Flutter **asset**. Changing it requires a **new app
  build**. Editing Supabase or Razorpay after that does **not** require a
  rebuild; editing `CHECKOUT_URL` does.

For Codemagic: create `.env` in the build script from Codemagic environment
variables (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CHECKOUT_URL`). Do not commit
`.env`.

**iOS:** if “Continue on web” does nothing, add to `ios/Runner/Info.plist`:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>https</string>
</array>
```

### 6. Create the Live webhook (this is a new webhook, not an edit of Test)

Still in **Live Mode** → **Account & Settings → Webhooks** → Add.

| Field | Value |
|---|---|
| URL | `https://YOUR_PROJECT_REF.supabase.co/functions/v1/razorpay-webhook` |
| Secret | Generate a **new** Live secret. This becomes `RAZORPAY_WEBHOOK_SECRET`. |
| Active events | **`payment.captured`** only (required). `order.paid` is ignored. |

Custom headers (Supabase still wants the public anon key even with JWT
verification off):

| Header | Value |
|---|---|
| `apikey` | Flutter `SUPABASE_ANON_KEY` (public) |
| `Authorization` | `Bearer <same anon key>` |

Disable or delete the **Test** webhook that pointed at this same URL so it
does not retry with the old secret.

### 7. Put Live secrets on the Edge Functions

`.env` on your laptop (never commit):

```
RAZORPAY_KEY_ID=rzp_live_...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...   # must match the Live webhook secret from step 6
```

Push them and redeploy (redeploy so you are sure the running functions see
the new values):

```bash
npx supabase secrets set \
  RAZORPAY_KEY_ID="$RAZORPAY_KEY_ID" \
  RAZORPAY_KEY_SECRET="$RAZORPAY_KEY_SECRET" \
  RAZORPAY_WEBHOOK_SECRET="$RAZORPAY_WEBHOOK_SECRET"
npx supabase functions deploy create-razorpay-order
npx supabase functions deploy razorpay-webhook
```

Sanity check: Dashboard → Edge Functions → Secrets. `RAZORPAY_KEY_ID` must
start with `rzp_live_`.

### 8. Prove unsigned webhooks still fail

```bash
curl -i -X POST "$SUPABASE_URL/functions/v1/razorpay-webhook" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event":"payment.captured"}'
```

Expect **400** and `{"error":"Invalid signature"}`. If this is 200, **stop** —
anyone could grant themselves a plan.

Then run:

```bash
python3 scripts/validate_phase7_3_webhook.py
```

(Needs `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` in `.env`. Signed
HTTP check also needs `RAZORPAY_WEBHOOK_SECRET`.)

### 9. One real payment (then refund if you want)

1. Install a **release** build whose `.env` has the production `CHECKOUT_URL`
   (or open the hosted page in a desktop browser).
2. Sign in with a real MEDCAIN account you control.
3. Pay with a real UPI / card for Pro or Elite.
4. Razorpay → **Payments**: status **Captured**.
5. Razorpay → **Webhooks**: delivery **200**.
6. Supabase → Table Editor → `profiles`: that user’s `plan` and
   `plan_expires_at` (future date).
7. App → **Profile** → refresh icon. Plan label updates **without** a new
   binary.

If you do not want to keep the plan on that account, set `plan` back to
`free` and `plan_expires_at` to `null` in Table Editor. A Razorpay **refund
does not automatically downgrade** the user (there is no refund webhook
handler yet).

---

## Store listing (when you submit)

Phase 9 still applies. For payments specifically:

- The in-app Plans screen must keep **linking out**. Do not add an in-app
  “Buy” that charges inside the binary.
- Publish a **privacy policy** and **refund / cancellation** page (even
  though billing is on the website). First-time EdTech reviews often ask.
- Razorpay can issue GST invoices if you enable that in the Dashboard — turn
  it on before the first real customer if you need it.

---

## Discount and referral codes

The checkout page has a code field. Postgres computes the percent off. The
browser cannot choose the amount.

Issue a code in the Supabase SQL editor:

```sql
select public.issue_discount_code(
  p_percent_off => 20,
  p_owner_user_id => '00000000-0000-0000-0000-000000000000', -- profile id
  p_code => 'CAMPUS20'  -- omit this argument to generate a code
);
```

`p_owner_user_id` set: that student sees the code on **Profile** and can share
it. It discounts other students' payments. It does not discount the owner's
own payment. Issuing another code to the same student turns the previous one
off.

`p_owner_user_id` null: a promo anyone signed in can enter.

Optional: `p_max_redemptions => 50`, `p_expires_at => timestamptz '2026-12-31'`.
Percent is 1–99. Each student can use a given code once. To stop a code
without breaking a payment already in progress:

```sql
update public.discount_codes set active = false where code = 'CAMPUS20';
```

Leave `percent_off` as it was issued. The webhook checks that stored percent.

## Changing prices later

Three places must stay identical (the validator checks this):

1. `supabase/functions/_shared/paid_plans.ts` (Edge Function)
2. `checkout/paid_plans.js` (display only — keep `website/public/checkout/paid_plans.js` identical)
3. `paid_plan_terms()` in `supabase/migrations/20260930210000_discount_codes.sql`

Then: `python3 scripts/validate_phase7_3_webhook.py`, `npx supabase db push`,
redeploy `create-razorpay-order`, redeploy the hosted `paid_plans.js`.

---

## Day-2 operations

| Situation | What to do |
|---|---|
| Student paid, plan still Free | Razorpay webhook log: non-200? Redeploy function / check Live secret. Profile → refresh. |
| Webhook 400 Invalid signature | Live secret in Razorpay ≠ `RAZORPAY_WEBHOOK_SECRET` on Supabase. |
| Checkout says “not available” | Container started without `SUPABASE_URL` / `SUPABASE_ANON_KEY`. Rebuild after they are in `.env`. |
| Pay button says “not configured yet” | `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` are missing on the Edge Functions. |
| Pay button fails, Test keys in Live | `RAZORPAY_KEY_ID` still `rzp_test_`. |
| You refund in Razorpay | Manually set `profiles.plan = 'free'` (or wait until `plan_expires_at`). |
| Rotate keys | New Live API keys + new webhook secret → `secrets set` → redeploy both functions. Update Razorpay webhook secret to match. |
| Student buys again before expiry | Same payment id is ignored. A new payment adds a full window onto any time still left. |

---

## Copy-paste checklist

- [ ] `npx supabase db push` — `apply_razorpay_payment` exists
- [ ] Both Edge Functions deployed
- [ ] Razorpay KYC approved, **Live Mode** on
- [ ] Checkout hosted at `https://…` with a real `config.js`
- [ ] Flutter / Codemagic `.env` `CHECKOUT_URL` is that https URL
- [ ] New store build after changing `CHECKOUT_URL`
- [ ] Supabase Auth additional redirect URL includes the checkout origin
- [ ] Live API keys (`rzp_live_…`) in `npx supabase secrets`
- [ ] **New** Live webhook: `payment.captured` + custom `apikey` / `Authorization`
- [ ] `RAZORPAY_WEBHOOK_SECRET` matches that Live webhook
- [ ] Test webhook on the same URL is disabled
- [ ] Unsigned POST returns 400
- [ ] One Live payment updates `profiles`; app refresh shows the plan
- [ ] Privacy + refund pages ready before store submit
