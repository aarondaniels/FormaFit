import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../health_sync.dart';
import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../../widgets/rest.dart';
import '../exercise_detail_screen.dart' show trimNumber;
import 'exercise_picker_sheet.dart';
import 'template_picker_screen.dart';
import 'workout_complete_sheet.dart';

/// Groups items into contiguous runs sharing a non-null superset id, leaving
/// ungrouped items as runs of one.
///
/// These are the units drag moves. Keeping a superset's members adjacent is not
/// cosmetic: the focus traversal walks contiguous runs to interleave a group
/// (A1, B1, A2, B2), so an exercise dropped into the middle of one would
/// silently corrupt the order sets are worked through.
///
/// Generic over the item so the logic can be tested without the logger's
/// private draft types.
List<List<T>> supersetBlocks<T>(List<T> items, int? Function(T) groupOf) {
  final blocks = <List<T>>[];
  for (final item in items) {
    final group = groupOf(item);
    final previous = blocks.isEmpty ? null : blocks.last;
    if (group != null &&
        previous != null &&
        groupOf(previous.last) == group) {
      previous.add(item);
    } else {
      blocks.add([item]);
    }
  }
  return blocks;
}

/// Moves the block at [oldIndex] to [newIndex] and flattens back to a flat
/// list, taking the half-open index a reorderable list reports.
List<T> moveSupersetBlock<T>(
  List<T> items,
  int? Function(T) groupOf,
  int oldIndex,
  int newIndex,
) {
  final blocks = supersetBlocks(items, groupOf);
  if (oldIndex < 0 || oldIndex >= blocks.length) return items;
  // A drop below the origin is reported against the list before removal.
  var target = newIndex > oldIndex ? newIndex - 1 : newIndex;
  target = target.clamp(0, blocks.length - 1);
  final moved = blocks.removeAt(oldIndex);
  blocks.insert(target, moved);
  return [for (final block in blocks) ...block];
}

/// Asset key for the rest-timer chime.
///
/// The full key as declared in pubspec.yaml. `AssetSource` resolves against
/// `AudioCache.prefix`, which defaults to `assets/`, so the player is given a
/// prefix-free cache and this path must be complete. The mismatch is silent —
/// a wrong key throws inside `play()` — which is why it is a named constant
/// with a test asserting it resolves.
const restChimeAsset = 'lib/assets/sounds/rest_complete.wav';

/// Composes a workout in memory and writes it in one shot on save.
///
/// Nothing is persisted until the user saves, so an abandoned session leaves
/// no half-logged workout behind.
class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({super.key, this.existing, this.fromTemplate});

  /// When set, the screen edits this workout instead of starting a new one.
  final Workout? existing;

  /// When set (and [existing] is null), starts a fresh session pre-filled from
  /// this template — its exercises and their default sets, weight and reps.
  final Template? fromTemplate;

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen>
    with WidgetsBindingObserver {
  final List<_ExerciseEntry> _entries = [];
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  int _effort = 5;
  String? _templateName;
  bool _saving = false;

  /// Hands out group ids for supersets. Unique within this workout is enough;
  /// it starts above any group already present when editing.
  int _nextSupersetGroup = 1;

  /// Wall-clock timer for a live session. Editing an existing workout keeps
  /// its recorded duration rather than timing the edit.
  Stopwatch? _stopwatch;
  Timer? _ticker;
  int? _fixedDuration;

  /// Rest countdown, shared across the workout (one rest runs at a time).
  ///
  /// The countdown is anchored to a wall-clock [_restEndTime] rather than a
  /// decrementing counter, so backgrounding the app (which pauses the ticker)
  /// no longer loses time — on resume the remaining time is recomputed from the
  /// clock. [_restRemaining]/[_restTotal] are just the values the UI shows.
  Timer? _restTicker;
  DateTime? _restEndTime;
  int _restRemaining = 0;
  int _restTotal = 0;

  /// Plays the rest-complete chime. Created lazily on first use and reused so
  /// repeated alerts don't spin up a new player each time.
  AudioPlayer? _restPlayer;

  @override
  void initState() {
    super.initState();
    // Logging a set is a portrait task — the number pad and set rows are laid
    // out for it — so lock out landscape while this screen is up and a mid-set
    // rotation can't reflow the keypad. Restored in dispose.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    // Observe app lifecycle so a rest countdown running while the user switches
    // to another app is re-synced to the wall clock on return.
    WidgetsBinding.instance.addObserver(this);
    // Rebuild when focus moves so the keyboard toolbar shows only while a set
    // field is active and reflects which field that is.
    FocusManager.instance.addListener(_onFocusChange);
    final existing = widget.existing;
    if (existing != null) {
      _date = existing.date;
      _effort = existing.effortLevel;
      _templateName = existing.templateName;
      _notes.text = existing.notes ?? '';
      _fixedDuration = existing.duration;
      for (final we in existing.exercises) {
        _entries.add(
          _ExerciseEntry(
            exerciseId: we.exerciseId,
            notes: we.notes,
            supersetGroup: we.supersetGroup,
            restSeconds: we.restSeconds,
            sets: [
              // Sets coming back from a saved workout were performed, so they
              // open already checked.
              for (final s in we.sets)
                _SetEntry(weight: s.weight, reps: s.reps, complete: true),
            ],
          ),
        );
      }
      // Continue group numbering above whatever the workout already uses.
      final maxGroup = existing.exercises
          .map((e) => e.supersetGroup ?? 0)
          .fold(0, (a, b) => a > b ? a : b);
      _nextSupersetGroup = maxGroup + 1;
    } else {
      _stopwatch = Stopwatch()..start();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
      // A new session started from a template comes in pre-filled.
      final template = widget.fromTemplate;
      if (template != null) _populateFromTemplate(template);
    }
  }

  /// Appends a template's exercises to the current entries, seeding each set
  /// with the template's defaults. Mutates state directly so it can be called
  /// from [initState]; callers already inside the widget tree wrap it in
  /// [setState].
  void _populateFromTemplate(Template template) {
    _templateName = template.name;
    for (final te in template.exercises) {
      _entries.add(
        _ExerciseEntry(
          exerciseId: te.exerciseId,
          restSeconds: te.restSeconds,
          sets: List.generate(
            // A template with zero sets still needs one row to type into.
            te.defaultSets < 1 ? 1 : te.defaultSets,
            (_) => _SetEntry(weight: te.defaultWeight, reps: te.defaultReps),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    // Hand rotation back to the rest of the app (empty = all orientations the
    // app declares support for).
    SystemChrome.setPreferredOrientations(const []);
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChange);
    _ticker?.cancel();
    _restTicker?.cancel();
    _restPlayer?.dispose();
    _notes.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {});
    // A set field focused via the Enter key (or a tap that the number pad then
    // covers) won't scroll itself into view, so bring it above the pad here.
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !_isSetFieldNode(node)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isSetFieldNode(FocusNode node) {
    for (final e in _entries) {
      for (final s in e.sets) {
        if (s.weightFocus == node || s.repsFocus == node) return true;
      }
    }
    return false;
  }

  int? get _duration => _stopwatch?.elapsed.inSeconds ?? _fixedDuration;

  /// Every set field in the order focus should walk through them: down the sets
  /// of a plain exercise, but interleaved across the members of a superset
  /// (A1, B1, A2, B2, …), matching how a superset is actually performed.
  List<FocusNode> _focusOrder() {
    final order = <FocusNode>[];
    var i = 0;
    while (i < _entries.length) {
      final group = _entries[i].supersetGroup;
      if (group == null) {
        for (final s in _entries[i].sets) {
          order
            ..add(s.weightFocus)
            ..add(s.repsFocus);
        }
        i++;
        continue;
      }
      // Gather the contiguous run of exercises sharing this superset.
      final block = <_ExerciseEntry>[];
      while (i < _entries.length && _entries[i].supersetGroup == group) {
        block.add(_entries[i]);
        i++;
      }
      final maxSets = block.fold<int>(
        0,
        (m, e) => e.sets.length > m ? e.sets.length : m,
      );
      for (var s = 0; s < maxSets; s++) {
        for (final e in block) {
          if (s < e.sets.length) {
            order
              ..add(e.sets[s].weightFocus)
              ..add(e.sets[s].repsFocus);
          }
        }
      }
    }
    return order;
  }

  /// Moves focus to the field after [current]; dismisses the number pad when
  /// [current] is the last field in the workout.
  void _focusNextField(FocusNode current) {
    final order = _focusOrder();
    final idx = order.indexOf(current);
    if (idx == -1) return;
    if (idx + 1 < order.length) {
      FocusScope.of(context).requestFocus(order[idx + 1]);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  /// Lands on the weight of the set after [set], which for a superset is the
  /// same set number of the next exercise in the group rather than this
  /// exercise's next set — [_focusOrder] already walks them interleaved.
  ///
  /// Every set contributes exactly its weight then its reps to that order, so
  /// the field following a set's reps is the next set's weight.
  void _focusWeightAfter(_SetEntry set) {
    final order = _focusOrder();
    final idx = order.indexOf(set.repsFocus);
    if (idx == -1) return;
    if (idx + 1 < order.length) {
      FocusScope.of(context).requestFocus(order[idx + 1]);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  /// Marks a set done: the shared tail of all three completing gestures —
  /// tapping the check, pressing Next off a full set, and tapping the
  /// historical value that fills its last blank.
  void _completeSet(_SetEntry set, int restSeconds) {
    set.completed.value = true;
    if (restSeconds > 0) _startRest(restSeconds);
    _focusWeightAfter(set);
  }

  /// The set field currently focused: its controller, whether it is a weight
  /// field (decimals allowed) rather than reps, and which exercise/set it is
  /// (so its historical value can be looked up). Null when no set field has
  /// focus.
  ({
    TextEditingController controller,
    bool isWeight,
    int exerciseId,
    int setIndex,
    int restSeconds,
    _SetEntry set,
  })?
  _activeFieldTarget(FocusNode? node) {
    if (node == null) return null;
    for (final e in _entries) {
      for (var i = 0; i < e.sets.length; i++) {
        final s = e.sets[i];
        if (s.weightFocus == node) {
          return (
            controller: s.weightController,
            isWeight: true,
            exerciseId: e.exerciseId,
            setIndex: i,
            restSeconds: e.restSeconds,
            set: s,
          );
        }
        if (s.repsFocus == node) {
          return (
            controller: s.repsController,
            isWeight: false,
            exerciseId: e.exerciseId,
            setIndex: i,
            restSeconds: e.restSeconds,
            set: s,
          );
        }
      }
    }
    return null;
  }

  /// Advances from [current] to the next field, first filling it with this
  /// set's value from last time when it was left blank — so a user can adopt
  /// their previous workout by tapping Enter straight down the fields.
  ///
  /// Pressing Next off the reps of a set that now holds both a weight and a
  /// rep count completes it and jumps to the next set's weight, skipping the
  /// fields already behind you.
  void _enterFromField(FocusNode current) {
    final target = _activeFieldTarget(current);
    if (target == null) {
      _focusNextField(current);
      return;
    }

    if (target.controller.text.trim().isEmpty) {
      final value = _historicalValue(
        target.exerciseId,
        target.setIndex,
        target.isWeight,
      );
      if (value != null) {
        target.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }

    if (!target.isWeight && target.set.isFull) {
      _completeSet(target.set, target.restSeconds);
      return;
    }
    _focusNextField(current);
  }

  /// The value logged for this exercise's set at [setIndex] the last time it
  /// was performed — the same figure shown greyed under the field. Null when
  /// there is no matching historical set.
  String? _historicalValue(int exerciseId, int setIndex, bool isWeight) {
    final last = ref.read(exerciseHistoryProvider(exerciseId)).value?.firstOrNull;
    if (last == null || setIndex >= last.sets.length) return null;
    final set = last.sets[setIndex];
    if (isWeight) {
      final w = set.weight;
      return w == null ? null : trimNumber(w);
    }
    return set.reps?.toString();
  }

  /// Inserts [key] at the caret, keeping weights to a single decimal point.
  void _typeInto(TextEditingController ctrl, bool decimal, String key) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final candidate = text.replaceRange(start, end, key);
    if (key == '.' && (!decimal || '.'.allMatches(candidate).length > 1)) {
      return;
    }
    ctrl.value = TextEditingValue(
      text: candidate,
      selection: TextSelection.collapsed(offset: start + key.length),
    );
  }

  // --- Rest timer ---------------------------------------------------------

  void _startRest(int seconds) {
    _restTicker?.cancel();
    if (seconds <= 0) return;
    _restEndTime = DateTime.now().add(Duration(seconds: seconds));
    setState(() {
      _restTotal = seconds;
      _restRemaining = seconds;
    });
    _restTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickRest());
  }

  /// Recomputes the remaining rest from the wall clock and, on reaching zero,
  /// ends the rest and fires the alert. Driven both by the 1-second ticker and
  /// by an app resume, so a rest that elapsed while foregrounded still alerts.
  void _tickRest() {
    if (!mounted) return;
    final end = _restEndTime;
    if (end == null) return;
    final msLeft = end.difference(DateTime.now()).inMilliseconds;
    if (msLeft <= 0) {
      _completeRest(alert: true);
    } else {
      setState(() => _restRemaining = (msLeft / 1000).ceil());
    }
  }

  /// Clears the running rest. Fires the buzz + chime when [alert] is set (a
  /// natural expiry) and stays silent otherwise (skip, or manual -15 to zero).
  void _completeRest({required bool alert}) {
    _restTicker?.cancel();
    _restTicker = null;
    _restEndTime = null;
    setState(() => _restRemaining = 0);
    if (alert) _fireRestAlert();
  }

  /// A buzz and a chime so the end of rest lands without watching the screen.
  /// The haptic is reliable on iOS; the audio is what makes it audible, since
  /// SystemSound.alert is a no-op in-app there.
  Future<void> _fireRestAlert() async {
    HapticFeedback.heavyImpact();
    try {
      final player = _restPlayer ??= AudioPlayer()
        // Default prefix is `assets/`; this project keeps its assets under
        // `lib/assets/`, so the key is given in full instead.
        ..audioCache = AudioCache(prefix: '');
      await player.stop();
      await player.play(AssetSource(restChimeAsset));
    } catch (e) {
      // The haptic already fired, so a silent alert beats a crash mid-workout
      // — but say so, rather than leaving a broken chime indistinguishable
      // from a working one.
      debugPrint('[rest] chime failed: $e');
    }
  }

  void _adjustRest(int delta) {
    final end = _restEndTime;
    if (end == null) return;
    final newEnd = end.add(Duration(seconds: delta));
    final msLeft = newEnd.difference(DateTime.now()).inMilliseconds;
    // Trimming rest down to zero just ends it — no alarm for a manual stop.
    if (msLeft <= 0) {
      _completeRest(alert: false);
      return;
    }
    setState(() {
      _restEndTime = newEnd;
      _restRemaining = (msLeft / 1000).ceil();
      if (_restRemaining > _restTotal) _restTotal = _restRemaining;
    });
  }

  void _skipRest() => _completeRest(alert: false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The ticker is paused while backgrounded, so on resume re-sync the
    // countdown to the clock. If the rest already elapsed while away, end it
    // (silently — the moment has passed and a stale chime would confuse).
    if (state != AppLifecycleState.resumed || _restEndTime == null) return;
    final msLeft = _restEndTime!.difference(DateTime.now()).inMilliseconds;
    if (msLeft <= 0) {
      _completeRest(alert: false);
    } else {
      setState(() => _restRemaining = (msLeft / 1000).ceil());
    }
  }

  /// Deletes the selection, or the character before the caret.
  void _backspaceIn(TextEditingController ctrl) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    if (start == end) {
      if (start == 0) return;
      ctrl.value = TextEditingValue(
        text: text.replaceRange(start - 1, start, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      ctrl.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
  }

  /// Collapses the number pad by dropping focus from the active set field; the
  /// pad is only shown while such a field is focused. A rest countdown in
  /// progress keeps running.
  void _collapseKeypad() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _addExercises() async {
    final picked = await showExercisePicker(context);
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final id in picked) {
        _entries.add(
          _ExerciseEntry(exerciseId: id, sets: [_SetEntry()]),
        );
      }
    });
  }

  Future<void> _applyTemplate() async {
    final template = await Navigator.of(context).push<Template>(
      MaterialPageRoute(builder: (_) => const TemplatePickerScreen()),
    );
    if (template == null) return;
    setState(() => _populateFromTemplate(template));
  }

  /// Links the exercise at [i] into a superset with the one directly above it.
  void _supersetWithPrevious(int i) {
    if (i > 0) _mergeSuperset(i - 1, i);
  }

  /// Links the exercise at [i] into a superset with the one directly below it.
  void _supersetWithNext(int i) {
    if (i < _entries.length - 1) _mergeSuperset(i, i + 1);
  }

  /// Puts the exercises at [a] and [b] in the same superset group. Whichever
  /// side is already grouped wins; if both are (in different groups) the two
  /// groups are folded into one, so any number of exercises can end up joined.
  void _mergeSuperset(int a, int b) {
    setState(() {
      final ga = _entries[a].supersetGroup;
      final gb = _entries[b].supersetGroup;
      if (ga == null && gb == null) {
        final group = _nextSupersetGroup++;
        _entries[a].supersetGroup = group;
        _entries[b].supersetGroup = group;
      } else if (ga == null) {
        _entries[a].supersetGroup = gb;
      } else if (gb == null) {
        _entries[b].supersetGroup = ga;
      } else if (ga != gb) {
        for (final e in _entries) {
          if (e.supersetGroup == gb) e.supersetGroup = ga;
        }
      }
    });
  }

  /// Removes the exercise at [i] from its superset. A group left with a single
  /// member is dissolved, since a superset of one is meaningless.
  void _leaveSuperset(int i) {
    setState(() {
      final group = _entries[i].supersetGroup;
      _entries[i].supersetGroup = null;
      if (group == null) return;
      final remaining = _entries.where((e) => e.supersetGroup == group);
      if (remaining.length == 1) remaining.first.supersetGroup = null;
    });
  }

  /// A stable color per superset group, so grouped cards read as one unit.
  Color? _supersetColor(int? group) =>
      group == null ? null : AppColors.forSuperset(group);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    // showDatePicker returns midnight, which would throw away the time of day.
    // That time is the session's start, and Apple Health is queried for the
    // window it opens, so moving a workout to another date has to keep it.
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _save() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first.')),
      );
      return;
    }
    setState(() => _saving = true);
    _stopwatch?.stop();

    final drafts = [
      for (final e in _entries)
        WorkoutExerciseDraft(
          exerciseId: e.exerciseId,
          notes: e.notes,
          supersetGroup: e.supersetGroup,
          restSeconds: e.restSeconds,
          // Drop rows the user left completely blank rather than storing
          // empty sets that would skew set counts.
          sets: [
            for (final s in e.sets)
              if (!s.isEmpty)
                WorkoutSetDraft(weight: s.weight, reps: s.reps),
          ],
        ),
    ]..removeWhere((d) => d.sets.isEmpty);

    if (drafts.isEmpty) {
      setState(() {
        _saving = false;
        _stopwatch?.start();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a weight or reps for a set.')),
      );
      return;
    }

    try {
      final existing = widget.existing;
      final saved = await mutateWith(ref, (api) async {
        if (existing == null) {
          return api.createWorkout(
            date: _date,
            effortLevel: _effort,
            notes: _emptyToNull(_notes.text),
            templateName: _templateName,
            duration: _duration,
            exercises: drafts,
          );
        }
        return api.updateWorkout(
          id: existing.id,
          date: _date,
          effortLevel: _effort,
          notes: _emptyToNull(_notes.text),
          duration: _duration,
          exercises: drafts,
        );
      });
      // Mirror the session into Apple Health and pick up whatever the watch
      // measured. Only on a fresh save — an edit would write a second,
      // duplicate workout for the same window.
      if (existing == null) await _syncToHealth(saved);
      // Celebrate a freshly completed workout with its highlights; editing an
      // existing one just returns to the detail without the fanfare.
      if (existing == null && mounted) {
        final summary = await _buildSummary(saved);
        if (summary != null && mounted) {
          await showWorkoutCompleteSheet(context, summary);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _stopwatch?.start();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  /// Writes the finished session to Apple Health and stores back whatever the
  /// watch measured over it.
  ///
  /// Entirely best-effort: sync being off, permission refused, or Health simply
  /// not having synced from the watch yet are all ordinary outcomes, and none
  /// of them should interrupt saving a workout. The workout screen offers a
  /// refresh for the last of those.
  Future<void> _syncToHealth(Workout saved) async {
    try {
      if (!HealthSync.isSupported) return;
      final enabled = await ref.read(apiProvider).healthSyncEnabled();
      if (!enabled) return;

      final health = ref.read(healthSyncProvider);
      // Skip the write if Health already has something covering this window —
      // our own earlier attempt, or a session recorded on the watch itself.
      final duplicate = await health.hasWorkoutInWindow(
        start: saved.date,
        end: saved.endsAt,
      );
      if (!duplicate) {
        final failure = await health.writeWorkout(
          start: saved.date,
          end: saved.endsAt,
        );
        if (failure != null) debugPrint('[health] $failure');
      }

      final metrics = await health.readMetrics(
        start: saved.date,
        end: saved.endsAt,
      );
      if (metrics == null || !mounted) return;
      await mutateWith(
        ref,
        (api) => api.setWorkoutHealthMetrics(
          saved.id,
          activeEnergy: metrics.activeEnergy,
          avgHeartRate: metrics.avgHeartRate,
          maxHeartRate: metrics.maxHeartRate,
        ),
      );
    } catch (_) {
      // Health is outside the app's control; a failure here is not the user's
      // problem and must not cost them the workout they just logged.
    }
  }

  /// Gathers the highlights for the completion sheet: this session's totals,
  /// any exercise that beat its previous best, and where the workout lands in
  /// the all-time and weekly counts. Returns null if the store can't be read,
  /// so a stats hiccup never blocks leaving the logger.
  Future<WorkoutSummary?> _buildSummary(Workout saved) async {
    try {
      final all = await ref.read(workoutsProvider.future);
      final byId = await ref.read(exercisesByIdProvider.future);
      final stats = await ref.read(statsProvider.future);
      return WorkoutSummary(
        exerciseCount: saved.exerciseCount,
        setCount: saved.setCount,
        volume: saved.volume,
        durationLabel: saved.formattedDuration,
        totalWorkouts: stats.totalWorkouts,
        workoutsThisWeek: stats.workoutsThisWeek,
        weekStreak: stats.weekStreak,
        prs: _sessionPRs(saved, all, byId),
        volumeChanges: _volumeChanges(saved, all, byId),
      );
    } catch (_) {
      return null;
    }
  }

  /// Each exercise's work this session against the most recent earlier session
  /// that included it, in the order it was trained.
  static List<ExerciseVolumeChange> _volumeChanges(
    Workout saved,
    List<Workout> all,
    Map<int, Exercise> byId,
  ) {
    // Newest first, so the first earlier workout containing an exercise is the
    // one to measure against.
    final earlier = [...all.where((w) => w.id != saved.id)]
      ..sort((a, b) => b.date.compareTo(a.date));

    final changes = <ExerciseVolumeChange>[];
    for (final we in saved.exercises) {
      List<WorkoutSet>? previousSets;
      for (final w in earlier) {
        final match = w.exercises
            .where((e) => e.exerciseId == we.exerciseId)
            .firstOrNull;
        if (match != null) {
          previousSets = match.sets;
          break;
        }
      }

      final volume = VolumeComparison.of(
        current: [for (final s in we.sets) (weight: s.weight, reps: s.reps)],
        previous: [
          for (final s in previousSets ?? const <WorkoutSet>[])
            (weight: s.weight, reps: s.reps),
        ],
      );
      changes.add(
        ExerciseVolumeChange(
          exerciseName: byId[we.exerciseId]?.name ?? 'Exercise',
          current: volume.current,
          previous: previousSets == null ? null : volume.previousTotal,
          unit: volume.unit,
        ),
      );
    }
    return changes;
  }

  /// Exercises in [saved] whose best set beat that exercise's previous all-time
  /// best — by heaviest weight or by estimated one-rep max, so both "lifted
  /// heavier" and "same weight for more reps" count. Only exercises with prior
  /// history qualify, so a first-ever session isn't reported as a wall of PRs.
  static List<PrHighlight> _sessionPRs(
    Workout saved,
    List<Workout> all,
    Map<int, Exercise> byId,
  ) {
    final priorWeight = <int, double>{};
    final priorOrm = <int, double>{};
    for (final w in all) {
      if (w.id == saved.id) continue;
      for (final we in w.exercises) {
        for (final s in we.sets) {
          final wt = s.weight;
          final r = s.reps;
          if (wt == null || r == null || wt <= 0) continue;
          if (wt > (priorWeight[we.exerciseId] ?? 0)) {
            priorWeight[we.exerciseId] = wt;
          }
          final orm = _epley(wt, r);
          if (orm > (priorOrm[we.exerciseId] ?? 0)) {
            priorOrm[we.exerciseId] = orm;
          }
        }
      }
    }

    // The session's best set per exercise (heaviest weight and the reps at it),
    // plus its best estimated one-rep max.
    final bestWeight = <int, double>{};
    final bestReps = <int, int>{};
    final bestOrm = <int, double>{};
    for (final we in saved.exercises) {
      for (final s in we.sets) {
        final wt = s.weight;
        final r = s.reps;
        if (wt == null || r == null || wt <= 0) continue;
        if (wt > (bestWeight[we.exerciseId] ?? 0)) {
          bestWeight[we.exerciseId] = wt;
          bestReps[we.exerciseId] = r;
        }
        final orm = _epley(wt, r);
        if (orm > (bestOrm[we.exerciseId] ?? 0)) {
          bestOrm[we.exerciseId] = orm;
        }
      }
    }

    final prs = <PrHighlight>[];
    for (final id in bestWeight.keys) {
      if (!priorWeight.containsKey(id)) continue; // no prior history to beat
      final beatWeight = bestWeight[id]! > (priorWeight[id] ?? 0);
      final beatOrm = (bestOrm[id] ?? 0) > (priorOrm[id] ?? 0);
      if (beatWeight || beatOrm) {
        prs.add(
          PrHighlight(
            exerciseName: byId[id]?.name ?? 'Exercise',
            weight: bestWeight[id]!,
            reps: bestReps[id]!,
          ),
        );
      }
    }
    prs.sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    return prs;
  }

  /// Epley one-rep-max estimate, matching the analytics computation.
  static double _epley(double weight, int reps) =>
      reps <= 1 ? weight : weight * (1 + reps / 30.0);

  /// The exercises grouped into the units that drag moves: a contiguous run
  /// sharing a superset group is one block, and a standalone exercise is a
  /// block of one.
  ///
  /// Dragging blocks rather than individual cards is what keeps a superset's
  /// members adjacent. [_focusOrder] walks contiguous runs to build the
  /// interleaved A1, B1, A2 traversal, so an exercise dropped into the middle
  /// of a group would quietly corrupt it. Reordering *within* a group stays the
  /// superset menu's job.
  static List<List<_ExerciseEntry>> groupIntoBlocks(
    List<_ExerciseEntry> entries,
  ) => supersetBlocks(entries, (e) => e.supersetGroup);

  void _onReorderBlocks(int oldIndex, int newIndex) {
    setState(() {
      final reordered = moveSupersetBlock(
        _entries,
        (e) => e.supersetGroup,
        oldIndex,
        newIndex,
      );
      _entries
        ..clear()
        ..addAll(reordered);
    });
  }

  /// Picking a block up drops the number pad — it covers the bottom of the
  /// list, which is exactly where you are usually dragging to.
  void _onReorderStart(int _) {
    HapticFeedback.mediumImpact();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// One exercise card, wired to its position in [_entries].
  ///
  /// [dragIndex] is the *block* index the card belongs to, since drag moves
  /// superset groups whole.
  Widget _exerciseCardAt(int i, {required int dragIndex}) {
    return _ExerciseCard(
      entry: _entries[i],
      dragIndex: dragIndex,
      supersetColor: _supersetColor(_entries[i].supersetGroup),
      // The first card has nothing above it, the last nothing below, to pair
      // with.
      canSupersetWithPrevious: i > 0,
      canSupersetWithNext: i < _entries.length - 1,
      onSupersetWithPrevious: () => _supersetWithPrevious(i),
      onSupersetWithNext: () => _supersetWithNext(i),
      onLeaveSuperset: () => _leaveSuperset(i),
      onRestChanged: (v) => setState(() => _entries[i].restSeconds = v),
      onStartRest: () => _startRest(_entries[i].restSeconds),
      onSetCompleted: (s) => _completeSet(s, _entries[i].restSeconds),
      onChanged: () => setState(() {}),
      onRemove: () => setState(() {
        _entries.removeAt(i).dispose();
      }),
    );
  }

  /// What follows the finger while dragging.
  ///
  /// A full card runs to several hundred pixels once it has sets in it, which
  /// would blanket the list you are trying to aim at. This stands in a compact
  /// summary instead, so the drop target stays visible.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    final blocks = groupIntoBlocks(_entries);
    if (index < 0 || index >= blocks.length) return child;
    final block = blocks[index];
    final byId = ref.read(exercisesByIdProvider).value;

    return Material(
      color: Colors.transparent,
      child: _CollapsedDragCard(
        names: [
          for (final e in block) byId?[e.exerciseId]?.name ?? 'Exercise',
        ],
        setCount: block.fold<int>(0, (n, e) => n + e.sets.length),
        color: _supersetColor(block.first.supersetGroup) ?? AppColors.primary,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (_entries.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('This session has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static String? _emptyToNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final elapsed = _stopwatch?.elapsed;

    // Show the keyboard toolbar only while one of the numeric set fields holds
    // focus — not for the notes field, which has its own return key.
    final setNodes = <FocusNode>{
      for (final e in _entries)
        for (final s in e.sets) ...[s.weightFocus, s.repsFocus],
    };
    final focused = FocusManager.instance.primaryFocus;
    final activeField = (focused != null && setNodes.contains(focused))
        ? focused
        : null;
    final activeTarget = _activeFieldTarget(activeField);
    final order = activeField == null ? const <FocusNode>[] : _focusOrder();
    final isLastField =
        activeField != null && order.isNotEmpty && order.last == activeField;

    // Exercises grouped into the units drag moves, plus where each block starts
    // in _entries so the cards keep addressing their own positions.
    final blocks = groupIntoBlocks(_entries);
    final blockStarts = <int>[];
    var runningIndex = 0;
    for (final block in blocks) {
      blockStarts.add(runningIndex);
      runningIndex += block.length;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          leading: const GlassBackButton(icon: Icons.close),
          title: Text(isEdit ? 'Edit workout' : 'Log workout'),
          actions: [
            if (elapsed != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text(
                    _formatElapsed(elapsed),
                    style: AppTypography.numeric.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            GlassIconButton(
              icon: const Icon(Icons.check),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              // Slivers rather than a ListView: the exercise cards need to be
              // a SliverReorderableList while the surrounding content stays
              // ordinary boxes in the same scroll view.
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      glassTopInset(context) + AppSpacing.sm,
                      AppSpacing.md,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _entries.isEmpty
                          ? GlassCard(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.fitness_center,
                                    size: 40,
                                    color: AppColors.cta,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text('No exercises yet',
                                      style: AppTypography.h5),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Add exercises directly, or start from a '
                                    'template.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.small.copyWith(
                                      color: AppColors.mutedOnDark,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    sliver: SliverReorderableList(
                      itemCount: blocks.length,
                      onReorder: _onReorderBlocks,
                      onReorderStart: _onReorderStart,
                      proxyDecorator: _dragProxy,
                      itemBuilder: (context, blockIndex) {
                        final block = blocks[blockIndex];
                        final start = blockStarts[blockIndex];
                        return Column(
                          // Keyed on the block's first entry, which is a stable
                          // object across rebuilds; positions are not.
                          key: ObjectKey(block.first),
                          children: [
                            for (var j = 0; j < block.length; j++)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _exerciseCardAt(
                                  start + j,
                                  dragIndex: blockIndex,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      glassBottomInset(context),
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _addExercises,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add exercise'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _applyTemplate,
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('Template'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _sessionDetails(),
                          const SizedBox(height: AppSpacing.lg),
                          TextField(
                            controller: _notes,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Workout notes',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save workout'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_restRemaining > 0)
              _RestBar(
                remaining: _restRemaining,
                total: _restTotal,
                onAdd: () => _adjustRest(15),
                onSubtract: () => _adjustRest(-15),
                onSkip: _skipRest,
              ),
            if (activeTarget != null)
              _NumberPad(
                decimalEnabled: activeTarget.isWeight,
                isLastField: isLastField,
                onKey: (k) => _typeInto(
                  activeTarget.controller,
                  activeTarget.isWeight,
                  k,
                ),
                onBackspace: () => _backspaceIn(activeTarget.controller),
                onEnter: () => _enterFromField(activeField!),
                onCollapse: _collapseKeypad,
              ),
          ],
        ),
      ),
    );
  }

  /// Date, effort and template — the workout's metadata. Kept below the
  /// exercises so the logging surface leads with the work itself.
  Widget _sessionDetails() {
    return GlassSection(
      title: 'Session details',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today, size: 20),
            title: Text(DateFormat.yMMMEd().format(_date)),
            trailing: TextButton(
              onPressed: _pickDate,
              child: const Text('Change'),
            ),
          ),
          if (_templateName != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, size: 20),
              title: Text(_templateName!),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _templateName = null),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('Effort', style: AppTypography.caption),
              Expanded(
                child: Slider(
                  value: _effort.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_effort',
                  onChanged: (v) => setState(() => _effort = v.round()),
                ),
              ),
              Text(
                '$_effort/10',
                style: AppTypography.numeric.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required this.entry,
    required this.dragIndex,
    required this.supersetColor,
    required this.canSupersetWithPrevious,
    required this.canSupersetWithNext,
    required this.onSupersetWithPrevious,
    required this.onSupersetWithNext,
    required this.onLeaveSuperset,
    required this.onRestChanged,
    required this.onStartRest,
    required this.onSetCompleted,
    required this.onChanged,
    required this.onRemove,
  });

  final _ExerciseEntry entry;

  /// Index of the reorderable *block* this card sits in — a superset moves
  /// whole, so every member of a group shares one drag index.
  final int dragIndex;

  /// Non-null when this exercise belongs to a superset; the shared group color.
  final Color? supersetColor;
  final bool canSupersetWithPrevious;
  final bool canSupersetWithNext;
  final VoidCallback onSupersetWithPrevious;
  final VoidCallback onSupersetWithNext;
  final VoidCallback onLeaveSuperset;
  final ValueChanged<int> onRestChanged;
  final VoidCallback onStartRest;

  /// A set the user declared done — the screen marks it, starts rest and moves
  /// focus on, since only it knows the order sets are worked through.
  final ValueChanged<_SetEntry> onSetCompleted;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// One set row, swipeable to remove.
  ///
  /// Removal used to live on the trailing control, but that space is now the
  /// completion check — so it moves to a swipe, matching how rows are removed
  /// elsewhere in the app. The only remaining set stays put: an exercise with
  /// no sets has nothing to show.
  Widget _setRow(int i, List<WorkoutSet>? lastSets) {
    final row = _SetRow(
      index: i,
      set: entry.sets[i],
      // The set at the same position last time, if there was one.
      previousSet: (lastSets != null && i < lastSets.length)
          ? lastSets[i]
          : null,
      onCompleted: () => onSetCompleted(entry.sets[i]),
    );

    if (entry.sets.length == 1) return row;

    return Dismissible(
      key: ObjectKey(entry.sets[i]),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: const Icon(Icons.delete, size: 18, color: Colors.white),
      ),
      onDismissed: (_) {
        entry.sets.removeAt(i).dispose();
        onChanged();
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = ref.watch(exercisesByIdProvider).value?[entry.exerciseId];
    // The most recent time this exercise was logged, matched set-for-set below
    // the entry fields as a reference for what to beat.
    final lastSets = ref
        .watch(exerciseHistoryProvider(entry.exerciseId))
        .value
        ?.firstOrNull
        ?.sets;

    final card = GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (supersetColor != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.link, size: 14, color: supersetColor),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Superset',
                    style: AppTypography.small.copyWith(
                      color: supersetColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Drag starts from the grip, never from a long-press on the card
              // — the set fields are read-only with their own tap handler, and
              // a press anywhere would be ambiguous with them.
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  exercise?.name ?? 'Exercise',
                  style: AppTypography.h5,
                ),
              ),
              RestChip(seconds: entry.restSeconds, onChanged: onRestChanged),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) => switch (value) {
                  'start-rest' => onStartRest(),
                  'superset-prev' => onSupersetWithPrevious(),
                  'superset-next' => onSupersetWithNext(),
                  'leave' => onLeaveSuperset(),
                  'remove' => onRemove(),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (entry.restSeconds > 0)
                    const PopupMenuItem(
                      value: 'start-rest',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.timer_outlined),
                        title: Text('Start rest timer'),
                      ),
                    ),
                  if (canSupersetWithPrevious)
                    const PopupMenuItem(
                      value: 'superset-prev',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.arrow_upward),
                        title: Text('Superset with previous'),
                      ),
                    ),
                  if (canSupersetWithNext)
                    const PopupMenuItem(
                      value: 'superset-next',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.arrow_downward),
                        title: Text('Superset with next'),
                      ),
                    ),
                  if (entry.supersetGroup != null)
                    const PopupMenuItem(
                      value: 'leave',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.link_off),
                        title: Text('Leave superset'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Remove exercise'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (lastSets != null && lastSets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _VolumeBar(entry: entry, lastSets: lastSets),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const SizedBox(width: 28),
              Expanded(
                child: Text(
                  'Weight (lb)',
                  textAlign: TextAlign.center,
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Reps',
                  textAlign: TextAlign.center,
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < entry.sets.length; i++) _setRow(i, lastSets),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: () {
              // Carry the previous set's values forward — most sets repeat the
              // one before them, so this is usually the right starting point.
              final prev = entry.sets.lastOrNull;
              entry.sets.add(
                _SetEntry(weight: prev?.weight, reps: prev?.reps),
              );
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add set'),
          ),
        ],
      ),
    );

    // Ring grouped exercises in their shared color so a superset reads as one
    // unit even between the separate cards.
    if (supersetColor == null) return card;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: supersetColor!.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: card,
    );
  }
}

/// The compact stand-in that follows the finger while an exercise is dragged.
///
/// A superset shows every member, since the whole group travels together.
class _CollapsedDragCard extends StatelessWidget {
  const _CollapsedDragCard({
    required this.names,
    required this.setCount,
    required this.color,
  });

  final List<String> names;
  final int setCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkBlue,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in names)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.h6,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$setCount ${setCount == 1 ? 'set' : 'sets'}',
            style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
          ),
        ],
      ),
    );
  }
}

/// Whole numbers with thousands separators — volumes run to four figures fast.
String _volumeLabel(double value) =>
    NumberFormat.decimalPattern().format(value.round());

/// Work done on this exercise so far against the last time it was trained.
///
/// The bar fills toward the previous session's total, so a part-finished
/// exercise reads as "not there yet" rather than as a deficit. The pace figure
/// beside it is the honest comparison — this session against the same number of
/// sets last time — since a raw delta at set one of four is only ever a large
/// negative number.
///
/// Hidden entirely until the exercise has history to measure against.
class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.entry, required this.lastSets});

  final _ExerciseEntry entry;
  final List<WorkoutSet> lastSets;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final s in entry.sets) s.weightController,
        for (final s in entry.sets) s.repsController,
      ]),
      builder: (context, _) {
        final volume = VolumeComparison.of(
          current: [
            for (final s in entry.sets) (weight: s.weight, reps: s.reps),
          ],
          previous: [
            for (final s in lastSets) (weight: s.weight, reps: s.reps),
          ],
        );
        if (!volume.hasHistory) return const SizedBox.shrink();

        final beaten = volume.current >= volume.previousTotal;
        final tint = beaten ? AppColors.success : AppColors.primary;
        final delta = volume.paceDelta;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_volumeLabel(volume.current)}'
                    ' / ${_volumeLabel(volume.previousTotal)} ${volume.unit}',
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                ),
                if (delta != null && delta != 0)
                  Text(
                    '${delta > 0 ? '+' : '−'}'
                    '${_volumeLabel(delta.abs())} vs pace',
                    style: AppTypography.small.copyWith(
                      color: delta > 0 ? AppColors.success : AppColors.warning,
                    ),
                  )
                else if (beaten)
                  Text(
                    'Beat last session',
                    style: AppTypography.small.copyWith(
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: volume.progress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.cta,
                valueColor: AlwaysStoppedAnimation<Color>(tint),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.previousSet,
    required this.onCompleted,
  });

  final int index;
  final _SetEntry set;

  /// What was logged for this set position last time, shown greyed below the
  /// fields as a reference. Null when there is no matching historical set.
  final WorkoutSet? previousSet;

  /// Called when the set transitions to complete, so the exercise can start its
  /// rest timer — the same event as leaving a filled reps field.
  final VoidCallback onCompleted;

  /// Copies a historical value into a field that is still blank, so checking an
  /// untouched set records what you did last time rather than nothing.
  void _fillIfBlank(TextEditingController controller, String? value) {
    if (value == null || controller.text.trim().isNotEmpty) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _toggle() {
    if (set.isComplete) {
      set.completed.value = false;
      return;
    }

    _fillIfBlank(
      set.weightController,
      previousSet?.weight == null ? null : trimNumber(previousSet!.weight!),
    );
    _fillIfBlank(set.repsController, previousSet?.reps?.toString());

    // With nothing typed and no history to borrow, there is nothing to mark
    // complete — an empty set is dropped on save, so a check here would promise
    // a record that never gets written. Send the user to the field instead.
    if (set.isEmpty) {
      set.weightFocus.requestFocus();
      return;
    }

    onCompleted();
  }

  /// Tapping a greyed historical value fills its field; when that fills the
  /// last blank, the set is done and we move on — the third completing gesture,
  /// alongside the check and Next.
  void _onReferenceFilled() {
    if (!set.isFull || set.isComplete) return;
    onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final prevWeight = previousSet?.weight;
    final prevReps = previousSet?.reps;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: AppTypography.numeric.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
            ),
          ),
          Expanded(
            child: _FieldWithReference(
              controller: set.weightController,
              focusNode: set.weightFocus,
              reference: prevWeight == null ? null : trimNumber(prevWeight),
              onFilled: _onReferenceFilled,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FieldWithReference(
              controller: set.repsController,
              focusNode: set.repsFocus,
              reference: prevReps?.toString(),
              onFilled: _onReferenceFilled,
            ),
          ),
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              // Reacts live to the fields and to an explicit tap: a set with
              // reps still reads as done on its own, and the empty ring is a
              // real target you can hit to complete the set yourself.
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  set.weightController,
                  set.repsController,
                  set.completed,
                ]),
                builder: (context, _) {
                  final done = set.isComplete;
                  final animated = AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: done
                        ? const Icon(
                            Icons.check_circle,
                            key: ValueKey('done'),
                            size: 22,
                            color: AppColors.success,
                          )
                        : const Icon(
                            Icons.radio_button_unchecked,
                            key: ValueKey('open'),
                            size: 20,
                            color: AppColors.mutedOnDark,
                          ),
                  );
                  return IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: _toggle,
                    tooltip: done ? 'Mark set incomplete' : 'Mark set complete',
                    icon: animated,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A numeric entry field with the previous session's value greyed out beneath
/// it. The reference line always reserves its height so rows with and without
/// history stay aligned, and tapping it copies that value into the field.
///
/// The field is read-only so the system keyboard never appears — editing is
/// driven entirely by the in-app [_NumberPad], which the screen shows whenever
/// one of these holds focus.
class _FieldWithReference extends StatelessWidget {
  const _FieldWithReference({
    required this.controller,
    required this.focusNode,
    required this.reference,
    required this.onFilled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? reference;

  /// Called after the reference is copied in, so the row can complete itself
  /// when that was the last blank field.
  final VoidCallback onFilled;

  void _fillFromReference() {
    final value = reference;
    if (value == null) return;
    controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    onFilled();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: true,
          showCursor: true,
          textAlign: TextAlign.center,
          // Tapping focuses the field, which brings up the number pad.
          onTap: () => FocusScope.of(context).requestFocus(focusNode),
          decoration: const InputDecoration(isDense: true, hintText: '—'),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: reference == null ? null : _fillFromReference,
          child: Text(
            // A middle dot keeps the baseline when there is nothing to copy.
            reference ?? '·',
            textAlign: TextAlign.center,
            style: AppTypography.small.copyWith(
              color: AppColors.mutedOnDark,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// The running rest countdown, shown above the number pad. Reads out the time
/// left over a progress bar, with quick adjust and skip controls.
class _RestBar extends StatelessWidget {
  const _RestBar({
    required this.remaining,
    required this.total,
    required this.onAdd,
    required this.onSubtract,
    required this.onSkip,
  });

  final int remaining;
  final int total;
  final VoidCallback onAdd;
  final VoidCallback onSubtract;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cta,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Rest  ${formatRest(remaining)}',
                    style: AppTypography.numeric.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                  const Spacer(),
                  _RestControl(label: '-15', onTap: onSubtract),
                  const SizedBox(width: AppSpacing.xs),
                  _RestControl(label: '+15', onTap: onAdd),
                  const SizedBox(width: AppSpacing.xs),
                  _RestControl(label: 'Skip', onTap: onSkip, emphasized: true),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : remaining / total,
                  minHeight: 5,
                  backgroundColor: AppColors.dark,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestControl extends StatelessWidget {
  const _RestControl({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        foregroundColor: emphasized ? AppColors.primary : AppColors.onDark,
      ),
      child: Text(label),
    );
  }
}

/// The app's own numeric keypad, shown in place of the system keyboard while a
/// set field is focused. Its Enter key advances to the next field — the whole
/// point of a custom pad, since iOS's number pad has no return key.
class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.onKey,
    required this.onBackspace,
    required this.onEnter,
    required this.onCollapse,
    required this.decimalEnabled,
    required this.isLastField,
  });

  final void Function(String) onKey;
  final VoidCallback onBackspace;
  final VoidCallback onEnter;

  /// Dismisses the pad by dropping focus from the active field. Lets the user
  /// reach content the pad would otherwise cover without leaving the screen.
  final VoidCallback onCollapse;

  /// Reps are whole numbers, so the decimal key is disabled for them.
  final bool decimalEnabled;

  /// The Enter key reads "Done" on the workout's final field, since there is
  /// nothing after it to advance to.
  final bool isLastField;

  @override
  Widget build(BuildContext context) {
    // Keep the pad out of the focus tree so tapping keys never pulls focus off
    // the active field. Stretch so the tall Enter key fills the pad height.
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Material(
        color: AppColors.darkBlue,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CollapseBar(onTap: onCollapse),
                SizedBox(
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _row(['1', '2', '3']),
                            _row(['4', '5', '6']),
                            _row(['7', '8', '9']),
                            Expanded(
                              child: Row(
                                children: [
                                  _key(
                                    label: '.',
                                    onTap:
                                        decimalEnabled ? () => onKey('.') : null,
                                  ),
                                  _key(label: '0', onTap: () => onKey('0')),
                                  _key(
                                    onTap: onBackspace,
                                    child:
                                        const Icon(Icons.backspace_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _button(
                          onTap: onEnter,
                          background: AppColors.primary,
                          foreground: AppColors.onPrimary,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.keyboard_return),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                isLastField ? 'Done' : 'Next',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One row of the digit grid; each key shares the width equally.
  Widget _row(List<String> labels) => Expanded(
    child: Row(
      children: [
        for (final l in labels) _key(label: l, onTap: () => onKey(l)),
      ],
    ),
  );

  /// A key sized to share its row's width equally.
  Widget _key({String? label, Widget? child, VoidCallback? onTap}) =>
      Expanded(child: _button(label: label, child: child, onTap: onTap));

  /// The visual key itself, filling whatever box it is given.
  Widget _button({
    String? label,
    Widget? child,
    VoidCallback? onTap,
    Color? background,
    Color? foreground,
  }) {
    final fg = onTap == null
        ? AppColors.mutedOnDark
        : (foreground ?? AppColors.onDark);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: background ?? AppColors.cta,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          onTap: onTap,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: fg),
              child:
                  child ??
                  Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dismiss affordance across the top of the number pad: a centered grab
/// handle with a chevron, the whole bar tappable to collapse the pad.
class _CollapseBar extends StatelessWidget {
  const _CollapseBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: SizedBox(
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cta,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: AppColors.mutedOnDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One exercise being composed, holding its own set rows.
class _ExerciseEntry {
  _ExerciseEntry({
    required this.exerciseId,
    this.notes,
    this.supersetGroup,
    this.restSeconds = 90,
    required List<_SetEntry> sets,
  }) : sets = List.of(sets);

  final int exerciseId;
  final String? notes;
  final List<_SetEntry> sets;

  /// Group id shared with other exercises supersetted with this one; null when
  /// standalone. Mutable — set and cleared by the superset menu actions.
  int? supersetGroup;

  /// Rest between sets, in seconds (0 = off). Mutable — set via the rest chip.
  int restSeconds;

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

/// A set row's live text, kept in controllers so partially-typed values
/// survive rebuilds.
class _SetEntry {
  _SetEntry({double? weight, int? reps, bool complete = false})
    : weightController = TextEditingController(
        text: weight == null ? '' : trimNumber(weight),
      ),
      repsController = TextEditingController(
        text: reps?.toString() ?? '',
      ),
      completed = ValueNotifier(complete);

  final TextEditingController weightController;
  final TextEditingController repsController;
  final FocusNode weightFocus = FocusNode();
  final FocusNode repsFocus = FocusNode();

  /// Whether the user has declared this set done.
  ///
  /// Completion is deliberately never inferred from the fields: typing a rep
  /// count means you are entering a set, not that you finished it. Only three
  /// gestures set this — tapping the check, pressing Next off a full set, and
  /// tapping a historical value that fills the last blank. Sets rehydrated from
  /// a saved workout start complete, since they were performed.
  final ValueNotifier<bool> completed;

  double? get weight => double.tryParse(weightController.text.trim());

  int? get reps => int.tryParse(repsController.text.trim());

  bool get isEmpty => weight == null && reps == null;

  /// Both fields carry a value, which is what the completing gestures require.
  bool get isFull =>
      weightController.text.trim().isNotEmpty &&
      repsController.text.trim().isNotEmpty;

  /// A row emptied after the fact drops its check: empty sets are dropped on
  /// save, so the mark would advertise a record that never gets written.
  bool get isComplete => completed.value && !isEmpty;

  void dispose() {
    weightController.dispose();
    repsController.dispose();
    weightFocus.dispose();
    repsFocus.dispose();
    completed.dispose();
  }
}
