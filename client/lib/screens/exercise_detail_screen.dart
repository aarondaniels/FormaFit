import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/glass.dart';
import 'exercise_form_screen.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final int exerciseId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final sessions =
        await ref.read(exerciseHistoryProvider(exerciseId).future);
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete exercise?'),
        content: Text(
          sessions.isEmpty
              ? 'This exercise will be removed from your library.'
              : 'This exercise appears in ${sessions.length} logged '
                    '${sessions.length == 1 ? "session" : "sessions"}. '
                    'Deleting it also removes those sets from your history.',
        ),
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
    await mutateWith(ref, (api) => api.deleteExercise(exerciseId));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = ref.watch(exercisesByIdProvider);
    final exercise = byId.value?[exerciseId];
    final equipment = ref.watch(equipmentTypesByIdProvider).value ?? {};
    final history = ref.watch(exerciseHistoryProvider(exerciseId));
    final progress = ref.watch(exerciseProgressProvider(exerciseId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(exercise?.name ?? 'Exercise'),
        actions: [
          if (exercise != null)
            GlassIconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExerciseFormScreen(existing: exercise),
                ),
              ),
            ),
          GlassIconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: exercise == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: glassPagePadding(context),
              children: [
                _About(exercise: exercise, equipment: equipment),
                const SizedBox(height: AppSpacing.lg),
                progress.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (p) => p.estimatedOneRepMax.length < 2
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            GlassSection(
                              title: 'Estimated 1RM',
                              child: SizedBox(
                                height: 180,
                                child: TimeSeriesChart(
                                  points: p.estimatedOneRepMax,
                                  color: AppColors.primary,
                                  unit: 'lb',
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                ),
                history.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => AsyncFailure(error: e),
                  data: (sessions) => sessions.isEmpty
                      ? const EmptyState(
                          icon: Icons.history,
                          title: 'No history yet',
                          message:
                              'Sets you log for this exercise will show up here.',
                        )
                      : GlassSection(
                          title: 'History',
                          child: Column(
                            children: [
                              for (final s in sessions)
                                _SessionRow(session: s),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.exercise, required this.equipment});

  final Exercise exercise;
  final Map<int, EquipmentType> equipment;

  @override
  Widget build(BuildContext context) {
    final equipmentName = exercise.equipmentTypeId == null
        ? null
        : equipment[exercise.equipmentTypeId]?.name;

    return GlassSection(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (exercise.muscleGroup != null)
                Chip(
                  label: Text(exercise.muscleGroup!),
                  backgroundColor: AppColors.forMuscleGroup(
                    exercise.muscleGroup!,
                  ).withValues(alpha: 0.2),
                ),
              if (equipmentName != null) Chip(label: Text(equipmentName)),
            ],
          ),
          if (exercise.description != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(exercise.description!, style: AppTypography.caption),
          ],
          if (exercise.instructions != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('How to', style: AppTypography.h6),
            const SizedBox(height: AppSpacing.xs),
            Text(
              exercise.instructions!,
              style: AppTypography.caption.copyWith(
                color: AppColors.mutedOnDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final ExerciseSession session;

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
                child: Text(
                  DateFormat.yMMMEd().format(session.date),
                  style: AppTypography.h6,
                ),
              ),
              Text(
                '${session.volume.round()} lb',
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in session.sets)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cta,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    formatSet(s),
                    style: AppTypography.small.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                ),
            ],
          ),
          if (session.notes != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              session.notes!,
              style: AppTypography.small.copyWith(
                color: AppColors.mutedOnDark,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "135 × 8", degrading gracefully when only one of the two was recorded.
String formatSet(WorkoutSet s) {
  final w = s.weight;
  final r = s.reps;
  if (w != null && r != null) return '${trimNumber(w)} × $r';
  if (w != null) return trimNumber(w);
  if (r != null) return '$r reps';
  return '—';
}

/// Drops the trailing ".0" so whole weights read as "135", not "135.0".
String trimNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
