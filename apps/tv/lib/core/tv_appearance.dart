import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart' show AppColors;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TV appearance preset name (matches Settings → Appearance list).
const tvAppearancePrefsKey = 'tv_appearance';

class TvAppearanceState {
  const TvAppearanceState({
    this.name = 'Cinematic',
    this.loaded = false,
  });

  final String name;
  final bool loaded;

  /// primary, secondary, scaffold — aligned with mobile appearance_controller.
  (Color, Color, Color) get accents {
    switch (name) {
      case 'Midnight':
        return (
          const Color(0xFF4DE1FF),
          const Color(0xFF7C9CFF),
          const Color(0xFF020617),
        );
      case 'Carbon':
        return (
          const Color(0xFF94A3B8),
          const Color(0xFFE879F9),
          const Color(0xFF0A0A0B),
        );
      case 'Deep Cinema':
        return (
          AppColors.cyan,
          AppColors.magenta,
          const Color(0xFF000000),
        );
      case 'Cinematic':
      default:
        return (
          AppColors.cyan,
          AppColors.magenta,
          const Color(0xFF000000),
        );
    }
  }
}

class TvAppearanceController extends StateNotifier<TvAppearanceState> {
  TvAppearanceController() : super(const TvAppearanceState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = TvAppearanceState(
      name: prefs.getString(tvAppearancePrefsKey) ?? 'Cinematic',
      loaded: true,
    );
  }

  Future<void> setAppearance(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tvAppearancePrefsKey, name);
    state = TvAppearanceState(name: name, loaded: true);
  }
}

final tvAppearanceProvider =
    StateNotifierProvider<TvAppearanceController, TvAppearanceState>(
  (ref) => TvAppearanceController(),
);
