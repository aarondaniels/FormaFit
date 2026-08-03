/// Body measurements: an overview of everything tracked, a per-kind history,
/// and batch entry.
///
/// Measuring is a batch act — the tape comes out once and five or six values
/// follow — so entry is one sheet covering every tracked kind rather than a
/// modal per value, and the screen opens on all kinds at once instead of one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/glass.dart';
import 'exercise_detail_screen.dart' show trimNumber;

/// Color for a change, given which direction counts as progress for the kind.
///
/// Kinds with no universal direction ([MeasurementGoal.neutral] — body weight
/// above all) stay neutral rather than guessing whether the user is cutting or
/// bulking and congratulating them for the opposite.
Color changeColor(String kind, double change) {
  if (change == 0) return AppColors.mutedOnDark;
  return switch (MeasurementKinds.goalFor(kind)) {
    MeasurementGoal.increase =>
      change > 0 ? AppColors.success : AppColors.warning,
    MeasurementGoal.decrease =>
      change < 0 ? AppColors.success : AppColors.warning,
    MeasurementGoal.neutral => AppColors.primary,
  };
}

/// A signed change, e.g. "+1.5 in" / "-2 lb".
String formatChange(double change, String unit) =>
    '${change > 0 ? '+' : ''}${trimNumber(change)} $unit';

/// "Today" / "Yesterday" / "12 days ago", for how stale a measurement is.
String formatAge(int days) => switch (days) {
  <= 0 => 'Today',
  1 => 'Yesterday',
  _ => '$days days ago',
};

class MeasurementsScreen extends ConsumerWidget {
  const MeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(measurementSummariesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(
        leading: GlassBackButton(),
        title: Text('Measurements'),
      ),
      body: summaries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(
          error: e,
          onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.straighten,
              title: 'No measurements yet',
              message:
                  'Record body weight and tape measurements to watch them '
                  'move alongside your training.',
              action: FilledButton.icon(
                onPressed: () => showMeasurementSession(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Log measurements'),
              ),
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              glassTopInset(context) + AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => showMeasurementSession(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Log measurements'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassSection(
                title: 'Tracked',
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Divider(height: 1),
                        ),
                      _SummaryRow(summary: list[i]),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One kind in the overview: where it stands, how far it has moved, when it was
/// last taken, and the shape of its history.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final MeasurementSummary summary;

  @override
  Widget build(BuildContext context) {
    final change = summary.changeOverall;
    final age = summary.daysSince(DateTime.now());

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MeasurementDetailScreen(kind: summary.kind),
        ),
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.kind, style: AppTypography.h6),
                  const SizedBox(height: 2),
                  Text(
                    formatAge(age),
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 56,
              height: 32,
              child: Sparkline(
                points: summary.series,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${trimNumber(summary.latest)} ${summary.unit}',
                  style: AppTypography.numeric,
                ),
                const SizedBox(height: 2),
                Text(
                  change == null
                      ? 'First entry'
                      : formatChange(change, summary.unit),
                  style: AppTypography.small.copyWith(
                    color: change == null
                        ? AppColors.mutedOnDark
                        : changeColor(summary.kind, change),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.mutedOnDark,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full history for one kind: the trend, where it stands, and every entry.
class MeasurementDetailScreen extends ConsumerWidget {
  const MeasurementDetailScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(measurementsProvider(kind));
    final series = ref.watch(measurementSeriesProvider(kind));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const GlassBackButton(),
        title: Text(kind),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showMeasurementSession(context, ref, onlyKind: kind),
        icon: const Icon(Icons.add),
        label: const Text('Log'),
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(error: e),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.straighten,
              title: 'No $kind entries',
              message: 'Log a value to start tracking $kind over time.',
              action: FilledButton.icon(
                onPressed: () =>
                    showMeasurementSession(context, ref, onlyKind: kind),
                icon: const Icon(Icons.add),
                label: const Text('Log measurement'),
              ),
            );
          }

          final latest = list.first;
          final points = series.value ?? const <TimePoint>[];
          final change = points.length >= 2
              ? points.last.value - points.first.value
              : null;
          // Body weight swings day to day with water and food; the trailing
          // average is the line worth reading. Tape measurements are taken far
          // apart and don't need it.
          final trend = kind == MeasurementKinds.bodyWeight
              ? ApiClient.rollingAverage(points)
              : null;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              glassTopInset(context) + AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl * 3,
            ),
            children: [
              GlassSection(
                title: 'Current',
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: '${trimNumber(latest.value)} ${latest.unit}',
                        label: DateFormat.yMMMd().format(latest.date),
                      ),
                    ),
                    if (change != null)
                      Expanded(
                        child: StatTile(
                          value: formatChange(change, latest.unit),
                          label: 'Since first entry',
                          color: changeColor(kind, change),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (points.length >= 2) ...[
                GlassSection(
                  title: trend != null && trend.length >= 2
                      ? 'Trend (7-day average)'
                      : 'Trend',
                  child: SizedBox(
                    height: 200,
                    child: TimeSeriesChart(
                      points: points,
                      trend: trend,
                      color: AppColors.primary,
                      unit: ' ${latest.unit}',
                      // Ranges here are narrow — a whole arm history can sit
                      // between 16 and 17 in — so integer axis labels would
                      // repeat instead of describing anything.
                      decimals: 1,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              GlassSection(
                title: 'History',
                child: Column(
                  children: [
                    for (final m in list)
                      _HistoryRow(measurement: m, kind: kind),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One stored entry: tap to correct it, swipe to remove it.
class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.measurement, required this.kind});

  final Measurement measurement;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(measurement.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final removed = measurement;
        await mutateWith(ref, (api) => api.deleteMeasurement(removed.id));
        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted ${trimNumber(removed.value)} ${removed.unit}'),
            action: SnackBarAction(
              label: 'Undo',
              // Restores the values, not the id — a measurement is its date and
              // number, and the row reappears where it was.
              onPressed: () => mutateWith(
                ref,
                (api) => api.createMeasurement(
                  date: removed.date,
                  kind: removed.kind,
                  value: removed.value,
                  unit: removed.unit,
                  notes: removed.notes,
                ),
              ),
            ),
          ),
        );
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => _showEditSheet(context, ref, measurement),
        title: Text(
          '${trimNumber(measurement.value)} ${measurement.unit}',
          style: AppTypography.numeric,
        ),
        subtitle: Text(
          DateFormat.yMMMEd().format(measurement.date),
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
        trailing: measurement.notes == null
            ? null
            : Text(
                measurement.notes!,
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
      ),
    );
  }
}

/// Opens the batch entry sheet.
///
/// Pass [onlyKind] to record a single kind (from its detail screen); otherwise
/// every tracked kind is offered at once.
Future<void> showMeasurementSession(
  BuildContext context,
  WidgetRef ref, {
  String? onlyKind,
}) async {
  final summaries = await ref.read(measurementSummariesProvider.future);
  if (!context.mounted) return;

  final previous = {for (final s in summaries) s.kind: s};
  final kinds = onlyKind != null
      ? [onlyKind]
      : summaries.isEmpty
      // Nothing tracked yet: body weight is the near-universal starting point,
      // and the sheet's "Add measurement" covers the rest.
      ? [MeasurementKinds.bodyWeight]
      : [for (final s in summaries) s.kind];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SessionSheet(initialKinds: kinds, previous: previous),
  );
}

class _SessionSheet extends ConsumerStatefulWidget {
  const _SessionSheet({required this.initialKinds, required this.previous});

  final List<String> initialKinds;
  final Map<String, MeasurementSummary> previous;

  @override
  ConsumerState<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<_SessionSheet> {
  late final List<String> _kinds = [...widget.initialKinds];
  final Map<String, TextEditingController> _controllers = {};
  DateTime _date = DateTime.now();
  bool _saving = false;

  TextEditingController _controllerFor(String kind) =>
      _controllers.putIfAbsent(kind, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Standard kinds not already on the sheet.
  List<String> get _available =>
      [for (final k in MeasurementKinds.all) if (!_kinds.contains(k)) k];

  Future<void> _save() async {
    final entries = <MeasurementDraft>[];
    for (final kind in _kinds) {
      final text = _controllerFor(kind).text.trim();
      // Blank rows are skipped, so a partial session costs nothing.
      if (text.isEmpty) continue;
      final value = double.tryParse(text);
      if (value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$kind needs a number.')),
        );
        return;
      }
      entries.add(MeasurementDraft(kind: kind, value: value));
    }

    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one value.')),
      );
      return;
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    // One queued write for the whole session rather than one per value.
    await mutateWith(
      ref,
      (api) => api.createMeasurements(date: _date, entries: entries),
    );
    if (mounted) navigator.pop();
  }

  Future<void> _addKind() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final kind in _available)
              ListTile(
                title: Text(kind),
                trailing: Text(
                  MeasurementKinds.unitFor(kind),
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(kind),
              ),
          ],
        ),
      ),
    );
    if (choice != null) setState(() => _kinds.add(choice));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log measurements', style: AppTypography.h4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, size: 20),
              title: Text(DateFormat.yMMMEd().format(_date)),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: const Text('Change'),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final kind in _kinds)
                    _SessionRow(
                      kind: kind,
                      controller: _controllerFor(kind),
                      previous: widget.previous[kind],
                      autofocus: kind == _kinds.first,
                    ),
                ],
              ),
            ),
            if (_available.isNotEmpty)
              TextButton.icon(
                onPressed: _addKind,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add measurement'),
              ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One kind's field in a session, with the last recorded value beneath it.
///
/// Measurements move slowly, so the previous number is both the anchor and the
/// typo check — "16.5 or 17.5?" is only answerable against last time. Tapping
/// it copies it in, the same affordance the workout logger uses for sets.
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.kind,
    required this.controller,
    required this.previous,
    required this.autofocus,
  });

  final String kind;
  final TextEditingController controller;
  final MeasurementSummary? previous;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final unit = previous?.unit ?? MeasurementKinds.unitFor(kind);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind, style: AppTypography.h6),
                  if (previous != null)
                    GestureDetector(
                      onTap: () {
                        controller.text = trimNumber(previous!.latest);
                        controller.selection = TextSelection.collapsed(
                          offset: controller.text.length,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Last ${trimNumber(previous!.latest)} $unit · '
                          '${formatAge(previous!.daysSince(DateTime.now()))}',
                          style: AppTypography.small.copyWith(
                            color: AppColors.mutedOnDark,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 108,
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: previous == null
                    ? null
                    : trimNumber(previous!.latest),
                suffixText: unit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Corrects a stored entry. A mistyped value used to mean deleting the row and
/// re-adding it.
Future<void> _showEditSheet(
  BuildContext context,
  WidgetRef ref,
  Measurement measurement,
) async {
  final valueController = TextEditingController(
    text: trimNumber(measurement.value),
  );
  final notesController = TextEditingController(text: measurement.notes ?? '');
  var date = measurement.date;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md,
      ),
      child: StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit ${measurement.kind}', style: AppTypography.h4),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: valueController,
              autofocus: true,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Value',
                suffixText: measurement.unit,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, size: 20),
              title: Text(DateFormat.yMMMEd().format(date)),
              trailing: TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
                child: const Text('Change'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final value = double.tryParse(valueController.text.trim());
                  if (value == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Enter a number.')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  final notes = notesController.text.trim();
                  mutateWith(
                    ref,
                    // Built directly rather than via copyWith, which coalesces
                    // a null note back to the old one and so can't clear it.
                    (api) => api.updateMeasurement(
                      Measurement(
                        id: measurement.id,
                        date: date,
                        kind: measurement.kind,
                        value: value,
                        unit: measurement.unit,
                        notes: notes.isEmpty ? null : notes,
                      ),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  valueController.dispose();
  notesController.dispose();
}
