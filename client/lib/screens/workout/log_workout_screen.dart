import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../exercise_detail_screen.dart' show trimNumber;
import 'exercise_picker_sheet.dart';
import 'template_picker_screen.dart';

/// Composes a workout in memory and writes it in one shot on save.
///
/// Nothing is persisted until the user saves, so an abandoned session leaves
/// no half-logged workout behind.
class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({super.key, this.existing});

  /// When set, the screen edits this workout instead of starting a new one.
  final Workout? existing;

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen> {
  final List<_ExerciseEntry> _entries = [];
  final _notes = TextEditingController();

  DateTime _date = DateTime.now();
  int _effort = 5;
  String? _templateName;
  bool _saving = false;

  /// Wall-clock timer for a live session. Editing an existing workout keeps
  /// its recorded duration rather than timing the edit.
  Stopwatch? _stopwatch;
  Timer? _ticker;
  int? _fixedDuration;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _date = existing.date;
      _effort = existing.effortLevel;
      _templateName = existing.templateName;
      _notes.text = existing.notes ?? '';
      _fixedDuration = existing.duration;
      for (final we in existing.exercises) {
        _entries.add(
          _ExerciseEntry(
            exerciseId: we.exerciseId,
            notes: we.notes,
            sets: [
              for (final s in we.sets) _SetEntry(weight: s.weight, reps: s.reps),
            ],
          ),
        );
      }
    } else {
      _stopwatch = Stopwatch()..start();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notes.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  int? get _duration => _stopwatch?.elapsed.inSeconds ?? _fixedDuration;

  Future<void> _addExercises() async {
    final picked = await showExercisePicker(context);
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final id in picked) {
        _entries.add(_ExerciseEntry(exerciseId: id, sets: [_SetEntry()]));
      }
    });
  }

  Future<void> _applyTemplate() async {
    final template = await Navigator.of(context).push<Template>(
      MaterialPageRoute(builder: (_) => const TemplatePickerScreen()),
    );
    if (template == null) return;
    setState(() {
      _templateName = template.name;
      for (final te in template.exercises) {
        _entries.add(
          _ExerciseEntry(
            exerciseId: te.exerciseId,
            sets: List.generate(
              // A template with zero sets still needs one row to type into.
              te.defaultSets < 1 ? 1 : te.defaultSets,
              (_) => _SetEntry(
                weight: te.defaultWeight,
                reps: te.defaultReps,
              ),
            ),
          ),
        );
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first.')),
      );
      return;
    }
    setState(() => _saving = true);
    _stopwatch?.stop();

    final drafts = [
      for (final e in _entries)
        WorkoutExerciseDraft(
          exerciseId: e.exerciseId,
          notes: e.notes,
          // Drop rows the user left completely blank rather than storing
          // empty sets that would skew set counts.
          sets: [
            for (final s in e.sets)
              if (!s.isEmpty)
                WorkoutSetDraft(weight: s.weight, reps: s.reps),
          ],
        ),
    ]..removeWhere((d) => d.sets.isEmpty);

    if (drafts.isEmpty) {
      setState(() {
        _saving = false;
        _stopwatch?.start();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a weight or reps for a set.')),
      );
      return;
    }

    try {
      final existing = widget.existing;
      await mutateWith(ref, (api) async {
        if (existing == null) {
          return api.createWorkout(
            date: _date,
            effortLevel: _effort,
            notes: _emptyToNull(_notes.text),
            templateName: _templateName,
            duration: _duration,
            exercises: drafts,
          );
        }
        return api.updateWorkout(
          id: existing.id,
          date: _date,
          effortLevel: _effort,
          notes: _emptyToNull(_notes.text),
          duration: _duration,
          exercises: drafts,
        );
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _stopwatch?.start();
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_entries.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('This session has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static String? _emptyToNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final elapsed = _stopwatch?.elapsed;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: Text(isEdit ? 'Edit workout' : 'Log workout'),
          actions: [
            GlassIconButton(
              icon: const Icon(Icons.check),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: ListView(
          padding: glassPagePadding(context),
          children: [
            GlassSection(
              title: 'Session',
              trailing: elapsed == null
                  ? null
                  : Text(
                      _formatElapsed(elapsed),
                      style: AppTypography.numeric.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: Text(DateFormat.yMMMEd().format(_date)),
                    trailing: TextButton(
                      onPressed: _pickDate,
                      child: const Text('Change'),
                    ),
                  ),
                  if (_templateName != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined, size: 20),
                      title: Text(_templateName!),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _templateName = null),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text('Effort', style: AppTypography.caption),
                      Expanded(
                        child: Slider(
                          value: _effort.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_effort',
                          onChanged: (v) =>
                              setState(() => _effort = v.round()),
                        ),
                      ),
                      Text(
                        '$_effort/10',
                        style: AppTypography.numeric.copyWith(
                          color: AppColors.mutedOnDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_entries.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 40,
                      color: AppColors.cta,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No exercises yet',
                      style: AppTypography.h5,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Add exercises directly, or start from a template.',
                      textAlign: TextAlign.center,
                      style: AppTypography.small.copyWith(
                        color: AppColors.mutedOnDark,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < _entries.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ExerciseCard(
                    entry: _entries[i],
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() {
                      _entries.removeAt(i).dispose();
                    }),
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addExercises,
                    icon: const Icon(Icons.add),
                    label: const Text('Add exercise'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _applyTemplate,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Template'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Workout notes'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save workout'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  final _ExerciseEntry entry;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise =
        ref.watch(exercisesByIdProvider).value?[entry.exerciseId];
    final lastSession = ref
        .watch(exerciseHistoryProvider(entry.exerciseId))
        .value
        ?.firstOrNull;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise?.name ?? 'Exercise',
                  style: AppTypography.h5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          if (lastSession != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Last time: ${lastSession.sets.map(_shortSet).join(', ')}',
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const SizedBox(width: 28),
              Expanded(
                child: Text(
                  'Weight (lb)',
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Reps',
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < entry.sets.length; i++)
            _SetRow(
              index: i,
              set: entry.sets[i],
              onRemove: entry.sets.length == 1
                  ? null
                  : () {
                      entry.sets.removeAt(i).dispose();
                      onChanged();
                    },
            ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: () {
              // Carry the previous set's values forward — most sets repeat the
              // one before them, so this is usually the right starting point.
              final prev = entry.sets.lastOrNull;
              entry.sets.add(
                _SetEntry(weight: prev?.weight, reps: prev?.reps),
              );
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add set'),
          ),
        ],
      ),
    );
  }

  static String _shortSet(WorkoutSet s) {
    final w = s.weight;
    final r = s.reps;
    if (w != null && r != null) return '${trimNumber(w)}×$r';
    if (w != null) return trimNumber(w);
    return '${r ?? 0}';
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.index, required this.set, this.onRemove});

  final int index;
  final _SetEntry set;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: AppTypography.numeric.copyWith(
                color: AppColors.mutedOnDark,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: set.weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, hintText: '—'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: set.repsController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, hintText: '—'),
            ),
          ),
          SizedBox(
            width: 40,
            child: onRemove == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: AppColors.mutedOnDark,
                    onPressed: onRemove,
                  ),
          ),
        ],
      ),
    );
  }
}

/// One exercise being composed, holding its own set rows.
class _ExerciseEntry {
  _ExerciseEntry({
    required this.exerciseId,
    this.notes,
    required List<_SetEntry> sets,
  }) : sets = List.of(sets);

  final int exerciseId;
  final String? notes;
  final List<_SetEntry> sets;

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

/// A set row's live text, kept in controllers so partially-typed values
/// survive rebuilds.
class _SetEntry {
  _SetEntry({double? weight, int? reps})
    : weightController = TextEditingController(
        text: weight == null ? '' : trimNumber(weight),
      ),
      repsController = TextEditingController(
        text: reps?.toString() ?? '',
      );

  final TextEditingController weightController;
  final TextEditingController repsController;

  double? get weight => double.tryParse(weightController.text.trim());

  int? get reps => int.tryParse(repsController.text.trim());

  bool get isEmpty => weight == null && reps == null;

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}
