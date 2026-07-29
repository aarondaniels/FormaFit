import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';

/// Picks a template to start a workout from. Pops with the chosen [Template].
class TemplatePickerScreen extends ConsumerWidget {
  const TemplatePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    final all = ref.watch(templatesProvider(null));
    final exercises = ref.watch(exercisesByIdProvider).value ?? {};

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(
        leading: GlassBackButton(),
        title: Text('Choose a template'),
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(error: e),
        data: (templates) {
          if (templates.isEmpty) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'No templates yet',
              message:
                  'Create one from the Templates tab to reuse a workout here.',
            );
          }

          final byFolder = <int, List<Template>>{};
          for (final t in templates) {
            byFolder.putIfAbsent(t.folderId, () => []).add(t);
          }
          final folderNames = {
            for (final f in folders.value ?? const <TemplateFolder>[])
              f.id: f.name,
          };

          return ListView(
            padding: glassPagePadding(context),
            children: [
              for (final entry in byFolder.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xs,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    folderNames[entry.key] ?? 'Templates',
                    style: AppTypography.h5,
                  ),
                ),
                for (final t in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        title: Text(t.name, style: AppTypography.h6),
                        subtitle: Text(
                          t.exercises
                              .map((e) => exercises[e.exerciseId]?.name)
                              .whereType<String>()
                              .join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.small.copyWith(
                            color: AppColors.mutedOnDark,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(t),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}
