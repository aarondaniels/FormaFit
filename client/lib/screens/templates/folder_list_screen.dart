import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import 'template_list_screen.dart';

class FolderListScreen extends ConsumerStatefulWidget {
  const FolderListScreen({super.key});

  @override
  ConsumerState<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends ConsumerState<FolderListScreen> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createFolder() async {
    final name = await promptForName(
      context,
      title: 'New folder',
      hint: 'e.g. Push / Pull / Legs',
    );
    if (name == null) return;
    await _createFolderNamed(name);
  }

  /// Creates a folder with a known name (from the search box) and clears the
  /// search so the new folder shows in the full list.
  Future<void> _createFolderNamed(String name) async {
    try {
      await mutateWith(ref, (api) => api.createFolder(name: name));
      if (mounted) {
        setState(() {
          _query = '';
          _searchController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(foldersProvider);
    // All templates, to let a search by template name surface its folder.
    final templates = ref.watch(templatesProvider(null)).value ?? const [];

    return Column(
      children: [
        // Search full-width; creating a folder is offered from the empty
        // state when a search finds nothing.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search templates',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _query = '';
                        _searchController.clear();
                      }),
                    ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: folders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AsyncFailure(
              error: e,
              onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
            ),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'No template folders',
                  message:
                      'Folders group your saved workouts — a “Push / Pull / '
                      'Legs” folder, for example.',
                  action: FilledButton.icon(
                    onPressed: _createFolder,
                    icon: const Icon(Icons.add),
                    label: const Text('New folder'),
                  ),
                );
              }

              final q = _query.trim().toLowerCase();
              final visible = q.isEmpty
                  ? list
                  : list.where((f) {
                      if (f.name.toLowerCase().contains(q)) return true;
                      return templates.any(
                        (t) =>
                            t.folderId == f.id &&
                            t.name.toLowerCase().contains(q),
                      );
                    }).toList();

              if (visible.isEmpty) {
                final name = _query.trim();
                return EmptyState(
                  icon: Icons.create_new_folder_outlined,
                  title: 'No matching templates',
                  message:
                      'Create a “$name” folder to group templates under it.',
                  action: FilledButton.icon(
                    onPressed: () => _createFolderNamed(name),
                    icon: const Icon(Icons.add),
                    label: Text('Create “$name” folder'),
                  ),
                );
              }

              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  glassBottomInset(context),
                ),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _FolderCard(folder: visible[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FolderCard extends ConsumerWidget {
  const _FolderCard({required this.folder});

  final TemplateFolder folder;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final templates = await ref.read(templatesProvider(folder.id).future);
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${folder.name}”?'),
        content: Text(
          templates.isEmpty
              ? 'This folder is empty.'
              : 'This also deletes the ${templates.length} '
                    '${templates.length == 1 ? "template" : "templates"} inside '
                    'it. Workouts you already logged are not affected.',
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
    await mutateWith(ref, (api) => api.deleteFolder(folder.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(templatesProvider(folder.id)).value?.length ?? 0;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
        title: Text(folder.name, style: AppTypography.h6),
        subtitle: Text(
          count == 1 ? '1 template' : '$count templates',
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TemplateListScreen(folder: folder),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ),
    );
  }
}

/// Single-field name prompt shared by the folder and template screens.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.of(ctx).pop(_clean(v)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_clean(controller.text)),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

String? _clean(String v) {
  final t = v.trim();
  return t.isEmpty ? null : t;
}
