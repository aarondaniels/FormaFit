import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/glass.dart';
import 'dashboard_screen.dart' show compactNumber;
import 'exercise_detail_screen.dart' show trimNumber;

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);

    return stats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AsyncFailure(
        error: e,
        onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
      ),
      data: (s) {
        if (s.totalWorkouts == 0) {
          return const EmptyState(
            icon: Icons.insights,
            title: 'No progress to show yet',
            message:
                'Log a few workouts and your volume, frequency and personal '
                'records will appear here.',
          );
        }

        return ListView(
          padding: glassPagePadding(context),
          children: [
            _Totals(stats: s),
            const SizedBox(height: AppSpacing.lg),
            GlassSection(
              title: 'Volume per week',
              child: SizedBox(
                height: 200,
                child: WeeklyBarChart(
                  points: s.volumeByWeek,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassSection(
              title: 'Workouts per week',
              child: SizedBox(
                height: 180,
                child: WeeklyBarChart(
                  points: s.frequencyByWeek,
                  color: AppColors.success,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassSection(
              title: 'Muscle group balance',
              child: MuscleGroupDonut(volumeByGroup: s.volumeByMuscleGroup),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PersonalRecords(records: s.personalRecords),
          ],
        );
      },
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats});

  final WorkoutStats stats;

  @override
  Widget build(BuildContext context) {
    final hours = stats.totalDuration / 3600;
    return GlassSection(
      title: 'Totals',
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        children: [
          StatTile(
            value: '${stats.totalWorkouts}',
            label: 'Workouts',
            icon: Icons.event_available,
          ),
          StatTile(
            value: '${stats.totalSets}',
            label: 'Sets',
            icon: Icons.repeat,
            color: AppColors.success,
          ),
          StatTile(
            value: compactNumber(stats.totalVolume),
            label: 'Volume (lb)',
            icon: Icons.scale,
            color: AppColors.warning,
          ),
          StatTile(
            value: hours >= 1
                ? '${hours.toStringAsFixed(1)}h'
                : '${(stats.totalDuration / 60).round()}m',
            label: 'Time trained',
            icon: Icons.timer_outlined,
            color: AppColors.accent,
          ),
          StatTile(
            value: stats.averageEffort.toStringAsFixed(1),
            label: 'Avg effort (1–10)',
            icon: Icons.bolt,
          ),
          StatTile(
            value: '${stats.workoutsThisMonth}',
            label: 'This month',
            icon: Icons.calendar_month,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _PersonalRecords extends StatelessWidget {
  const _PersonalRecords({required this.records});

  final List<PersonalRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return GlassSection(
        title: 'Personal records',
        child: Text(
          'Log a set with both weight and reps to start tracking records.',
          style: AppTypography.caption.copyWith(color: AppColors.mutedOnDark),
        ),
      );
    }

    // Heaviest lifts first — that's what people look for.
    final sorted = [...records]
      ..sort((a, b) => b.heaviestWeight.compareTo(a.heaviestWeight));

    return GlassSection(
      title: 'Personal records',
      child: Column(
        children: [
          for (final r in sorted.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.exerciseName, style: AppTypography.h6),
                        Text(
                          DateFormat.yMMMd().format(r.achievedOn),
                          style: AppTypography.small.copyWith(
                            color: AppColors.mutedOnDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${trimNumber(r.heaviestWeight)} lb'
                    '${r.repsAtHeaviest == null ? '' : ' × ${r.repsAtHeaviest}'}',
                    style: AppTypography.numeric.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
