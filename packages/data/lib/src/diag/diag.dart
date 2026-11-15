import 'dart:math';

import 'package:flutter/foundation.dart';

/// Gate for Section 9 diag tags. Release stays quiet unless [forceEnable].
abstract final class DiagConfig {
  /// Flip true for a one-off release capture (e.g. client device issue).
  static bool forceEnable = false;

  /// Log every auth/device/heartbeat poll request+response (very noisy).
  /// Default off: only status *changes* and non-pending responses print.
  static bool verboseApi = false;

  /// Logs from the old app backend (removed): `[API]`, `[TokenStore]`,
  /// `[ApiEndpoints]`, `SPORTS_DATA`. Off so `[PANEL]` lines stay readable.
  static bool legacyBackend = false;

  static bool get isOn =>
      forceEnable || kDebugMode || kProfileMode;

  /// [ERR] still prints in release when forced, or when [isOn].
  static bool get errOn => isOn || forceEnable;
}

/// Grepable tags: `[API]` `[NET]` `[PB]` `[PERF]` `[DEV]` `[ERR]`.
abstract final class Diag {
  static int _reqSeq = 0;
  static final _rand = Random();

  static int nextRequestId() => ++_reqSeq;

  /// Short id per playback attempt (e.g. `ab12`).
  static String newSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List.generate(4, (_) => chars.codeUnitAt(_rand.nextInt(chars.length))),
    );
  }

  static int bootMs() => DateTime.now().millisecondsSinceEpoch;

  static void api(String message) => _emit('API', message);
  static void net(String message) => _emit('NET', message);
  static void pb(String message) => _emit('PB', message);
  static void perf(String message) => _emit('PERF', message);
  static void dev(String message) {
    if (!DiagConfig.legacyBackend && message.startsWith('SPORTS_DATA')) return;
    _emit('DEV', message);
  }

  /// IPTV panel traffic (Xtream / M3U / Stalker): host + path + status +
  /// timing + the real error. Callers pass text already made safe with
  /// [panelUrl] / [panelText]; this never prints credentials.
  static void panel(String message) => event('PANEL', message);

  /// Where important lines also go (the app uploads them for support /
  /// remote testing). Gets text that is already scrubbed.
  static void Function(String tag, String message)? remoteSink;

  /// A tagged, important line (`[PANEL]`, `[SYNC]`, `[ACCOUNT]`, `[BACKEND]`,
  /// `[APP]`, `[CRASH]`): printed in debug, kept in the trail, and handed to
  /// [remoteSink]. URLs / credential params are masked first.
  static void event(String tag, String message) {
    final safe = panelText(message);
    DiagTrail.add(tag, safe);
    try {
      remoteSink?.call(tag, safe);
    } catch (_) {
      // Logging must never break the app.
    }
    if (!DiagConfig.isOn) return;
    debugPrint('[$tag] $safe');
  }

  static final _credPath = RegExp(r'/(live|movie|series|timeshift)/[^/\s]+/[^/\s]+/');
  static final _credParam = RegExp(r'(username|password|mac|token|play_token|sn2?)=[^&\s]*', caseSensitive: false);

  /// `scheme://host:port/path` (+ `?action=` / `type=`), credentials masked.
  static String panelUrl(Uri u) {
    final path = u.path.replaceAllMapped(_credPath, (m) => '/${m[1]}/***/***/');
    final keep = [
      for (final k in const ['action', 'type'])
        if (u.queryParameters[k] case final v? when v.isNotEmpty) '$k=$v',
    ];
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}$path${keep.isEmpty ? '' : '?${keep.join('&')}'}';
  }

  /// Any URL inside [text] → [panelUrl]; leftover credential params masked.
  static String panelText(String text) => text
      .replaceAllMapped(_url, (m) {
        final u = Uri.tryParse(m[0]!);
        return u == null || u.host.isEmpty ? '<url>' : panelUrl(u);
      })
      .replaceAllMapped(_credParam, (m) => '${m[1]}=***');

  static void err(
    String message, [
    Object? error,
    StackTrace? st,
  ]) {
    const maxFrames = 10;
    final buf = StringBuffer('[ERR] t=${bootMs()} ${scrub(message)}');
    if (error != null) buf.write(' error=${scrub('$error')}');
    DiagTrail.add('ERR', buf.toString().substring(6));
    try {
      remoteSink?.call('ERR', panelText(buf.toString().substring(6)));
    } catch (_) {}
    if (!DiagConfig.errOn) return;
    debugPrint(buf.toString());
    if (st != null) {
      final lines = st.toString().split('\n').take(maxFrames).join('\n');
      if (lines.isNotEmpty) debugPrint('[ERR] $lines');
    }
  }

  static void _emit(String tag, String message) {
    if (tag == 'API' && !DiagConfig.legacyBackend) return;
    // [API] lines carry payloads; the trail keeps playback/device lines only.
    if (tag != 'API') DiagTrail.add(tag, message);
    if (!DiagConfig.isOn) return;
    debugPrint('[$tag] t=${bootMs()} ${scrub(message)}');
  }

  static final _url = RegExp(r'''[a-zA-Z][a-zA-Z0-9+.-]*://[^\s'"<>]+''');
  // Xtream paths without a scheme: /movie/USER/PASS/123.mkv
  static final _xtreamPath = RegExp(
    r'''/(movie|series|live|timeshift)/[^/\s'"<>]+/[^/\s'"<>]+/[^\s'"<>]*''',
  );

  /// Removes URLs from log text. mpv/FFmpeg errors and some exceptions embed
  /// the full source URL, which for Xtream sources carries line credentials.
  static String scrub(String text) => text
      .replaceAll(_url, '<url>')
      .replaceAll(_xtreamPath, '/<path>');
}

/// In-memory tail of recent diagnostic lines, kept in every build mode so a
/// release user can copy it from the error screen. Never written to disk or
/// sent anywhere; every line is passed through [Diag.scrub].
abstract final class DiagTrail {
  static const maxLines = 150;
  static const maxLineChars = 500;
  static final _lines = <String>[];

  static void add(String tag, String message) {
    var line = '${_clock()} [$tag] ${Diag.scrub(message)}';
    if (line.length > maxLineChars) line = '${line.substring(0, maxLineChars)}…';
    _lines.add(line);
    if (_lines.length > maxLines) _lines.removeRange(0, _lines.length - maxLines);
  }

  static List<String> get lines => List.unmodifiable(_lines);

  /// Most recent line containing [needle], without its time and tag prefix.
  static String? lastContaining(String needle) {
    for (final l in _lines.reversed) {
      final i = l.indexOf(needle);
      if (i >= 0) return l.substring(i);
    }
    return null;
  }

  static void clear() => _lines.clear();

  static String _clock() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = n.millisecond.toString().padLeft(3, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.$ms';
  }
}
