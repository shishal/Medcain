# Announcements — publish ops

Students see a published row in the in-app inbox the next time they open Home
or pull to refresh. The first time that row becomes active, Android phones
that allowed notifications also get **one** lock-screen alert with the same
title and body. Saving the row again while it stays published updates the
inbox and does not alert again.

Who receives it depends on `announcements.audience`:

- `all` (the Announcements page, the phone admin, and the Table Editor): every
  signed-in student sees the inbox row. The alert goes to the FCM topic
  `broadcast`.
- `selected` (website **Users**): only the accounts in
  `announcement_recipients` see the inbox row. The alert goes to each of
  those accounts' rows in `push_tokens`, not to the topic.

iOS is not wired up yet. A phone on an older build, or one that denied the
permission, still gets the inbox row only. A selected alert also needs a
build that registers an FCM token. Until that build is installed, those
phones still get the inbox row and stay quiet.

## Tables

| Table | Who writes | Who reads |
|---|---|---|
| `announcements` | admin app (`/admin` → Notifications), website admin, or Table Editor / `service_role` | signed-in students (active, not expired, and either `audience = all` or a recipient row for them) |
| `announcement_recipients` | `admin_notify_users` | that user only (so the inbox policy can see their own rows) |
| `announcement_reads` | the app (per user) | that user only |
| `push_tokens` | the app, while signed in (`register_push_token` / `unregister_push_token`) | `service_role` only |

`announcements.push_sent_at` is set when the alert is claimed. For a
broadcast, that is when Firebase accepts the topic message. For a selected
send, it stays set when at least one phone was alerted, or when nobody has a
token yet (the inbox row is the delivery). It is cleared when no phone was
alerted and at least one send failed, so a later publish can retry. Tokens
Firebase reports as unregistered are deleted either way. Null means it can
still be sent. Students do not need this column.

## One-time: Firebase and the sender

Do this before expecting a lock-screen alert. Until it is done, Publish still
fills the inbox and the phone stays quiet.

1. In [Firebase console](https://console.firebase.google.com), create a project
   and add an Android app with package name `com.shishal.medico`.
2. Download `google-services.json`.
   - Local release builds: put it at `android/app/google-services.json`
     (gitignored). A debug run without the file still opens the app.
   - Codemagic: paste the whole file into the `medico_app` variable
     `GOOGLE_SERVICES_JSON`. See `docs/08_CODEMAGIC.md`.
3. Firebase → Project settings → Service accounts → **Generate new private key**.
   This JSON can send messages. Do not commit it and do not put it in the app.
4. Supabase → Edge Functions → Secrets:
   - `FCM_SERVICE_ACCOUNT_JSON` = that private-key file
   - `PUSH_WEBHOOK_SECRET` = a long random string you invent
5. Deploy the function (this keeps `verify_jwt` off; the secret above is the check):

   ```bash
   npx supabase functions deploy send-announcement-push
   ```

6. Apply the migration (`push_sent_at` and the queue trigger):

   ```bash
   npx supabase db push
   ```

7. In the Supabase SQL editor, store the function URL and the same secret.
   Replace the project ref. Run each statement once; a second run with the
   same name fails, which is fine if the value is already correct.

   ```sql
   select vault.create_secret(
     'https://<project-ref>.supabase.co/functions/v1/send-announcement-push',
     'push_function_url'
   );
   select vault.create_secret(
     '<same value as PUSH_WEBHOOK_SECRET>',
     'push_function_secret'
   );
   ```

A message for everyone is an FCM message to the topic `broadcast`. The app
subscribes after sign-in and unsubscribes on sign-out. A message for selected
people is one FCM message per row in `push_tokens`. The app saves that token
while the account is signed in and deletes it before sign-out. Apply
`20261122140000_targeted_announcements.sql` with the same `db push` as above.

## Publish a message

From the app (admin account): **Admin → Notifications → New**. Turn on
**Publish** and save.

Or the website admin (**Announcements**), or a row in **Table Editor → announcements**:

1. Fill:
   - `title` (short)
   - `body` (full text)
   - `category`: `general` | `version` | `offer` | `payment`
   - `deep_link` (optional app path, e.g. `/upgrade`)
   - `is_active`: `true` to show, `false` to draft
   - `expires_at` (optional; leave empty for no expiry)
2. Save.

What happens:

- **Draft** (`is_active = false`): hidden, no alert.
- **First publish** (new row with Publish on, or a draft switched on): inbox
  row goes live, and one phone alert is queued. A tap opens `deep_link` when
  it is an allowed in-app path, otherwise the Notifications screen.
- **Save again while published:** inbox updates, no second alert.
- **Publish off, then on again:** sends only if `push_sent_at` is still null
  (the previous attempt never succeeded). A successful alert is not repeated.

## Notify selected people

On the website admin, open **Users**. This does not publish to everyone.

1. Filter by name or phone, effective plan, and/or “expires within” a number
   of days (1–365). Free includes expired and suspended accounts. Expires
   within finds a paid plan that is still active. Blocked accounts are hidden
   unless **Include blocked accounts** is checked.
2. Tick the people you want (the ticks stay as you change pages), or skip the
   ticks and send to everyone who matches. A selection can include 500
   accounts. Everyone matching can include 2,000. Narrow the filters past that.
3. Fill title, body, category, and an optional app path, then send.

What happens:

- One `audience = selected` row is published, with one recipient per account.
- Those accounts see it in the inbox. Other students do not.
- Each of their registered Android phones gets one alert. A phone with no
  token, a denied permission, iOS, or an older build does not.
- The Announcements page lists it as “N people”. Unpublish hides it from
  those inboxes. That page cannot turn it into a broadcast.

## Hide or expire

- Set `is_active = false`, **or**
- Set `expires_at` to a past timestamp.

Either way RLS hides the row from the app. Hiding does not send an alert.

## Check it worked

1. Install a build that includes this change and `google-services.json`.
2. Sign in on a phone with Play services. Allow notifications when asked.
3. From an admin account, publish a new message.
4. The other phone shows one alert. Home bell and the Notifications screen
   show the same title. Tap opens the app.
5. Save that published row again: no second alert.
6. Deny the permission prompt on a phone: no alert, and the inbox still shows
   the row after Home refresh.
7. From website **Users**, filter to one test account and send. That phone's
   inbox shows it. A different signed-in account does not. The lock-screen
   alert arrives only after that phone has opened a build that registers a
   token.
