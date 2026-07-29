import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';

/// Create or edit an exercise. Pass [existing] to edit.
///
/// On save it pops with the created/updated [Exercise], so callers like the
/// exercise picker can immediately use a freshly created one.
class ExerciseFormScreen extends ConsumerStatefulWidget {
  const ExerciseFormScreen({super.key, this.existing, this.initialName});

  final Exercise? existing;

  /// Prefills the name field when creating — used by "create from search".
  final String? initialName;

  @override
  ConsumerState<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends ConsumerState<ExerciseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _instructions;
  String? _muscleGroup;
  int? _equipmentTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? widget.initialName ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _instructions = TextEditingController(text: e?.instructions ?? '');
    _muscleGroup = e?.muscleGroup;
    _equipmentTypeId = e?.equipmentTypeId;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final saved = await mutateWith(ref, (api) async {
        if (existing == null) {
          return api.createExercise(
            name: _name.text.trim(),
            muscleGroup: _muscleGroup,
            description: _emptyToNull(_description.text),
            equipmentTypeId: _equipmentTypeId,
            instructions: _emptyToNull(_instructions.text),
          );
        }
        return api.updateExercise(
          Exercise(
            id: existing.id,
            name: _name.text.trim(),
            muscleGroup: _muscleGroup,
            description: _emptyToNull(_description.text),
            equipmentTypeId: _equipmentTypeId,
            instructions: _emptyToNull(_instructions.text),
            isDefault: existing.isDefault,
          ),
        );
      });
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  static String? _emptyToNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final equipment = ref.watch(equipmentTypesProvider).value ?? const [];
    final isEdit = widget.existing != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const GlassBackButton(icon: Icons.close),
        title: Text(isEdit ? 'Edit exercise' : 'New exercise'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: glassPagePadding(context),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _muscleGroup,
              decoration: const InputDecoration(labelText: 'Muscle group'),
              items: [
                for (final g in MuscleGroups.all)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _muscleGroup = v),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int>(
              initialValue: _equipmentTypeId,
              decoration: const InputDecoration(labelText: 'Equipment'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final t in equipment)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _equipmentTypeId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _instructions,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Instructions'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
