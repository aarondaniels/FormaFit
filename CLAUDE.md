# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All work happens in `client/` — the repo root holds only the README and this file.

```bash
cd client
flutter pub get
flutter analyze                  # must be clean; it is today
flutter test                     # 46 tests, all in test/api_client_test.dart
flutter run                      # iOS simulator is the verified target
```

Run one test or one group by name:

```bash
flutter test test/api_client_test.dart --plain-name 'concurrent writes do not lose records'
flutter test test/api_client_test.dart --plain-name 'CSV'
```

Toolchain: Flutter 3.41.7 stable, Dart SDK `^3.11.5`. Lints are stock
`flutter_lints` with no project overrides.

## Architecture

### There is no backend

`ApiClient` ([lib/api_client.dart](client/lib/api_client.dart)) keeps its name
from a former FastAPI server, but every method is a local read-modify-write
against a single JSON file (`forma_data.json`) in the documents directory. There
is no network layer anywhere in the app. Don't add HTTP calls, auth, or caching
layers on the assumption that a server exists — cross-device sync is
deliberately out of scope, and export/import is the answer to "move my data".

This one file is ~1,500 lines and holds both storage and every derived-value
computation (stats, muscle recovery, personal records, 1RM progression, CSV
import/export). Derived values are computed on read and never persisted, so
they cannot drift from the underlying history — keep it that way rather than
caching a computed field into the store.

### Store invariants

These are load-bearing and easy to break by accident:

- **Every write goes through `ApiClient._mutate`**, which chains onto a
  `_writeQueue` so overlapping read-modify-write cycles can't interleave and
  lose records. A new mutating method that skips it will corrupt data under
  concurrent calls. There is a test for this.
- **Persistence is atomic**: `_persist()` writes a `.tmp` file and renames it
  over the live one, so a crash mid-write can't truncate the store.
- **Unreadable data is quarantined, never overwritten.** A corrupt file — or one
  whose `schema_version` is *newer* than this build — is renamed aside
  (`.corrupt-<ts>`) and a fresh seeded store takes its place.
- **`_AppData.schemaVersion` is currently `1`.** Bump it for any breaking layout
  change and migrate old files inside `_AppData.fromJson`.
- **Ids are `int` everywhere**, handed out by the monotonic `next*Id` counters on
  `_AppData`. Never reuse or renumber them; seeded library records and user
  records draw from the same counters.

### State flow

The store is a file, not a stream, so there is nothing for Riverpod to listen
to. [lib/providers.dart](client/lib/providers.dart) stands in a single revision
counter for one:

- Mutations are wrapped in `mutate(ref, ...)` / `mutateWith(widgetRef, ...)`,
  which run the action and then bump `storeRevisionProvider`.
- Every read provider calls `ref.watch(storeRevisionProvider)` before hitting
  the store, so all of them refetch after any write.

The consequence: **screens never invalidate providers by hand.** If you add a
read provider, watch the revision. If you add a write path, route it through
`mutate`. Don't reach for `ref.invalidate` — a mutation that bypasses the helper
leaves the UI stale in places far from the change.

`ExerciseFilter` is the exception to the pattern — pure in-memory UI state
(library search/filter chips) held so filters survive navigation, with no store
involvement.

### The workout logger

[lib/screens/workout/log_workout_screen.dart](client/lib/screens/workout/log_workout_screen.dart)
is the largest and most intricate screen (~1,700 lines) and carries most of the
app's real-time behavior. It composes a workout **entirely in memory**
(`_ExerciseEntry` / `_SetEntry` drafts) and writes it in one shot on save, so an
abandoned session leaves nothing half-logged. Editing an existing workout
rehydrates the same drafts.

Things in here that were deliberate and are worth not undoing:

- **The rest countdown is anchored to a wall-clock `_restEndTime`**, not a
  decrementing counter, and the screen is a `WidgetsBindingObserver` — so
  backgrounding the app (which pauses the ticker) doesn't lose rest time.
- **The chime is `audioplayers`, not `SystemSound.alert`**, which is a silent
  no-op in-app on iOS. Asset: `lib/assets/sounds/rest_complete.wav`.
- **Set fields are read-only on purpose**, driven by the in-app `_NumberPad`
  instead of the system keyboard — iOS's number pad has no return key, and Enter
  advancing to the next field is the whole point.
- **Portrait is locked for this screen only**, in `initState`, and released in
  `dispose` (the Info.plist still declares landscape support app-wide).

### UI conventions

- [lib/theme/tokens.dart](client/lib/theme/tokens.dart) is the single source of
  colors, spacing and typography (`AppColors`, `AppSpacing`, `AppTypography`).
  Use the tokens rather than literal colors or paddings — including
  `AppColors.muscleGroup` for per-group coloring and `supersetPalette` for
  superset grouping.
- [lib/widgets/glass.dart](client/lib/widgets/glass.dart) holds the shared
  chrome (`GlassSection`, `StatTile`, `LargeTitle`, `EmptyState`,
  `AsyncFailure`). Reach for these before building a one-off card or error view.
- The app uses `liquid_glass_widgets` for real GPU shader refraction, which
  requires `LiquidGlassWidgets.initialize()` and the `wrap()` call in
  [lib/main.dart](client/lib/main.dart). Navigation is a four-tab `GlassTabBar`
  in `HomeScreen` (Home / Exercises / Templates / Progress).

### Data conventions

- **Units are US pounds throughout.** CSV import converts kg to lb on the way in
  (either via the toggle or a `Weight (kg)` header); nothing stores kg.
- **CSV import is Strong-compatible and additive** — it never replaces the log.
  Exercise-name matching normalizes both naming styles ("Bench Press (Barbell)"
  vs "Barbell Bench Press") by splitting equipment words out of the name and
  sorting/de-pluralizing the rest. `_equipmentWords` and `_muscleAliases` are the
  knobs there.
- **JSON import is destructive by design** (restore-a-backup, not merge). It
  copies the current file aside first, and the UI must confirm before calling it.
- Muscle-group recovery windows live in `_recoveryHours`; free-form group
  strings map onto the eight tracked groups via `_muscleAliases`.
- **Measurements are entered as a batch**, not one value at a time — the sheet
  covers every tracked kind and saves through `createMeasurements` as a single
  queued write. `measurementSummaries()` drives the overview and only reports
  kinds that actually have entries.
- **`MeasurementKinds.goalFor` decides change colors.** Waist and body fat count
  down, chest and limbs count up, and body weight is deliberately *neutral* —
  the app has both cutters and bulkers, and coloring a gain red would
  congratulate half of them for the opposite of their goal. `kind` is a
  free-form string, so new kinds need no schema change.

## Testing

Only the store is covered — [test/api_client_test.dart](client/test/api_client_test.dart),
39 tests across seeding, workouts, stats, recovery, templates, measurements,
persistence, export/import and CSV. There are no widget tests.

Tests swap in a `_FakePathProvider` pointing `path_provider` at a temp
directory, so they never touch a real documents folder. Any new store behavior
belongs here; note the existing tests for the concurrency and quarantine
invariants above, which are the ones most likely to regress silently.

## Note on the README

[README.md](README.md) is accurate on architecture but stale on status: its "Not
yet included" section still lists rest timers (shipped), and it says 25 tests
(now 39). It also predates CSV import/export. Worth updating alongside any
change to those areas.
