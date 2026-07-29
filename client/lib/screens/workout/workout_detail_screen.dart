import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../../widgets/rest.dart';
import '../dashboard_screen.dart' show compactNumber;
import '../exercise_detail_screen.dart' show formatSet;
import 'log_workout_screen.dart';

class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final int workoutId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await mutateWith(ref, (api) => api.deleteWorkout(workoutId));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(workoutProvider(workoutId));
    final exercises = ref.watch(exercisesByIdProvider).value ?? {};

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const GlassBackButton(),
        title: const Text('Workout'),
        actions: [
          GlassIconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              final w = workout.value;
              if (w == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogWorkoutScreen(existing: w),
                ),
              );
            },
          ),
          GlassIconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: workout.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(error: e),
        data: (w) {
          if (w == null) {
            return const EmptyState(
              icon: Icons.help_outline,
              title: 'Workout not found',
              message: 'It may have been deleted.',
            );
          }
          return ListView(
            padding: glassPagePadding(context),
            children: [
              GlassSection(
                title: DateFormat.yMMMEd().format(w.date),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (w.templateName != null) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: AppColors.mutedOnDark,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(w.templateName!, style: AppTypography.caption),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            value: '${w.exerciseCount}',
                            label: 'Exercises',
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            value: '${w.setCount}',
                            label: 'Sets',
                            color: AppColors.success,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            value: compactNumber(w.volume),
                            label: 'Volume (lb)',
                            color: AppColors.warning,
                          ),
                        ),
                        Expanded(
                          child: StatTile(
                            value: w.formattedDuration,
                            label: 'Duration',
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Effort ${w.effortLevel}/10',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.mutedOnDark,
                      ),
                    ),
                    if (w.notes != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(w.notes!, style: AppTypography.caption),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final we in w.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ExerciseBlock(
                    name: exercises[we.exerciseId]?.name ?? 'Unknown exercise',
                    exercise: we,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.name, required this.exercise});

  final String name;
  final WorkoutExercise exercise;

  @override
  Widget build(BuildContext context) {
    final supersetColor = exercise.supersetGroup == null
        ? null
        : AppColors.forSuperset(exercise.supersetGroup!);

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
              Expanded(child: Text(name, style: AppTypography.h5)),
              if (exercise.restSeconds > 0) ...[
                const Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: AppColors.mutedOnDark,
                ),
                const SizedBox(width: 2),
                Text(
                  formatRest(exercise.restSeconds),
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                '${exercise.volume.round()} lb',
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final s in exercise.sets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${s.setNumber}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.mutedOnDark,
                      ),
                    ),
                  ),
                  Text(formatSet(s), style: AppTypography.numeric),
                ],
              ),
            ),
          if (exercise.notes != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              exercise.notes!,
              style: AppTypography.small.copyWith(
                color: AppColors.mutedOnDark,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );

    if (supersetColor == null) return card;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: supersetColor.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: card,
    );
  }
}
