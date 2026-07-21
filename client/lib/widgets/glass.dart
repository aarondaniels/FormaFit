/// App-specific glass helpers layered on top of `package:liquid_glass_widgets`
/// (real GPU shader refraction/lighting — see the package for the actual glass
/// primitives: [GlassAppBar], [GlassTabBar], [GlassIconButton], [GlassCard],
/// [GlassModalSheet], etc., all re-exported here).
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/tokens.dart';

export 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Height reserved at the top of scrollable content so it rests just below the
/// floating [GlassAppBar] at first paint, and can be seen refracting through it
/// once scrolled up.
double glassTopInset(BuildContext context) =>
    MediaQuery.of(context).padding.top + 44.0;

/// Height reserved at the bottom of scrollable content / floating action
/// buttons so they clear the floating [GlassTabBar.bottom].
double glassBottomInset(BuildContext context) =>
    64.0 + 24.0 + MediaQuery.of(context).padding.bottom;

/// Standard page padding: full-bleed horizontally, inset vertically to clear
/// the floating glass chrome at both ends.
EdgeInsets glassPagePadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.md,
  glassTopInset(context) + AppSpacing.sm,
  AppSpacing.md,
  glassBottomInset(context),
);

/// A titled group of content on a glass card, the app's default section shape.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
  });

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.h5)),
              ?trailing,
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ],
    );
  }
}

/// A single headline number with a caption, used across the dashboard and
/// stats screens.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: tint),
          const SizedBox(height: AppSpacing.sm),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppTypography.h3.copyWith(color: AppColors.onDark),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.small.copyWith(color: AppColors.mutedOnDark),
        ),
      ],
    );
  }
}

/// Centered explanatory state for empty lists, with an optional call to
/// action. Used instead of a bare "no data" string.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppColors.cta),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.h4,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.mutedOnDark,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard rendering for a provider that is still loading or has failed, so
/// every screen reports errors the same way instead of spinning forever.
class AsyncFailure extends StatelessWidget {
  const AsyncFailure({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: '$error',
      action: onRetry == null
          ? null
          : FilledButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}
