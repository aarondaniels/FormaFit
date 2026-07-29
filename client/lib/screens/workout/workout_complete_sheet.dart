/// The celebration sheet shown after a new workout is saved: a summary of the
/// session, any personal records set, and where it lands against the user's
/// all-time and weekly totals.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../dashboard_screen.dart' show compactNumber;

/// One exercise that beat its previous best in the just-finished session.
class PrHighlight {
  const PrHighlight({
    required this.exerciseName,
    required this.weight,
    required this.reps,
  });

  final String exerciseName;
  final double weight;
  final int reps;
}

/// Everything the completion sheet renders, computed by the caller so the sheet
/// stays a pure presentation of a finished workout.
class WorkoutSummary {
  const WorkoutSummary({
    required this.exerciseCount,
    required this.setCount,
    required this.volume,
    required this.durationLabel,
    required this.totalWorkouts,
    required this.workoutsThisWeek,
    required this.weekStreak,
    required this.prs,
  });

  final int exerciseCount;
  final int setCount;
  final double volume;
  final String durationLabel;

  /// All-time and current-week completed workout counts, and the run of
  /// consecutive weeks with at least one workout ending this week.
  final int totalWorkouts;
  final int workoutsThisWeek;
  final int weekStreak;

  final List<PrHighlight> prs;
}

/// Presents the completion sheet and completes when it is dismissed (by the
/// Done button, a drag, or a scrim tap) so the caller can then leave the logger.
Future<void> showWorkoutCompleteSheet(
  BuildContext context,
  WorkoutSummary summary,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WorkoutCompleteSheet(summary: summary),
  );
}

class _WorkoutCompleteSheet extends StatelessWidget {
  const _WorkoutCompleteSheet({required this.summary});

  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasPr = summary.prs.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radius),
        ),
      ),
      // Cap height so a workout with many PRs scrolls rather than overflowing.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DragHandle(),
              const SizedBox(height: AppSpacing.lg),
              _Header(hasPr: hasPr, summary: summary),
              const SizedBox(height: AppSpacing.lg),
              _sessionCard(),
              if (hasPr) ...[
                const SizedBox(height: AppSpacing.md),
                _prCard(),
              ],
              const SizedBox(height: AppSpacing.md),
              _milestoneCard(),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionCard() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          StatCell(
            value: '${summary.exerciseCount}',
            label: 'Exercises',
            icon: Icons.fitness_center,
            color: AppColors.primary,
          ),
          const CellDivider(),
          StatCell(
            value: '${summary.setCount}',
            label: 'Sets',
            icon: Icons.repeat,
            color: AppColors.success,
          ),
          const CellDivider(),
          StatCell(
            value: compactNumber(summary.volume),
            label: 'Volume (lb)',
            icon: Icons.scale,
            color: AppColors.warning,
          ),
          const CellDivider(),
          StatCell(
            value: summary.durationLabel,
            label: 'Duration',
            icon: Icons.timer_outlined,
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _prCard() {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                summary.prs.length == 1
                    ? 'Personal record'
                    : '${summary.prs.length} personal records',
                style: AppTypography.h5.copyWith(color: AppColors.onDark),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < summary.prs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _PrRow(pr: summary.prs[i]),
          ],
        ],
      ),
    );
  }

  Widget _milestoneCard() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          StatCell(
            value: '${summary.totalWorkouts}',
            label: 'All-time',
            icon: Icons.military_tech,
            color: AppColors.primary,
          ),
          const CellDivider(),
          StatCell(
            value: '${summary.workoutsThisWeek}',
            label: 'This week',
            icon: Icons.date_range,
            color: AppColors.success,
          ),
          const CellDivider(),
          StatCell(
            value: '${summary.weekStreak}',
            label: 'Week streak',
            icon: Icons.local_fire_department,
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasPr, required this.summary});

  final bool hasPr;
  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final tint = hasPr ? AppColors.warning : AppColors.success;
    final subtitle = _subtitle();
    return Column(
      children: [
        // A brief spring-in on the badge gives the moment a beat of celebration
        // without pulling in an animation package.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.elasticOut,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasPr ? Icons.emoji_events : Icons.check_rounded,
              size: 40,
              color: tint,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          hasPr ? 'New personal record!' : 'Workout complete!',
          textAlign: TextAlign.center,
          style: AppTypography.h3.copyWith(color: AppColors.onDark),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.mutedOnDark),
          ),
        ],
      ],
    );
  }

  String? _subtitle() {
    final bits = <String>[];
    if (summary.workoutsThisWeek > 0) {
      bits.add('${summary.workoutsThisWeek} this week');
    }
    if (summary.weekStreak >= 2) {
      bits.add('${summary.weekStreak}-week streak');
    }
    return bits.isEmpty ? null : bits.join('  ·  ');
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});

  final PrHighlight pr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            pr.exerciseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(color: AppColors.onDark),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${_formatWeight(pr.weight)} lb × ${pr.reps}',
          style: AppTypography.numeric.copyWith(color: AppColors.warning),
        ),
      ],
    );
  }
}

/// Whole weights lose the trailing `.0`; fractional plates keep one decimal.
String _formatWeight(double w) =>
    w == w.roundToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.cta,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
