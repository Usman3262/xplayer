import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../backend/remote_config.dart';
import '../diag/diag.dart';
import 'provider_models.dart';

/// Timeouts and limits for panel calls. Defaults are built in; the admin panel
/// changes them (App customization → Access: `providers.connect_timeout_ms`;
/// Versions → Panel connections: `providers.request_timeout_ms`,
/// `providers.request_concurrency`).
class ProviderLimits {
  const ProviderLimits({
    this.authTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(seconds: 20),
    this.concurrency = 4,
    this.retries = 2,
    this.isolateDecodeBytes = 256 * 1024,
  });

  factory ProviderLimits.fromConfig(RemoteConfig c) {
    const d = ProviderLimits();
    int clamp(int v, int lo, int hi) => math.min(hi, math.max(lo, v));
    return ProviderLimits(
      authTimeout: Duration(
        milliseconds: clamp(c.intSetting('providers.connect_timeout_ms', d.authTimeout.inMilliseconds), 1000, 60000),
      ),
      requestTimeout: Duration(
        milliseconds: clamp(c.intSetting('providers.request_timeout_ms', d.requestTimeout.inMilliseconds), 2000, 120000),
      ),
      concurrency: clamp(c.intSetting('providers.request_concurrency', d.concurrency), 1, 16),
    );
  }

  /// Login / account check — short, so "connect" answers in seconds.
  final Duration authTimeout;

  /// Catalog requests (lists can be tens of MB).
  final Duration requestTimeout;

  /// Parallel requests per panel (panels ban bursts).
  final int concurrency;

  /// Extra attempts for retryable failures (network / timeout / 5xx / 429).
  final int retries;

  /// Responses larger than this are JSON-decoded off the UI thread.
  final int isolateDecodeBytes;
}

/// Shared HTTP for adapters: timeout on every call, retries with backoff,
/// a per-panel concurrency cap, big JSON decoded in an isolate, and every
/// error turned into a [ProviderFailure]. Never logs URLs (they hold credentials).
class ProviderHttp {
  ProviderHttp({http.Client? client, this.limits = const ProviderLimits(), Duration? backoffBase})
      : _client = client ?? http.Client(),
        _backoffBase = backoffBase ?? const Duration(milliseconds: 400),
        _slots = _Slots(limits.concurrency);

  final http.Client _client;
  final ProviderLimits limits;
  final Duration _backoffBase;
  final _Slots _slots;
  bool _closed = false;

  /// GET [uri] and decode JSON. [auth] uses the short login timeout.
  /// [priority] = the user is waiting (details, episodes, play): jumps the
  /// queue, may use the slot kept free for it, and fails fast (no retries).
  Future<Object?> getJson(Uri uri, {Map<String, String> headers = const {}, bool auth = false, bool priority = false}) async {
    final body = await getText(uri, headers: headers, auth: auth, priority: priority);
    return decodeJson(body);
  }

  /// Hosts where https failed (refused / TLS) and plain http worked. Many
  /// IPTV panels only run http, and users often paste "https://" by habit.
  /// Shared by all panels and kept across app starts ([onHttpOnlyHost]):
  /// a blocked/slow https otherwise times out on every start instead of
  /// being refused, and the fallback never happens.
  static final Set<String> httpOnlyHosts = {};
  static void Function(String host)? onHttpOnlyHost;
  Set<String> get _httpOnlyHosts => httpOnlyHosts;

  /// [uri] with the scheme that works for its host (http after a fallback).
  /// Adapters use it for stream URLs too.
  Uri effective(Uri uri) =>
      uri.scheme == 'https' && _httpOnlyHosts.contains(uri.host) ? uri.replace(scheme: 'http', port: _httpPort(uri)) : uri;

  /// https on the default port 443 → http on 80; an explicit port is kept.
  static int? _httpPort(Uri u) => u.hasPort && u.port != 443 ? u.port : null;

  /// GET [uri] as text (M3U playlists, XMLTV).
  Future<String> getText(Uri uri, {Map<String, String> headers = const {}, bool auth = false, bool priority = false}) async {
    final timeout = auth ? limits.authTimeout : limits.requestTimeout;
    uri = effective(uri);
    final urgent = priority || auth;
    var attempt = 0;
    while (true) {
      try {
        return await _slots.run(() => _once(uri, headers, timeout), priority: urgent);
      } on ProviderFailure catch (f) {
        if (uri.scheme == 'https' && _isHttpsProblem(f)) {
          final plain = uri.replace(scheme: 'http', port: _httpPort(uri));
          Diag.panel('https failed (${f.detail}) → trying http: ${Diag.panelUrl(plain)}');
          final text = await _slots.run(() => _once(plain, headers, timeout), priority: urgent);
          if (_httpOnlyHosts.add(uri.host)) onHttpOnlyHost?.call(uri.host);
          Diag.panel('http works for ${uri.host}: using http for this panel');
          return text;
        }
        // The user is waiting (login, details, play): fail fast, no retries.
        if (urgent || !f.isRetryable || attempt >= limits.retries || _closed) rethrow;
        attempt++;
        final wait = _backoffBase * math.pow(2, attempt - 1).toInt();
        Diag.panel('retry $attempt/${limits.retries} in ${wait.inMilliseconds}ms → ${Diag.panelUrl(uri)}');
        await Future<void>.delayed(wait);
      }
    }
  }

  /// The https side is the problem (nothing listening on 443, TLS / cert
  /// failure) — worth one try over http before giving up.
  static bool _isHttpsProblem(ProviderFailure f) {
    if (f.kind != ProviderFailureKind.network) return false;
    final d = f.detail.toLowerCase();
    return d.contains('refused') ||
        d.contains('handshake') ||
        d.contains('certificate') ||
        d.contains('tls') ||
        d.contains('ssl') ||
        d.contains('reset by peer');
  }

  Future<String> _once(Uri uri, Map<String, String> headers, Duration timeout) async {
    if (_closed) throw const ProviderFailure(ProviderFailureKind.network, 'closed');
    final where = 'GET ${Diag.panelUrl(uri)}';
    final sw = Stopwatch()..start();
    final http.Response res;
    try {
      res = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      Diag.panel('$where → TIMEOUT: no answer within ${timeout.inMilliseconds}ms');
      throw ProviderFailure(ProviderFailureKind.timeout, '${timeout.inMilliseconds}ms ${uri.host}');
    } catch (e) {
      // ClientException wraps the real cause (SocketException: Failed host
      // lookup / Connection refused / reset, HandshakeException, …).
      final why = Diag.panelText(e is http.ClientException ? e.message : '$e');
      Diag.panel('$where → NETWORK ERROR after ${sw.elapsedMilliseconds}ms: ${e.runtimeType}: $why');
      throw ProviderFailure(ProviderFailureKind.network, '${uri.host}: $why');
    }
    final code = res.statusCode;
    final ms = sw.elapsedMilliseconds;
    // Panels rarely send a charset; `res.body` would then fall back to
    // Latin-1 and garble Arabic/other names. Panels speak UTF-8.
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (code >= 200 && code < 300) {
      final line = '$where → HTTP $code in ${ms}ms, ${_size(res.bodyBytes.length)}, '
          'type ${res.headers['content-type'] ?? '?'}, starts "${_peek(text)}"';
      // Upload only what matters: logins, slow or very big replies. Routine
      // catalog requests (thousands per sync) stay local.
      final important = timeout == limits.authTimeout || ms > 3000 || res.bodyBytes.length > 5 * 1048576;
      important ? Diag.panel(line) : Diag.panelQuiet(line);
      return text;
    }
    Diag.panel('$where → HTTP $code in ${ms}ms, server: ${res.headers['server'] ?? '?'}, body "${_peek(text)}"');
    throw ProviderFailure(failureKindForStatus(code), 'HTTP $code');
  }

  /// First characters of a reply, one line, credentials masked (Xtream login
  /// replies echo username/password, so those values are masked too).
  static String _peek(String text) {
    var t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAllMapped(RegExp(r'"(username|password|mac)"\s*:\s*"[^"]*"'), (m) => '"${m[1]}":"***"');
    return Diag.panelText(t.length > 90 ? '${t.substring(0, 90)}…' : t);
  }

  static String _size(int n) => n >= 1048576
      ? '${(n / 1048576).toStringAsFixed(1)} MB'
      : n >= 1024
          ? '${(n / 1024).toStringAsFixed(1)} KB'
          : '$n B';

  /// Big bodies are decoded in an isolate; bad JSON → `badResponse`.
  Future<Object?> decodeJson(String body) async {
    final text = body.trim();
    if (text.isEmpty) return null;
    try {
      if (text.length >= limits.isolateDecodeBytes) return await compute(_decode, text);
      return jsonDecode(text);
    } on FormatException {
      // Often an HTML error / captive portal page instead of JSON.
      Diag.panel('reply is not JSON: "${_peek(text)}"');
      throw const ProviderFailure(ProviderFailureKind.badResponse, 'not JSON');
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }

  /// Panel HTTP status → failure kind. 884 is the Xtream panel's "this is not
  /// allowed for this line" (Neo answers it to every `get.php` M3U export,
  /// whatever the User-Agent; measured 2026-11-15) → `unsupported`, so the app
  /// suggests the Xtream login instead of calling the account banned.
  static ProviderFailureKind failureKindForStatus(int code) {
    if (code == 401 || code == 403) return ProviderFailureKind.unauthorized;
    if (code == 429) return ProviderFailureKind.rateLimited;
    if (code == 884) return ProviderFailureKind.unsupported;
    if (code >= 500) return ProviderFailureKind.server;
    return ProviderFailureKind.badResponse;
  }

}

Object? _decode(String s) => jsonDecode(s);

/// Per-panel request slots with a priority lane. Many panels answer only a
/// couple of requests at once and silently drop the rest (seen on the
/// user's line: details/episodes timed out while the sync was running).
/// * background requests (sync) use at most `max - 1` slots, and only 1
///   while the user is waiting on something;
/// * priority requests (the user is waiting) jump the queue and may use any
///   free slot.
class _Slots {
  _Slots(this.max);

  final int max;
  int _busy = 0;
  int _priorityActive = 0;
  final _waitingPriority = <Completer<void>>[];
  final _waitingNormal = <Completer<void>>[];

  int get _normalLimit => max <= 1 ? 1 : (_priorityActive > 0 || _waitingPriority.isNotEmpty ? 1 : max - 1);

  bool _canStart(bool priority) => priority ? _busy < max : _busy < _normalLimit;

  Future<T> run<T>(Future<T> Function() task, {bool priority = false}) async {
    if (!_canStart(priority)) {
      final c = Completer<void>();
      (priority ? _waitingPriority : _waitingNormal).add(c);
      await c.future; // the slot is handed over (already counted)
    } else {
      _busy++;
    }
    if (priority) _priorityActive++;
    try {
      return await task();
    } finally {
      if (priority) _priorityActive--;
      _busy--;
      _wake();
    }
  }

  void _wake() {
    while (_waitingPriority.isNotEmpty && _busy < max) {
      _busy++;
      _waitingPriority.removeAt(0).complete();
    }
    while (_waitingNormal.isNotEmpty && _busy < _normalLimit) {
      _busy++;
      _waitingNormal.removeAt(0).complete();
    }
  }
}
