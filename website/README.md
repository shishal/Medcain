# MEDCAIN public site (medcain.shishal.com)

Static marketing + Play Store legal pages. Served by nginx in Docker on your
machine; Cloudflare sits in front.

Positioning: **MBBS university-exam companion** (generic — no named
university on the public site), not NEET-PG mocks. Theme follows the Flutter
chrome (coral `#F25C2D`, charcoal, indigo accent).

Checkout at `/checkout/` signs the student in with Supabase (public URL and
anon key only) and opens Razorpay Checkout. Card data stays with Razorpay.
Secret keys stay on the Supabase Edge Functions, not in this image.

## Pages (paste these into Play Console)

| Play / store field | URL |
|---|---|
| Website | https://medcain.shishal.com/ |
| Privacy policy | https://medcain.shishal.com/privacy/ |
| Manage / cancel a plan | https://medcain.shishal.com/account/ |
| Terms (optional extra) | https://medcain.shishal.com/terms/ |
| Support email | medcain@shishal.com |

`/refunds/` redirects to `/account/`.

`/admin/` is the operator console (questions, catalog, users, announcements,
prices, coupons). It is not linked from the marketing pages. Sign-in is the
same WhatsApp flow as checkout, and every save goes through an admin-only
database function. The container writes `admin/config.js` from the same public
`SUPABASE_URL` and `SUPABASE_ANON_KEY` as checkout.

Support mail goes to `medcain@shishal.com`.

## Run with Docker Compose

From the **repo root** (same `docker-compose.yml` the host machine should use):

```bash
docker compose up --build -d
```

Or from this directory:

```bash
docker compose up --build -d
```

Either way the site is at http://127.0.0.1:8083 (`medico-site` container).
Change the host port with `MEDICO_SITE_PORT` in the repo-root `.env` if 8083 is taken.

Without Docker:

```bash
python3 -m http.server 8080 --directory public
```

## Deploy on your machine + Cloudflare

### 1. DNS

In Cloudflare, zone `shishal.com`:

- Add a **CNAME** (or the Tunnel hostname) for `medico` → your tunnel, **or**
- If the box already has a public IP and you terminate TLS at Cloudflare:
  **A/AAAA** for `medico` to that IP, orange-cloud proxied.

SSL/TLS mode:

- Tunnel or origin HTTP on loopback: **Full** is enough.
- Origin with a real certificate: **Full (strict)**.

### 2. Docker on the host

Copy this repo onto the machine. From the **repo root**:

```bash
docker compose up --build -d
```

The container listens on **127.0.0.1:8083** only. Do not publish `8083` to
`0.0.0.0` unless you intend the origin to be reachable without Cloudflare.

### 3. Cloudflare Tunnel (recommended)

Zero open inbound ports.

1. Cloudflare Zero Trust → Networks → Tunnels → Create.
2. Public hostname: `medcain.shishal.com` → service `http://127.0.0.1:8083`
   (or `http://site:80` if cloudflared is on the same Compose network).
3. Put the tunnel token in `.env` at the **repo root** (gitignored):

   ```
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...
   ```

4. Start the tunnel sidecar (same Compose file):

   ```bash
   docker compose --profile tunnel up -d
   ```

   The tunnel container reaches nginx as `http://site:80`. In the Cloudflare
   dashboard, set the public hostname `medcain.shishal.com` to that origin
   (not `127.0.0.1`) when cloudflared is on this Compose network.

If you already run `cloudflared` as a host service, skip the Compose profile
and point that tunnel at `http://127.0.0.1:8083`.

### 4. Check

- https://medcain.shishal.com/healthz → `ok`
- https://medcain.shishal.com/privacy/ loads without a login
- View source is HTML files, not a Flutter web build

## Payments

`/checkout/` is the live pay page. The rupee amount is
`paid_plan_catalog` in Postgres (seed: Pro ₹1,499 / 1 year on 1 device,
Elite ₹2,999 / 1 year on 2 devices; longer periods are that price × years,
plus free extra months). `app.js` and `paid_plans.js` are copies of `checkout/`.
`python3 scripts/validate_phase7_2_paid_plans.py` fails if they drift.

The container writes `config.js` on startup from `SUPABASE_URL` and
`SUPABASE_ANON_KEY` in the **repo-root** `.env` (the same public values as
the Flutter app). That file is used whether you run Compose from the repo
root or from `website/`. Do not put `RAZORPAY_KEY_SECRET`,
`RAZORPAY_WEBHOOK_SECRET`, or `SUPABASE_SERVICE_ROLE_KEY` in the image;
Compose blanks those on the site container even though they live in `.env`.

```bash
docker compose up --build -d
```

Then open https://medcain.shishal.com/checkout — you should see a sign-in
form. Razorpay API keys and the webhook are a separate step:
[`docs/06_PAYMENTS_PRODUCTION.md`](../docs/06_PAYMENTS_PRODUCTION.md).

Flutter store builds should set
`CHECKOUT_URL=https://medcain.shishal.com/checkout`.
