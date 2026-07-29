import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../../widgets/rest.dart';
import '../exercise_detail_screen.dart' show trimNumber;
import '../workout/exercise_picker_sheet.dart';

/// Builds a reusable workout: an ordered exercise list with default sets,
/// weight and reps.
class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({
    super.key,
    required this.folderId,
    this.existing,
  });

  final int folderId;
  final Template? existing;

  @override
  ConsumerState<TemplateEditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<TemplateEditorScreen> {
  late final TextEditingController _name;
  final List<_Row> _rows = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    if (existing != null) {
      final ordered = [...existing.exercises]
        ..sort((a, b) => a.order.compareTo(b.order));
      for (final te in ordered) {
        _rows.add(
          _Row(
            exerciseId: te.exerciseId,
            sets: te.defaultSets,
            weight: te.defaultWeight,
            reps: te.defaultReps,
            restSeconds: te.restSeconds,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _addExercises() async {
    final picked = await showExercisePicker(context);
    if (picked == null) return;
    setState(() {
      for (final id in picked) {
        _rows.add(_Row(exerciseId: id, sets: 3));
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the template a name.')),
      );
      return;
    }
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise.')),
      );
      return;
    }

    setState(() => _saving = true);
    final exercises = [
      for (var i = 0; i < _rows.length; i++)
        TemplateExercise(
          exerciseId: _rows[i].exerciseId,
          order: i,
          defaultSets: _rows[i].sets,
          defaultWeight: _rows[i].weight,
          defaultReps: _rows[i].reps,
          restSeconds: _rows[i].restSeconds,
        ),
    ];

    try {
      final existing = widget.existing;
      await mutateWith(ref, (api) {
        if (existing == null) {
          return api.createTemplate(
            folderId: widget.folderId,
            name: name,
            exercises: exercises,
          );
        }
        return api.updateTemplate(
          id: existing.id,
          name: name,
          exercises: exercises,
        );
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesByIdProvider).value ?? {};

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const GlassBackButton(icon: Icons.close),
        title: Text(
          widget.existing == null ? 'New template' : 'Edit template',
        ),
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
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Template name'),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_rows.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(
                    Icons.list_alt,
                    size: 40,
                    color: AppColors.cta,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('No exercises yet', style: AppTypography.h5),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Add the exercises this workout should include.',
                    textAlign: TextAlign.center,
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                ],
              ),
            )
          else
            // Drag to set the order exercises appear in when the template is
            // applied to a workout.
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _rows.length,
              onReorder: (oldIndex, newIndex) => setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                _rows.insert(newIndex, _rows.removeAt(oldIndex));
              }),
              itemBuilder: (context, i) => Padding(
                key: ValueKey(_rows[i]),
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ExerciseRowCard(
                  index: i,
                  row: _rows[i],
                  name: exercises[_rows[i].exerciseId]?.name ?? 'Exercise',
                  onRemove: () => setState(() => _rows.removeAt(i).dispose()),
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _addExercises,
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save template'),
          ),
        ],
      ),
    );
  }
}

class _ExerciseRowCard extends StatelessWidget {
  const _ExerciseRowCard({
    required this.index,
    required this.row,
    required this.name,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _Row row;
  final String name;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    Icons.drag_handle,
                    size: 20,
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
              Expanded(child: Text(name, style: AppTypography.h6)),
              RestChip(
                seconds: row.restSeconds,
                onChanged: (v) {
                  row.restSeconds = v;
                  onChanged();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Sets',
                  controller: row.setsController,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: 'Weight',
                  controller: row.weightController,
                  decimal: true,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: 'Reps',
                  controller: row.repsController,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textAlign: TextAlign.center,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        hintText: '—',
      ),
    );
  }
}

/// One template exercise being edited.
class _Row {
  _Row({
    required this.exerciseId,
    int sets = 3,
    double? weight,
    int? reps,
    this.restSeconds = 90,
  }) : setsController = TextEditingController(text: '$sets'),
       weightController = TextEditingController(
         text: weight == null ? '' : trimNumber(weight),
       ),
       repsController = TextEditingController(text: reps?.toString() ?? '');

  final int exerciseId;
  final TextEditingController setsController;
  final TextEditingController weightController;
  final TextEditingController repsController;

  /// Rest between sets, in seconds; carried into a workout. Mutable via the
  /// rest chip.
  int restSeconds;

  /// At least one set, so an applied template always produces a row to fill in.
  int get sets {
    final parsed = int.tryParse(setsController.text.trim()) ?? 1;
    return parsed < 1 ? 1 : parsed;
  }

  double? get weight => double.tryParse(weightController.text.trim());

  int? get reps => int.tryParse(repsController.text.trim());

  void dispose() {
    setsController.dispose();
    weightController.dispose();
    repsController.dispose();
  }
}
