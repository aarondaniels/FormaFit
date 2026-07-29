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
                final query = filter.query.trim();
                // Searching with no match → offer to create that exercise.
                if (query.isNotEmpty) {
                  return EmptyState(
                    icon: Icons.add_circle_outline,
                    title: 'No matching exercise',
                    message: 'Create “$query” and add it to your library.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ExerciseFormScreen(initialName: query),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text('Create “$query”'),
                    ),
                  );
                }
                // A muscle-group chip with nothing under it.
                if (filter.muscleGroup != null) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'No exercises in this group',
                    message: 'Try another group, or clear the filter.',
                    action: TextButton(
                      onPressed: () =>
                          ref.read(exerciseFilterProvider.notifier).clear(),
                      child: const Text('Clear filter'),
                    ),
                  );
                }
                // Truly empty library.
                return EmptyState(
                  icon: Icons.fitness_center,
                  title: 'No exercises',
                  message: 'Add your first exercise to get started.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ExerciseFormScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add exercise'),
                  ),
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
        // Rolling muscle-group filter across the top.
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
        // Search full-width; creating a new exercise is offered from the
        // empty state when a search finds nothing.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
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
        // Uniform, low-key icon chips: the muscle group is conveyed by the
        // subtitle text, so the leading art stays neutral and doesn't turn the
        // list into a wall of color.
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.cta,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: const Icon(
            Icons.fitness_center,
            size: 20,
            color: AppColors.mutedOnDark,
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
