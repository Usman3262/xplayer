import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase connection. URL + publishable (public) key come from
/// `--dart-define-from-file=../../env/app.json` — never hard-coded.
/// Without them the app runs on built-in defaults (no remote config).
class Backend {
  Backend._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;
  static bool _ready = false;

  /// Safe to call once at startup; never throws.
  static Future<void> init() async {
    if (_ready) return;
    if (!configured) {
      // Accounts + admin config need these. Run with
      // --dart-define-from-file=../../env/app.json
      debugPrint('[BACKEND] NOT CONFIGURED: SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY missing '
          '(run with --dart-define-from-file=../../env/app.json). Accounts and admin config are off.');
      return;
    }
    try {
      await Supabase.initialize(url: url, publishableKey: publishableKey);
      _ready = true;
      debugPrint('[BACKEND] ready: ${Uri.tryParse(url)?.host ?? '?'}');
    } catch (e) {
      debugPrint('[BACKEND] Supabase init FAILED: ${e.runtimeType}: $e');
    }
  }

  /// Null when not configured or init failed.
  static SupabaseClient? get client => _ready ? Supabase.instance.client : null;
}
