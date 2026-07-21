import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(apiProvider).exportToFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Forma backup',
        ),
      );
    } catch (e) {
      _report('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This replaces everything currently in the app — workouts, '
          'exercises, templates and measurements — with the contents of the '
          'backup file.\n\n'
          'Your current data is copied aside first, so this can be undone by '
          'restoring an export you take now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;

      final json = await File(path).readAsString();
      await mutateWith(ref, (api) => api.importJson(json));
      _report('Backup restored.');
    } on ImportException catch (e) {
      _report(e.message);
    } catch (e) {
      _report('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDefaults() async {
    setState(() => _busy = true);
    try {
      final added = await mutateWith(
        ref,
        (api) => api.restoreDefaultExercises(),
      );
      _report(
        added == 0
            ? 'The default library is already complete.'
            : 'Restored $added default '
                  '${added == 1 ? "exercise" : "exercises"}.',
      );
    } catch (e) {
      _report('Could not restore defaults: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
          'Every workout, template and measurement is deleted and the default '
          'exercise library is restored. This cannot be undone — export a '
          'backup first if you might want any of it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await mutateWith(ref, (api) => api.resetAll());
      _report('All data erased.');
    } catch (e) {
      _report('Could not erase: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider).value;
    final exercises = ref.watch(exercisesProvider).value?.length ?? 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('Settings')),
      body: ListView(
        padding: glassPagePadding(context),
        children: [
          GlassSection(
            title: 'Your data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Everything Forma stores lives in a single file on this '
                  'device. Nothing is uploaded, and there is no account.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        value: '${stats?.totalWorkouts ?? 0}',
                        label: 'Workouts',
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        value: '$exercises',
                        label: 'Exercises',
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassSection(
            title: 'Backup',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Export a backup'),
                  subtitle: Text(
                    'Save or send a JSON copy of everything.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                  onTap: _busy ? null : _export,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Restore from backup'),
                  subtitle: Text(
                    'Replaces everything currently in the app.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                  onTap: _busy ? null : _import,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassSection(
            title: 'Library',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: const Text('Restore default exercises'),
              subtitle: Text(
                'Re-adds any starter exercises you deleted. Your own '
                'exercises are left alone.',
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
              onTap: _busy ? null : _restoreDefaults,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassSection(
            title: 'Danger zone',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_forever,
                color: AppColors.error,
              ),
              title: const Text('Erase all data'),
              subtitle: Text(
                'Deletes everything on this device.',
                style: AppTypography.small.copyWith(
                  color: AppColors.mutedOnDark,
                ),
              ),
              onTap: _busy ? null : _reset,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              'Forma · on-device workout tracking',
              style: AppTypography.small.copyWith(
                color: AppColors.mutedOnDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
