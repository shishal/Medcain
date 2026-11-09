# Phase 9.4 — Google Play (Android first)

This is the operator guide for putting MEDCAIN on Play. **iOS is later;
do not start App Store Connect until Android internal testers can install.**

**Current goal:** Internal testers only. The app must not appear in public
Play search, and strangers must not be able to install it.

Listing copy and screenshot sizes stay in [`07_STORE_LISTING.md`](07_STORE_LISTING.md).
Signed-build setup stays in [`08_CODEMAGIC.md`](08_CODEMAGIC.md).

---

## What “internal only” means on Play

Use the **Internal testing** track. Do **not** use Production, Open testing,
or Pre-registration.

| Track | Who can install | Public listing? | Use now? |
|---|---|---|---|
| **Internal testing** | Up to 100 people you invite by Google account email | No | **Yes — this is the goal** |
| Closed testing | People on your tester list (larger) | Listing is more visible; full app setup required | Later, if you want a bigger private group |
| Open testing | Anyone with the link (and it can be found) | Effectively public beta | No |
| Production | Anyone in selected countries | Yes, searchable | No, until you decide to launch |

Internal testing is invite-only. Testers need a Google account (Gmail is
fine). They install from the Play Store after opening an **opt-in link**
you send them.

Organization Play accounts are **not** subject to the “12 closed testers
for 14 days” rule that applies to some personal accounts. You can stay on
Internal testing as long as you want.

---

## Package identity (do not change after first upload)

| Field | Value |
|---|---|
| Application ID | `com.shishal.medico` |
| App name | MEDCAIN |
| Version (first upload) | `1.0.0` (`pubspec.yaml` `version: 1.0.0+1`) |
| Play icon | `store/play/icon-512.png` |
| Feature graphic | `store/play/feature-graphic-1024x500.png` |

The application ID is permanent on that Play listing. If you upload a
bundle with a different ID, Play treats it as a different app.

---

## Do these in order

Stop at the first blocker and fix it before continuing. Play Console is in
your browser; the repo cannot log you in.

### 1. Confirm you have a signed App Bundle

Play rejects debug-signed binaries. You need a **release `.aab`** signed
with the **upload keystore** from Phase 9.3.

**Preferred:** Codemagic → this app → **Start new build** → **Android signed
release**. Download `app-release.aab` from the finished build.

**If Codemagic is not ready yet**, finish [`08_CODEMAGIC.md`](08_CODEMAGIC.md)
first (keystore named `medico`, env group `medico_app`). Then come back.

Install the matching **APK** on a real phone and sign in before you upload
the AAB. Do not send testers a build you have not opened yourself.

### 2. Create the app in Play Console

1. Open [Google Play Console](https://play.google.com/console) with the
   **organization** developer account.
2. **All apps → Create app**.
3. Fill:
   - App name: `MEDCAIN`
   - Default language: English (United States) or English (India)
   - App or game: **App**
   - Free or paid: **Free**
4. Accept the declarations (Play policies, US export law, etc.).
5. Create.

You now have a dashboard of setup tasks. For Internal testing you do **not**
need to finish every task. Skip Production, ads, and the full store listing
until you want a public launch.

### 3. Countries (optional but recommended)

**Test and release → Countries / regions** (or **Production → Countries**,
depending on Console UI). Include **India**. Internal testers outside
selected countries sometimes cannot install.

### 4. Create the Internal testing release

1. **Test and release → Testing → Internal testing**.
2. If asked to create a release, choose **Create new release**.
3. First upload: Play enrolls you in **Play App Signing**. Keep the default
   (Google holds the *app signing* key; you keep the *upload* keystore).
   Back up `upload-keystore.jks` and both passwords somewhere that is not
   GitHub. Losing that file means you cannot update this listing.
4. Upload the `.aab`.
5. Release name: `1.0.0 (internal)`.
6. Release notes (English):

   ```
   First internal build: catalog tests, practice, results, and bookmarks.
   ```

7. **Next → Save → Review → Start rollout to Internal testing**.

The first release can take from a few minutes to a few hours before the
opt-in link works. Later updates are usually faster.

### 5. Add only your people

1. On the Internal testing page, open **Testers**.
2. Create an email list (e.g. `medico-internal`).
3. Add each tester’s **Google account email** (the account on their Android
   phone). Other email providers work only if that address is a Google
   account.
4. Copy the **opt-in URL** (looks like
   `https://play.google.com/apps/internaltest/...`).
5. Send testers that URL. They must:
   1. Open it while signed into the Google account you added.
   2. Tap **Accept** / become a tester.
   3. Tap **Download it on Google Play**.
   4. Install **MEDCAIN** from the Play Store listing that opens (it is
      not searchable; the link is the only door).

Cap is 100 testers. Remove people who should no longer have access.

### 6. Confirm it is not public

- Searching “MEDCAIN” on Play on a phone that is **not** on the tester list
  must not show this app.
- Dashboard **Production** must stay empty / not rolled out.
- Do not turn on Open testing.

---

## What you can skip for internal-only

These are required before **closed testing or production**. Leave them until
you decide to launch publicly:

- Privacy policy URL (you have a domain; no page is needed yet)
- Data safety form (exempt while the app is **only** on Internal testing)
- Content rating questionnaire
- Target audience / ads / news declarations (finish them before closed/prod)
- Phone screenshots and the full store listing text
- The 12-tester closed-test rule (organization account; not this path)

When you *do* go public, paste listing copy from `07_STORE_LISTING.md`
(privacy / account URLs already point at https://medcain.shishal.com), then
complete Data safety using the draft at the bottom of this file. Deploy
steps for the site are in `website/README.md`.

---

## Play Console answers that match this app

Use these if a form still appears (some accounts ask during app create).

| Question | Answer |
|---|---|
| App contains ads? | **No** |
| In-app purchases / Play Billing? | **No** — checkout is an external website, and the store binary currently has the web CTA off (`CheckoutEnv.webCheckoutEnabled`) |
| News app? | **No** |
| Government / political? | **No** |
| COVID / health claims as a medical device? | **No** — this is exam prep, not a clinical app |
| Target age | **18 and older** (NEET-PG) |
| Appeal to children? | **No** |
| Sensitive permissions (SMS, contacts, location)? | **No** — only `INTERNET` |

---

## Common failures

| What you see | What to do |
|---|---|
| “You need to use a different package name” | `com.shishal.medico` is already used on this or another Play account. |
| Upload rejected: not signed / wrong key | Use the Codemagic `medico` keystore AAB, not a local debug build. |
| Testers cannot find the app | They must open the **opt-in link** first, while using the invited Google account. Search will not work. |
| “Item not found” / app unavailable in country | Add India (and the tester’s country) under countries. |
| Opt-in link does nothing for hours | First internal release can lag. Wait, or check the release is **Rolled out**, not Draft. |
| Version code already used | Bump the `+N` in `pubspec.yaml` (`1.0.0+2`) and rebuild. Play never accepts a reused `versionCode`. |

---

## Data safety draft (for later — not now)

Complete this form only when you leave Internal testing. Answers match the
current Flutter app + Supabase (email auth, profile, attempts, bookmarks,
screenshot-event log). Payments are **not** collected inside the app.

**Privacy policy:** required on that form. Host it on your domain first.

**Does your app collect user data?** Yes.

| Data type | Collected? | Shared with third parties? | Required / optional | Purpose |
|---|---|---|---|---|
| Email | Yes (Supabase Auth) | No (your backend only) | Required to sign in | App functionality, account |
| Name | Yes (`profiles.full_name`) | No | Optional | App functionality (watermark) |
| Phone | Yes (`profiles.phone`) | No | Optional | App functionality (watermark) |
| App activity (tests, answers, scores, bookmarks) | Yes | No | Required for the product | App functionality |
| Other user-generated content (practice filters, etc.) | Yes | No | App functionality | App functionality |
| Crash / diagnostics | Only if you later add Crashlytics — **No** today | — | — | — |
| Location, photos, contacts, financial info in-app | **No** | — | — | — |

- Encrypted in transit: **Yes** (HTTPS to Supabase).
- Users can request deletion: plan to offer account deletion before a public
  listing (Play User Data policy). Not required for internal testers.
- Data is not sold. No ads. Not used for “personalization” / advertising.

---

## When Phase 9.4 Android is “done” (this pass)

- [ ] App record exists in Play Console (`com.shishal.medico`)
- [ ] A signed `.aab` is on **Internal testing** (rolled out, not draft)
- [ ] Your Google account is a tester and you installed from the opt-in link
- [ ] A second internal user can do the same
- [ ] Production and Open testing are unused
- [ ] Searching Play on a non-tester phone does not show MEDCAIN
