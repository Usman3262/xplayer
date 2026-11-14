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
    if (!configured || _ready) return;
    try {
      await Supabase.initialize(url: url, publishableKey: publishableKey);
      _ready = true;
    } catch (e) {
      debugPrint('[Backend] Supabase init failed: $e');
    }
  }

  /// Null when not configured or init failed.
  static SupabaseClient? get client => _ready ? Supabase.instance.client : null;
}
