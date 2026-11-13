# Codemagic builds — Phase 9.3

One-click signed binaries. Workflows live in `codemagic.yaml` at the repo
root. They do **not** start on every git push (that would burn the 500 free
minutes fast). You start them from the Codemagic UI.

**Package ID (both platforms):** `com.shishal.medico`

After a successful build, install that binary on a real phone **before**
Phase 9.4 store submission. Do not submit an untested artifact.

---

## What each workflow produces

| Workflow in the UI | Artifact | How you install it |
|---|---|---|
| **Android signed release** | `.apk` (sideload) and `.aab` (Play) | APK: copy to a phone and open it. AAB: upload in Play Console (Phase 9.4). |
| **iOS signed release** | `.ipa` signed for App Store / TestFlight | Install via TestFlight on a real iPhone. You cannot sideload an App Store IPA like an APK. |

Download artifacts from the finished build page in Codemagic.

---

## One-time: GitHub app in Codemagic

If Phase 0.1 already connected the repo, skip this.

1. [codemagic.io](https://codemagic.io) → **Add application** → GitHub → this repo.
2. Project type: **Flutter App**.
3. Open the app → **Check for configuration file** on the branch that has `codemagic.yaml`.

---

## One-time: app secrets group `medico_app`

The Flutter app loads `assets/env` as an asset. That file is gitignored, so CI
must write it. It is not named `.env`: Android's packager drops dotfile assets,
and the release build then stays on the splash. In Codemagic: **Application
settings → Environment variables**.

Create a group named exactly `medico_app` (must match `codemagic.yaml`) and add:

| Variable | Secret? | Value |
|---|---|---|
| `SUPABASE_URL` | yes | same as local `.env` |
| `SUPABASE_ANON_KEY` | yes | same as local `.env` (public by design; RLS is the real gate) |
| `CHECKOUT_URL` | yes | **production** HTTPS checkout, not `127.0.0.1` |

Do **not** put `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`, or Razorpay secrets
in this group. They would be baked into every install.

---

## One-time: Android upload keystore

Google Play will only accept later updates signed with the **same** key. Keep a
backup of the `.jks` and passwords somewhere that is not GitHub.

Generate once on your machine:

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Store `upload-keystore.jks` at `android/upload-keystore.jks` (gitignored) or
anywhere outside the repo. Keep a backup of the file and both passwords —
Play will reject later updates signed with a different key.

1. Codemagic team → **codemagic.yaml settings → Code signing identities → Android keystores**.
2. Upload the `.jks`. Enter keystore password, alias `upload`, key password.
3. **Reference name** must be exactly `medico`.

Optional local signed builds: copy `android/key.properties.example` to
`android/key.properties` and set `storeFile` to the keystore path. Codemagic
ignores that file and uses the uploaded keystore instead.

---

## One-time: iOS signing (needs a paid Apple Developer account)

1. **App ID** — [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list):
   bundle ID `com.shishal.medico`.
2. **App Store Connect app record** — create the app with that bundle ID
   (first IPA upload needs this record to exist).
3. **App Store Connect API key** — App Store Connect → Users and Access →
   Integrations → App Store Connect API. Role **App Manager**. Download the
   `.p8` (once). Note **Issuer ID** and **Key ID**.
4. Codemagic team → **Team integrations → Developer Portal → Manage keys**:
   upload the `.p8`. **Key name** must be exactly `medico`.
5. **Distribution certificate + App Store provisioning profile** for
   `com.shishal.medico`. Either:
   - Codemagic **Code signing identities** → generate/fetch after the API key
     is saved, or
   - Create them in the Apple Developer portal and upload the `.p12` +
     `.mobileprovision`.

`codemagic.yaml` asks for `distribution_type: app_store` and bundle
`com.shishal.medico`. Codemagic then picks matching uploaded files.

TestFlight encryption questions: `Info.plist` already sets
`ITSAppUsesNonExemptEncryption` to false (HTTPS only). If Apple still asks,
answer that you only use standard encryption.

---

## Run a build (the “one click”)

1. Push the branch that contains `codemagic.yaml`.
2. Codemagic → this app → **Start new build**.
3. Pick **Android signed release** or **iOS signed release**.
4. Wait. Download the artifact from the build page.

Linux Android builds are cheaper than macOS. iOS **must** use a Mac instance.

---

## Validate on a real device (required before 9.4)

**Android**

1. Download `app-release.apk`.
2. On the phone: allow install from that source, open the APK, install.
3. Sign in, start a short test, confirm splash/icon match Phase 9.2.

**iOS**

The iOS workflow uploads the IPA to App Store Connect (not App Store review).

1. In App Store Connect, add your Apple ID as an **internal** TestFlight tester.
2. Wait until the build shows as processed (email from Apple, usually minutes).
3. Install **TestFlight** on a real iPhone, open MEDCAIN, confirm splash/icon
   and that you can sign in.

Leave `submit_to_app_store` off until Phase 9.4. To also send the build to a
TestFlight group automatically, set `submit_to_testflight: true` and list
`beta_groups` in `codemagic.yaml`.

---

## Common failures

| Symptom | Likely cause |
|---|---|
| `CM_KEYSTORE_PATH is not set` | Keystore reference is not named `medico`, or it was not uploaded. |
| Splash never leaves, log says `FileNotFoundError` | `assets/env` was not written, or the group variables are empty. A bundled file named `.env` is dropped from the APK. |
| iOS signing / provisioning | Bundle ID not `com.shishal.medico`, or no App Store profile/certificate matching that ID. |
| `app_store_connect: medico` integration error | API key in Codemagic is not named `medico`. |
| Release APK cannot load data | Checkout/Supabase URL in the group is still localhost; or (fixed in this phase) missing `INTERNET` on the main manifest. |
| Play Console rejects the AAB | First upload must use this upload keystore forever after. If you regenerate a keystore, you cannot update the same Play listing. |
