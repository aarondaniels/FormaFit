import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../health_sync.dart';
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
          final work = workoutWork(w, exercises);
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
                          // A session with no loaded exercise reports its work
                          // in reps rather than as a flat 0 lb.
                          child: work.tonnage > 0 || work.bodyweightReps == 0
                              ? StatTile(
                                  value: compactNumber(work.tonnage),
                                  label: 'Volume (lb)',
                                  color: AppColors.warning,
                                )
                              : StatTile(
                                  value: '${work.bodyweightReps}',
                                  label: 'Reps',
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
              _HealthSection(workout: w),
              for (final we in w.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ExerciseBlock(
                    name: exercises[we.exerciseId]?.name ?? 'Unknown exercise',
                    exercise: we,
                    bodyweight: exercises[we.exerciseId]?.isBodyweight ?? false,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// What the watch measured over this session.
///
/// Hidden entirely when sync is off or the platform has no Health, so the
/// screen doesn't advertise a feature that isn't running. When sync is on but
/// nothing has arrived, it offers a refresh instead: Health often takes a few
/// minutes to receive a session from the watch, so the reading at save time is
/// frequently missing rather than genuinely zero.
class _HealthSection extends ConsumerStatefulWidget {
  const _HealthSection({required this.workout});

  final Workout workout;

  @override
  ConsumerState<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends ConsumerState<_HealthSection> {
  bool _refreshing = false;

  /// Sends this workout to Health if it isn't there, then pulls back whatever
  /// the watch measured.
  ///
  /// Doubles as the repair path: a session logged while writing was broken
  /// never reached Health, and this is how it gets there without re-logging.
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final health = ref.read(healthSyncProvider);
      final w = widget.workout;

      if (!await health.hasWorkoutInWindow(start: w.date, end: w.endsAt)) {
        final failure = await health.writeWorkout(start: w.date, end: w.endsAt);
        if (failure != null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(failure)));
          }
          return;
        }
      }

      final metrics = await health.readMetrics(start: w.date, end: w.endsAt);
      if (metrics == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Apple Health has nothing for this session yet.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      await mutateWith(
        ref,
        (api) => api.setWorkoutHealthMetrics(
          widget.workout.id,
          activeEnergy: metrics.activeEnergy,
          avgHeartRate: metrics.avgHeartRate,
          maxHeartRate: metrics.maxHeartRate,
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!HealthSync.isSupported) return const SizedBox.shrink();
    final enabled = ref.watch(healthSyncEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();

    final w = widget.workout;
    final hasAny = w.activeEnergy != null || w.avgHeartRate != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: GlassSection(
        title: 'Apple Health',
        trailing: TextButton(
          onPressed: _refreshing ? null : _refresh,
          child: Text(_refreshing ? 'Syncing…' : 'Sync now'),
        ),
        child: hasAny
            ? Row(
                children: [
                  Expanded(
                    child: StatTile(
                      value: w.activeEnergy == null
                          ? '—'
                          : compactNumber(w.activeEnergy!),
                      label: 'Active kcal',
                      color: AppColors.accent,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      value: w.avgHeartRate == null ? '—' : '${w.avgHeartRate}',
                      label: 'Avg bpm',
                      color: AppColors.error,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      value: w.maxHeartRate == null ? '—' : '${w.maxHeartRate}',
                      label: 'Max bpm',
                      color: AppColors.warning,
                    ),
                  ),
                ],
              )
            : Text(
                'Nothing recorded for this session yet. Health can take a few '
                'minutes to receive a workout from your watch — "Sync now" '
                'also sends this session to Health if it never arrived.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
      ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({
    required this.name,
    required this.exercise,
    required this.bodyweight,
  });

  final String name;
  final WorkoutExercise exercise;

  /// Swaps the exercise's tonnage readout for a rep count, and drops the
  /// weight from each set line.
  final bool bodyweight;

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
                bodyweight
                    ? '${exercise.totalReps} reps'
                    : '${exercise.volume.round()} lb',
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
                  Text(
                    formatSet(s, bodyweight: bodyweight),
                    style: AppTypography.numeric,
                  ),
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
