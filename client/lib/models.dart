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

  WorkoutExercise({
    required this.id,
    required this.exerciseId,
    this.notes,
    required this.sets,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) => WorkoutExercise(
    id: j['id'] as int,
    exerciseId: j['exercise_id'] as int,
    notes: j['notes'] as String?,
    sets: (j['sets'] as List? ?? [])
        .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'exercise_id': exerciseId,
    'notes': notes,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  WorkoutExercise copyWith({
    int? id,
    int? exerciseId,
    String? notes,
    List<WorkoutSet>? sets,
  }) => WorkoutExercise(
    id: id ?? this.id,
    exerciseId: exerciseId ?? this.exerciseId,
    notes: notes ?? this.notes,
    sets: sets ?? this.sets,
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

  /// Calendar date the work was done. Time-of-day is not tracked.
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

  Workout({
    required this.id,
    required this.date,
    required this.effortLevel,
    this.notes,
    this.templateName,
    this.duration,
    required this.exercises,
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'effort_level': effortLevel,
    'notes': notes,
    'template_name': templateName,
    'duration': duration,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Workout copyWith({
    int? id,
    DateTime? date,
    int? effortLevel,
    String? notes,
    String? templateName,
    int? duration,
    List<WorkoutExercise>? exercises,
  }) => Workout(
    id: id ?? this.id,
    date: date ?? this.date,
    effortLevel: effortLevel ?? this.effortLevel,
    notes: notes ?? this.notes,
    templateName: templateName ?? this.templateName,
    duration: duration ?? this.duration,
    exercises: exercises ?? this.exercises,
  );

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

  TemplateExercise({
    required this.exerciseId,
    required this.order,
    required this.defaultSets,
    this.defaultWeight,
    this.defaultReps,
  });

  factory TemplateExercise.fromJson(Map<String, dynamic> j) => TemplateExercise(
    exerciseId: j['exercise_id'] as int,
    order: j['order'] as int,
    defaultSets: j['default_sets'] as int,
    defaultWeight: (j['default_weight'] as num?)?.toDouble(),
    defaultReps: j['default_reps'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'order': order,
    'default_sets': defaultSets,
    'default_weight': defaultWeight,
    'default_reps': defaultReps,
  };

  TemplateExercise copyWith({
    int? exerciseId,
    int? order,
    int? defaultSets,
    double? defaultWeight,
    int? defaultReps,
  }) => TemplateExercise(
    exerciseId: exerciseId ?? this.exerciseId,
    order: order ?? this.order,
    defaultSets: defaultSets ?? this.defaultSets,
    defaultWeight: defaultWeight ?? this.defaultWeight,
    defaultReps: defaultReps ?? this.defaultReps,
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
}

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

/// A single point on a time-series chart.
class TimePoint {
  final DateTime date;
  final double value;

  TimePoint(this.date, this.value);
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

  ExerciseProgress({
    required this.exerciseId,
    required this.exerciseName,
    required this.topWeight,
    required this.volume,
    required this.estimatedOneRepMax,
  });
}
