import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'health_sync.dart';
import 'models.dart';

/// Single shared in-device storage client.
final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Apple Health bridge. Inert off iOS.
final healthSyncProvider = Provider<HealthSync>((ref) => HealthSync());

/// Whether the user has turned Health sync on.
final healthSyncEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).healthSyncEnabled();
});

/// Bumped after every mutation so the derived providers below refetch.
///
/// The store is a file rather than a stream, so there is nothing to listen to;
/// this is the invalidation signal that stands in for one.
class StoreRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final storeRevisionProvider = NotifierProvider<StoreRevision, int>(
  StoreRevision.new,
);

/// Runs a mutation, then refreshes everything reading the store.
///
/// Every write goes through here so no screen has to remember which providers
/// its change invalidates.
Future<T> mutate<T>(Ref ref, Future<T> Function(ApiClient api) action) async {
  final result = await action(ref.read(apiProvider));
  ref.read(storeRevisionProvider.notifier).bump();
  return result;
}

/// Same as [mutate], for widgets holding a [WidgetRef].
Future<T> mutateWith<T>(
  WidgetRef ref,
  Future<T> Function(ApiClient api) action,
) async {
  final result = await action(ref.read(apiProvider));
  ref.read(storeRevisionProvider.notifier).bump();
  return result;
}

final exercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listExercises();
});

/// Exercises keyed by id, for the many places that resolve an id to a name.
final exercisesByIdProvider = FutureProvider<Map<int, Exercise>>((ref) async {
  final exercises = await ref.watch(exercisesProvider.future);
  return {for (final e in exercises) e.id: e};
});

final equipmentTypesProvider = FutureProvider<List<EquipmentType>>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listEquipmentTypes();
});

final equipmentTypesByIdProvider = FutureProvider<Map<int, EquipmentType>>((
  ref,
) async {
  final types = await ref.watch(equipmentTypesProvider.future);
  return {for (final t in types) t.id: t};
});

/// All workouts, most recent first.
final workoutsProvider = FutureProvider<List<Workout>>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listWorkouts();
});

final workoutProvider = FutureProvider.family<Workout?, int>((ref, id) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).getWorkout(id);
});

final foldersProvider = FutureProvider<List<TemplateFolder>>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listFolders();
});

/// Templates in one folder. Pass a null id for every template.
final templatesProvider = FutureProvider.family<List<Template>, int?>((
  ref,
  folderId,
) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listTemplates(folderId: folderId);
});

final templateProvider = FutureProvider.family<Template?, int>((ref, id) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).getTemplate(id);
});

final statsProvider = FutureProvider<WorkoutStats>((ref) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).stats();
});

final muscleRecoveryProvider = FutureProvider<List<MuscleRecovery>>((
  ref,
) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).muscleRecovery();
});

final exerciseProgressProvider = FutureProvider.family<ExerciseProgress, int>((
  ref,
  exerciseId,
) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).exerciseProgress(exerciseId);
});

final exerciseHistoryProvider =
    FutureProvider.family<List<ExerciseSession>, int>((ref, exerciseId) async {
      ref.watch(storeRevisionProvider);
      return ref.watch(apiProvider).exerciseHistory(exerciseId);
    });

/// Measurements of one kind, newest first. Pass null for all kinds.
final measurementsProvider = FutureProvider.family<List<Measurement>, String?>((
  ref,
  kind,
) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).listMeasurements(kind: kind);
});

final measurementSeriesProvider =
    FutureProvider.family<List<TimePoint>, String>((ref, kind) async {
      ref.watch(storeRevisionProvider);
      return ref.watch(apiProvider).measurementSeries(kind);
    });

/// Every kind that has been measured, condensed for the overview list.
final measurementSummariesProvider = FutureProvider<List<MeasurementSummary>>((
  ref,
) async {
  ref.watch(storeRevisionProvider);
  return ref.watch(apiProvider).measurementSummaries();
});

/// Which exercise-library filters are active. Held in memory so the list
/// keeps its filters while navigating in and out of exercise details.
class ExerciseFilter {
  const ExerciseFilter({this.query = '', this.muscleGroup, this.equipmentId});

  final String query;
  final String? muscleGroup;
  final int? equipmentId;

  bool get isActive =>
      query.isNotEmpty || muscleGroup != null || equipmentId != null;

  ExerciseFilter copyWith({
    String? query,
    String? muscleGroup,
    int? equipmentId,
    bool clearMuscleGroup = false,
    bool clearEquipment = false,
  }) => ExerciseFilter(
    query: query ?? this.query,
    muscleGroup: clearMuscleGroup ? null : muscleGroup ?? this.muscleGroup,
    equipmentId: clearEquipment ? null : equipmentId ?? this.equipmentId,
  );

  bool matches(Exercise e) {
    if (muscleGroup != null && e.muscleGroup != muscleGroup) return false;
    if (equipmentId != null && e.equipmentTypeId != equipmentId) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return e.name.toLowerCase().contains(q) ||
        (e.muscleGroup?.toLowerCase().contains(q) ?? false);
  }
}

class ExerciseFilterNotifier extends Notifier<ExerciseFilter> {
  @override
  ExerciseFilter build() => const ExerciseFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setMuscleGroup(String? group) => state = group == null
      ? state.copyWith(clearMuscleGroup: true)
      : state.copyWith(muscleGroup: group);

  void setEquipment(int? id) => state = id == null
      ? state.copyWith(clearEquipment: true)
      : state.copyWith(equipmentId: id);

  void clear() => state = const ExerciseFilter();
}

final exerciseFilterProvider =
    NotifierProvider<ExerciseFilterNotifier, ExerciseFilter>(
      ExerciseFilterNotifier.new,
    );

/// The exercise library with the active filters applied.
final filteredExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final exercises = await ref.watch(exercisesProvider.future);
  final filter = ref.watch(exerciseFilterProvider);
  return exercises.where(filter.matches).toList();
});

/// Muscle groups present in the library, for the filter chips.
final muscleGroupsInUseProvider = FutureProvider<List<String>>((ref) async {
  final exercises = await ref.watch(exercisesProvider.future);
  final groups = exercises
      .map((e) => e.muscleGroup)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();
  return groups;
});
