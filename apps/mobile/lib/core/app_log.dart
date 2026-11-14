import 'package:flutter/foundation.dart';

/// Structured console logging for taps, nav, and diagnostics.
///
/// Tap/nav/action are off by default ([verbose]). Errors and explicit
/// [info] still print in debug/profile.
abstract final class AppLog {
  /// Flip true when debugging UI flows (very chatty on every tap/route).
  static bool verbose = false;

  static void tap(String target, {Map<String, Object?>? data}) {
    if (!verbose) return;
    debugPrint('[TAP] $target${_fmt(data)}');
  }

  static void nav(String action, {String? from, String? to}) {
    if (!verbose) return;
    debugPrint(
      '[NAV] $action'
      '${from != null ? ' from=$from' : ''}'
      '${to != null ? ' to=$to' : ''}',
    );
  }

  static void action(String name, {Map<String, Object?>? data}) {
    if (!verbose) return;
    debugPrint('[ACTION] $name${_fmt(data)}');
  }

  static void info(String tag, String message) {
    if (!kDebugMode && !kProfileMode) return;
    debugPrint('[$tag] $message');
  }

  static void error(String tag, Object error, [StackTrace? st]) {
    debugPrint('[$tag] ERROR: $error');
    if (st != null) debugPrint('[$tag] $st');
  }

  static String _fmt(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return '';
    final parts = data.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return ' $parts';
  }
}
