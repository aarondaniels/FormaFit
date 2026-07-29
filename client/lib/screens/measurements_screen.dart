import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/glass.dart';
import 'exercise_detail_screen.dart' show trimNumber;

class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  String _kind = MeasurementKinds.bodyWeight;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(measurementsProvider(_kind));
    final series = ref.watch(measurementSeriesProvider(_kind));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(
        leading: GlassBackButton(),
        title: Text('Measurements'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEntrySheet(context, ref, kind: _kind),
        icon: const Icon(Icons.add),
        label: const Text('Log'),
      ),
      body: Column(
        children: [
          SizedBox(height: glassTopInset(context) + AppSpacing.sm),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                for (final k in MeasurementKinds.all)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(k),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncFailure(error: e),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.straighten,
                    title: 'No $_kind entries',
                    message:
                        'Log a value to start tracking $_kind over time.',
                    action: FilledButton.icon(
                      onPressed: () =>
                          _showEntrySheet(context, ref, kind: _kind),
                      icon: const Icon(Icons.add),
                      label: const Text('Log measurement'),
                    ),
                  );
                }

                final latest = list.first;
                final points = series.value ?? const <TimePoint>[];
                // Change since the first recorded value, which is the number
                // people actually want from a measurements list.
                final change = points.length >= 2
                    ? points.last.value - points.first.value
                    : null;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl * 2,
                  ),
                  children: [
                    GlassSection(
                      title: 'Current',
                      child: Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              value:
                                  '${trimNumber(latest.value)} ${latest.unit}',
                              label: DateFormat.yMMMd().format(latest.date),
                            ),
                          ),
                          if (change != null)
                            Expanded(
                              child: StatTile(
                                value:
                                    '${change >= 0 ? '+' : ''}'
                                    '${trimNumber(change)} ${latest.unit}',
                                label: 'Since first entry',
                                color: change >= 0
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (points.length >= 2) ...[
                      GlassSection(
                        title: 'Trend',
                        child: SizedBox(
                          height: 200,
                          child: TimeSeriesChart(
                            points: points,
                            color: AppColors.primary,
                            unit: ' ${latest.unit}',
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
                            Dismissible(
                              key: ValueKey(m.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.md,
                                ),
                                color: AppColors.error,
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) => mutateWith(
                                ref,
                                (api) => api.deleteMeasurement(m.id),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${trimNumber(m.value)} ${m.unit}',
                                  style: AppTypography.numeric,
                                ),
                                subtitle: Text(
                                  DateFormat.yMMMEd().format(m.date),
                                  style: AppTypography.small.copyWith(
                                    color: AppColors.mutedOnDark,
                                  ),
                                ),
                                trailing: m.notes == null
                                    ? null
                                    : Text(
                                        m.notes!,
                                        style: AppTypography.small.copyWith(
                                          color: AppColors.mutedOnDark,
                                        ),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
}) async {
  final valueController = TextEditingController();
  final notesController = TextEditingController();
  var date = DateTime.now();

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
            Text('Log $kind', style: AppTypography.h4),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: valueController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Value',
                suffixText: MeasurementKinds.unitFor(kind),
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
                  mutateWith(
                    ref,
                    (api) => api.createMeasurement(
                      date: date,
                      kind: kind,
                      value: value,
                      notes: notesController.text.trim().isEmpty
                          ? null
                          : notesController.text.trim(),
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
