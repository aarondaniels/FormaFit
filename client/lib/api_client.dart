/// On-device storage and all derived-value computation.
///
/// Everything the app knows lives in one JSON file in the documents
/// directory. There is no network layer: the class keeps the `ApiClient` name
/// from when it wrapped a FastAPI backend so call sites read the same, but
/// every method here is a local read-modify-write.
library;

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import 'data/default_library.dart';
import 'models.dart';

/// Hours of rest each muscle group needs before it is considered recovered.
const Map<String, int> _recoveryHours = {
  MuscleGroups.chest: 48,
  MuscleGroups.back: 48,
  MuscleGroups.shoulders: 48,
  MuscleGroups.arms: 24,
  MuscleGroups.legs: 72,
  MuscleGroups.core: 24,
  MuscleGroups.glutes: 72,
  MuscleGroups.calves: 24,
};

/// Free-form muscle group strings are matched against these substrings to map
/// an exercise onto one of the tracked groups.
const Map<String, List<String>> _muscleAliases = {
  MuscleGroups.chest: ['chest', 'pectoralis', 'pecs'],
  MuscleGroups.back: [
    'back',
    'latissimus',
    'lats',
    'rhomboids',
    'trapezius',
    'traps',
  ],
  MuscleGroups.shoulders: ['shoulders', 'deltoids', 'delts'],
  MuscleGroups.arms: ['biceps', 'triceps', 'forearms', 'arms'],
  MuscleGroups.legs: ['quadriceps', 'quads', 'hamstrings', 'hams', 'thighs'],
  MuscleGroups.core: ['core', 'abs', 'abdominals', 'obliques'],
  MuscleGroups.glutes: ['glutes', 'gluteus', 'butt'],
  MuscleGroups.calves: ['calves', 'gastrocnemius', 'soleus'],
};

/// Sessions for one muscle group within this window count toward fatigue.
const int _fatigueWindowDays = 7;

/// Sessions per group per week that read as a full fatigue load.
const int _fatigueSaturationSessions = 4;

/// Equipment words that Strong appends in parentheses ("Bench Press
/// (Barbell)") and that Forma bakes into names ("Barbell Bench Press"). Pulled
/// out of the name so the two styles match on the movement itself.
const Set<String> _equipmentWords = {
  'barbell',
  'dumbbell',
  'cable',
  'machine',
  'bodyweight',
  'kettlebell',
  'band',
  'resistance',
  'smith',
  'ez',
  'plate',
  'weighted',
  'assisted',
  'lever',
  'sled',
  'trap',
  'hex',
};

/// Strips a simple trailing plural so "Squats"/"Squat" and "Curls"/"Curl"
/// collapse together. Leaves "press", "-us" words and short words alone.
String _stemPlural(String w) {
  // > 2 so 3-letter plurals like "ups" (Pull-ups) reduce to "up". Applied to
  // both library and imported names, so it only has to be consistent.
  if (w.length > 2 &&
      w.endsWith('s') &&
      !w.endsWith('ss') &&
      !w.endsWith('us')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// Normalizes an exercise name to a `(base, equipment)` pair so names in
/// Strong's "Movement (Equipment)" form match Forma's "Equipment Movement"
/// form. The base is order-independent (sorted, de-pluralized movement words);
/// equipment is kept aside to disambiguate variants that share a base.
({String base, Set<String> equipment}) _normalizeExerciseName(String name) {
  final words = name
      .toLowerCase()
      .replaceAll(RegExp(r'[()]'), ' ')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .map(_stemPlural);
  final base = <String>{};
  final equipment = <String>{};
  for (final w in words) {
    (_equipmentWords.contains(w) ? equipment : base).add(w);
  }
  final sortedBase = base.toList()..sort();
  return (base: sortedBase.join(' '), equipment: equipment);
}

/// Raised when an import file can't be used, so the UI can explain why
/// instead of surfacing a decode error.
class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient();

  _AppData? _cache;

  /// Serializes mutations so overlapping read-modify-write cycles (and their
  /// file writes) can't interleave and lose data.
  Future<void> _writeQueue = Future.value();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> get _storageFile async {
    // If the documents directory is unavailable, let the error propagate to
    // the UI rather than silently writing to a volatile location.
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/forma_data.json');
  }

  Future<_AppData> _load() async {
    if (_cache != null) return _cache!;
    final file = await _storageFile;
    if (await file.exists()) {
      try {
        final contents = await file.readAsString();
        _cache = _AppData.fromJson(jsonDecode(contents) as Map<String, dynamic>);
      } catch (_) {
        // Never silently discard user data: set the unreadable file aside for
        // manual recovery, then start fresh.
        final backupPath =
            '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        await file.rename(backupPath);
        _cache = _AppData.seeded();
        await _persist();
      }
    } else {
      _cache = _AppData.seeded();
      await _persist();
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final data = _cache;
    if (data == null) return;
    final file = await _storageFile;
    // Atomic write: flush to a temp file, then rename over the live file so a
    // crash mid-write can never leave it truncated.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  // -------------------------------------------------------------------------
  // Equipment types
  // -------------------------------------------------------------------------

  Future<List<EquipmentType>> listEquipmentTypes() async {
    final data = await _load();
    return List.unmodifiable(
      [...data.equipmentTypes]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  Future<EquipmentType> createEquipmentType({
    required String name,
    String? description,
    String? icon,
    String? category,
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = EquipmentType(
        id: data.nextEquipmentTypeId++,
        name: name,
        description: description,
        icon: icon,
        category: category,
      );
      data.equipmentTypes.add(created);
      await _persist();
      return created;
    });
  }

  Future<EquipmentType> updateEquipmentType(EquipmentType updated) {
    return _mutate(() async {
      final data = await _load();
      final i = data.equipmentTypes.indexWhere((e) => e.id == updated.id);
      if (i == -1) throw StateError('No equipment type ${updated.id}');
      data.equipmentTypes[i] = updated;
      await _persist();
      return updated;
    });
  }

  Future<void> deleteEquipmentType(int id) {
    return _mutate(() async {
      final data = await _load();
      data.equipmentTypes.removeWhere((e) => e.id == id);
      // Exercises outlive their equipment type rather than being deleted with
      // it; they just lose the association.
      for (var i = 0; i < data.exercises.length; i++) {
        if (data.exercises[i].equipmentTypeId == id) {
          data.exercises[i] = data.exercises[i].copyWith(equipmentTypeId: null);
        }
      }
      await _persist();
    });
  }

  // -------------------------------------------------------------------------
  // Exercises
  // -------------------------------------------------------------------------

  Future<List<Exercise>> listExercises() async {
    final data = await _load();
    return List.unmodifiable(
      [...data.exercises]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  Future<Exercise> createExercise({
    required String name,
    String? muscleGroup,
    String? description,
    int? equipmentTypeId,
    String? instructions,
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = Exercise(
        id: data.nextExerciseId++,
        name: name,
        muscleGroup: muscleGroup,
        description: description,
        equipmentTypeId: equipmentTypeId,
        instructions: instructions,
      );
      data.exercises.add(created);
      await _persist();
      return created;
    });
  }

  Future<Exercise> updateExercise(Exercise updated) {
    return _mutate(() async {
      final data = await _load();
      final i = data.exercises.indexWhere((e) => e.id == updated.id);
      if (i == -1) throw StateError('No exercise ${updated.id}');
      data.exercises[i] = updated;
      await _persist();
      return updated;
    });
  }

  /// Removes an exercise and every reference to it.
  ///
  /// Logged sets for the exercise go with it — leaving orphaned history that
  /// renders as a blank row would be worse than removing it outright, and the
  /// UI warns before calling this.
  Future<void> deleteExercise(int id) {
    return _mutate(() async {
      final data = await _load();
      data.exercises.removeWhere((e) => e.id == id);
      for (var i = 0; i < data.workouts.length; i++) {
        final w = data.workouts[i];
        final kept = w.exercises.where((e) => e.exerciseId != id).toList();
        if (kept.length != w.exercises.length) {
          data.workouts[i] = w.copyWith(exercises: kept);
        }
      }
      for (var i = 0; i < data.templates.length; i++) {
        final t = data.templates[i];
        final kept = t.exercises.where((e) => e.exerciseId != id).toList();
        if (kept.length != t.exercises.length) {
          data.templates[i] = t.copyWith(exercises: _reorder(kept));
        }
      }
      await _persist();
    });
  }

  /// Consolidates a duplicate exercise into another: moves every logged set and
  /// template reference from [sourceId] onto [targetId], then removes the
  /// source. Where a single workout ends up with the target exercise twice its
  /// sets are combined into one entry; a template that ends up referencing it
  /// twice keeps the first reference.
  Future<void> mergeExercise({
    required int sourceId,
    required int targetId,
  }) {
    return _mutate(() async {
      final data = await _load();
      if (sourceId == targetId) return;
      if (!data.exercises.any((e) => e.id == targetId)) {
        throw StateError('No target exercise $targetId');
      }

      for (var i = 0; i < data.workouts.length; i++) {
        final w = data.workouts[i];
        if (!w.exercises.any((we) => we.exerciseId == sourceId)) continue;
        final repointed = [
          for (final we in w.exercises)
            we.exerciseId == sourceId
                ? we.copyWith(exerciseId: targetId)
                : we,
        ];
        data.workouts[i] = w.copyWith(
          exercises: _mergeSameExercise(repointed),
        );
      }

      for (var i = 0; i < data.templates.length; i++) {
        final t = data.templates[i];
        if (!t.exercises.any((te) => te.exerciseId == sourceId)) continue;
        final repointed = [
          for (final te in t.exercises)
            te.exerciseId == sourceId
                ? te.copyWith(exerciseId: targetId)
                : te,
        ];
        final seen = <int>{};
        final kept = [
          for (final te in repointed)
            if (seen.add(te.exerciseId)) te,
        ];
        data.templates[i] = t.copyWith(exercises: _reorder(kept));
      }

      data.exercises.removeWhere((e) => e.id == sourceId);
      await _persist();
    });
  }

  /// Folds workout-exercise entries that share an exercise id into one, in
  /// first-seen order, concatenating and renumbering their sets.
  static List<WorkoutExercise> _mergeSameExercise(List<WorkoutExercise> list) {
    final order = <int>[];
    final byId = <int, WorkoutExercise>{};
    for (final we in list) {
      final existing = byId[we.exerciseId];
      if (existing == null) {
        order.add(we.exerciseId);
        byId[we.exerciseId] = we;
      } else {
        byId[we.exerciseId] = existing.copyWith(
          sets: [...existing.sets, ...we.sets],
          notes: existing.notes ?? we.notes,
        );
      }
    }
    return [
      for (final id in order)
        byId[id]!.copyWith(
          sets: [
            for (var (i, s) in byId[id]!.sets.indexed)
              s.copyWith(setNumber: i + 1),
          ],
        ),
    ];
  }

  /// Re-adds any seeded exercises the user deleted, leaving their own entries
  /// and any edits to surviving seeds untouched.
  Future<int> restoreDefaultExercises() {
    return _mutate(() async {
      final data = await _load();
      final present = data.exercises.map((e) => e.id).toSet();
      final missingEquipment = defaultEquipmentTypes().where(
        (e) => !data.equipmentTypes.any((x) => x.id == e.id),
      );
      data.equipmentTypes.addAll(missingEquipment);

      final missing = defaultExercises()
          .where((e) => !present.contains(e.id))
          .toList();
      data.exercises.addAll(missing);
      await _persist();
      return missing.length;
    });
  }

  // -------------------------------------------------------------------------
  // Workouts
  // -------------------------------------------------------------------------

  /// All workouts, most recent first.
  Future<List<Workout>> listWorkouts() async {
    final data = await _load();
    return List.unmodifiable(
      [...data.workouts]..sort((a, b) => b.date.compareTo(a.date)),
    );
  }

  Future<Workout?> getWorkout(int id) async {
    final data = await _load();
    for (final w in data.workouts) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Creates a workout together with its exercises and sets.
  ///
  /// The whole session is written in one shot: a workout with no sets is not a
  /// useful intermediate state to persist, and one write keeps the file
  /// consistent if the app dies mid-log.
  Future<Workout> createWorkout({
    required DateTime date,
    required int effortLevel,
    String? notes,
    String? templateName,
    int? duration,
    List<WorkoutExerciseDraft> exercises = const [],
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = Workout(
        id: data.nextWorkoutId++,
        date: date,
        effortLevel: effortLevel,
        notes: notes,
        templateName: templateName,
        duration: duration,
        exercises: _materialize(data, exercises),
      );
      data.workouts.add(created);
      await _persist();
      return created;
    });
  }

  Future<Workout> updateWorkout({
    required int id,
    DateTime? date,
    int? effortLevel,
    String? notes,
    int? duration,
    List<WorkoutExerciseDraft>? exercises,
  }) {
    return _mutate(() async {
      final data = await _load();
      final i = data.workouts.indexWhere((w) => w.id == id);
      if (i == -1) throw StateError('No workout $id');
      final updated = data.workouts[i].copyWith(
        date: date,
        effortLevel: effortLevel,
        notes: notes,
        duration: duration,
        exercises: exercises == null ? null : _materialize(data, exercises),
      );
      data.workouts[i] = updated;
      await _persist();
      return updated;
    });
  }

  Future<void> deleteWorkout(int id) {
    return _mutate(() async {
      final data = await _load();
      data.workouts.removeWhere((w) => w.id == id);
      await _persist();
    });
  }

  /// Turns drafts into stored records, assigning ids and normalizing set
  /// numbering so gaps left by deleted sets don't reach the file.
  List<WorkoutExercise> _materialize(
    _AppData data,
    List<WorkoutExerciseDraft> drafts,
  ) {
    return drafts.map((d) {
      var setNumber = 1;
      return WorkoutExercise(
        id: data.nextWorkoutExerciseId++,
        exerciseId: d.exerciseId,
        notes: d.notes,
        supersetGroup: d.supersetGroup,
        restSeconds: d.restSeconds,
        sets: d.sets
            .map(
              (s) => WorkoutSet(
                id: data.nextWorkoutSetId++,
                setNumber: setNumber++,
                weight: s.weight,
                reps: s.reps,
              ),
            )
            .toList(),
      );
    }).toList();
  }

  /// Every logged set for one exercise, newest session first, for history and
  /// "last time you did this" prompts during logging.
  Future<List<ExerciseSession>> exerciseHistory(int exerciseId) async {
    final data = await _load();
    final sessions = <ExerciseSession>[];
    for (final w in data.workouts) {
      for (final we in w.exercises) {
        if (we.exerciseId != exerciseId) continue;
        sessions.add(
          ExerciseSession(
            workoutId: w.id,
            date: w.date,
            notes: we.notes,
            sets: we.sets,
          ),
        );
      }
    }
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(sessions);
  }

  // -------------------------------------------------------------------------
  // Template folders and templates
  // -------------------------------------------------------------------------

  Future<List<TemplateFolder>> listFolders() async {
    final data = await _load();
    return List.unmodifiable(
      [...data.folders]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  Future<TemplateFolder> createFolder({
    required String name,
    String? description,
  }) {
    return _mutate(() async {
      final data = await _load();
      final trimmed = name.trim();
      // The server rejected duplicate names per user; keep that rule so the
      // folder list stays unambiguous.
      final clash = data.folders.any(
        (f) => f.name.toLowerCase() == trimmed.toLowerCase(),
      );
      if (clash) throw StateError('A folder named "$trimmed" already exists');
      final created = TemplateFolder(
        id: data.nextFolderId++,
        name: trimmed,
        description: description,
        createdAt: DateTime.now(),
      );
      data.folders.add(created);
      await _persist();
      return created;
    });
  }

  Future<TemplateFolder> updateFolder(TemplateFolder updated) {
    return _mutate(() async {
      final data = await _load();
      final i = data.folders.indexWhere((f) => f.id == updated.id);
      if (i == -1) throw StateError('No folder ${updated.id}');
      data.folders[i] = updated;
      await _persist();
      return updated;
    });
  }

  /// Deletes a folder and the templates filed under it.
  Future<void> deleteFolder(int id) {
    return _mutate(() async {
      final data = await _load();
      data.folders.removeWhere((f) => f.id == id);
      data.templates.removeWhere((t) => t.folderId == id);
      await _persist();
    });
  }

  Future<List<Template>> listTemplates({int? folderId}) async {
    final data = await _load();
    final filtered = data.templates
        .where((t) => folderId == null || t.folderId == folderId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(filtered);
  }

  Future<Template?> getTemplate(int id) async {
    final data = await _load();
    for (final t in data.templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<Template> createTemplate({
    required int folderId,
    required String name,
    required List<TemplateExercise> exercises,
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = Template(
        id: data.nextTemplateId++,
        folderId: folderId,
        name: name.trim(),
        createdAt: DateTime.now(),
        exercises: _reorder(exercises),
      );
      data.templates.add(created);
      await _persist();
      return created;
    });
  }

  Future<Template> updateTemplate({
    required int id,
    int? folderId,
    String? name,
    List<TemplateExercise>? exercises,
  }) {
    return _mutate(() async {
      final data = await _load();
      final i = data.templates.indexWhere((t) => t.id == id);
      if (i == -1) throw StateError('No template $id');
      data.templates[i] = data.templates[i].copyWith(
        folderId: folderId,
        name: name?.trim(),
        exercises: exercises == null ? null : _reorder(exercises),
      );
      await _persist();
      return data.templates[i];
    });
  }

  Future<void> deleteTemplate(int id) {
    return _mutate(() async {
      final data = await _load();
      data.templates.removeWhere((t) => t.id == id);
      await _persist();
    });
  }

  /// Renumbers `order` to match list position so reordering in the UI doesn't
  /// have to keep the field consistent itself.
  static List<TemplateExercise> _reorder(List<TemplateExercise> exercises) {
    var order = 0;
    return exercises.map((e) => e.copyWith(order: order++)).toList();
  }

  // -------------------------------------------------------------------------
  // Measurements
  // -------------------------------------------------------------------------

  /// All measurements, newest first.
  Future<List<Measurement>> listMeasurements({String? kind}) async {
    final data = await _load();
    final filtered =
        data.measurements.where((m) => kind == null || m.kind == kind).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(filtered);
  }

  Future<Measurement> createMeasurement({
    required DateTime date,
    required String kind,
    required double value,
    String? unit,
    String? notes,
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = Measurement(
        id: data.nextMeasurementId++,
        date: date,
        kind: kind,
        value: value,
        unit: unit ?? MeasurementKinds.unitFor(kind),
        notes: notes,
      );
      data.measurements.add(created);
      await _persist();
      return created;
    });
  }

  /// Records several kinds taken in one sitting.
  ///
  /// Measuring is a batch act — the tape comes out once — so the whole session
  /// is a single queued write and a single file flush rather than one per
  /// value. Drafts with no value are the caller's to filter; anything passed
  /// here is stored.
  Future<List<Measurement>> createMeasurements({
    required DateTime date,
    required List<MeasurementDraft> entries,
  }) {
    return _mutate(() async {
      final data = await _load();
      final created = <Measurement>[];
      for (final draft in entries) {
        created.add(
          Measurement(
            id: data.nextMeasurementId++,
            date: date,
            kind: draft.kind,
            value: draft.value,
            unit: draft.unit ?? MeasurementKinds.unitFor(draft.kind),
            notes: draft.notes,
          ),
        );
      }
      data.measurements.addAll(created);
      await _persist();
      return List.unmodifiable(created);
    });
  }

  Future<Measurement> updateMeasurement(Measurement updated) {
    return _mutate(() async {
      final data = await _load();
      final i = data.measurements.indexWhere((m) => m.id == updated.id);
      if (i == -1) throw StateError('No measurement ${updated.id}');
      data.measurements[i] = updated;
      await _persist();
      return updated;
    });
  }

  Future<void> deleteMeasurement(int id) {
    return _mutate(() async {
      final data = await _load();
      data.measurements.removeWhere((m) => m.id == id);
      await _persist();
    });
  }

  /// Values for one measurement kind as a chart series, oldest first.
  Future<List<TimePoint>> measurementSeries(String kind) async {
    final entries = await listMeasurements(kind: kind);
    final points = entries
        .map((m) => TimePoint(m.date, m.value))
        .toList()
        .reversed
        .toList();
    return List.unmodifiable(points);
  }

  /// One summary per kind that has been measured at least once, in the order
  /// [MeasurementKinds.all] declares with any user-invented kinds after.
  ///
  /// Kinds with no entries are left out entirely: the overview is a record of
  /// what is actually being tracked, not a checklist of what could be.
  Future<List<MeasurementSummary>> measurementSummaries() async {
    final data = await _load();
    final byKind = <String, List<Measurement>>{};
    for (final m in data.measurements) {
      byKind.putIfAbsent(m.kind, () => []).add(m);
    }

    final summaries = <MeasurementSummary>[];
    for (final entry in byKind.entries) {
      final sorted = [...entry.value]..sort((a, b) => a.date.compareTo(b.date));
      final latest = sorted.last;
      summaries.add(
        MeasurementSummary(
          kind: entry.key,
          unit: latest.unit,
          latest: latest.value,
          latestDate: latest.date,
          changeOverall: sorted.length >= 2
              ? latest.value - sorted.first.value
              : null,
          changeLast: sorted.length >= 2
              ? latest.value - sorted[sorted.length - 2].value
              : null,
          entryCount: sorted.length,
          series: List.unmodifiable([
            for (final m in sorted) TimePoint(m.date, m.value),
          ]),
        ),
      );
    }

    summaries.sort((a, b) {
      final byOrder = MeasurementKinds.orderOf(
        a.kind,
      ).compareTo(MeasurementKinds.orderOf(b.kind));
      return byOrder != 0 ? byOrder : a.kind.compareTo(b.kind);
    });
    return List.unmodifiable(summaries);
  }

  /// Trailing average over [windowDays], for series noisy enough that the raw
  /// line hides the trend — body weight above all, where day-to-day water
  /// swings dwarf the change anyone is actually looking for.
  ///
  /// Each point averages every value within the preceding window (inclusive),
  /// so the result is defined from the first point on and never runs ahead of
  /// the data. Fewer than two points has no trend to draw.
  static List<TimePoint> rollingAverage(
    List<TimePoint> points, {
    int windowDays = 7,
  }) {
    if (points.length < 2) return const [];
    final smoothed = <TimePoint>[];
    for (var i = 0; i < points.length; i++) {
      final cutoff = points[i].date.subtract(Duration(days: windowDays));
      var sum = 0.0;
      var count = 0;
      // Walk back while inside the window; points are oldest first.
      for (var j = i; j >= 0; j--) {
        if (points[j].date.isBefore(cutoff)) break;
        sum += points[j].value;
        count++;
      }
      smoothed.add(TimePoint(points[i].date, sum / count));
    }
    return List.unmodifiable(smoothed);
  }

  // -------------------------------------------------------------------------
  // Derived values
  // -------------------------------------------------------------------------

  Future<WorkoutStats> stats() async {
    final data = await _load();
    final workouts = data.workouts;
    if (workouts.isEmpty) return WorkoutStats.empty;

    final byId = {for (final e in data.exercises) e.id: e};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = _weekStart(today);
    final monthStart = DateTime(today.year, today.month);

    var totalSets = 0;
    var totalVolume = 0.0;
    var totalDuration = 0;
    var effortSum = 0;
    var thisWeek = 0;
    var thisMonth = 0;
    final volumeByWeek = <DateTime, double>{};
    final countByWeek = <DateTime, int>{};
    final volumeByMuscle = <String, double>{};

    for (final w in workouts) {
      totalSets += w.setCount;
      totalVolume += w.volume;
      totalDuration += w.duration ?? 0;
      effortSum += w.effortLevel;

      final day = DateTime(w.date.year, w.date.month, w.date.day);
      if (!day.isBefore(weekStart)) thisWeek++;
      if (!day.isBefore(monthStart)) thisMonth++;

      final bucket = _weekStart(day);
      volumeByWeek[bucket] = (volumeByWeek[bucket] ?? 0) + w.volume;
      countByWeek[bucket] = (countByWeek[bucket] ?? 0) + 1;

      for (final we in w.exercises) {
        final group = _groupFor(byId[we.exerciseId]);
        volumeByMuscle[group] = (volumeByMuscle[group] ?? 0) + we.volume;
      }
    }

    return WorkoutStats(
      totalWorkouts: workouts.length,
      totalSets: totalSets,
      totalVolume: totalVolume,
      totalDuration: totalDuration,
      workoutsThisWeek: thisWeek,
      workoutsThisMonth: thisMonth,
      weekStreak: _weekStreak(countByWeek.keys.toSet(), weekStart),
      averageEffort: effortSum / workouts.length,
      volumeByWeek: _series(volumeByWeek),
      frequencyByWeek: _series(
        countByWeek.map((k, v) => MapEntry(k, v.toDouble())),
      ),
      volumeByMuscleGroup: Map.unmodifiable(volumeByMuscle),
      personalRecords: _personalRecords(workouts, byId),
    );
  }

  /// Per-session progression for one exercise, oldest first.
  Future<ExerciseProgress> exerciseProgress(int exerciseId) async {
    final data = await _load();
    final exercise = data.exercises.firstWhere(
      (e) => e.id == exerciseId,
      orElse: () => Exercise(id: exerciseId, name: 'Unknown exercise'),
    );

    final topWeight = <TimePoint>[];
    final volume = <TimePoint>[];
    final oneRepMax = <TimePoint>[];
    final reps = <TimePoint>[];

    final sorted = [...data.workouts]..sort((a, b) => a.date.compareTo(b.date));
    for (final w in sorted) {
      for (final we in w.exercises) {
        if (we.exerciseId != exerciseId) continue;
        final top = we.topWeight;
        if (top != null) topWeight.add(TimePoint(w.date, top));
        if (we.volume > 0) volume.add(TimePoint(w.date, we.volume));
        final orm = _bestOneRepMax(we.sets);
        if (orm != null) oneRepMax.add(TimePoint(w.date, orm));
        final totalReps = we.sets.fold<int>(0, (sum, s) => sum + (s.reps ?? 0));
        if (totalReps > 0) reps.add(TimePoint(w.date, totalReps.toDouble()));
      }
    }

    return ExerciseProgress(
      exerciseId: exerciseId,
      exerciseName: exercise.name,
      topWeight: List.unmodifiable(topWeight),
      volume: List.unmodifiable(volume),
      estimatedOneRepMax: List.unmodifiable(oneRepMax),
      reps: List.unmodifiable(reps),
    );
  }

  Future<List<MuscleRecovery>> muscleRecovery() async {
    final data = await _load();
    final byId = {for (final e in data.exercises) e.id: e};
    final now = DateTime.now();
    final fatigueCutoff = now.subtract(
      const Duration(days: _fatigueWindowDays),
    );

    final lastWorked = <String, DateTime>{};
    final recentSessions = <String, int>{};

    for (final w in data.workouts) {
      // A group can appear in several exercises of one workout; count the
      // session once so fatigue tracks sessions, not exercise selection.
      final groups = <String>{
        for (final we in w.exercises) _groupFor(byId[we.exerciseId]),
      };
      for (final g in groups) {
        final prev = lastWorked[g];
        if (prev == null || w.date.isAfter(prev)) lastWorked[g] = w.date;
        if (w.date.isAfter(fatigueCutoff)) {
          recentSessions[g] = (recentSessions[g] ?? 0) + 1;
        }
      }
    }

    return List.unmodifiable(
      MuscleGroups.all.map((group) {
        final last = lastWorked[group];
        final needed = _recoveryHours[group] ?? 48;

        if (last == null) {
          return MuscleRecovery(
            muscleGroup: group,
            recoveryPercentage: 1.0,
            lastWorked: null,
            daysSinceLastWorkout: null,
            fatigueLevel: 0,
            status: RecoveryStatus.untrained,
            recommendation: 'Not trained yet — a good place to start.',
          );
        }

        final elapsed = now.difference(last);
        final recovery = (elapsed.inMinutes / (needed * 60)).clamp(0.0, 1.0);
        final sessions = recentSessions[group] ?? 0;
        final fatigue = (sessions / _fatigueSaturationSessions).clamp(0.0, 1.0);
        final days = elapsed.inDays;

        // Frequent training keeps a group "overworked" even once the clock
        // says it is recovered, which is the signal worth surfacing.
        final status = fatigue >= 1.0 && recovery < 1.0
            ? RecoveryStatus.overworked
            : recovery >= 1.0
            ? RecoveryStatus.ready
            : RecoveryStatus.recovering;

        return MuscleRecovery(
          muscleGroup: group,
          recoveryPercentage: recovery.toDouble(),
          lastWorked: last,
          daysSinceLastWorkout: days,
          fatigueLevel: fatigue.toDouble(),
          status: status,
          recommendation: switch (status) {
            RecoveryStatus.ready =>
              days >= 7
                  ? 'Recovered, and it has been $days days — time to train it.'
                  : 'Recovered and ready to train.',
            RecoveryStatus.recovering =>
              'Still recovering — about ${_hoursRemaining(elapsed, needed)} to go.',
            RecoveryStatus.overworked =>
              'Trained $sessions times in the last week and not yet recovered. '
                  'Consider resting it.',
            RecoveryStatus.untrained => 'Not trained yet.',
          },
        );
      }),
    );
  }

  static String _hoursRemaining(Duration elapsed, int neededHours) {
    final remaining = neededHours - elapsed.inHours;
    if (remaining >= 24) {
      final days = (remaining / 24).ceil();
      return days == 1 ? '1 day' : '$days days';
    }
    return remaining <= 1 ? '1 hour' : '$remaining hours';
  }

  /// Maps an exercise onto a tracked muscle group, falling back when the
  /// exercise is missing or its group string isn't recognized.
  static String _groupFor(Exercise? exercise) {
    final raw = exercise?.muscleGroup?.toLowerCase();
    if (raw == null || raw.isEmpty) return MuscleGroups.fallback;
    for (final entry in _muscleAliases.entries) {
      if (entry.value.any(raw.contains)) return entry.key;
    }
    return MuscleGroups.fallback;
  }

  /// Epley estimate. Single reps are returned as-is, since the formula only
  /// applies above one rep.
  static double? _oneRepMax(double weight, int reps) {
    if (reps <= 0) return null;
    if (reps == 1) return weight;
    return weight * (1 + reps / 30.0);
  }

  static double? _bestOneRepMax(List<WorkoutSet> sets) {
    double? best;
    for (final s in sets) {
      final w = s.weight;
      final r = s.reps;
      if (w == null || r == null) continue;
      final orm = _oneRepMax(w, r);
      if (orm != null && (best == null || orm > best)) best = orm;
    }
    return best;
  }

  static List<PersonalRecord> _personalRecords(
    List<Workout> workouts,
    Map<int, Exercise> byId,
  ) {
    final best = <int, PersonalRecord>{};
    for (final w in workouts) {
      for (final we in w.exercises) {
        for (final s in we.sets) {
          final weight = s.weight;
          final reps = s.reps;
          if (weight == null || reps == null || weight <= 0) continue;
          final existing = best[we.exerciseId];
          if (existing != null && existing.heaviestWeight >= weight) {
            // Not a weight PR, but it may still be the biggest single set.
            if (s.volume > existing.bestSetVolume) {
              best[we.exerciseId] = PersonalRecord(
                exerciseId: existing.exerciseId,
                exerciseName: existing.exerciseName,
                heaviestWeight: existing.heaviestWeight,
                repsAtHeaviest: existing.repsAtHeaviest,
                achievedOn: existing.achievedOn,
                bestSetVolume: s.volume,
              );
            }
            continue;
          }
          best[we.exerciseId] = PersonalRecord(
            exerciseId: we.exerciseId,
            exerciseName: byId[we.exerciseId]?.name ?? 'Unknown exercise',
            heaviestWeight: weight,
            repsAtHeaviest: reps,
            achievedOn: w.date,
            bestSetVolume: existing != null && existing.bestSetVolume > s.volume
                ? existing.bestSetVolume
                : s.volume,
          );
        }
      }
    }
    final records = best.values.toList()
      ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    return List.unmodifiable(records);
  }

  /// Monday of the week containing [day].
  static DateTime _weekStart(DateTime day) =>
      DateTime(day.year, day.month, day.day).subtract(
        Duration(days: day.weekday - DateTime.monday),
      );

  /// Consecutive weeks with at least one workout, counting back from the
  /// current week. An empty current week doesn't break a streak that is still
  /// live — the week isn't over yet — so counting starts from last week.
  static int _weekStreak(Set<DateTime> weeks, DateTime currentWeek) {
    if (weeks.isEmpty) return 0;
    var streak = 0;
    var cursor = currentWeek;
    if (!weeks.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 7));
    }
    while (weeks.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }

  static List<TimePoint> _series(Map<DateTime, double> byDate) {
    final keys = byDate.keys.toList()..sort();
    return List.unmodifiable([
      for (final k in keys) TimePoint(k, byDate[k]!),
    ]);
  }

  // -------------------------------------------------------------------------
  // Export / import
  // -------------------------------------------------------------------------

  /// The whole store as pretty-printed JSON, for the share sheet.
  Future<String> exportJson() async {
    final data = await _load();
    return const JsonEncoder.withIndent('  ').convert(data.toJson());
  }

  /// Writes an export to a temp file and returns it, ready to share.
  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/forma-backup-$stamp.json');
    await file.writeAsString(await exportJson(), flush: true);
    return file;
  }

  // -------------------------------------------------------------------------
  // CSV — workout log interchange (Strong-compatible, one row per set)
  // -------------------------------------------------------------------------

  /// The workout log as CSV, one row per set. Lossy by nature — templates,
  /// measurements, supersets and rest aren't represented — but portable to
  /// spreadsheets and other trackers. Weights are in pounds.
  Future<String> exportWorkoutsCsv() async {
    final data = await _load();
    final byId = {for (final e in data.exercises) e.id: e};
    final rows = <List<Object?>>[
      [
        'Date',
        'Workout Name',
        'Exercise Name',
        'Set Order',
        'Weight (lb)',
        'Reps',
        'Effort',
        'Set Notes',
        'Workout Notes',
      ],
    ];
    final workouts = [...data.workouts]..sort((a, b) => a.date.compareTo(b.date));
    for (final w in workouts) {
      final date = w.date.toIso8601String().split('.').first.replaceFirst(
        'T',
        ' ',
      );
      for (final we in w.exercises) {
        final name = byId[we.exerciseId]?.name ?? 'Unknown exercise';
        var order = 1;
        for (final s in we.sets) {
          rows.add([
            date,
            w.templateName ?? '',
            name,
            order++,
            s.weight ?? '',
            s.reps ?? '',
            w.effortLevel,
            we.notes ?? '',
            w.notes ?? '',
          ]);
        }
      }
    }
    return const ListToCsvConverter().convert(rows);
  }

  Future<File> exportWorkoutsCsvToFile() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/forma-workouts-$stamp.csv');
    await file.writeAsString(await exportWorkoutsCsv(), flush: true);
    return file;
  }

  /// Imports a Strong-style workout CSV, adding to the existing log (never
  /// replacing). Rows are grouped into workouts by date + workout name and
  /// into exercises by name; unknown exercise names are created. When
  /// [weightsInKg] (or a "kg" weight header) applies, weights convert to lb.
  Future<CsvImportResult> importWorkoutsCsv(
    String csv, {
    required bool weightsInKg,
  }) {
    return _mutate(() async {
      final data = await _load();

      final normalized = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final delimiter = _sniffCsvDelimiter(normalized);
      List<List<dynamic>> rows;
      try {
        rows = CsvToListConverter(
          fieldDelimiter: delimiter,
          eol: '\n',
          shouldParseNumbers: false,
        ).convert(normalized);
      } catch (e) {
        throw ImportException('That CSV could not be read: $e');
      }
      if (rows.length < 2) {
        throw ImportException('The file has no data rows.');
      }

      final header = rows.first
          .map((c) => c.toString().trim().toLowerCase())
          .toList();
      int col(List<String> names) =>
          header.indexWhere((h) => names.contains(h));
      final iDate = col(['date']);
      final iWorkout = col(['workout name', 'workout']);
      final iExercise = col(['exercise name', 'exercise']);
      final iWeight = header.indexWhere((h) => h.startsWith('weight'));
      final iReps = col(['reps', 'rep']);
      final iRpe = col(['rpe']);
      final iSetNotes = col(['set notes', 'notes']);
      final iWorkoutNotes = col(['workout notes']);
      if (iDate == -1 || iExercise == -1) {
        throw ImportException(
          "This doesn't look like a workout CSV — a Date and an Exercise "
          'Name column are required.',
        );
      }
      // A "Weight (kg)" header wins over the toggle; otherwise trust the caller.
      final useKg = (iWeight != -1 && header[iWeight].contains('kg')) ||
          weightsInKg;

      // Index the library by normalized base signature so imported names map
      // onto existing exercises across the Strong/Forma naming difference.
      final index = <String, List<({int id, Set<String> equipment})>>{};
      for (final e in data.exercises) {
        final n = _normalizeExerciseName(e.name);
        index
            .putIfAbsent(n.base, () => [])
            .add((id: e.id, equipment: n.equipment));
      }

      var exercisesCreated = 0;
      int resolveExercise(String name) {
        final n = _normalizeExerciseName(name);
        final candidates = n.base.isEmpty ? null : index[n.base];
        if (candidates != null && candidates.isNotEmpty) {
          // A single base match is a strong signal on its own.
          if (candidates.length == 1) return candidates.first.id;
          // Several movements share this base (e.g. barbell vs dumbbell bench
          // press) — pick by equipment: exact, then overlapping, then the
          // equipment-free generic.
          for (final c in candidates) {
            if (c.equipment.length == n.equipment.length &&
                c.equipment.containsAll(n.equipment)) {
              return c.id;
            }
          }
          for (final c in candidates) {
            if (c.equipment.any(n.equipment.contains)) return c.id;
          }
          for (final c in candidates) {
            if (c.equipment.isEmpty) return c.id;
          }
          // Distinct equipment none of them have → a genuinely new variant.
        }
        final created = Exercise(id: data.nextExerciseId++, name: name);
        data.exercises.add(created);
        index
            .putIfAbsent(n.base, () => [])
            .add((id: created.id, equipment: n.equipment));
        exercisesCreated++;
        return created.id;
      }

      final order = <String>[];
      final builders = <String, _CsvWorkout>{};
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        String cell(int i) =>
            (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

        final exName = cell(iExercise);
        if (exName.isEmpty) continue;
        final dateStr = cell(iDate);
        final date =
            DateTime.tryParse(dateStr) ??
            DateTime.tryParse(dateStr.replaceFirst(' ', 'T'));
        if (date == null) continue;

        var weight = double.tryParse(cell(iWeight));
        // Parse via double so reps written as "8" or "8.0" both work; int
        // parsing alone drops decimal-formatted reps and loses the reps entirely.
        final reps = double.tryParse(cell(iReps))?.round();
        if (weight == null && reps == null) continue; // nothing to log
        if (weight != null && useKg) {
          weight = double.parse((weight * 2.2046226218).toStringAsFixed(1));
        }
        final rpe = iRpe >= 0 ? double.tryParse(cell(iRpe)) : null;

        final wName = iWorkout >= 0 ? cell(iWorkout) : '';
        final key = '$dateStr|$wName';
        final builder = builders.putIfAbsent(key, () {
          order.add(key);
          return _CsvWorkout(
            date: date,
            name: wName.isEmpty ? null : wName,
            notes: iWorkoutNotes >= 0 ? cell(iWorkoutNotes) : '',
          );
        });
        builder.addSet(
          exercise: exName,
          weight: weight,
          reps: reps,
          rpe: rpe,
          setNotes: iSetNotes >= 0 ? cell(iSetNotes) : '',
        );
      }

      var workoutsAdded = 0;
      var setsAdded = 0;
      for (final key in order) {
        final b = builders[key]!;
        if (b.exercises.isEmpty) continue;
        final exercises = <WorkoutExercise>[];
        for (final eb in b.exercises) {
          var setNo = 1;
          final sets = [
            for (final s in eb.sets)
              WorkoutSet(
                id: data.nextWorkoutSetId++,
                setNumber: setNo++,
                weight: s.weight,
                reps: s.reps,
              ),
          ];
          setsAdded += sets.length;
          exercises.add(
            WorkoutExercise(
              id: data.nextWorkoutExerciseId++,
              exerciseId: resolveExercise(eb.name),
              notes: eb.notes.isEmpty ? null : eb.notes,
              sets: sets,
            ),
          );
        }
        data.workouts.add(
          Workout(
            id: data.nextWorkoutId++,
            date: b.date,
            effortLevel: b.effort,
            notes: b.notes.isEmpty ? null : b.notes,
            templateName: b.name,
            exercises: exercises,
          ),
        );
        workoutsAdded++;
      }

      if (workoutsAdded == 0) {
        throw ImportException('No workouts could be read from that file.');
      }
      await _persist();
      return CsvImportResult(
        workouts: workoutsAdded,
        sets: setsAdded,
        exercisesCreated: exercisesCreated,
      );
    });
  }

  static String _sniffCsvDelimiter(String csv) {
    final firstLine = csv
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final semis = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    return semis > commas ? ';' : ',';
  }

  /// Replaces the entire store with [json].
  ///
  /// Destructive by design — this restores a backup rather than merging, so
  /// the UI must confirm first. The current file is copied aside beforehand so
  /// a mistaken import is recoverable.
  Future<void> importJson(String json) {
    return _mutate(() async {
      final _AppData incoming;
      try {
        incoming = _AppData.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } on FormatException catch (e) {
        throw ImportException('That file is not a valid Forma backup: $e');
      } catch (e) {
        throw ImportException('That backup could not be read: $e');
      }

      final file = await _storageFile;
      if (await file.exists()) {
        await file.copy(
          '${file.path}.pre-import-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      _cache = incoming;
      await _persist();
    });
  }

  /// Deletes every record and re-seeds the starter library.
  Future<void> resetAll() {
    return _mutate(() async {
      _cache = _AppData.seeded();
      await _persist();
    });
  }
}

/// Outcome of a CSV import, for the confirmation message.
class CsvImportResult {
  CsvImportResult({
    required this.workouts,
    required this.sets,
    required this.exercisesCreated,
  });

  final int workouts;
  final int sets;

  /// Exercise names in the file that weren't in the library and were created.
  final int exercisesCreated;
}

// Transient builders used only while grouping CSV rows into workouts.

class _CsvWorkout {
  _CsvWorkout({required this.date, this.name, this.notes = ''});

  final DateTime date;
  final String? name;
  final String notes;
  final List<_CsvExercise> exercises = [];
  final Map<String, _CsvExercise> _byName = {};
  final List<double> _rpes = [];

  void addSet({
    required String exercise,
    double? weight,
    int? reps,
    double? rpe,
    String setNotes = '',
  }) {
    final e = _byName.putIfAbsent(exercise, () {
      final created = _CsvExercise(exercise, setNotes);
      exercises.add(created);
      return created;
    });
    e.sets.add(_CsvSet(weight, reps));
    if (rpe != null) _rpes.add(rpe);
  }

  /// Effort from the workout's average RPE when present, else a neutral 5.
  int get effort {
    if (_rpes.isEmpty) return 5;
    final avg = _rpes.reduce((a, b) => a + b) / _rpes.length;
    return avg.round().clamp(1, 10);
  }
}

class _CsvExercise {
  _CsvExercise(this.name, this.notes);

  final String name;
  final String notes;
  final List<_CsvSet> sets = [];
}

class _CsvSet {
  _CsvSet(this.weight, this.reps);

  final double? weight;
  final int? reps;
}

/// A workout exercise being composed in the UI, before the store assigns ids.
class WorkoutExerciseDraft {
  WorkoutExerciseDraft({
    required this.exerciseId,
    this.notes,
    required this.sets,
    this.supersetGroup,
    this.restSeconds = 0,
  });

  final int exerciseId;
  final String? notes;
  final List<WorkoutSetDraft> sets;

  /// Group id shared by exercises supersetted together; null when standalone.
  final int? supersetGroup;

  /// Rest between sets, in seconds; 0 for no rest timer.
  final int restSeconds;
}

/// One kind's value within a measurement session, before it is stored.
class MeasurementDraft {
  MeasurementDraft({
    required this.kind,
    required this.value,
    this.unit,
    this.notes,
  });

  final String kind;
  final double value;

  /// Defaults to [MeasurementKinds.unitFor] when omitted.
  final String? unit;
  final String? notes;
}

class WorkoutSetDraft {
  WorkoutSetDraft({this.weight, this.reps});

  final double? weight;
  final int? reps;
}

/// One exercise as performed in one workout.
class ExerciseSession {
  ExerciseSession({
    required this.workoutId,
    required this.date,
    required this.notes,
    required this.sets,
  });

  final int workoutId;
  final DateTime date;
  final String? notes;
  final List<WorkoutSet> sets;

  double get volume => sets.fold(0.0, (sum, s) => sum + s.volume);
}

class _AppData {
  _AppData({
    required this.nextEquipmentTypeId,
    required this.nextExerciseId,
    required this.nextWorkoutId,
    required this.nextWorkoutExerciseId,
    required this.nextWorkoutSetId,
    required this.nextFolderId,
    required this.nextTemplateId,
    required this.nextMeasurementId,
    required this.equipmentTypes,
    required this.exercises,
    required this.workouts,
    required this.folders,
    required this.templates,
    required this.measurements,
  });

  /// A fresh store carrying the starter exercise library.
  factory _AppData.seeded() => _AppData(
    nextEquipmentTypeId: seedIdCeiling + 1,
    nextExerciseId: seedIdCeiling + 1,
    nextWorkoutId: 1,
    nextWorkoutExerciseId: 1,
    nextWorkoutSetId: 1,
    nextFolderId: 1,
    nextTemplateId: 1,
    nextMeasurementId: 1,
    equipmentTypes: defaultEquipmentTypes(),
    exercises: defaultExercises(),
    workouts: [],
    folders: [],
    templates: [],
    measurements: [],
  );

  factory _AppData.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'] as int? ?? schemaVersion;
    if (version > schemaVersion) {
      // Written by a newer app version; refuse to parse so _load() sets the
      // file aside instead of mangling it.
      throw FormatException('unsupported schema version $version');
    }
    return _AppData(
      nextEquipmentTypeId: json['next_equipment_type_id'] as int,
      nextExerciseId: json['next_exercise_id'] as int,
      nextWorkoutId: json['next_workout_id'] as int,
      nextWorkoutExerciseId: json['next_workout_exercise_id'] as int,
      nextWorkoutSetId: json['next_workout_set_id'] as int,
      nextFolderId: json['next_folder_id'] as int,
      nextTemplateId: json['next_template_id'] as int,
      nextMeasurementId: json['next_measurement_id'] as int,
      equipmentTypes: (json['equipment_types'] as List? ?? [])
          .map((e) => EquipmentType.fromJson(e as Map<String, dynamic>))
          .toList(),
      exercises: (json['exercises'] as List? ?? [])
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      workouts: (json['workouts'] as List? ?? [])
          .map((e) => Workout.fromJson(e as Map<String, dynamic>))
          .toList(),
      folders: (json['folders'] as List? ?? [])
          .map((e) => TemplateFolder.fromJson(e as Map<String, dynamic>))
          .toList(),
      templates: (json['templates'] as List? ?? [])
          .map((e) => Template.fromJson(e as Map<String, dynamic>))
          .toList(),
      measurements: (json['measurements'] as List? ?? [])
          .map((e) => Measurement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  int nextEquipmentTypeId;
  int nextExerciseId;
  int nextWorkoutId;
  int nextWorkoutExerciseId;
  int nextWorkoutSetId;
  int nextFolderId;
  int nextTemplateId;
  int nextMeasurementId;

  List<EquipmentType> equipmentTypes;
  List<Exercise> exercises;
  List<Workout> workouts;
  List<TemplateFolder> folders;
  List<Template> templates;
  List<Measurement> measurements;

  /// Version of the on-disk JSON layout. Bump on breaking changes and migrate
  /// older files in [_AppData.fromJson].
  static const schemaVersion = 1;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'next_equipment_type_id': nextEquipmentTypeId,
    'next_exercise_id': nextExerciseId,
    'next_workout_id': nextWorkoutId,
    'next_workout_exercise_id': nextWorkoutExerciseId,
    'next_workout_set_id': nextWorkoutSetId,
    'next_folder_id': nextFolderId,
    'next_template_id': nextTemplateId,
    'next_measurement_id': nextMeasurementId,
    'equipment_types': equipmentTypes.map((e) => e.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'workouts': workouts.map((e) => e.toJson()).toList(),
    'folders': folders.map((e) => e.toJson()).toList(),
    'templates': templates.map((e) => e.toJson()).toList(),
    'measurements': measurements.map((e) => e.toJson()).toList(),
  };
}
