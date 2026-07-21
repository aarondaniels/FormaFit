import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';

/// Multi-select exercise picker. Returns the chosen ids in tap order, or null
/// if dismissed.
Future<List<int>?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ExercisePickerSheet(),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet();

  @override
  ConsumerState<_ExercisePickerSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_ExercisePickerSheet> {
  final _selected = <int>[];
  String _query = '';
  String? _group;

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider).value ?? const [];
    final groups = ref.watch(muscleGroupsInUseProvider).value ?? const [];

    final filtered = exercises.where((e) {
      if (_group != null && e.muscleGroup != _group) return false;
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
            child: Row(
              children: [
                Expanded(child: Text('Add exercises', style: AppTypography.h4)),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  child: Text(
                    _selected.isEmpty ? 'Add' : 'Add ${_selected.length}',
                  ),
                ),
              ],
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
          if (groups.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: FilterChip(
                        label: Text(g),
                        selected: _group == g,
                        onSelected: (on) =>
                            setState(() => _group = on ? g : null),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No matches',
                    message: 'Try a different search or filter.',
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final index = _selected.indexOf(e.id);
                      return _PickerRow(
                        exercise: e,
                        // Show tap order, so a multi-add lands in the order
                        // the user chose rather than list order.
                        order: index == -1 ? null : index + 1,
                        onTap: () => setState(() {
                          if (index == -1) {
                            _selected.add(e.id);
                          } else {
                            _selected.removeAt(index);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.exercise,
    required this.order,
    required this.onTap,
  });

  final Exercise exercise;
  final int? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order != null;
    return ListTile(
      onTap: onTap,
      title: Text(exercise.name),
      subtitle: exercise.muscleGroup == null
          ? null
          : Text(
              exercise.muscleGroup!,
              style: AppTypography.small.copyWith(
                color: AppColors.mutedOnDark,
              ),
            ),
      trailing: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cta,
            width: 2,
          ),
          shape: BoxShape.circle,
        ),
        child: selected
            ? Center(
                child: Text(
                  '$order',
                  style: AppTypography.small.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
