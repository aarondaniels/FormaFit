import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import 'folder_list_screen.dart' show promptForName;
import 'template_editor_screen.dart';

class TemplateListScreen extends ConsumerWidget {
  const TemplateListScreen({super.key, required this.folder});

  final TemplateFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider(folder.id));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(folder.name),
        actions: [
          GlassIconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () async {
              final name = await promptForName(
                context,
                title: 'Rename folder',
                initial: folder.name,
              );
              if (name == null) return;
              await mutateWith(
                ref,
                (api) => api.updateFolder(folder.copyWith(name: name)),
              );
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TemplateEditorScreen(folderId: folder.id),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncFailure(error: e),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'No templates here',
              message:
                  'A template is a reusable workout — its exercises and your '
                  'usual sets, weight and reps.',
            );
          }
          return ListView.separated(
            padding: glassPagePadding(context),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _TemplateCard(template: list[i]),
          );
        },
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({required this.template});

  final Template template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(exercisesByIdProvider).value ?? {};
    final names = template.exercises
        .map((e) => exercises[e.exerciseId]?.name)
        .whereType<String>()
        .toList();

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        title: Text(template.name, style: AppTypography.h6),
        subtitle: Text(
          names.isEmpty ? 'No exercises' : names.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TemplateEditorScreen(
              folderId: template.folderId,
              existing: template,
            ),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Delete “${template.name}”?'),
                content: const Text(
                  'Workouts you already logged from it are not affected.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            await mutateWith(ref, (api) => api.deleteTemplate(template.id));
          },
        ),
      ),
    );
  }
}
