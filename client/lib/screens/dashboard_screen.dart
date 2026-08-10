import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import 'measurements_screen.dart' show formatAge;
import 'workout/log_workout_screen.dart';
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
          return ListView(
            padding: glassContentPadding(context),
            children: [
              const _StartWorkoutCta(),
              const SizedBox(height: AppSpacing.lg),
              if (s.totalWorkouts == 0)
                const _FirstSessionNote()
              else ...[
                _StatTrio(stats: s),
                const SizedBox(height: AppSpacing.lg),
                const _RecoverySection(),
                const SizedBox(height: AppSpacing.lg),
                _RecentWorkouts(workouts: workouts),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Primary call-to-action at the top of the home tab.
class _StartWorkoutCta extends StatelessWidget {
  const _StartWorkoutCta();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LogWorkoutScreen()),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.activeCTA],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fitness_center,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Start a workout',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Log a new session',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The home tab's headline trifecta: total workouts, this week, week streak.
/// Values stay in ink; the icons carry the accent (the streak's flame is the
/// warm, motivational one).
class _StatTrio extends StatelessWidget {
  const _StatTrio({required this.stats});

  final WorkoutStats stats;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          StatCell(
            value: '${stats.totalWorkouts}',
            label: 'Total workouts',
            icon: Icons.fitness_center,
            color: AppColors.primary,
          ),
          const CellDivider(),
          StatCell(
            value: '${stats.workoutsThisWeek}',
            label: 'This week',
            icon: Icons.calendar_today,
            color: AppColors.success,
          ),
          const CellDivider(),
          StatCell(
            value: '${stats.weekStreak}',
            label: 'Week streak',
            icon: Icons.local_fire_department,
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

/// Shown on the home tab before any workout is logged.
class _FirstSessionNote extends StatelessWidget {
  const _FirstSessionNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.fitness_center, size: 48, color: AppColors.cta),
          const SizedBox(height: AppSpacing.md),
          Text('No workouts yet', style: AppTypography.h4),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap “Start a workout” above to log your first session. '
            'Everything stays on this device.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.mutedOnDark),
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
                (a, b) => a.recoveryPercentage.compareTo(b.recoveryPercentage),
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
    // How long ago leads the line: on a list of recent sessions it is the
    // thing being scanned for, and a row titled with its template name carried
    // no date at all before this.
    final age = formatAge(workout.daysSince(DateTime.now()));

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
      subtitle: Text.rich(
        TextSpan(
          children: [
            // The age is the brighter half of the line; the exercise list is
            // supporting detail and stays muted.
            TextSpan(
              text: age,
              style: AppTypography.small.copyWith(color: AppColors.onDark),
            ),
            TextSpan(
              text: ' · $subtitle',
              style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
