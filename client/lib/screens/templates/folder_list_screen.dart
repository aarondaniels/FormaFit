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

  /// Creates a folder with a known name, clears any search so it isn't
  /// filtered out of the list behind you, and opens it.
  ///
  /// Opening it is the point: a folder is made to hold templates, and the next
  /// thing anyone wants is the "New template" button inside it. Landing back on
  /// a list of folders instead left the second step to be found on its own.
  Future<void> _createFolderNamed(String name) async {
    try {
      final folder = await mutateWith(
        ref,
        (api) => api.createFolder(name: name),
      );
      if (!mounted) return;
      setState(() {
        _query = '';
        _searchController.clear();
      });
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TemplateListScreen(folder: folder),
        ),
      );
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

    return folders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AsyncFailure(
        error: e,
        onRetry: () => ref.read(storeRevisionProvider.notifier).bump(),
      ),
      data: (list) {
        // Nothing saved yet: the whole tab is the instruction. No search field
        // above it — an empty list is not something anyone means to search,
        // and offering the box first made typing look like the way in.
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.folder_outlined,
            title: 'No templates yet',
            message:
                'A template is a workout you can start again — its exercises '
                'and your usual sets, weight and reps.\n\n'
                'Templates live in folders, so start with one: “Push / Pull / '
                'Legs”, or just “My workouts”.',
            action: FilledButton.icon(
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New folder'),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: AppSpacing.sm),
                  // A standing way to add a folder. Creating one used to mean
                  // typing a name the search could not match and taking the
                  // offer in the empty state, which is no way to find a
                  // feature. The tab bar deliberately carries no "+" (it would
                  // mean something different per tab), so the action lives
                  // here, next to the list it adds to.
                  IconButton.filled(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onPressed: _createFolder,
                  ),
                ],
              ),
            ),
            Expanded(child: _folderList(list, templates)),
          ],
        );
      },
    );
  }

  /// The filtered list, or an offer to create what was searched for.
  Widget _folderList(List<TemplateFolder> list, List<Template> templates) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? list
        : list.where((f) {
            if (f.name.toLowerCase().contains(q)) return true;
            return templates.any(
              (t) => t.folderId == f.id && t.name.toLowerCase().contains(q),
            );
          }).toList();

    if (visible.isEmpty) {
      final name = _query.trim();
      return EmptyState(
        icon: Icons.create_new_folder_outlined,
        title: 'No matching templates',
        message: 'Create a “$name” folder to group templates under it.',
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
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _FolderCard(folder: visible[i]),
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
    final count = ref.watch(templatesProvider(folder.id)).value?.length ?? 0;

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
