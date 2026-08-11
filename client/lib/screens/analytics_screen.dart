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
import 'measurements_screen.dart'
    show MeasurementsScreen, changeColor, formatChange, showMeasurementSession;

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
        final hasWorkouts = s.totalWorkouts > 0;

        return ListView(
          padding: glassContentPadding(context),
          children: [
            // Body measurements sit above the training charts and show even
            // with no workouts logged — they're tracked independently, and
            // this card is the only signpost that the feature exists.
            const _BodyCard(),
            const SizedBox(height: AppSpacing.lg),
            if (!hasWorkouts)
              GlassSection(
                title: 'Training',
                child: Text(
                  'Log a few workouts and your volume, frequency and personal '
                  'records will appear here.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
            if (hasWorkouts) ...[
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
                child: MuscleGroupDonut(setsByGroup: s.setsByMuscleGroup),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PersonalRecords(records: s.personalRecords),
            ],
          ],
        );
      },
    );
  }
}

/// The measurements entry point on Progress.
///
/// A labeled card rather than an icon in the title bar: measurements were
/// previously reachable only through an unlabeled control that appeared on this
/// tab alone, which meant nobody found them.
class _BodyCard extends ConsumerWidget {
  const _BodyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(measurementSummariesProvider);

    void open() => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MeasurementsScreen()));

    return GlassSection(
      title: 'Body',
      // Logging is the frequent act and browsing the rare one, so the card
      // carries both: the sheet opens from here rather than two screens in.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: open, child: const Text('All')),
          IconButton.filled(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Log measurements',
            visualDensity: VisualDensity.compact,
            onPressed: () => showMeasurementSession(context, ref),
          ),
        ],
      ),
      child: summaries.maybeWhen(
        data: (list) => list.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track body weight and tape measurements alongside your '
                    'training.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.add),
                    label: const Text('Log measurements'),
                  ),
                ],
              )
            : Column(
                children: [
                  // The three most recently measured kinds — the card is a
                  // signpost, not the full list. Each row logs that one kind,
                  // which is the whole session for a weigh-in.
                  for (final s in _mostRecent(list, 3))
                    InkWell(
                      onTap: () => showMeasurementSession(
                        context,
                        ref,
                        onlyKind: s.kind,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusSmall,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(s.kind, style: AppTypography.h6),
                            ),
                            Text(
                              '${trimNumber(s.latest)} ${s.unit}',
                              style: AppTypography.numeric,
                            ),
                            if (s.changeOverall != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                formatChange(s.changeOverall!, s.unit),
                                style: AppTypography.small.copyWith(
                                  color: changeColor(s.kind, s.changeOverall!),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
        orElse: () => const SizedBox(height: 24),
      ),
    );
  }

  static List<MeasurementSummary> _mostRecent(
    List<MeasurementSummary> list,
    int count,
  ) {
    final sorted = [...list]
      ..sort((a, b) => b.latestDate.compareTo(a.latestDate));
    return sorted.take(count).toList();
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats});

  final WorkoutStats stats;

  @override
  Widget build(BuildContext context) {
    final hours = stats.totalDuration / 3600;
    final time = hours >= 1
        ? '${hours.toStringAsFixed(1)}h'
        : '${(stats.totalDuration / 60).round()}m';

    // The aggregates that only live on Progress — Workouts/streak/this-week
    // are the Home trifecta's job. One calm accent, numbers in ink.
    return GlassSection(
      title: 'Totals',
      child: Column(
        children: [
          Row(
            children: [
              StatCell(
                value: compactNumber(stats.totalVolume),
                label: 'Volume (lb)',
                icon: Icons.scale,
                color: AppColors.primary,
              ),
              const CellDivider(),
              StatCell(
                value: '${stats.totalSets}',
                label: 'Sets',
                icon: Icons.repeat,
                color: AppColors.primary,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              StatCell(
                value: time,
                label: 'Time trained',
                icon: Icons.timer_outlined,
                color: AppColors.primary,
              ),
              const CellDivider(),
              StatCell(
                value: stats.averageEffort.toStringAsFixed(1),
                label: 'Avg effort',
                icon: Icons.bolt,
                color: AppColors.primary,
              ),
            ],
          ),
          // Bodyweight work is counted in reps and kept out of the volume
          // figure above, so it gets its own line rather than being added to
          // pounds. Hidden entirely for someone who logs none.
          if (stats.totalBodyweightReps > 0) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                StatCell(
                  value: compactNumber(stats.totalBodyweightReps.toDouble()),
                  label: 'Bodyweight reps',
                  icon: Icons.accessibility_new,
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
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
          'Log a set with weight and reps — or just reps, for a bodyweight '
          'exercise — to start tracking records.',
          style: AppTypography.caption.copyWith(color: AppColors.mutedOnDark),
        ),
      );
    }

    // Heaviest lifts first — that's what people look for — with the rep
    // records after them, since the two can't be ranked against each other.
    final sorted = [...records]
      ..sort((a, b) {
        if (a.isBodyweight != b.isBodyweight) return a.isBodyweight ? 1 : -1;
        return a.isBodyweight
            ? (b.bestReps ?? 0).compareTo(a.bestReps ?? 0)
            : (b.heaviestWeight ?? 0).compareTo(a.heaviestWeight ?? 0);
      });

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
                    r.isBodyweight
                        ? '${r.bestReps} reps'
                        : '${trimNumber(r.heaviestWeight ?? 0)} lb'
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
