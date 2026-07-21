import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import 'exercise_detail_screen.dart';
import 'exercise_form_screen.dart';

class ExerciseLibraryScreen extends ConsumerWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(filteredExercisesProvider);
    final filter = ref.watch(exerciseFilterProvider);

    return Column(
      children: [
        SizedBox(height: glassTopInset(context) + AppSpacing.sm),
        const _FilterBar(),
        Expanded(
          child: exercises.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AsyncFailure(
              error: e,
              onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
            ),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off,
                  title: filter.isActive
                      ? 'No matching exercises'
                      : 'No exercises',
                  message: filter.isActive
                      ? 'Try clearing the filters.'
                      : 'Add an exercise to get started.',
                  action: filter.isActive
                      ? TextButton(
                          onPressed: () => ref
                              .read(exerciseFilterProvider.notifier)
                              .clear(),
                          child: const Text('Clear filters'),
                        )
                      : null,
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  glassBottomInset(context),
                ),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _ExerciseCard(exercise: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(exerciseFilterProvider);
    final notifier = ref.read(exerciseFilterProvider.notifier);
    final groups = ref.watch(muscleGroupsInUseProvider).value ?? const [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: notifier.setQuery,
                  decoration: InputDecoration(
                    hintText: 'Search exercises',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: filter.query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => notifier.setQuery(''),
                          ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ExerciseFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                tooltip: 'New exercise',
              ),
            ],
          ),
        ),
        if (groups.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(g),
                      selected: filter.muscleGroup == g,
                      onSelected: (on) =>
                          notifier.setMuscleGroup(on ? g : null),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(equipmentTypesByIdProvider).value ?? {};
    final equipmentName = exercise.equipmentTypeId == null
        ? null
        : equipment[exercise.equipmentTypeId]?.name;
    final group = exercise.muscleGroup;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExerciseDetailScreen(exerciseId: exercise.id),
          ),
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: group == null
                ? AppColors.cta
                : AppColors.forMuscleGroup(group).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: Icon(
            Icons.fitness_center,
            size: 20,
            color: group == null
                ? AppColors.mutedOnDark
                : AppColors.forMuscleGroup(group),
          ),
        ),
        title: Text(exercise.name, style: AppTypography.h6),
        subtitle: Text(
          [group, equipmentName].whereType<String>().join(' · '),
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}
