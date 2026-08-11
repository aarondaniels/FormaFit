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
    final sessions = await ref.read(exerciseHistoryProvider(exerciseId).future);
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

  /// Consolidates this exercise into another the user chooses: its history and
  /// template references move over, then this one is deleted.
  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    Exercise source,
  ) async {
    final target = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MergeTargetSheet(excludeId: source.id),
    );
    if (target == null || !context.mounted) return;

    final sessions = await ref.read(exerciseHistoryProvider(source.id).future);
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge exercise?'),
        content: Text(
          'Move all history from “${source.name}” into “${target.name}”'
          '${sessions.isEmpty ? '' : ' (${sessions.length} '
                    '${sessions.length == 1 ? "session" : "sessions"})'}, '
          'then delete “${source.name}”. This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await mutateWith(
      ref,
      (api) => api.mergeExercise(sourceId: source.id, targetId: target.id),
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = ref.watch(exercisesByIdProvider);
    final exercise = byId.value?[exerciseId];
    final history = ref.watch(exerciseHistoryProvider(exerciseId));
    final progress = ref.watch(exerciseProgressProvider(exerciseId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const GlassBackButton(),
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
          if (exercise != null)
            GlassIconButton(
              icon: const Icon(Icons.merge_type),
              onPressed: () => _merge(context, ref, exercise),
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
                progress.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (p) {
                    final hasData =
                        p.estimatedOneRepMax.isNotEmpty ||
                        p.topWeight.isNotEmpty ||
                        p.volume.isNotEmpty ||
                        p.reps.isNotEmpty;
                    return hasData
                        ? Column(
                            children: [
                              _ProgressSection(progress: p),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                          )
                        : const SizedBox.shrink();
                  },
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
                                _SessionRow(
                                  session: s,
                                  bodyweight: exercise.isBodyweight,
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// The progression metrics chartable for an exercise over its logged history.
enum _Metric {
  oneRepMax('1RM', 'Estimated 1RM', 'lb'),
  topWeight('Weight', 'Heaviest weight', 'lb'),
  volume('Volume', 'Total volume', 'lb'),
  reps('Reps', 'Total reps', 'reps');

  const _Metric(this.chip, this.title, this.unit);

  /// Short label for the toggle chip.
  final String chip;

  /// Section heading for this metric.
  final String title;

  /// Unit suffix for the best-value readout and chart.
  final String unit;
}

/// Time-series progression for an exercise across its full logged history —
/// switchable between estimated 1RM, heaviest weight, and volume — with the
/// date span, best value, and a metric explainer.
class _ProgressSection extends StatefulWidget {
  const _ProgressSection({required this.progress});

  final ExerciseProgress progress;

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  late _Metric _metric = _available.first;

  List<_Metric> get _available => [
    if (widget.progress.estimatedOneRepMax.isNotEmpty) _Metric.oneRepMax,
    if (widget.progress.topWeight.isNotEmpty) _Metric.topWeight,
    if (widget.progress.volume.isNotEmpty) _Metric.volume,
    if (widget.progress.reps.isNotEmpty) _Metric.reps,
  ];

  List<TimePoint> _series(_Metric m) => switch (m) {
    _Metric.oneRepMax => widget.progress.estimatedOneRepMax,
    _Metric.topWeight => widget.progress.topWeight,
    _Metric.volume => widget.progress.volume,
    _Metric.reps => widget.progress.reps,
  };

  String _tooltip(_Metric m) => switch (m) {
    _Metric.oneRepMax =>
      'Estimated one-rep max — the most weight you could lift for a single '
          'rep. Estimated from each logged set with the Epley formula, '
          'weight × (1 + reps ÷ 30); each session plots its best set.',
    _Metric.topWeight =>
      'The heaviest weight you lifted for this exercise in each session.',
    _Metric.volume =>
      'Total weight moved per session — the sum of weight × reps across '
          'every set.',
    _Metric.reps => 'Total reps performed for this exercise in each session.',
  };

  @override
  Widget build(BuildContext context) {
    final available = _available;
    // Guard against the selected metric losing its data after a store change.
    final metric = available.contains(_metric) ? _metric : available.first;
    final points = _series(metric);
    final first = points.first.date;
    final last = points.last.date;
    final best = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final fmt = DateFormat.yMMMd();
    final span = first == last
        ? fmt.format(first)
        : '${fmt.format(first)} – ${fmt.format(last)}';

    return GlassSection(
      title: metric.title,
      trailing: Tooltip(
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 8),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        message: _tooltip(metric),
        child: const Icon(
          Icons.info_outline,
          size: 18,
          color: AppColors.mutedOnDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (available.length > 1) ...[
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in available)
                  ChoiceChip(
                    label: Text(m.chip),
                    selected: metric == m,
                    onSelected: (_) => setState(() => _metric = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  span,
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              Text(
                'Best ${trimNumber(best)} ${metric.unit}',
                style: AppTypography.numeric.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 180,
            child: TimeSeriesChart(
              points: points,
              color: AppColors.primary,
              unit: metric.unit == 'reps' ? ' reps' : ' ${metric.unit}',
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.bodyweight});

  final ExerciseSession session;

  /// Drops the tonnage line and the weight on each set chip: this exercise is
  /// counted in reps.
  final bool bodyweight;

  @override
  Widget build(BuildContext context) {
    final totalReps = session.sets.fold<int>(
      0,
      (sum, s) => sum + (s.reps ?? 0),
    );
    final totalVolume = session.volume;
    final n = NumberFormat.decimalPattern();
    final summary = [
      '${session.sets.length} ${session.sets.length == 1 ? "set" : "sets"}',
      if (totalReps > 0) '$totalReps reps',
      if (!bodyweight && totalVolume > 0) '${n.format(totalVolume.round())} lb',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMEd().format(session.date),
            style: AppTypography.h6,
          ),
          const SizedBox(height: 2),
          Text(
            summary,
            style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
          ),
          const SizedBox(height: AppSpacing.sm),
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
                    formatSet(s, bodyweight: bodyweight),
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
///
/// [bodyweight] drops the weight half whatever is stored, so an exercise marked
/// as carrying no load reads the same way its stats are counted — a leftover
/// weight from before it was marked (or a 0 out of a Strong CSV) shows as reps
/// rather than as "0 × 12".
String formatSet(WorkoutSet s, {bool bodyweight = false}) {
  final w = bodyweight ? null : s.weight;
  final r = s.reps;
  if (w != null && r != null) return '${trimNumber(w)} × $r';
  if (w != null) return trimNumber(w);
  if (r != null) return '$r reps';
  return '—';
}

/// Drops the trailing ".0" so whole weights read as "135", not "135.0".
String trimNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Single-select exercise chooser for a merge target, excluding the exercise
/// being merged. Pops with the chosen [Exercise].
class _MergeTargetSheet extends ConsumerStatefulWidget {
  const _MergeTargetSheet({required this.excludeId});

  final int excludeId;

  @override
  ConsumerState<_MergeTargetSheet> createState() => _MergeTargetSheetState();
}

class _MergeTargetSheetState extends ConsumerState<_MergeTargetSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider).value ?? const [];
    final filtered = exercises.where((e) {
      if (e.id == widget.excludeId) return false;
      if (_query.isEmpty) return true;
      return e.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cta,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Merge into', style: AppTypography.h4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No other exercises',
                    message: 'There is nothing to merge into.',
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      return ListTile(
                        title: Text(e.name),
                        subtitle: e.muscleGroup == null
                            ? null
                            : Text(
                                e.muscleGroup!,
                                style: AppTypography.small.copyWith(
                                  color: AppColors.mutedOnDark,
                                ),
                              ),
                        onTap: () => Navigator.of(context).pop(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
