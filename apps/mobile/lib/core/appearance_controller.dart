import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart' show AppColors;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device appearance prefs — applied app-wide (not decorative-only).
class AppearanceState {
  const AppearanceState({
    this.preset = 0,
    this.depth = 0,
    this.neonGlow = true,
    this.reducedMotion = false,
    this.loaded = false,
  });

  final int preset;
  final int depth;
  final bool neonGlow;
  final bool reducedMotion;
  final bool loaded;

  AppearanceState copyWith({
    int? preset,
    int? depth,
    bool? neonGlow,
    bool? reducedMotion,
    bool? loaded,
  }) {
    return AppearanceState(
      preset: preset ?? this.preset,
      depth: depth ?? this.depth,
      neonGlow: neonGlow ?? this.neonGlow,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      loaded: loaded ?? this.loaded,
    );
  }

  /// Atmosphere intensity 0.35–1.0 from depth slider (0 soft → 2 strong).
  double get atmosphereIntensity {
    switch (depth) {
      case 0:
        return neonGlow ? 0.7 : 0.45;
      case 1:
        return neonGlow ? 0.9 : 0.6;
      default:
        return neonGlow ? 1.0 : 0.75;
    }
  }

  /// Scaffold / radial accent pair for curated presets.
  (Color cyan, Color magenta, Color background) get accents {
    switch (preset) {
      case 1: // Midnight
        return (
          const Color(0xFF4DE1FF),
          const Color(0xFF7C9CFF),
          const Color(0xFF020617),
        );
      case 2: // Carbon
        return (
          const Color(0xFF94A3B8),
          const Color(0xFFE879F9),
          const Color(0xFF0A0A0B),
        );
      case 3: // Deep Cinema
        return (
          AppColors.cyan,
          AppColors.magenta,
          AppColors.background,
        );
      default: // Cinematic (follows the global theme)
        return (
          AppColors.cyan,
          AppColors.magenta,
          AppColors.background,
        );
    }
  }
}

class AppearanceController extends StateNotifier<AppearanceState> {
  AppearanceController() : super(const AppearanceState()) {
    _load();
  }

  static const themeKey = 'app.theme.preset';
  static const depthKey = 'app.theme.depth';
  static const glowKey = 'app.theme.neon';
  static const motionKey = 'app.theme.reduced_motion';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppearanceState(
      preset: prefs.getInt(themeKey) ?? 0,
      depth: prefs.getInt(depthKey) ?? 0,
      neonGlow: prefs.getBool(glowKey) ?? true,
      reducedMotion: prefs.getBool(motionKey) ?? false,
      loaded: true,
    );
  }

  Future<void> save({
    required int preset,
    required int depth,
    required bool neonGlow,
    required bool reducedMotion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(themeKey, preset);
    await prefs.setInt(depthKey, depth);
    await prefs.setBool(glowKey, neonGlow);
    await prefs.setBool(motionKey, reducedMotion);
    state = AppearanceState(
      preset: preset,
      depth: depth,
      neonGlow: neonGlow,
      reducedMotion: reducedMotion,
      loaded: true,
    );
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, AppearanceState>(
  (ref) => AppearanceController(),
);
