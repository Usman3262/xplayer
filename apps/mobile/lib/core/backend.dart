import 'dart:convert';

import 'package:data/data.dart' show Diag;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase connection. URL + publishable (public) key come from
/// `--dart-define-from-file=../../env/app.json` — never hard-coded.
/// Without them the app runs on built-in defaults (no remote config).
class Backend {
  Backend._();

  /// --dart-define values win; else the bundled assets/config/app_env.json
  /// (copied from env/app.json by the Android build).
  static String url = const String.fromEnvironment('SUPABASE_URL');
  static String publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static String _source = 'dart-define';

  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<void> _loadBundled() async {
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/config/app_env.json'));
      if (raw is! Map) return;
      url = '${raw['SUPABASE_URL'] ?? ''}'.trim();
      publishableKey = '${raw['SUPABASE_PUBLISHABLE_KEY'] ?? ''}'.trim();
      _source = 'bundled env/app.json';
    } catch (_) {
      // Not bundled (e.g. env/app.json missing on this machine).
    }
  }
  static bool _ready = false;

  /// Safe to call once at startup; never throws.
  static Future<void> init() async {
    if (_ready) return;
    if (!configured) await _loadBundled();
    if (!configured) {
      // Accounts + admin config need these. Run with
      // --dart-define-from-file=../../env/app.json
      Diag.event('BACKEND', 'NOT CONFIGURED: SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing '
          '(run with --dart-define-from-file=../../env/app.json). Accounts and admin config are off.');
      return;
    }
    try {
      await Supabase.initialize(url: url, publishableKey: publishableKey);
      _ready = true;
      Diag.event('BACKEND', 'ready: ${Uri.tryParse(url)?.host ?? '?'} (from $_source)');
    } catch (e) {
      Diag.event('BACKEND', 'Supabase init FAILED: ${e.runtimeType}: $e');
    }
  }

  /// Null when not configured or init failed.
  static SupabaseClient? get client => _ready ? Supabase.instance.client : null;
}
