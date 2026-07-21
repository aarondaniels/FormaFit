import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import 'workout/workout_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final workouts = ref.watch(workoutsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.read(storeRevisionProvider.notifier).bump(),
      child: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(
          error: e,
          onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
        ),
        data: (s) {
          if (s.totalWorkouts == 0) {
            return ListView(
              padding: glassPagePadding(context),
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.fitness_center,
                  title: 'No workouts yet',
                  message:
                      'Tap “Log workout” to record your first session. '
                      'Everything stays on this device.',
                ),
              ],
            );
          }

          return ListView(
            padding: glassPagePadding(context),
            children: [
              _SummaryGrid(stats: s),
              const SizedBox(height: AppSpacing.lg),
              const _RecoverySection(),
              const SizedBox(height: AppSpacing.lg),
              _RecentWorkouts(workouts: workouts),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});

  final WorkoutStats stats;

  @override
  Widget build(BuildContext context) {
    final hours = stats.totalDuration / 3600;
    return GlassSection(
      title: 'At a glance',
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        children: [
          StatTile(
            value: '${stats.workoutsThisWeek}',
            label: 'This week',
            icon: Icons.calendar_today,
          ),
          StatTile(
            value: '${stats.weekStreak}',
            label: stats.weekStreak == 1 ? 'Week streak' : 'Week streak',
            icon: Icons.local_fire_department,
            color: AppColors.accent,
          ),
          StatTile(
            value: compactNumber(stats.totalVolume),
            label: 'Total volume (lb)',
            icon: Icons.scale,
            color: AppColors.success,
          ),
          StatTile(
            value: hours >= 1
                ? '${hours.toStringAsFixed(1)}h'
                : '${(stats.totalDuration / 60).round()}m',
            label: 'Time trained',
            icon: Icons.timer_outlined,
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

class _RecoverySection extends ConsumerWidget {
  const _RecoverySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(muscleRecoveryProvider);

    return recovery.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (groups) {
        // Lead with what needs attention: least-recovered first, and skip
        // groups never trained so the list stays actionable.
        final trained =
            groups.where((g) => g.status != RecoveryStatus.untrained).toList()
              ..sort(
                (a, b) =>
                    a.recoveryPercentage.compareTo(b.recoveryPercentage),
              );
        if (trained.isEmpty) return const SizedBox.shrink();

        return GlassSection(
          title: 'Muscle recovery',
          child: Column(
            children: [
              for (final g in trained.take(4)) _RecoveryRow(recovery: g),
            ],
          ),
        );
      },
    );
  }
}

class _RecoveryRow extends StatelessWidget {
  const _RecoveryRow({required this.recovery});

  final MuscleRecovery recovery;

  Color get _statusColor => switch (recovery.status) {
    RecoveryStatus.ready => AppColors.success,
    RecoveryStatus.recovering => AppColors.warning,
    RecoveryStatus.overworked => AppColors.error,
    RecoveryStatus.untrained => AppColors.secondary,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(recovery.muscleGroup, style: AppTypography.h6),
              ),
              Text(
                '${(recovery.recoveryPercentage * 100).round()}%',
                style: AppTypography.numeric.copyWith(color: _statusColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: recovery.recoveryPercentage,
              minHeight: 6,
              backgroundColor: AppColors.cta,
              valueColor: AlwaysStoppedAnimation(_statusColor),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            recovery.recommendation,
            style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
          ),
        ],
      ),
    );
  }
}

class _RecentWorkouts extends ConsumerWidget {
  const _RecentWorkouts({required this.workouts});

  final AsyncValue<List<Workout>> workouts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return workouts.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => AsyncFailure(error: e),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final exercises = ref.watch(exercisesByIdProvider).value ?? {};

        return GlassSection(
          title: 'Recent workouts',
          child: Column(
            children: [
              for (final w in list.take(5))
                _WorkoutRow(workout: w, exercises: exercises),
            ],
          ),
        );
      },
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout, required this.exercises});

  final Workout workout;
  final Map<int, Exercise> exercises;

  @override
  Widget build(BuildContext context) {
    final names = workout.exercises
        .map((e) => exercises[e.exerciseId]?.name)
        .whereType<String>()
        .toList();
    final subtitle = names.isEmpty
        ? 'No exercises'
        : names.take(3).join(' · ') +
              (names.length > 3 ? ' +${names.length - 3}' : '');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutDetailScreen(workoutId: workout.id),
        ),
      ),
      title: Text(
        workout.templateName ?? DateFormat.MMMEd().format(workout.date),
        style: AppTypography.h6,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${workout.setCount} sets',
            style: AppTypography.small.copyWith(color: AppColors.onDark),
          ),
          Text(
            workout.formattedDuration,
            style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
          ),
        ],
      ),
    );
  }
}

/// Compact large numbers so volume totals stay readable in a stat tile.
String compactNumber(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return value.round().toString();
}
