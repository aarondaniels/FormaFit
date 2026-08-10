# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All work happens in `client/` — the repo root holds only the README and this file.

```bash
cd client
flutter pub get
flutter analyze                  # must be clean; it is today
flutter test                     # 83 tests, all in test/api_client_test.dart
flutter run                      # iOS simulator is the verified target
```

**Alternating `flutter build ipa`/`build ios` with `flutter run` corrupts the
build directory.** The release and simulator builds fight over `build/`, and the
symptom is a runtime `Couldn't resolve native function 'DOBJC_initializeApi'` —
native assets missing from the app bundle, not a code error. `flutter clean &&
flutter pub get` fixes it. Note that `flutter clean` also deletes any IPA in
`build/ios/ipa/`, so copy one aside before cleaning if it hasn't been uploaded.

Installing a locally-signed build over a differently-signed one (TestFlight,
say) makes iOS **delete and reinstall** rather than upgrade, which wipes the app
container — and the container holds the entire store. Export a JSON backup
before doing that to any device carrying real data.

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

This one file is ~1,700 lines and holds both storage and every derived-value
computation (stats, muscle recovery, personal records, 1RM progression, CSV
import/export). Derived values are computed on read and never persisted, so
they cannot drift from the underlying history — keep it that way rather than
caching a computed field into the store.

**The one exception is Apple Health data.** `Workout.activeEnergy`,
`avgHeartRate` and `maxHeartRate` are *stored*, because they are observations
from outside the app rather than anything recomputable from these records, and
they must survive the Health permission being withdrawn. Don't "fix" them into
derived values.

### Fail soft, never fail silent

Two separate features shipped broken because a `catch (_)` swallowed a hard,
100%-reproducible error and left it looking like the feature was merely quiet:

- Health writes threw `HealthException` on every save (wrong activity type) and
  Health simply showed no data from Forma.
- The rest chime threw `Unable to load asset` on every play; the haptic fired
  from the line above, so the alert felt like it worked with the sound turned
  down.

Swallowing is right — a Health outage or a missing sound must not cost someone
the workout they just logged — but the failure has to be *reachable*. Log it
with `debugPrint`, or return a reason the caller can surface, and prefer
reporting on paths the user explicitly triggered (a Settings toggle, a Sync
button). An `catch (_)` with an empty body is how a bug hides for a release.

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
  change and migrate old files inside `_AppData.fromJson`. Adding a *nullable*
  field is not breaking — `fromJson` tolerates missing keys, which is how the
  Health metrics and the `health_sync_enabled` preference were added without a
  bump. Only reshaping or removing existing keys needs one.
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
is the largest and most intricate screen (~2,300 lines, and overdue a split) and
carries most of the app's real-time behavior. It composes a workout **entirely in memory**
(`_ExerciseEntry` / `_SetEntry` drafts) and writes it in one shot on save, so an
abandoned session leaves nothing half-logged. Editing an existing workout
rehydrates the same drafts.

Things in here that were deliberate and are worth not undoing:

- **The rest countdown is anchored to a wall-clock `_restEndTime`**, not a
  decrementing counter, and the screen is a `WidgetsBindingObserver` — so
  backgrounding the app (which pauses the ticker) doesn't lose rest time.
- **The chime is `audioplayers`, not `SystemSound.alert`**, which is a silent
  no-op in-app on iOS. Asset: `lib/assets/sounds/rest_complete.wav`, referenced
  through the `restChimeAsset` constant with a test asserting it resolves.
  `AssetSource` prefixes with `AudioCache.prefix` (default `assets/`), and this
  project keeps assets under `lib/assets/`, so the player gets a prefix-free
  cache and the full key. A mismatch throws inside `play()` and is invisible.
- **Audio focus is `duckOthers`**, set once in `main.dart`. The default, `gain`,
  claims to be the sole audio source and would stop the user's music every time
  rest ended. `respectSilence` stays false so the chime is heard with the ring
  switch off — it's an alert, not media.
- **`audioplayers` never deactivates the iOS audio session, so the app has to.**
  Ducking lasts as long as the session is active, and the plugin's one
  `AVAudioSession.setActive` call (`controlAudioSession`, from
  `onSoundComplete`) runs while the player still reports `isPlaying` — so it
  re-activates on completion and nothing ever passes `false`. The symptom is the
  user's music staying quiet long after the chime, coming back only when iOS
  reclaims the session (backgrounding the app, or minutes later).
  [lib/audio_session.dart](client/lib/audio_session.dart) is the missing half: a
  `forma/audio_session` channel to `AppDelegate` calling `setActive(false,
  options: .notifyOthersOnDeactivation)`. The logger fires it off
  `onPlayerComplete`, with a 5s timer as a backstop for a chime that errors or
  never completes. `setActive(false)` throws *is busy* if the tail is still
  audible, hence the single retry.
- **Exercises reorder by dragging whole superset blocks.** `supersetBlocks()`
  groups contiguous runs sharing a group id, and the `SliverReorderableList`
  moves those blocks — a member dropped inside another group would break the
  interleaved focus traversal. Drag starts from a grip in the card header
  (`ReorderableDragStartListener`), never a long-press: the set fields are
  read-only with their own tap handler and would fight it. A `proxyDecorator`
  substitutes a compact pill, since a real card is far too tall to drag.
- **Set fields are read-only on purpose**, driven by the in-app `NumberPad`
  instead of the system keyboard — iOS's number pad has no return key, and Enter
  advancing to the next field is the whole point. The pad now lives in
  [lib/widgets/number_pad.dart](client/lib/widgets/number_pad.dart) with the
  field-editing helpers (`typeIntoField`, `backspaceInField`), shared with the
  measurement session sheet. Any new column of numeric fields should use it
  rather than the system keypad.
- **A session started from a template offers to update it on save.**
  `_offerTemplateUpdate` asks only when something actually differs, and only
  after the workout is already stored, so declining costs nothing. Supersets
  are the one change that can't be carried back — `TemplateExercise` has no
  group id.
- **Portrait is locked for this screen only**, in `initState`, and released in
  `dispose` (the Info.plist still declares landscape support app-wide).
- **Completion is never inferred from the fields.** Typing a rep count means you
  are entering a set, not that you finished it. Only three gestures set
  `_SetEntry.completed`: tapping the check, pressing Next off a set holding both
  a weight and reps, and tapping a historical value that fills the last blank.
  All three start rest and jump focus to the *next set's weight* via
  `_focusWeightAfter` — which for a superset is the next exercise in the group,
  since `_focusOrder` already walks them interleaved (A1, B1, A2, B2).
- Sets rehydrated from a saved workout open **already checked**; they were
  performed. Template sets and new rows do not.
- **The trailing control is the check, so removing a set is a swipe.** It used
  to be the remove button, which meant tapping a green check deleted the set.
- **`_VolumeBar` compares against the last session**: the bar fills toward that
  session's total, while the figure beside it is set-matched — this session
  against the *same number of sets* last time. A raw delta partway through an
  exercise is only ever a large negative number.
- **The workout date carries a real time of day**, and it is the session start:
  Apple Health is queried for `[date, date + duration]`. `showDatePicker`
  returns midnight, so anything editing the date must splice the old time back
  in or the Health window silently moves to 00:00.

### Apple Health

[lib/health_sync.dart](client/lib/health_sync.dart) is the only bridge, and it
is deliberately shaped so no caller needs a platform check: every entry point
returns false or null off iOS, and `HealthSync.isSupported` gates the UI.
Android's equivalent is Health Connect, a separate API that is not implemented.

- **Off until the user turns it on** (`health_sync_enabled` in the store), since
  enabling it triggers the system permission prompt. The Settings switch asks
  for permission first and stays off if refused.
- **Forma writes the workout but never the energy.** The watch is already
  recording active energy for that window; writing our own would double-count it
  in the activity rings.
- **Written only on create, never on edit** — a second write for the same window
  would show up as a duplicate session in Health.
- **A missing reading is normal, not an error.** Health often takes minutes to
  receive a session from the watch, which is why the workout screen offers a
  refresh instead of treating the first answer as final, and why
  `setWorkoutHealthMetrics` leaves a metric alone when passed null rather than
  clearing it.
- Everything fails soft. Sync off, permission refused, plugin throwing — all
  return null, and none of them may cost the user the workout they just logged.
- **The activity type must be `TRADITIONAL_STRENGTH_TRAINING`.** The plugin
  classifies `STRENGTH_TRAINING` as Android-only and throws on iOS. Check
  `_isOnIOS` in the plugin source before using any activity type; the two sets
  overlap enough to look interchangeable and aren't.
- **List each `HealthDataType` once** in `requestAuthorization`, using
  `READ_WRITE` where both are needed. Naming a type twice — once READ, once
  WRITE — registers only one, and write is the one that goes missing.
- **Writing a workout does not move the activity rings.** Move comes from
  `activeEnergyBurned` samples and Exercise from `appleExerciseTime`, both the
  watch's own. Our write makes the session *appear* in Fitness and gives it a
  name; it adds no energy by design. Don't promise rings in UI copy.
- **The plugin forces a minimum iOS.** `health` needs 14.0; the floor is set to
  15.0 to clear App Store Connect warning 90068. It lives in
  `project.pbxproj` (three configs) *and* `ios/Podfile` — change both.
- **`Runner.entitlements` is wired via `CODE_SIGN_ENTITLEMENTS`** in all three
  Runner configs. It was orphaned before this — present but referenced nowhere,
  so it silently did nothing. If an entitlement seems ignored, check that
  setting first, and verify against the built app rather than the source file:
  `codesign -d --entitlements - --xml <app> | plutil -p -`.

### Notifications

[lib/workout_reminder.dart](client/lib/workout_reminder.dart) raises one alert
and only one: the logger has been open and untouched for 30 minutes, so a
workout is sitting there unsaved.

- **They are local notifications, not push.** There is no backend and no
  account, so there is nothing to push *from* — see "There is no backend". If a
  reminder is ever asked for, it has to be something the device can schedule
  against a clock by itself.
- **The fire time belongs to iOS, not to a `Timer`.** The case this exists for
  is a phone that went into a bag mid-session, and iOS suspends the isolate
  seconds after backgrounding — a Dart timer would simply never run.
  `UNTimeIntervalNotificationTrigger` delivers whether the app is foreground,
  suspended or terminated.
- **One pending request, reused id** (`forma.workout_idle`). Scheduling again
  replaces it, which is what makes each interaction push the reminder out
  another half hour instead of queueing a second alert.
- **Activity is any touch**, caught by one `Listener` over the whole logger
  rather than wired into individual controls — scrolling back through the
  session counts as tending it. Rescheduling is throttled to once a minute,
  since a tap-by-tap channel call would cross the boundary dozens of times a
  set.
- **`dispose` cancels unconditionally**, delivered ones included. A saved
  workout that still gets told it is "in progress" is worse than no reminder.
- **The app takes `UNUserNotificationCenter.delegate`** in `AppDelegate` and
  overrides `willPresent`. Without a delegate iOS drops anything that comes due
  while the app is frontmost, and untouched-but-visible is exactly the case
  here. `FlutterAppDelegate` already conforms and stubs `willPresent`, so it is
  an `override` and must not be restated in the conformance list. If a
  notification plugin is ever added, it will want the same delegate.
- Off until the user turns it on, like Health sync, and for the same reason:
  the switch triggers the permission prompt. It also re-checks `hasPermission`
  when the logger opens — permission can be revoked in iOS Settings long after
  the switch was flipped, and scheduling would otherwise be accepted and never
  delivered.

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
- **The tab title bar carries settings, and only on Home.** There is no global
  "+": it meant "log a workout" everywhere while reading as "new template" on
  Templates and "new exercise" on Exercises. Starting a workout has exactly two
  entrances — the Home tab's `_StartWorkoutCta` and tapping a saved template.
  Resist re-adding a title-bar action that means something different per tab.
- **No title-bar "+" does not mean no way to create.** Because the title bar
  carries nothing, a tab that only offers creation through "search for a name
  that matches nothing, then take the offer in the empty state" has effectively
  hidden the feature — that is exactly how the Templates tab shipped, and it
  reads as if searching is the way in. A tab that owns a list needs a standing
  create action **in its own body**: `IconButton.filled` beside the search
  field on `FolderListScreen`, a `FloatingActionButton.extended` on
  `TemplateListScreen`, which has a Scaffold of its own. The exercise library
  still has the old shape and would benefit from the same treatment.
- **Search appears only when there is something to search.** `FolderListScreen`
  renders no field at all when there are no folders: an empty list plus a
  search box reads as "type here to begin". The empty state alone, with one
  labelled button, is the whole instruction.
- **Creating a folder opens it.** A folder exists to hold templates, so the
  next thing wanted is the "New template" button inside it. This applies to
  both entrances (the empty state's button and the search-no-match offer).
- `AsyncFailure`/`EmptyState` renders the raw error string and **overflows on a
  long one** — a failing provider with a verbose message blows out the layout.
  Known, unfixed.
- **A search field needs its own `TextEditingController`.** Without one the
  `TextField` owns its text privately and nothing can clear it: the exercise
  library's clear button reset the filter — re-filtering the list and hiding the
  button — while the typed text stayed on screen. Seed the controller from
  current filter state, and `ref.listen` the notifier so resets triggered
  elsewhere (an empty state's "clear filters") also reach the field.

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
- **Ages are counted in calendar days, never elapsed hours.** `formatAge` in
  [measurements_screen.dart](client/lib/screens/measurements_screen.dart) is the
  one vocabulary ("Today" / "Yesterday" / "N days ago"), and both
  `Workout.daysSince` and `MeasurementSummary.daysSince` floor to midnight
  before subtracting. A workout date carries a real time of day, so a raw
  `Duration` would call an 8pm session fourteen hours later "Today". Tested.
- **Measurements are entered as a batch**, not one value at a time — the sheet
  covers every tracked kind and saves through `createMeasurements` as a single
  queued write. `measurementSummaries()` drives the overview and only reports
  kinds that actually have entries. `showMeasurementSession(onlyKind:)` narrows
  it to one, which is what the per-kind shortcuts use.
- **Logging is offered wherever a measurement is shown.** A weigh-in is a
  weekly habit and used to be four taps and two screens deep: the Progress
  tab's Body card carries a "+" and each of its rows logs that one kind, as do
  the rows on the Measurements screen. The batch sheet is still the full act;
  these are the shortcuts to it.
- **`ApiClient.templateDefaultsFor` picks a template's load from a session** —
  the most *repeated* (weight, reps) pair, ties going to the heavier. Not the
  heaviest set (that's a top single) and not the last (that's fatigue). A
  template describes working sets, and "3×5 at 185" is what should come back
  next time. Tested.
- **`MeasurementKinds.goalFor` decides change colors.** Waist and body fat count
  down, chest and limbs count up, and body weight is deliberately *neutral* —
  the app has both cutters and bulkers, and coloring a gain red would
  congratulate half of them for the opposite of their goal. `kind` is a
  free-form string, so new kinds need no schema change.
- **`VolumeComparison` measures work in whichever unit the exercise is loaded
  with.** Tonnage (`weight × reps`) normally, but total *reps* when neither
  session has a loaded set — bodyweight movements multiply out to zero, and a
  progress bar that never fills is worse than none. One weighted set anywhere
  keeps the whole exercise on tonnage, so a belt on the first set can't switch
  units mid-exercise.

## Testing

Only the store and pure computation are covered —
[test/api_client_test.dart](client/test/api_client_test.dart), 83 tests across
seeding, workouts, stats, recovery, templates, measurements, persistence,
export/import, CSV, volume comparison, stored Health metrics, preferences and
workout age. **There are no widget tests at all**, so every screen change rests
on running the app.

Tests swap in a `_FakePathProvider` pointing `path_provider` at a temp
directory, so they never touch a real documents folder. Any new store behavior
belongs here; note the existing tests for the concurrency and quarantine
invariants above, which are the ones most likely to regress silently.

`HealthSync` is untested — it wraps a plugin that needs a real device and a
watch, and neither the simulator nor CI has either.

## Verifying UI changes

There is no tap automation set up (`idb` is not installed), so driving the app
means a human. `flutter run -d <simulator-id>` plus
`xcrun simctl io <id> screenshot` confirms a screen renders and gets you a look
at it, which catches layout errors and crashes but not interaction. Anything
about *behavior* — completion gestures, focus order, Health — needs hands on the
device. Say so rather than implying it was verified.

Two tricks reach screens and states a screenshot otherwise can't, without taps:

- **To open a tab other than Home**, temporarily set `_HomeScreenState._index`
  to that tab's position. Revert it before committing — check with `git diff`.
- **To reach a data state, write the store directly.** The simulator's copy
  lives at `$(xcrun simctl get_app_container <id> com.forma.workout
  data)/Documents/forma_data.json`. Terminate the app first (a running one
  holds `_cache` in memory and will overwrite the file), edit, then relaunch
  with `xcrun simctl launch` — **not** `flutter run`, which reinstalls the app
  and mints a fresh, empty container. Seeded records must carry *every*
  non-nullable key their `fromJson` reads (`created_at` is the easy one to
  forget); a partial record throws and the store quarantines the file and
  reseeds, which looks exactly like the seeding silently not working. Clear the
  test data out afterwards.
