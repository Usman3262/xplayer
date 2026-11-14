import 'package:flutter/material.dart';

import 'app_theme_config.dart';

/// Colour tokens used across the UI. Values come from the global theme
/// ([AppThemeConfig.current]) — never hard-code colours, change the theme.
///
/// The old token names ([cyan], [magenta], [match]) are kept so existing
/// screens work unchanged; they map to primary / secondary / success.
abstract final class AppColors {
  static AppThemeConfig get _t => AppThemeConfig.current;

  static Color get background => _t.background;
  static Color get surface => _t.surface;
  static Color get surfaceElevated => _t.surfaceElevated;

  /// Main accent.
  static Color get primary => _t.primary;
  /// Second accent.
  static Color get secondary => _t.secondary;

  /// = [primary] (legacy name).
  static Color get cyan => _t.primary;
  /// = darker [primary] (legacy name).
  static Color get cyanDim => _t.primaryDim;
  /// = [secondary] (legacy name).
  static Color get magenta => _t.secondary;
  static Color get gold => _t.gold;
  static Color get live => _t.live;
  /// = success (legacy name).
  static Color get match => _t.success;
  static Color get textPrimary => _t.textPrimary;
  static Color get textSecondary => _t.textSecondary;
  static Color get border => _t.border;
  static Color get danger => _t.danger;

  /// Rotating accents for card placeholders.
  static Color themeAccent(int seed) {
    final accents = [cyan, magenta, gold, live, match, cyanDim];
    return accents[seed.abs() % accents.length];
  }
}
