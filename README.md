# Forma

A standalone mobile app for tracking strength training — workouts, sets,
exercises, reusable templates, body measurements and progress charts. All data
is stored locally on the device; there is no account, login, or backend.

Built with Flutter · Riverpod (iOS & Android). The app lives in
[`client/`](client/).

## Features

- **Workout logging**: exercises, sets, weight and reps, with a live session
  timer, 1–10 effort rating and notes
- **Exercise library**: 40 seeded exercises across 8 muscle groups and 6
  equipment types, plus your own; search and filter by muscle group
- **Templates**: reusable workouts organized into folders, with default sets,
  weight and reps, applied to a new session in one tap
- **Muscle recovery**: per-group recovery and fatigue based on your training
  history, with a recommendation for each group
- **Progress**: volume and workout frequency per week, muscle-group balance,
  personal records, and estimated 1RM per exercise over time
- **Measurements**: body weight, body fat and circumference metrics charted
  over time
- **Backup**: export everything as JSON to the share sheet, and restore from a
  backup file

Units are US throughout (pounds).

## Quick start

```bash
cd client
flutter pub get
flutter run
```

## Architecture

The app has no network layer. Everything it knows lives in a single JSON file
in the device's documents directory, managed by
[`lib/api_client.dart`](client/lib/api_client.dart) — which keeps the
`ApiClient` name from when it wrapped a FastAPI backend, so call sites read the
same.

The store is deliberately careful with user data:

- **Serialized writes.** A queue orders overlapping read-modify-write cycles so
  concurrent mutations can't interleave and lose records.
- **Atomic persistence.** Writes flush to a temp file and rename over the live
  one, so a crash mid-write can't truncate it.
- **Quarantine over data loss.** An unreadable file — or one written by a newer
  schema version — is renamed aside for recovery rather than overwritten.
- **Versioned schema.** `schema_version` is stored with the data so future
  layout changes can migrate old files.

State is exposed through Riverpod providers in
[`lib/providers.dart`](client/lib/providers.dart). Since the store is a file
rather than a stream, a single revision counter is bumped after each mutation
and every derived provider watches it; screens never have to know which
providers their change invalidates.

Derived values — stats, muscle recovery, per-exercise progression, personal
records — are computed from the stored records on read and never persisted, so
they can't drift out of sync with the underlying history.

The UI uses `liquid_glass_widgets` for real GPU shader refraction on the app
bar, tab bar and cards, over Forma's own dark palette in
[`lib/theme/`](client/lib/theme/).

## Relationship to the original Forma

This project was derived from a client/server version of Forma: a Flutter
client against a FastAPI backend on Azure, with JWT auth, refresh tokens, guest
mode, and a `FeatureRegistry` gating analytics, templates and measurements
behind an account.

The revamp removed the server entirely. Along the way:

- **Auth, guest mode, and the premium tier system are gone.** With no backend
  there is no account to gate against, so every feature ships unlocked.
- **The caching layers are gone.** `persistent_cache_service`,
  `cached_api_service` and `token_storage` existed to hide network latency;
  a local file has none.
- **`TemplateFile` became `TemplateFolder`.** The server model carried
  `file_path`, `file_size` and `file_type`, but nothing was ever uploaded —
  the path was synthesized from the name and the other two were always null.
  It was always a folder, so it is named as one here.
- **Analytics and measurements were built for real.** Both were placeholder
  screens in the original ("Your workout analytics will appear here"); they are
  now backed by actual computation over the local history.
- **Ids are `int` throughout.** The original mixed server UUID strings with
  ints, which only worked because the two never met in a comparison.

## Status

`flutter analyze` is clean and the store's 25 tests pass:

```bash
cd client
flutter analyze
flutter test
```

Verified running on the iOS simulator.

## Not yet included

- Push notifications for recovery reminders (status is computed/shown in-app)
- Rest timers between sets
- Cross-device sync — by design; move data with an export/import
