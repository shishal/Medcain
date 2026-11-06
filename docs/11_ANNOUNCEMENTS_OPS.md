# Announcements — publish ops

In-app inbox only (no Firebase / OS push). Students see new rows the next
time they open Home or pull-to-refresh.

## Tables

| Table | Who writes | Who reads |
|---|---|---|
| `announcements` | admin app (`/admin` → Notifications) or Table Editor / `service_role` | signed-in students (active + not expired) |
| `announcement_reads` | the app (per user) | that user only |

## Publish a message

From the app (admin account): **Admin → Notifications → New**. Turn on **Publish** and save. Students see it on the next Home load. There is no phone push.

Or insert a row in **Table Editor → announcements**:

1. Fill:
   - `title` (short)
   - `body` (full text)
   - `category`: `general` | `version` | `offer` | `payment`
   - `deep_link` (optional app path, e.g. `/upgrade`)
   - `is_active`: `true` to show, `false` to draft
   - `expires_at` (optional; leave empty for no expiry)
2. Save. Signed-in users pick it up on next Home load as **unread**.

## Draft → publish

1. Insert with `is_active = false`.
2. When ready, edit the row and set `is_active = true`.

## Hide or expire

- Set `is_active = false`, **or**
- Set `expires_at` to a past timestamp.

Either way RLS hides the row from the app.

## Check it worked

1. Sign in on a device / emulator.
2. Pull to refresh on Home (or reopen the app).
3. Bell badge and the Home strip should show the unread item; Notifications
   screen lists it. Opening or dismissing marks it read.
