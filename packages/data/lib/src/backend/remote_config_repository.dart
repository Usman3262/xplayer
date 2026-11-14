import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_config.dart';

/// Calls the backend `get_app_config` RPC with [params] and returns the decoded
/// JSON. Injected by the app (Supabase client), so this package stays
/// backend-agnostic and unit-testable.
typedef ConfigFetcher = Future<Object?> Function(Map<String, dynamic> params);

/// Cache-first remote configuration (D6 / spec §18.3):
///  1. [loadCached] — last valid config from the device, instantly (no network).
///  2. [refresh] — asks the server, sending the known version; a tiny
///     "unchanged" reply costs almost nothing.
///  3. Invalid replies are ignored; the last valid config stays in use.
/// Listen to [current] to apply theme/flags/branding/home.
class RemoteConfigRepository {
  RemoteConfigRepository({
    required this.platform,
    required this.appVersion,
    required ConfigFetcher fetch,
    this.country,
    this.timeout = const Duration(seconds: 6),
  }) : _fetch = fetch;

  /// "android" | "ios" | "tv".
  final String platform;
  final String appVersion;

  /// ISO-2 country hint for guests (signed-in users use their profile).
  final String? country;
  final Duration timeout;
  final ConfigFetcher _fetch;

  static const cacheKey = 'app.remote_config.v1';

  /// The config in use. Starts empty (built-in defaults).
  final ValueNotifier<RemoteConfig> current = ValueNotifier(RemoteConfig.empty);

  Timer? _timer;
  Future<bool>? _inFlight;

  /// Load the last valid config saved on this device. Never throws.
  Future<RemoteConfig> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final cfg = RemoteConfig.tryParse(jsonDecode(raw));
        if (cfg != null) current.value = cfg;
      }
    } catch (e) {
      debugPrint('[RemoteConfig] cache unreadable: $e');
    }
    return current.value;
  }

  /// Fetch from the server. Returns true when a NEW config was applied.
  /// Concurrent calls share one request. Never throws.
  Future<bool> refresh() => _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<bool> _refresh() async {
    try {
      final known = current.value.version;
      final reply = await _fetch({
        'p_platform': platform,
        'p_app_version': appVersion,
        if (known > 0) 'p_known_version': known,
        if (country != null && country!.isNotEmpty) 'p_country': country,
      }).timeout(timeout);

      if (RemoteConfig.isUnchanged(reply)) return false;
      final cfg = RemoteConfig.tryParse(reply);
      if (cfg == null) {
        debugPrint('[RemoteConfig] ignored an invalid reply');
        return false;
      }
      if (cfg.version < known) return false; // never go backwards
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(cfg.toJson()));
      final changed = cfg.version != known || jsonEncode(cfg.raw) != jsonEncode(current.value.raw);
      current.value = cfg;
      return changed;
    } catch (e) {
      debugPrint('[RemoteConfig] refresh failed (keeping last config): $e');
      return false;
    }
  }

  /// Re-check every `config.refresh_interval_s` (from the config itself).
  void startAutoRefresh() {
    _timer?.cancel();
    final seconds = current.value.intSetting('config.refresh_interval_s', 900).clamp(60, 86400);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => refresh());
  }

  void dispose() {
    _timer?.cancel();
    current.dispose();
  }
}
