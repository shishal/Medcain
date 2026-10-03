# MEDCAIN public site (medico.shishal.com)

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
| Website | https://medico.shishal.com/ |
| Privacy policy | https://medico.shishal.com/privacy/ |
| Manage / cancel a plan | https://medico.shishal.com/account/ |
| Terms (optional extra) | https://medico.shishal.com/terms/ |
| Support email | support@medico.shishal.com |

`/refunds/` redirects to `/account/`.

Create the mailbox `support@medico.shishal.com` (or a forward to your real
inbox) before you submit a public listing.

## Run with Docker Compose

From the **repo root** (same `docker-compose.yml` the host machine should use):

```bash
docker compose up --build -d
```

Or from this directory:

```bash
docker compose up --build -d
```

Either way the site is at http://127.0.0.1:8080 (`medico-site` container).
Change the host port with `MEDICO_SITE_PORT=8081` if 8080 is taken.

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

The container listens on **127.0.0.1:8080** only. Do not publish `8080` to
`0.0.0.0` unless you intend the origin to be reachable without Cloudflare.

### 3. Cloudflare Tunnel (recommended)

Zero open inbound ports.

1. Cloudflare Zero Trust → Networks → Tunnels → Create.
2. Public hostname: `medico.shishal.com` → service `http://127.0.0.1:8080`
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
   dashboard, set the public hostname `medico.shishal.com` to that origin
   (not `127.0.0.1`) when cloudflared is on this Compose network.

If you already run `cloudflared` as a host service, skip the Compose profile
and point that tunnel at `http://127.0.0.1:8080`.

### 4. Check

- https://medico.shishal.com/healthz → `ok`
- https://medico.shishal.com/privacy/ loads without a login
- View source is HTML files, not a Flutter web build

## Payments

`/checkout/` is the live pay page (Pro ₹1,499 / 6 months, Elite ₹2,999 / 12
months). `app.js` and `paid_plans.js` are copies of `checkout/`.
`python3 scripts/validate_phase7_2_paid_plans.py` fails if they drift.

The container writes `config.js` on startup from `SUPABASE_URL` and
`SUPABASE_ANON_KEY` in the `.env` next to the compose file you run. Those
are the same public values as the Flutter app. Do not put
`RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, or
`SUPABASE_SERVICE_ROLE_KEY` here.

```bash
docker compose up --build -d
```

Then open https://medico.shishal.com/checkout — you should see a sign-in
form. Razorpay API keys and the webhook are a separate step:
[`docs/06_PAYMENTS_PRODUCTION.md`](../docs/06_PAYMENTS_PRODUCTION.md).

Flutter store builds should set
`CHECKOUT_URL=https://medico.shishal.com/checkout`.
