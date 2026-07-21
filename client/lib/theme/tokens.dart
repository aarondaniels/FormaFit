
import 'package:flutter/material.dart';

/// Forma's palette, carried over from the original client.
class AppColors {
  static const primary = Color(0xFF2196F3); // Main interactive / branding
  static const secondary = Color(0xFFBDBDBD); // Secondary text, borders
  static const surface = Color(0xFFF5F5F5); // Light surfaces
  static const dark = Color(0xFF0D1A26); // App background
  static const darkBlue = Color(0xFF1A2633); // Raised surfaces, nav
  static const accent = Color(0xFFE65100); // Rust orange accent
  static const error = Color(0xFFB00020);
  static const success = Color(0xFF0AD95E);
  static const warning = Color(0xFFFF9800);
  static const inactiveNav = Color(0xFF94ABC7);
  static const cta = Color(0xFF2B3640);
  static const activeCTA = Color(0xFF4080BF);
  static const iconBg = Color(0xFF2B3640);

  static const onDark = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFFFFFFFF);

  /// Muted body text on the dark background.
  static const mutedOnDark = Color(0xFF94ABC7);

  /// Per-muscle-group colors for charts and recovery tiles. Distinct in hue so
  /// groups stay separable in the volume breakdown.
  static const muscleGroup = <String, Color>{
    'Chest': Color(0xFF4080BF),
    'Back': Color(0xFF0AD95E),
    'Shoulders': Color(0xFFFF9800),
    'Arms': Color(0xFFE65100),
    'Legs': Color(0xFF9C6ADE),
    'Core': Color(0xFF00BCD4),
    'Glutes': Color(0xFFE91E63),
    'Calves': Color(0xFFFFC107),
  };

  static Color forMuscleGroup(String group) => muscleGroup[group] ?? secondary;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  static const radius = 16.0;
  static const radiusSmall = 10.0;
}

class AppTypography {
  static const h1 = TextStyle(fontSize: 32, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
  static const h3 = TextStyle(fontSize: 24, fontWeight: FontWeight.w600);
  static const h4 = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const h5 = TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
  static const h6 = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static const body = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const small = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  /// Tabular figures, so weights and reps don't jitter as they change.
  static const numeric = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
