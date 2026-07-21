/// On-device storage and all derived-value computation.
///
/// Everything the app knows lives in one JSON file in the documents
/// directory. There is no network layer: the class keeps the `ApiClient` name
/// from when it wrapped a FastAPI backend so call sites read the same, but
/// every method here is a local read-modify-write.
library;

import 'dart:convert';
import 'dart:io';

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

    final sorted = [...data.workouts]..sort((a, b) => a.date.compareTo(b.date));
    for (final w in sorted) {
      for (final we in w.exercises) {
        if (we.exerciseId != exerciseId) continue;
        final top = we.topWeight;
        if (top != null) topWeight.add(TimePoint(w.date, top));
        if (we.volume > 0) volume.add(TimePoint(w.date, we.volume));
        final orm = _bestOneRepMax(we.sets);
        if (orm != null) oneRepMax.add(TimePoint(w.date, orm));
      }
    }

    return ExerciseProgress(
      exerciseId: exerciseId,
      exerciseName: exercise.name,
      topWeight: List.unmodifiable(topWeight),
      volume: List.unmodifiable(volume),
      estimatedOneRepMax: List.unmodifiable(oneRepMax),
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

/// A workout exercise being composed in the UI, before the store assigns ids.
class WorkoutExerciseDraft {
  WorkoutExerciseDraft({
    required this.exerciseId,
    this.notes,
    required this.sets,
  });

  final int exerciseId;
  final String? notes;
  final List<WorkoutSetDraft> sets;
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
