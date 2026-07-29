/// Rest-duration formatting and the picker shared by the workout logger and
/// the template editor.
library;

import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Rest as `m:ss`, or "Off" when there is no rest timer.
String formatRest(int seconds) {
  if (seconds <= 0) return 'Off';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Preset rest lengths offered in the picker, in seconds. 0 is "Off".
const List<int> restPresets = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300];

/// Lets the user pick a rest duration, returning the chosen seconds (0 = off)
/// or null if dismissed.
Future<int?> showRestPicker(BuildContext context, int current) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rest between sets', style: AppTypography.h4),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in restPresets)
                  ChoiceChip(
                    label: Text(formatRest(p)),
                    selected: p == current,
                    onSelected: (_) => Navigator.of(ctx).pop(p),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.tune, size: 16),
                  label: const Text('Custom'),
                  onPressed: () async {
                    final custom = await _customRestDialog(ctx, current);
                    if (custom != null && ctx.mounted) {
                      Navigator.of(ctx).pop(custom);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<int?> _customRestDialog(BuildContext context, int current) {
  var duration = Duration(seconds: current > 0 ? current : 90);
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Custom rest'),
      content: SizedBox(
        height: 180,
        child: CupertinoTimerPicker(
          mode: CupertinoTimerPickerMode.ms,
          initialTimerDuration: duration,
          onTimerDurationChanged: (v) => duration = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(duration.inSeconds),
          child: const Text('Set'),
        ),
      ],
    ),
  );
}

/// The rest chip shown on an exercise, opening the picker when tapped.
class RestChip extends StatelessWidget {
  const RestChip({super.key, required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = seconds > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      onTap: () async {
        final picked = await showRestPicker(context, seconds);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cta,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: on ? AppColors.primary : AppColors.mutedOnDark,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              formatRest(seconds),
              style: AppTypography.small.copyWith(
                color: on ? AppColors.onDark : AppColors.mutedOnDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
