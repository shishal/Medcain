# Store listing — Phase 9.2

Paste these into Play Console and App Store Connect. Screenshot **sizes and
shot list** are below; capture the images from a real build before Phase 9.4
(do not upload the feature graphic as a screenshot — Play treats those as
separate slots).

**Brand color:** `#008FD6` (same as `AppTheme.seedColor`).
**Launcher / Play icon source:** `assets/branding/app_icon.png`.
**Play assets:** `store/play/icon-512.png`, `store/play/feature-graphic-1024x500.png`.
**Tagline:** Drug of Choice for Exam Pain.

Payments happen on the website, not in the app. Do not mention in-app
purchase, a price next to a Buy button, or “subscribe in the app.” Phase 9.4
notes that first-time EdTech reviews often ask for a **privacy policy** and a
visible way to **manage / cancel** a plan — publish those pages before you
submit, even though billing is external.

Public site (host on your machine via `website/` + Cloudflare):
https://medcain.shishal.com — privacy, terms, and account/refund pages live
there. Support mail goes to `medcain@shishal.com`.

---

## Google Play

### App name
MEDCAIN

### Short description (80 characters max)

```
MBBS PYQs & practice — Drug of Choice for Exam Pain.
```

(58 characters including spaces.)

### Full description

```
MEDCAIN is an MBBS university-exam companion: previous-year theory questions with direct answers, explanations, and textbook page refs — plus MCQ practice.

WHAT YOU CAN DO
• Browse university PYQs by subject and exam year, the way your paper is set.
• Open a question for a direct answer (DA) and explanation (EX) with textbook page refs.
• Practice MCQs in tutor mode (see the answer now) or exam mode (review at the end).
• Bookmark questions from review and come back to them later.

PLANS
Download is free. New accounts get Pro for 4 days. Free keeps a teaser slice of the bank. Pro and Elite unlock more PYQs, practice, and full explanations.

Plans are purchased on our website in the device browser — not inside this app. After you pay, return to MEDCAIN and refresh your profile to see the new plan.

PRIVACY AND ACCOUNT
You sign in with email. We do not show ads. See the privacy policy for what we store and why.

Privacy policy: https://medcain.shishal.com/privacy
Manage or cancel a plan: https://medcain.shishal.com/account
```

### Category
Education

### Tags (Play, optional)
Education, Medical, Exam prep, MBBS, PYQ

### Contact
Support email: medcain@shishal.com
Website: https://medcain.shishal.com

### Graphics to upload
| Slot | File | Size |
|---|---|---|
| App icon | `store/play/icon-512.png` | 512 × 512, 32-bit PNG |
| Feature graphic | `store/play/feature-graphic-1024x500.png` | 1024 × 500 |
| Phone screenshots | Capture per shot list below | At least 2; 16:9 or 9:16; 320–3840 px per side |

Play also accepts a 7-inch / 10-inch tablet screenshot if you ever ship a
tablet layout; phone shots are enough for a phone-first app.

---

## App Store

### Name
MEDCAIN

### Subtitle (30 characters max)

```
MBBS PYQs & Exam Practice
```

(25 characters including spaces.)

### Promotional text (170 characters max, optional, editable without a new review)

```
Drug of Choice for Exam Pain. University PYQs with answers, explanations, and textbook pages. Free to download — unlock Pro on our website.
```

### Description

```
MEDCAIN is an MBBS university-exam companion: previous-year theory questions with direct answers, explanations, and textbook page refs — plus MCQ practice.

Browse real university papers by year. Open a question for a direct answer and explanation, then jump to the textbook page. Practice MCQs in tutor or exam mode. Bookmark questions from review.

A Free plan is included. New accounts get Pro for 4 days. Pro and Elite unlock more of the bank and full explanations. Plans are bought on our website in Safari — this app does not charge inside the binary.

Privacy policy: https://medcain.shishal.com/privacy
Manage or cancel a plan: https://medcain.shishal.com/account
```

### Keywords (100 characters max, comma-separated, no spaces after commas preferred)

```
MBBS,PYQ,medical exam,university exam,MCQ,anatomy,KUHS
```

Do **not** repeat the app name here. Trim or swap words so the whole string stays ≤ 100 characters.

Current string is 55 characters.

### Category
Primary: Education
Secondary: Medical (if available in your developer account)

### Age rating
This is an education QBank with no user-generated public chat and no
controversial medical imagery beyond standard exam stems. Complete Apple’s
questionnaire honestly; typical result is 4+.

### What’s New (1.0.0)

```
First release: catalog tests, practice builder, results, bookmarks, and plan comparison.
```

### App Review notes (paste into App Review Information)

```
This app does not sell subscriptions or digital goods inside the binary. Tapping Upgrade opens our website checkout in the system browser (Razorpay). Sign in with the review account below to browse Free-tier tests without paying.

Demo account: (create a Free-plan reviewer account and paste email/password here)
Privacy policy: https://medcain.shishal.com/privacy
```

---

## Screenshot shot list (both stores)

Capture on a **physical device or a store-sized emulator**, light theme,
signed in as a Free user who has at least one completed attempt (so results
and review are not empty). Save PNG files under `store/screenshots/` using
the names below.

**Phone sizes to capture**
- Play: 1080 × 1920 (9:16)
- App Store 6.7": 1290 × 2796 (e.g. iPhone 15 Pro Max)
- App Store 6.5": 1284 × 2778 if Apple still requires that slot

Do not add device bezels unless you are using Apple’s official screenshot
templates. Prefer raw full-screen captures of the Flutter UI.

| File | Screen | Caption overlay (optional, keep short) |
|---|---|---|
| `01-tests.png` | Test list (Mini / Subject / Mock / Grand) | “Mini to Grand — the real exam shape” |
| `02-instructions.png` | Test instructions (sectional warning visible) | “Rules before the clock starts” |
| `03-player.png` | Test player, a question with palette | “Palette, mark for review, live timer” |
| `04-practice.png` | Practice builder | “Tutor or exam mode, your filters” |
| `05-results.png` | Results summary with subject breakdown | “Score, accuracy, percentile” |
| `06-review.png` | Solution review (answer + explanation if plan allows) | “Review every question” |
| `07-plans.png` | Plans screen (no price, no Buy — link-out CTA only) | “Compare Free, Pro, and Elite” |

Play requires at least two phone screenshots; upload 01–05 as the core set.
App Store looks more complete with 5–8.

**How to capture on Android (emulator)**

```
flutter install
# Then in another terminal, after you have the screen on-device:
adb exec-out screencap -p > store/screenshots/01-tests.png
```

The debug banner is already off (`debugShowCheckedModeBanner: false`). Still
capture from a **profile or release** build so the yellow slow-mode banner
is absent.

---

## Regenerating brand art

If you change the seed color or the mark:

```
scripts/.venv/bin/python scripts/generate_brand_assets.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Then visually check: home-screen icon is the MEDCAIN **M** (white + blue ECG)
on black, not the Flutter logo; cold start follows OS light/dark (paper +
dark-ink mark vs black + white mark).
