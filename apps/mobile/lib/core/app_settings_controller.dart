import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner-only settings from the Control Panel (client 27 Oct): screen capture
/// protection and Lineups. The last values are kept on the device, so the app
/// starts protected even offline; the server is asked at start and on resume.
final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettingsDto>((ref) {
  return AppSettingsController()..load();
});

class AppSettingsController extends StateNotifier<AppSettingsDto> {
  AppSettingsController({AppSettingsApi? api})
      : _api = api ?? AppSettingsApi(),
        super(const AppSettingsDto());

  static const _prefsKey = 'app.app_settings';
  final AppSettingsApi _api;
  DateTime? _lastFetch;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        state = AppSettingsDto.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (e) {
      debugPrint('[AppSettings] cached read failed: $e');
    }
    await refresh(force: true);
  }

  /// Asks the server again (at most once a minute unless [force]).
  Future<void> refresh({bool force = false}) async {
    final last = _lastFetch;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) return;
    _lastFetch = DateTime.now();
    final fresh = await _api.fetch();
    if (fresh == null || !mounted) return;
    state = fresh;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(fresh.toJson()));
    } catch (_) {}
  }
}
