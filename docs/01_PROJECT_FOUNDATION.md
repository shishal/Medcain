# Project Foundation

Read `docs/00_PRODUCT.md` first. This file is locked engineering decisions — if
the AI (or you) later suggests deviating from one of these, treat it as a flag
to stop and think, not a default to accept.

**Product:** MBBS university-exam companion. Students pick their university;
v1 **content** is KUHS. The stack below was chosen for a
timer-driven MCQ player; that player is now **practice-only**. Do not
reintroduce a NEET-PG catalog as the home screen.

Read this before writing any code. These are locked decisions — if the AI (or you) later suggests deviating from one of these, treat it as a flag to stop and think, not a default to accept.

## What "server-side" means in this stack (you're not hosting anything)

Every "must be server-side" note elsewhere in these docs refers to one of two Supabase-managed mechanisms — neither requires you to provision, run, or maintain a server:

- **Postgres functions (RPC)** — SQL/plpgsql functions living inside your Supabase database, called from Flutter via `supabase.rpc('function_name', params)`. Use these for anything that's pure data logic within your own database: plan checks, scoring, percentile calculation, the practice session generator. This is the default choice.
- **Supabase Edge Functions** — small TypeScript/Deno functions Supabase runs on demand, for anything a database can't do natively (verifying the Razorpay webhook's signature, calling an external API). You write and deploy these via the Supabase CLI; Supabase's infrastructure runs them.

Both are fully managed — you write code, Supabase executes it, there's no machine for you to patch or scale. The property that makes either one "server-side" (as opposed to code shipped in the Flutter app) is simply that the end user's device can call it but can't read or modify it — which is what makes it trustworthy for enforcing plan limits or computing a score that can't be faked.

## Tech stack (locked)

| Layer | Choice | Why |
|---|---|---|
| Framework | Flutter (latest stable channel) | Single codebase, consistent 60fps UI across Android/iOS — matters for a timer-driven test app |
| Language | Dart | Comes with Flutter, no alternative |
| State management | **Riverpod** (`flutter_riverpod` + `riverpod_annotation` for codegen) | Best-documented option for someone new to Flutter; testable without a widget tree; huge amount of training data so AI models write idiomatic Riverpod reliably |
| Navigation | **go_router** | The de facto standard; declarative routes, deep-linking support if you ever need "open this test from a push notification" |
| Backend | **Supabase** (Postgres + Auth + Storage + Edge Functions) | See rationale in prior planning — unlimited API requests on free tier, relational schema fits a question bank naturally, Row-Level Security gives real server-side plan gating |
| Local persistence during a test | Plain JSON files via `path_provider` (no local database for Phase 1) | You're new to Flutter — skip `drift`/`Isar` for now. A downloaded test and in-progress answers are small enough to persist as JSON; add a real local DB later only if this becomes a bottleneck |
| Auth | Supabase Auth (email/password to start; add phone/OTP in Phase 2 if you want India-first login) | Simplest to implement correctly first |
| CI / builds | **Codemagic** (free tier: 500 build minutes/month, macOS build machines) | You don't own a Mac — this is how you build and sign the iOS binary without one. You still need a paid Apple Developer account ($99/yr); there's no way around that part |
| Screenshot/recording block | `no_screenshot` package (check pub.dev score before locking in — verify it's still actively maintained when you actually start Phase 7, package health can shift) | Cross-platform wrapper around Android's FLAG_SECURE and iOS's best-effort blur-on-background |
| Payments | Razorpay, but **outside the app** (web checkout page you build separately) | Keeps you off both app stores' 15–30% in-app purchase cut — see `03_BUILD_PLAN.md` Phase 6 for the exact mechanics and the compliance boundary you need to stay inside |
| Push notifications | Firebase Cloud Messaging (Phase 2, not Phase 1) | Free and unlimited regardless of using Supabase as your primary backend |

## Architecture

Feature-first folder structure (not layer-first) — easier for an AI agent to reason about one feature in isolation without accidentally editing unrelated code:

```
lib/
  main.dart
  app.dart                    # MaterialApp.router setup, theme, root providers
  core/
    theme/                    # ThemeData, color scheme, text styles, spacing constants
    router/                   # go_router configuration, route names
    supabase/                 # Supabase client singleton, initialization
    utils/                    # Pure helper functions (formatters, validators)
    widgets/                  # Shared dumb widgets used across features (buttons, cards)
  features/
    auth/
      data/                   # Repository: talks to Supabase Auth
      domain/                 # Models (User, Profile)
      presentation/           # Screens + Riverpod providers for this feature
    onboarding/
      data/
      domain/
      presentation/
    catalog/                  # Year → subject → topic → lesson browse
      data/
      domain/
      presentation/
    pyq/                      # Theory PYQ reader (sample answer, textbook page, links)
      data/
      domain/
      presentation/
    tests/                    # MCQ player (practice sessions). Not the home catalog.
      data/
      domain/
      presentation/
    results/
      data/
      domain/
      presentation/
    progress/
      data/
      domain/
      presentation/
    search/
      data/
      domain/
      presentation/
    bookmarks/
      ...
    profile/
      ...
  shared/
    models/                   # Models shared across features (Question, Subject, Topic)
```

Rule for the AI agent: **a feature's `presentation/` layer never calls Supabase directly** — it calls its feature's `data/` repository, which calls Supabase. This makes it possible to swap the backend later without touching every screen, and makes each layer independently testable.

## Coding conventions

- **State**: use Riverpod `AsyncNotifier`/`Notifier` (codegen, `@riverpod` annotation) for anything with async state (fetching tests, submitting an attempt). Use plain `Provider` only for derived/computed values.
- **Error handling**: every repository method that talks to Supabase returns a typed result (success/failure), never lets a raw `PostgrestException` bubble to the UI. Define a small `Result<T>` sealed class or use a package like `fpdart`'s `Either` if you want AI-generated code to follow a consistent pattern — pick one and put it in this file's next revision once decided, then never deviate.
- **No magic strings for Supabase table/column names.** Define them as constants in `core/supabase/tables.dart` (e.g. `class Tables { static const questions = 'questions'; }`). This alone prevents a whole category of silent typo-bugs that AI-generated code is prone to.
- **Every screen that reads user-plan-gated data must handle the "content not available on your plan" case explicitly** — not just a generic error state. This is a product requirement, not just a coding style point: users need to see "Upgrade to Pro to unlock this test," not a blank screen or a crash.
- **Widgets over 150 lines get split.** If the AI generates a 400-line `build()` method, ask it to extract sub-widgets before you accept the change — long build methods are where subtle layout bugs hide.

## Design direction (MEDCAIN — blue on black)

Concrete enough for an AI coding assistant to act on. Docci and the MEDCAIN name stay; do not
copy a competitor mascot or pixel-identical layouts.

- **Material 3.** Seed / primary is **brand blue** (`#008FD6`) for CTAs,
  high-yield numbers, and filled buttons. Cooler indigo (`#3D6FBF`) is
  section chrome / progress. **Gold** (`#F5C542`) is Pro chips only.
- **Dark-first black** canvas (`#000000` / `#0A0A0A`) with slightly lighter
  raised cards. Light mode is clean white/gray cards with the same blue CTAs.
- **Theme modes:** System (follow the phone) / Light / Dark. Persist the
  choice. **Light is the app default** until the student picks something else
  — this matches docs/00_PRODUCT.md, build-plan task 10.1 and the code. Splash
  + brand marks follow light/dark (paper + dark-ink mark vs black + white
  mark); native splash tracks OS appearance — see `flutter_native_splash.yaml`.
- **Type scale**: use Material 3's built-in `TextTheme` roles (`headlineSmall`,
  `titleMedium`, `bodyLarge`, etc.) rather than ad-hoc `TextStyle(fontSize: 16)`.
- **Urgent actions** (timer running low, submit test) use a deeper blue
  (`#0072BC`) — do not invent a second red.
- **Spacing**: 8px scale (`Spacing.xs = 4, .sm = 8, .md = 16, .lg = 24,
  .xl = 32`). No arbitrary `SizedBox(height: 13)`.
- **Tagline:** “Drug of Choice for Exam Pain” — splash, store, and marketing.

## Environment setup checklist (do this once, in order)

1. Install Flutter SDK (stable channel), run `flutter doctor` until it's clean for Android at minimum.
2. Create a Supabase project (free tier) — save the project URL and anon key.
3. Create a Codemagic account, connect it to your GitHub repo (push your Flutter project to GitHub first — Codemagic builds from a repo, not a local zip).
4. Enroll in the Apple Developer Program ($99/yr) — do this early, approval can take a few days.
5. Register a Google Play Console account ($25 one-time).
6. Set up a `.env`-style secrets approach: Supabase anon key can be client-side (it's public by design, RLS is what actually protects data), but the Supabase **service_role** key (used only by the Google Sheet sync script, never the app) must never appear in the Flutter codebase or be committed to git.

## Open question for you to resolve before Phase 3

Pick one of `fpdart`'s `Either` or a hand-rolled `Result<T>` sealed class for error handling (mentioned above) — either is fine, but decide before you have 10 screens written inconsistently. If you're not sure, default to the hand-rolled version — one less package to learn while you're still new to Dart.
