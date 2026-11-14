import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../backend/remote_config.dart';
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
  Future<Object?> getJson(Uri uri, {Map<String, String> headers = const {}, bool auth = false}) async {
    final body = await getText(uri, headers: headers, auth: auth);
    return decodeJson(body);
  }

  /// GET [uri] as text (M3U playlists, XMLTV).
  Future<String> getText(Uri uri, {Map<String, String> headers = const {}, bool auth = false}) async {
    final timeout = auth ? limits.authTimeout : limits.requestTimeout;
    var attempt = 0;
    while (true) {
      try {
        return await _slots.run(() => _once(uri, headers, timeout));
      } on ProviderFailure catch (f) {
        // Login answers fast or fails fast: no retries on the auth call.
        if (auth || !f.isRetryable || attempt >= limits.retries || _closed) rethrow;
        attempt++;
        await Future<void>.delayed(_backoffBase * math.pow(2, attempt - 1).toInt());
      }
    }
  }

  Future<String> _once(Uri uri, Map<String, String> headers, Duration timeout) async {
    if (_closed) throw const ProviderFailure(ProviderFailureKind.network, 'closed');
    final http.Response res;
    try {
      res = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw ProviderFailure(ProviderFailureKind.timeout, '${timeout.inMilliseconds}ms ${uri.host}');
    } on http.ClientException catch (e) {
      throw ProviderFailure(ProviderFailureKind.network, '${uri.host}: ${_safe(e.message)}');
    } catch (e) {
      // SocketException / HandshakeException / browser fetch errors.
      throw ProviderFailure(ProviderFailureKind.network, '${uri.host}: ${e.runtimeType}');
    }
    final code = res.statusCode;
    if (code >= 200 && code < 300) return res.body;
    throw ProviderFailure(failureKindForStatus(code), 'HTTP $code');
  }

  /// Big bodies are decoded in an isolate; bad JSON → `badResponse`.
  Future<Object?> decodeJson(String body) async {
    final text = body.trim();
    if (text.isEmpty) return null;
    try {
      if (text.length >= limits.isolateDecodeBytes) return await compute(_decode, text);
      return jsonDecode(text);
    } on FormatException {
      // Often an HTML error / captive portal page instead of JSON.
      throw const ProviderFailure(ProviderFailureKind.badResponse, 'not JSON');
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }

  /// Panel HTTP status → failure kind. Some panels answer 884 / 512 for banned
  /// or blocked accounts.
  static ProviderFailureKind failureKindForStatus(int code) {
    if (code == 401 || code == 403) return ProviderFailureKind.unauthorized;
    if (code == 429) return ProviderFailureKind.rateLimited;
    if (code == 884 || code == 512) return ProviderFailureKind.banned;
    if (code >= 500) return ProviderFailureKind.server;
    return ProviderFailureKind.badResponse;
  }

  /// Strips anything URL-like from an error message (URLs carry credentials).
  static String _safe(String m) => m.replaceAll(RegExp(r'https?://\S+'), '<url>');
}

Object? _decode(String s) => jsonDecode(s);

/// Small async semaphore: at most [max] requests in flight per panel.
class _Slots {
  _Slots(this.max);

  final int max;
  int _busy = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_busy >= max) {
      // The finishing request hands its slot straight to us (no _busy++),
      // so a newcomer can never slip in between and exceed [max].
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    } else {
      _busy++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _busy--;
      }
    }
  }
}
