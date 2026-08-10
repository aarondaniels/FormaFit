import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../health_sync.dart';
import '../providers.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../workout_reminder.dart';

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

  /// Turning sync on asks for Health permission first, so the system prompt is
  /// a direct response to the switch rather than a surprise elsewhere. If the
  /// user declines, the switch stays off rather than claiming a sync that
  /// cannot happen.
  Future<void> _setHealthSync(bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled) {
        final health = ref.read(healthSyncProvider);
        final granted = await health.requestPermissions();
        if (!granted) {
          _report('Apple Health access was not granted.');
          return;
        }
        // iOS answers the prompt without saying what was allowed, and it only
        // ever asks once. Checking write access here means a refused workout
        // permission is reported now rather than discovered as silence later.
        if (!await health.canWriteWorkouts()) {
          _report(
            'Forma cannot write workouts yet. Enable it under Settings → '
            'Health → Data Access & Devices → Forma.',
          );
        }
      }
      await mutateWith(ref, (api) => api.setHealthSyncEnabled(enabled));
    } catch (e) {
      _report('Could not change Health sync: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Same shape as Health: ask for permission as a direct answer to the
  /// switch, and leave it off if the user says no rather than promising a
  /// reminder that iOS will never deliver.
  Future<void> _setWorkoutReminders(bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled) {
        final granted = await ref
            .read(workoutReminderProvider)
            .requestPermission();
        if (!granted) {
          _report(
            'Notifications are off for Forma. Turn them on under iOS '
            'Settings → Notifications → Forma.',
          );
          return;
        }
      } else {
        // Anything already pending would still arrive after the switch is off.
        await ref.read(workoutReminderProvider).cancel();
      }
      await mutateWith(ref, (api) => api.setWorkoutRemindersEnabled(enabled));
    } catch (e) {
      _report('Could not change workout reminders: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JSON backup',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null) return;

      final json = await file.readAsString();
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

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(apiProvider).exportWorkoutsCsvToFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Forma workout log',
        ),
      );
    } catch (e) {
      _report('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCsv() async {
    // Pick the file first, then ask what unit its weights are in — the CSV
    // carries no unit marker.
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'CSV',
          extensions: ['csv', 'txt'],
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'public.plain-text',
          ],
        ),
      ],
    );
    if (file == null || !mounted) return;

    final kg = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Weight units'),
        content: const Text(
          'The file has no unit marker, so pick the unit its weights are in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Pounds (lb)'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kilograms (kg)'),
          ),
        ],
      ),
    );
    if (kg == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final csv = await file.readAsString();
      final result = await mutateWith(
        ref,
        (api) => api.importWorkoutsCsv(csv, weightsInKg: kg),
      );
      final extras = result.exercisesCreated == 0
          ? ''
          : ' · ${result.exercisesCreated} new '
                '${result.exercisesCreated == 1 ? "exercise" : "exercises"}';
      _report(
        'Imported ${result.workouts} '
        '${result.workouts == 1 ? "workout" : "workouts"} '
        '(${result.sets} sets)$extras.',
      );
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
      appBar: const GlassAppBar(
        leading: GlassBackButton(),
        // Same bold, left-aligned language as the main tab titles, a step down
        // in size so it stays subordinate to them.
        centerTitle: false,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.onDark,
            letterSpacing: -0.3,
          ),
        ),
      ),
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
          if (HealthSync.isSupported) ...[
            const SizedBox(height: AppSpacing.lg),
            GlassSection(
              title: 'Apple Health',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: ref.watch(healthSyncEnabledProvider).value ?? false,
                onChanged: _busy ? null : _setHealthSync,
                title: const Text('Sync with Apple Health'),
                subtitle: Text(
                  'Saves each workout to Health so it counts toward your '
                  'rings, and shows the energy and heart rate your watch '
                  'recorded.',
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
            ),
          ],
          if (WorkoutReminder.isSupported) ...[
            const SizedBox(height: AppSpacing.lg),
            GlassSection(
              title: 'Reminders',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value:
                    ref.watch(workoutRemindersEnabledProvider).value ?? false,
                onChanged: _busy ? null : _setWorkoutReminders,
                title: const Text('Unfinished workout reminder'),
                subtitle: Text(
                  'If a workout is left open for '
                  '${WorkoutReminder.idleAfter.inMinutes} minutes without a '
                  'change, Forma sends a notification so it does not sit there '
                  'unsaved.',
                  style: AppTypography.small.copyWith(
                    color: AppColors.mutedOnDark,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          GlassSection(
            title: 'Workout log (CSV)',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Export workout log'),
                  subtitle: Text(
                    'A CSV of every set — for spreadsheets or another app.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                  onTap: _busy ? null : _exportCsv,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Import from CSV'),
                  subtitle: Text(
                    'Add workouts from a CSV export. Adds to your log; '
                    'nothing is overwritten.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.mutedOnDark,
                    ),
                  ),
                  onTap: _busy ? null : _importCsv,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassSection(
            title: 'Full backup (JSON)',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Export full backup'),
                  subtitle: Text(
                    'Everything — workouts, templates, measurements — as JSON.',
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
                  title: const Text('Restore full backup'),
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
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
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
              style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
            ),
          ),
        ],
      ),
    );
  }
}
