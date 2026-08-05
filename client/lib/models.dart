/// Plain data models for on-device storage.
///
/// Every entity uses a monotonically increasing `int` id handed out by the
/// store. The original client mixed server UUID strings (`Exercise.id`) with
/// ints (`WorkoutExercise.exerciseId`), which only worked because the two
/// never met in a comparison; with a single local store they do, so ids are
/// int everywhere.
library;

/// Muscle groups the app knows how to chart and recover-track. Exercises may
/// carry any free-form muscle group string; unrecognized ones fall back to
/// [MuscleGroups.fallback] when grouped.
class MuscleGroups {
  static const chest = 'Chest';
  static const back = 'Back';
  static const shoulders = 'Shoulders';
  static const arms = 'Arms';
  static const legs = 'Legs';
  static const core = 'Core';
  static const glutes = 'Glutes';
  static const calves = 'Calves';

  static const all = [
    chest,
    back,
    shoulders,
    arms,
    legs,
    core,
    glutes,
    calves,
  ];

  static const fallback = core;
}

class EquipmentType {
  final int id;
  final String name;
  final String? description;
  final String? icon;
  final String? category;

  EquipmentType({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.category,
  });

  factory EquipmentType.fromJson(Map<String, dynamic> j) => EquipmentType(
    id: j['id'] as int,
    name: j['name'] as String,
    description: j['description'] as String?,
    icon: j['icon'] as String?,
    category: j['category'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'category': category,
  };

  EquipmentType copyWith({
    int? id,
    String? name,
    String? description,
    String? icon,
    String? category,
  }) => EquipmentType(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    category: category ?? this.category,
  );
}

class Exercise {
  final int id;
  final String name;
  final String? muscleGroup;
  final String? description;
  final int? equipmentTypeId;
  final String? instructions;

  /// True for the exercises seeded on first launch. Used to let users restore
  /// the starter library without duplicating their own entries.
  final bool isDefault;

  Exercise({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.description,
    this.equipmentTypeId,
    this.instructions,
    this.isDefault = false,
  });

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    id: j['id'] as int,
    name: j['name'] as String,
    muscleGroup: j['muscle_group'] as String?,
    description: j['description'] as String?,
    equipmentTypeId: j['equipment_type_id'] as int?,
    instructions: j['instructions'] as String?,
    isDefault: j['is_default'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'muscle_group': muscleGroup,
    'description': description,
    'equipment_type_id': equipmentTypeId,
    'instructions': instructions,
    'is_default': isDefault,
  };

  Exercise copyWith({
    int? id,
    String? name,
    String? muscleGroup,
    String? description,
    int? equipmentTypeId,
    String? instructions,
    bool? isDefault,
  }) => Exercise(
    id: id ?? this.id,
    name: name ?? this.name,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    description: description ?? this.description,
    equipmentTypeId: equipmentTypeId ?? this.equipmentTypeId,
    instructions: instructions ?? this.instructions,
    isDefault: isDefault ?? this.isDefault,
  );
}

class WorkoutSet {
  final int id;
  final int setNumber;
  final double? weight;
  final int? reps;

  WorkoutSet({
    required this.id,
    required this.setNumber,
    this.weight,
    this.reps,
  });

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
    id: j['id'] as int,
    setNumber: j['set_number'] as int,
    weight: (j['weight'] as num?)?.toDouble(),
    reps: j['reps'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'set_number': setNumber,
    'weight': weight,
    'reps': reps,
  };

  WorkoutSet copyWith({int? id, int? setNumber, double? weight, int? reps}) =>
      WorkoutSet(
        id: id ?? this.id,
        setNumber: setNumber ?? this.setNumber,
        weight: weight ?? this.weight,
        reps: reps ?? this.reps,
      );

  /// Weight moved by this set. Sets missing either field contribute nothing
  /// rather than being treated as zero-weight work.
  double get volume => (weight ?? 0) * (reps ?? 0);
}

class WorkoutExercise {
  final int id;
  final int exerciseId;
  final String? notes;
  final List<WorkoutSet> sets;

  /// Exercises sharing a non-null [supersetGroup] within one workout are a
  /// superset — performed back-to-back. The value is only an identifier for
  /// grouping; it carries no order of its own.
  final int? supersetGroup;

  /// Rest to take between this exercise's sets, in seconds. 0 means no rest
  /// timer.
  final int restSeconds;

  WorkoutExercise({
    required this.id,
    required this.exerciseId,
    this.notes,
    required this.sets,
    this.supersetGroup,
    this.restSeconds = 0,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) => WorkoutExercise(
    id: j['id'] as int,
    exerciseId: j['exercise_id'] as int,
    notes: j['notes'] as String?,
    sets: (j['sets'] as List? ?? [])
        .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
        .toList(),
    supersetGroup: j['superset_group'] as int?,
    restSeconds: j['rest_seconds'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'exercise_id': exerciseId,
    'notes': notes,
    'sets': sets.map((s) => s.toJson()).toList(),
    'superset_group': supersetGroup,
    'rest_seconds': restSeconds,
  };

  WorkoutExercise copyWith({
    int? id,
    int? exerciseId,
    String? notes,
    List<WorkoutSet>? sets,
    int? supersetGroup,
    int? restSeconds,
  }) => WorkoutExercise(
    id: id ?? this.id,
    exerciseId: exerciseId ?? this.exerciseId,
    notes: notes ?? this.notes,
    sets: sets ?? this.sets,
    supersetGroup: supersetGroup ?? this.supersetGroup,
    restSeconds: restSeconds ?? this.restSeconds,
  );

  double get volume => sets.fold(0.0, (sum, s) => sum + s.volume);

  /// Heaviest weight moved for any set that also recorded reps.
  double? get topWeight {
    double? best;
    for (final s in sets) {
      final w = s.weight;
      if (w == null || s.reps == null) continue;
      if (best == null || w > best) best = w;
    }
    return best;
  }
}

class Workout {
  final int id;

  /// When the session started. The date carries a real time of day — Apple
  /// Health is queried for the window it opens — so anything that edits it must
  /// preserve the time component.
  final DateTime date;

  /// 1–10 subjective effort.
  final int effortLevel;
  final String? notes;

  /// Name of the template this was started from, captured at log time so
  /// renaming or deleting the template later doesn't rewrite history.
  final String? templateName;

  /// Elapsed workout time in seconds.
  final int? duration;
  final List<WorkoutExercise> exercises;

  /// Active energy in kilocalories, as measured by the watch over the session.
  ///
  /// Unlike stats or recovery this is *stored* rather than derived: it is an
  /// observation from outside the app, not something recomputable from the
  /// records here, and it must survive the permission being withdrawn. Null
  /// when Health had nothing for the window, or sync is off.
  final double? activeEnergy;

  /// Average and peak heart rate across the session, in beats per minute.
  final int? avgHeartRate;
  final int? maxHeartRate;

  Workout({
    required this.id,
    required this.date,
    required this.effortLevel,
    this.notes,
    this.templateName,
    this.duration,
    required this.exercises,
    this.activeEnergy,
    this.avgHeartRate,
    this.maxHeartRate,
  });

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
    id: j['id'] as int,
    date: DateTime.parse(j['date'] as String),
    effortLevel: j['effort_level'] as int,
    notes: j['notes'] as String?,
    templateName: j['template_name'] as String?,
    duration: j['duration'] as int?,
    exercises: (j['exercises'] as List? ?? [])
        .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    // Absent in files written before Health sync existed, which is why these
    // are nullable and the schema version doesn't move.
    activeEnergy: (j['active_energy'] as num?)?.toDouble(),
    avgHeartRate: j['avg_heart_rate'] as int?,
    maxHeartRate: j['max_heart_rate'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'effort_level': effortLevel,
    'notes': notes,
    'template_name': templateName,
    'duration': duration,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'active_energy': activeEnergy,
    'avg_heart_rate': avgHeartRate,
    'max_heart_rate': maxHeartRate,
  };

  Workout copyWith({
    int? id,
    DateTime? date,
    int? effortLevel,
    String? notes,
    String? templateName,
    int? duration,
    List<WorkoutExercise>? exercises,
    double? activeEnergy,
    int? avgHeartRate,
    int? maxHeartRate,
  }) => Workout(
    id: id ?? this.id,
    date: date ?? this.date,
    effortLevel: effortLevel ?? this.effortLevel,
    notes: notes ?? this.notes,
    templateName: templateName ?? this.templateName,
    duration: duration ?? this.duration,
    exercises: exercises ?? this.exercises,
    activeEnergy: activeEnergy ?? this.activeEnergy,
    avgHeartRate: avgHeartRate ?? this.avgHeartRate,
    maxHeartRate: maxHeartRate ?? this.maxHeartRate,
  );

  /// End of the session's window, for querying Health.
  DateTime get endsAt => date.add(Duration(seconds: duration ?? 0));

  int get exerciseCount => exercises.length;

  int get setCount => exercises.fold(0, (sum, e) => sum + e.sets.length);

  double get volume => exercises.fold(0.0, (sum, e) => sum + e.volume);

  String get formattedDuration {
    final totalSeconds = duration;
    if (totalSeconds == null) return '—';
    if (totalSeconds < 60) return '$totalSeconds sec';

    final totalMinutes = (totalSeconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes min';

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}

/// A named grouping of templates.
///
/// This was `TemplateFile` on the server, where it carried `file_path`,
/// `file_size` and `file_type` columns — but nothing was ever uploaded: the
/// path was synthesized from the name and the other two stayed null. It is
/// and always was a folder, so it is named as one here.
class TemplateFolder {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;

  TemplateFolder({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  factory TemplateFolder.fromJson(Map<String, dynamic> j) => TemplateFolder(
    id: j['id'] as int,
    name: j['name'] as String,
    description: j['description'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'created_at': createdAt.toIso8601String(),
  };

  TemplateFolder copyWith({
    int? id,
    String? name,
    String? description,
    DateTime? createdAt,
  }) => TemplateFolder(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
  );
}

class TemplateExercise {
  final int exerciseId;
  final int order;
  final int defaultSets;
  final double? defaultWeight;
  final int? defaultReps;

  /// Rest between sets, in seconds, carried into a workout started from the
  /// template. 0 means no rest timer.
  final int restSeconds;

  TemplateExercise({
    required this.exerciseId,
    required this.order,
    required this.defaultSets,
    this.defaultWeight,
    this.defaultReps,
    this.restSeconds = 90,
  });

  factory TemplateExercise.fromJson(Map<String, dynamic> j) => TemplateExercise(
    exerciseId: j['exercise_id'] as int,
    order: j['order'] as int,
    defaultSets: j['default_sets'] as int,
    defaultWeight: (j['default_weight'] as num?)?.toDouble(),
    defaultReps: j['default_reps'] as int?,
    // Templates predating rest timers default to a sensible 90s.
    restSeconds: j['rest_seconds'] as int? ?? 90,
  );

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'order': order,
    'default_sets': defaultSets,
    'default_weight': defaultWeight,
    'default_reps': defaultReps,
    'rest_seconds': restSeconds,
  };

  TemplateExercise copyWith({
    int? exerciseId,
    int? order,
    int? defaultSets,
    double? defaultWeight,
    int? defaultReps,
    int? restSeconds,
  }) => TemplateExercise(
    exerciseId: exerciseId ?? this.exerciseId,
    order: order ?? this.order,
    defaultSets: defaultSets ?? this.defaultSets,
    defaultWeight: defaultWeight ?? this.defaultWeight,
    defaultReps: defaultReps ?? this.defaultReps,
    restSeconds: restSeconds ?? this.restSeconds,
  );
}

class Template {
  final int id;
  final int folderId;
  final String name;
  final DateTime createdAt;
  final List<TemplateExercise> exercises;

  Template({
    required this.id,
    required this.folderId,
    required this.name,
    required this.createdAt,
    required this.exercises,
  });

  factory Template.fromJson(Map<String, dynamic> j) => Template(
    id: j['id'] as int,
    folderId: j['folder_id'] as int,
    name: j['name'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    exercises: (j['exercises'] as List? ?? [])
        .map((e) => TemplateExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'folder_id': folderId,
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Template copyWith({
    int? id,
    int? folderId,
    String? name,
    DateTime? createdAt,
    List<TemplateExercise>? exercises,
  }) => Template(
    id: id ?? this.id,
    folderId: folderId ?? this.folderId,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    exercises: exercises ?? this.exercises,
  );
}

/// Body metrics the measurements screen tracks over time.
class MeasurementKinds {
  static const bodyWeight = 'Body weight';
  static const bodyFat = 'Body fat';
  static const chest = 'Chest';
  static const waist = 'Waist';
  static const hips = 'Hips';
  static const thigh = 'Thigh';
  static const arm = 'Arm';
  static const calf = 'Calf';
  static const neck = 'Neck';

  static const all = [
    bodyWeight,
    bodyFat,
    chest,
    waist,
    hips,
    thigh,
    arm,
    calf,
    neck,
  ];

  /// Default unit per kind. US units throughout, matching the rest of the app.
  static String unitFor(String kind) => switch (kind) {
    bodyWeight => 'lb',
    bodyFat => '%',
    _ => 'in',
  };

  /// Which direction counts as progress, so a change can be colored honestly.
  ///
  /// Only the near-universal cases take a side: waist and body fat down, limbs
  /// and chest up. Body weight is deliberately [MeasurementGoal.neutral] — a
  /// strength app has people cutting and bulking, and guessing wrong would
  /// congratulate someone for the opposite of their goal.
  static MeasurementGoal goalFor(String kind) => switch (kind) {
    bodyFat || waist => MeasurementGoal.decrease,
    chest || thigh || arm || calf => MeasurementGoal.increase,
    _ => MeasurementGoal.neutral,
  };

  /// Sort key placing known kinds in declaration order and unknown (user-typed)
  /// kinds after them.
  static int orderOf(String kind) {
    final i = all.indexOf(kind);
    return i == -1 ? all.length : i;
  }
}

/// Whether an increase in a measurement is progress, a regression, or neither.
enum MeasurementGoal { increase, decrease, neutral }

class Measurement {
  final int id;
  final DateTime date;
  final String kind;
  final double value;
  final String unit;
  final String? notes;

  Measurement({
    required this.id,
    required this.date,
    required this.kind,
    required this.value,
    required this.unit,
    this.notes,
  });

  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(
    id: j['id'] as int,
    date: DateTime.parse(j['date'] as String),
    kind: j['kind'] as String,
    value: (j['value'] as num).toDouble(),
    unit: j['unit'] as String,
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'kind': kind,
    'value': value,
    'unit': unit,
    'notes': notes,
  };

  Measurement copyWith({
    int? id,
    DateTime? date,
    String? kind,
    double? value,
    String? unit,
    String? notes,
  }) => Measurement(
    id: id ?? this.id,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    value: value ?? this.value,
    unit: unit ?? this.unit,
    notes: notes ?? this.notes,
  );
}

// ---------------------------------------------------------------------------
// Computed values — derived from the stored records, never persisted.
// ---------------------------------------------------------------------------

enum RecoveryStatus { ready, recovering, overworked, untrained }

class MuscleRecovery {
  final String muscleGroup;

  /// 0.0 (just trained) to 1.0 (fully recovered).
  final double recoveryPercentage;
  final DateTime? lastWorked;
  final int? daysSinceLastWorkout;

  /// 0.0 to 1.0, driven by recent training frequency for the group.
  final double fatigueLevel;
  final RecoveryStatus status;
  final String recommendation;

  MuscleRecovery({
    required this.muscleGroup,
    required this.recoveryPercentage,
    required this.lastWorked,
    required this.daysSinceLastWorkout,
    required this.fatigueLevel,
    required this.status,
    required this.recommendation,
  });
}

/// One exercise's best-ever performance, used for the PR list.
class PersonalRecord {
  final int exerciseId;
  final String exerciseName;
  final double heaviestWeight;
  final int? repsAtHeaviest;
  final DateTime achievedOn;
  final double bestSetVolume;

  PersonalRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.heaviestWeight,
    required this.repsAtHeaviest,
    required this.achievedOn,
    required this.bestSetVolume,
  });
}

/// A weight/reps pair — what both a stored [WorkoutSet] and an in-progress set
/// draft reduce to, so work done can be measured the same way during a session
/// and after it is saved.
typedef SetLoad = ({double? weight, int? reps});

/// This session's work on one exercise against the last time it was trained.
///
/// "Work" is tonnage (weight × reps) for a loaded exercise, but total reps for
/// one that carries no weight — pull-ups and push-ups multiply out to zero
/// tonnage, and a bar that never fills is worse than no bar. [repsOnly] says
/// which reading applies, and both sides are always measured the same way.
class VolumeComparison {
  const VolumeComparison({
    required this.current,
    required this.previousTotal,
    required this.previousAtPace,
    required this.setsLogged,
    required this.repsOnly,
  });

  /// Work recorded so far this session.
  final double current;

  /// Work across the whole of the previous session; 0 with no history.
  final double previousTotal;

  /// Work in the previous session through its first [setsLogged] sets — the
  /// like-for-like figure. Comparing a part-finished exercise against a whole
  /// previous session only ever says "behind", which is true but useless.
  ///
  /// Null before anything is logged, or when there is no history.
  final double? previousAtPace;

  /// Sets this session carrying any value.
  final int setsLogged;

  final bool repsOnly;

  static double _valueOf(SetLoad set, {required bool repsOnly}) => repsOnly
      ? (set.reps ?? 0).toDouble()
      : (set.weight ?? 0) * (set.reps ?? 0);

  static bool _isLogged(SetLoad set) => set.weight != null || set.reps != null;

  factory VolumeComparison.of({
    required List<SetLoad> current,
    required List<SetLoad> previous,
  }) {
    // One loaded set on either side makes this a weighted exercise; a session
    // that is merely blank so far shouldn't flip the unit mid-workout.
    final repsOnly = ![...current, ...previous].any(
      (s) => (s.weight ?? 0) > 0,
    );

    double sum(Iterable<SetLoad> sets) =>
        sets.fold(0.0, (total, s) => total + _valueOf(s, repsOnly: repsOnly));

    final logged = current.where(_isLogged).length;
    return VolumeComparison(
      current: sum(current),
      previousTotal: sum(previous),
      previousAtPace: (logged == 0 || previous.isEmpty)
          ? null
          : sum(previous.take(logged)),
      setsLogged: logged,
      repsOnly: repsOnly,
    );
  }

  bool get hasHistory => previousTotal > 0;

  /// Share of the previous session's work done so far, uncapped so the caller
  /// can style an overshoot.
  double get progress => previousTotal <= 0 ? 0 : current / previousTotal;

  /// Ahead (or behind) the previous session at this point in the exercise.
  double? get paceDelta =>
      previousAtPace == null ? null : current - previousAtPace!;

  String get unit => repsOnly ? 'reps' : 'lb';
}

/// A single point on a time-series chart.
class TimePoint {
  final DateTime date;
  final double value;

  TimePoint(this.date, this.value);
}

/// One measurement kind condensed for the overview list: where it stands now,
/// how far it has moved, and enough history to draw a sparkline.
class MeasurementSummary {
  final String kind;
  final String unit;

  /// Most recent value and when it was taken.
  final double latest;
  final DateTime latestDate;

  /// Change from the first recorded value, and from the entry before this one.
  /// Both null until there are two entries.
  final double? changeOverall;
  final double? changeLast;

  final int entryCount;

  /// Every value for the kind, oldest first.
  final List<TimePoint> series;

  MeasurementSummary({
    required this.kind,
    required this.unit,
    required this.latest,
    required this.latestDate,
    required this.changeOverall,
    required this.changeLast,
    required this.entryCount,
    required this.series,
  });

  /// Whole days since the last entry, for the "measured N days ago" line.
  int daysSince(DateTime now) =>
      DateTime(now.year, now.month, now.day)
          .difference(
            DateTime(latestDate.year, latestDate.month, latestDate.day),
          )
          .inDays;
}

class WorkoutStats {
  final int totalWorkouts;
  final int totalSets;
  final double totalVolume;

  /// Seconds spent training across all workouts with a recorded duration.
  final int totalDuration;
  final int workoutsThisWeek;
  final int workoutsThisMonth;

  /// Consecutive weeks, ending with the current one, containing >= 1 workout.
  final int weekStreak;
  final double averageEffort;

  /// Total volume per calendar week, oldest first.
  final List<TimePoint> volumeByWeek;

  /// Workout count per calendar week, oldest first.
  final List<TimePoint> frequencyByWeek;

  /// Share of total volume per muscle group.
  final Map<String, double> volumeByMuscleGroup;

  final List<PersonalRecord> personalRecords;

  WorkoutStats({
    required this.totalWorkouts,
    required this.totalSets,
    required this.totalVolume,
    required this.totalDuration,
    required this.workoutsThisWeek,
    required this.workoutsThisMonth,
    required this.weekStreak,
    required this.averageEffort,
    required this.volumeByWeek,
    required this.frequencyByWeek,
    required this.volumeByMuscleGroup,
    required this.personalRecords,
  });

  static WorkoutStats get empty => WorkoutStats(
    totalWorkouts: 0,
    totalSets: 0,
    totalVolume: 0,
    totalDuration: 0,
    workoutsThisWeek: 0,
    workoutsThisMonth: 0,
    weekStreak: 0,
    averageEffort: 0,
    volumeByWeek: const [],
    frequencyByWeek: const [],
    volumeByMuscleGroup: const {},
    personalRecords: const [],
  );
}

/// Per-exercise progression over time, for the exercise detail chart.
class ExerciseProgress {
  final int exerciseId;
  final String exerciseName;

  /// Heaviest weight per session, oldest first.
  final List<TimePoint> topWeight;

  /// Total volume per session, oldest first.
  final List<TimePoint> volume;

  /// Estimated one-rep max per session (Epley), oldest first.
  final List<TimePoint> estimatedOneRepMax;

  /// Total reps per session, oldest first — the progression signal for
  /// bodyweight/rep-based work that has no weight to chart.
  final List<TimePoint> reps;

  ExerciseProgress({
    required this.exerciseId,
    required this.exerciseName,
    required this.topWeight,
    required this.volume,
    required this.estimatedOneRepMax,
    required this.reps,
  });
}
