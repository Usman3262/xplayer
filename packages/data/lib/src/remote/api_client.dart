import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpException, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

import '../diag/diag.dart';
import '../diag/network_diag.dart';
import 'api_config.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';
import 'token_store.dart';
import 'json_read.dart';
import '../security/device_binding_key.dart';

typedef TokenRefresher = Future<bool> Function();

/// Usman `/v1` success envelope (`data` + optional `meta` for pagination).
class ApiEnvelope {
  const ApiEnvelope({this.data, this.meta});

  final Map<String, dynamic>? data;
  final Map<String, dynamic>? meta;

  String? get nextCursor {
    final v = meta?['nextCursor'];
    if (v == null) return null;
    final s = '$v';
    return s.isEmpty || s == 'null' ? null : s;
  }

  int? get total {
    final v = meta?['total'];
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }
}

class PageResult<T> {
  const PageResult({required this.items, this.nextCursor, this.total});

  final List<T> items;
  final String? nextCursor;
  final int? total;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

class ApiClient {
  ApiClient({
    required ApiConfig config,
    required this.tokenStore,
    http.Client? httpClient,
    this.onRefresh,
    ApiEndpoints? endpoints,
  }) : _baseUrl = config.baseUrl,
       _endpoints = endpoints,
       _http = httpClient ?? _defaultHttp() {
    _endpoints?.ensurePrimary(_baseUrl);
    if (_baseUrl == ApiConfig.defaultBaseUrl) {
      _endpoints?.addBackups(ApiConfig.builtInBackupBaseUrls);
    }
  }

  /// Idle connections close after 10 s (Usman 12 Nov: keep them short,
  /// about 15 s). A connection the server or a proxy had already dropped
  /// was reused and hung: catalog lists waited 26–30 s, then "connection
  /// closed" (iPhone simulator, 12 Nov 17:36 UTC; the server answered them in
  /// under 50 ms).
  static http.Client _defaultHttp() => IOClient(
        HttpClient()
          ..idleTimeout = const Duration(seconds: 10)
          ..connectionTimeout = const Duration(seconds: 15),
      );

  /// The connection broke before an answer (closed / reset / read failed),
  /// not a timeout: worth one retry on a fresh connection.
  static bool _isBrokenConnection(Object e) =>
      e is http.ClientException || e is SocketException || e is HttpException;

  final String _baseUrl;

  /// Backup API bases from the signed config (null = single fixed base).
  final ApiEndpoints? _endpoints;
  final TokenStore tokenStore;
  final http.Client _http;
  TokenRefresher? onRefresh;

  Future<bool>? _refreshInFlight;
  final Map<String, Future<ApiEnvelope>> _inflightGets = {};

  String get _activeBase => _endpoints?.current(_baseUrl) ?? _baseUrl;

  Uri _uri(String path, String base) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<Map<String, dynamic>?> get(
    String path, {
    bool auth = true,
    Map<String, String>? query,
  }) async {
    return (await getEnvelope(path, auth: auth, query: query)).data;
  }

  Future<ApiEnvelope> getEnvelope(
    String path, {
    bool auth = true,
    Map<String, String>? query,
  }) {
    final key = _dedupeKey('GET', path, query);
    final existing = _inflightGets[key];
    if (existing != null) {
      _log('→ inflight coalesce GET $path cache=inflight');
      return existing;
    }
    final future = _send('GET', path, auth: auth, query: query);
    _inflightGets[key] = future;
    return future.whenComplete(() {
      if (identical(_inflightGets[key], future)) {
        _inflightGets.remove(key);
      }
    });
  }

  String _dedupeKey(String method, String path, Map<String, String>? query) {
    if (query == null || query.isEmpty) return '$method $path';
    final entries = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final q = entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$method $path?$q';
  }

  Future<Map<String, dynamic>?> post(
    String path, {
    Object? body,
    bool auth = false,
  }) async {
    return (await _send('POST', path, body: body, auth: auth)).data;
  }

  Future<Map<String, dynamic>?> put(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    return (await _send('PUT', path, body: body, auth: auth)).data;
  }

  Future<Map<String, dynamic>?> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    return (await _send('PATCH', path, body: body, auth: auth)).data;
  }

  Future<Map<String, dynamic>?> delete(String path, {bool auth = true}) async {
    return (await _send('DELETE', path, auth: auth)).data;
  }

  String _redact(Object? body) {
    if (body == null) return 'null';
    try {
      final map = body is Map
          ? Map<String, dynamic>.from(body)
          : jsonDecode(jsonEncode(body));
      return _truncate(_redactNode(map));
    } catch (_) {
      return body.toString();
    }
  }

  /// Redacts credentials in logged JSON, including nested `/auth/refresh` and `/me` payloads.
  String _redactResponseBody(String raw) {
    if (raw.isEmpty) return raw;
    // Huge catalog/series payloads: do not jsonDecode on the UI isolate just for logs.
    if (raw.length > 4000) return _truncate(raw);
    try {
      return _truncate(_redactNode(jsonDecode(raw)));
    } catch (_) {
      return _truncate(raw);
    }
  }

  String _truncate(Object? value, {int max = 500}) {
    final text = value is String ? value : jsonEncode(value);
    if (text.length > max) return '${text.substring(0, max)}…';
    return text;
  }

  Object? _redactNode(Object? node) {
    if (node is Map) {
      final copy = <String, dynamic>{};
      node.forEach((key, value) {
        final name = key.toString();
        if (_isSensitiveKey(name)) {
          final v = value?.toString() ?? '';
          copy[name] = v.isEmpty ? '***' : '***(${v.length})';
        } else {
          copy[name] = _redactNode(value);
        }
      });
      return copy;
    }
    if (node is List) {
      return node.map(_redactNode).toList();
    }
    return node;
  }

  bool _isSensitiveKey(String key) {
    final k = key.toLowerCase();
    if (k == 'email' || k.endsWith('email')) return true;
    if (k == 'accesstoken' || k == 'refreshtoken') return true;
    if (k.contains('password') || k.contains('secret') || k.contains('token')) {
      return true;
    }
    // Never log stream URLs (Xtream line credentials live in the query).
    if (k == 'playurl' || k == 'streamurl' || k == 'url') return true;
    // Alternate play URLs and the provider login URL carry the same credentials.
    if (k == 'alternateplayurls' || k == 'providerauthurl') return true;
    if (k.contains('code') && k != 'requestid') return true;
    return false;
  }

  void _log(String message) => Diag.api(message);

  /// High-frequency GETs that repeat the same pending/empty body.
  static bool _isQuietPollPath(String method, String path) {
    if (method != 'GET') return false;
    if (path.contains('/auth/login-challenges/pending')) return true;
    if (path.contains('/auth/device/code/')) return true;
    if (path.contains('/auth/device/challenges/')) return true;
    if (path.contains('/auth/login-challenges/') && path.endsWith('/wait')) {
      return true;
    }
    if (path.contains('/heartbeat')) return true;
    // GET /auth/login-challenges/{id} (not .../allow or .../deny).
    final challenge = RegExp(r'/auth/login-challenges/[^/]+/?$');
    return challenge.hasMatch(path);
  }

  static bool _isBoringPollBody(String body, String path) {
    final lower = body.toLowerCase();
    // Empty pending list only — a non-empty challenge list must always log.
    if (path.contains('/login-challenges/pending')) {
      return lower.contains('"data":[]') ||
          lower.contains('"data": null') ||
          lower.contains('"data":null');
    }
    if (lower.contains('"data":[]')) return true;
    // Single-challenge wait poll (TV / new device) repeats PENDING.
    if (lower.contains('"status":"pending"')) return true;
    // Heartbeat / lease renew success with no error surface.
    if (lower.contains('"message":"lease renewed"') ||
        lower.contains('"message":"heartbeat"')) {
      return true;
    }
    return false;
  }

  int _quietPollSuppressed = 0;
  String? _lastQuietKey;

  void _logQuietPollSummaryIfNeeded() {
    if (_quietPollSuppressed <= 0) return;
    final n = _quietPollSuppressed;
    _quietPollSuppressed = 0;
    _log('(suppressed $n identical pending/empty poll responses)');
  }

  /// Business 401s must NOT trigger refresh (burns refresh-token family).
  bool _shouldAttemptRefresh(String? message) {
    final m = (message ?? '').toLowerCase();
    if (m.isEmpty) return true;
    // Business / validation failures (still HTTP 401 on some backends).
    if (m.contains('invalid mfa') ||
        m.contains('mfa code') ||
        m.contains('invalid code') ||
        m.contains('wrong code') ||
        m.contains('recovery') ||
        m.contains('password') ||
        m.contains('not allowed') ||
        m.contains('validation') ||
        m.contains('reuse detected')) {
      return false;
    }
    return m.contains('authentication') ||
        m.contains('unauthorized') ||
        m.contains('access token') ||
        m.contains('jwt') ||
        m.contains('expired') ||
        m.contains('session');
  }

  /// After a failed refresh: signed out only if the refresh token was
  /// rejected (the refresher then cleared the tokens). A temporary failure
  /// (429 rate limit, 5xx, network) keeps the sign-in and asks to retry
  /// (client 20 Oct: logged out while watching after a refresh 429).
  Future<ApiException> _refreshFailed() async {
    final still = await tokenStore.read();
    if (still == null) {
      return ApiException('Session expired. Please sign in again.', statusCode: 401);
    }
    return ApiException(
      'Could not refresh your session right now. Please try again.',
      statusCode: 503,
      code: 'SESSION_REFRESH_RETRY',
    );
  }

  Future<bool> _runRefreshOnce() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final refresher = onRefresh;
    if (refresher == null) return false;
    final future = () async {
      try {
        return await refresher();
      } finally {
        _refreshInFlight = null;
      }
    }();
    _refreshInFlight = future;
    return future;
  }

  Future<ApiEnvelope> _send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    bool didRefresh = false,
    bool didFailover = false,
    bool didReconnect = false,
    Map<String, String>? query,
    int rateRetries = 0,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    // Runtime integrity report (client 3.6): which certificate signed this
    // app. The server logs copies signed by someone else; it never blocks.
    final signer = await DeviceBindingKey.signingCertSha256();
    if (signer.isNotEmpty) headers['X-App-Signer'] = signer;

    if (auth) {
      var tokens = await tokenStore.read();
      if (tokens == null) {
        _log('$method $path → LOCAL miss: no tokens in store');
        throw ApiException(
          'No access token stored. Please sign in again.',
          statusCode: 401,
        );
      }
      if (tokens.isAccessExpired && onRefresh != null && !didRefresh) {
        _log('$method $path → access expired, refreshing…');
        final ok = await _runRefreshOnce();
        Diag.api(
          'refresh ${ok ? 'ok' : 'FAIL'} reason=access_expired path=$path',
        );
        if (!ok) throw await _refreshFailed();
        tokens = await tokenStore.read();
        if (tokens == null) {
          throw ApiException(
            'Session expired. Please sign in again.',
            statusCode: 401,
          );
        }
      }
      headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }

    final base = _activeBase;
    var uri = _uri(path, base);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final needsBody = method == 'POST' || method == 'PUT' || method == 'PATCH';
    final encoded = body == null ? (needsBody ? '{}' : null) : jsonEncode(body);

    final reqId = Diag.nextRequestId();
    final started = DateTime.now();
    final quietPath = _isQuietPollPath(method, path);
    final logAll = DiagConfig.verboseApi || !quietPath;
    if (logAll) {
      _logQuietPollSummaryIfNeeded();
      _log(
        '→ #$reqId $method $uri auth=$auth '
        'payload=${_redact(body ?? (needsBody ? const <String, dynamic>{} : null))} '
        't=+0ms',
      );
    }

    late http.Response response;
    try {
      response = switch (method) {
        'GET' =>
          await _http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30)),
        'POST' =>
          await _http
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30)),
        'PUT' =>
          await _http
              .put(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30)),
        'PATCH' =>
          await _http
              .patch(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30)),
        'DELETE' =>
          await _http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 30)),
        _ => throw ApiException('Unsupported method $method'),
      };
    } catch (e) {
      if (e is ApiException) rethrow;
      final dur = DateTime.now().difference(started).inMilliseconds;
      _logQuietPollSummaryIfNeeded();
      _log('✖ #$reqId $method $path network error dur=${dur}ms err=$e');
      Diag.err('API network #$reqId $method $path', e);
      // Usman 12 Nov: a GET whose connection closed is asked once more, on a
      // fresh connection (the broken one is not reused). Not a POST: it may
      // have reached the server.
      if (method == 'GET' && !didReconnect && _isBrokenConnection(e)) {
        _log('↻ #$reqId retry GET $path once (connection closed)');
        return _send(
          method,
          path,
          body: body,
          auth: auth,
          didRefresh: didRefresh,
          didFailover: didFailover,
          didReconnect: true,
          query: query,
        );
      }
      // Unreachable API host: switch to a backup from the signed config.
      // Only GETs are retried at once; a POST may have reached the server.
      final next = _endpoints?.reportNetworkFailure(base);
      if (next != null && next != base && method == 'GET' && !didFailover) {
        _log('↻ #$reqId retry GET $path on backup API');
        return _send(
          method,
          path,
          body: body,
          auth: auth,
          didRefresh: didRefresh,
          didFailover: true,
          query: query,
        );
      }
      if (path.contains('playback')) {
        unawaited(
          logNetworkDiagnostics(context: 'api_playback_network_error'),
        );
      }
      throw ApiException('Network error. Check connection and try again.', code: 'NETWORK');
    }

    final dur = DateTime.now().difference(started).inMilliseconds;
    final sizeKb = (response.bodyBytes.length / 1024).toStringAsFixed(1);
    String? serverReqId;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) serverReqId = jsonStr(decoded['requestId']);
    } catch (_) {}
    final boring = quietPath &&
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        _isBoringPollBody(response.body, path);
    if (DiagConfig.verboseApi || !boring) {
      _logQuietPollSummaryIfNeeded();
      if (!logAll) {
        // Request was skipped; still show a short inbound line for status change.
        _log(
          '→ #$reqId $method $path auth=$auth (poll status change)',
        );
      }
      _log(
        '← #$reqId ${response.statusCode} dur=${dur}ms size=${sizeKb}KB '
        'reqId=${serverReqId ?? '-'} '
        'body=${_redactResponseBody(response.body)}',
      );
      _lastQuietKey = null;
    } else {
      final key = '$method $path ${response.statusCode}';
      if (_lastQuietKey == key) {
        _quietPollSuppressed++;
      } else {
        _logQuietPollSummaryIfNeeded();
        _lastQuietKey = key;
        _quietPollSuppressed = 1;
      }
    }

    // 429: wait as the server asks (Retry-After, capped) and repeat a read
    // once, instead of showing "could not load" (client 21 Oct). Writes are
    // never repeated (they may have been counted).
    if (response.statusCode == 429 && method == 'GET' && rateRetries < 1) {
      final ra = int.tryParse(response.headers['retry-after'] ?? '') ?? 2;
      final wait = Duration(seconds: ra.clamp(1, 8));
      _log('↻ #$reqId 429 on $path, retry in ${wait.inSeconds}s');
      await Future<void>.delayed(wait);
      return _send(
        method,
        path,
        body: body,
        auth: auth,
        didRefresh: didRefresh,
        didFailover: didFailover,
        query: query,
        rateRetries: rateRetries + 1,
      );
    }

    if (response.statusCode == 401 &&
        auth &&
        !didRefresh &&
        onRefresh != null) {
      String? message;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          message = jsonStr(decoded['message']);
        }
      } catch (_) {}
      if (_shouldAttemptRefresh(message)) {
        // Nested auth calls during an in-flight refresh (PoP challenge while
        // refreshing) must not await the same refresh — that deadlocks and
        // leaves every later API call on "Invalid access token".
        if (_refreshInFlight != null) {
          _log(
            '$method $path → auth 401 ($message), skip nested refresh '
            '(refresh already in flight)',
          );
        } else {
          _log('$method $path → auth 401 ($message), refreshing once');
          final ok = await _runRefreshOnce();
          Diag.api(
            'refresh ${ok ? 'ok' : 'FAIL'} reason=http_401 path=$path msg=$message',
          );
          if (ok) {
            return _send(
              method,
              path,
              body: body,
              auth: auth,
              didRefresh: true,
              didFailover: didFailover,
              query: query,
            );
          }
          throw await _refreshFailed();
        }
        throw await _refreshFailed();
      } else {
        _log('$method $path → business 401 ($message), skip refresh');
      }
    }

    return _parseFullEnvelope(response);
  }

  /// Large JSON (catalog rails, series detail) is decoded off the UI isolate.
  Future<ApiEnvelope> _parseFullEnvelope(http.Response response) async {
    final body = response.body;
    final status = response.statusCode;
    if (body.length < _kIsolateJsonMinBytes) {
      return _parseEnvelopePayload(body, status);
    }
    final result = await compute(_parseEnvelopeIsolate, <String, Object?>{
      'body': body,
      'status': status,
    });
    final err = jsonStr(result['error']);
    if (err != null) {
      final rawErrData = result['data'];
      Map<String, dynamic>? errData;
      if (rawErrData is Map) {
        errData = Map<String, dynamic>.from(rawErrData);
      }
      throw ApiException(
        err,
        statusCode: jsonInt(result['statusCode']) ?? status,
        requestId: jsonStr(result['requestId']),
        code: jsonStr(result['code']),
        data: errData,
      );
    }
    return ApiEnvelope(
      data: result['data'] as Map<String, dynamic>?,
      meta: result['meta'] as Map<String, dynamic>?,
    );
  }

  void close() => _http.close();
}

/// Bodies at/above this size decode on a worker isolate (low-end CPU relief).
const _kIsolateJsonMinBytes = 4096;

/// Top-level for [compute] — keep payload sendable (Map/String/int only).
Map<String, Object?> _parseEnvelopeIsolate(Map<String, Object?> args) {
  try {
    final env = _parseEnvelopePayload(
      args['body'] as String,
      args['status'] as int,
    );
    return <String, Object?>{'data': env.data, 'meta': env.meta};
  } on ApiException catch (e) {
    return <String, Object?>{
      'error': e.message,
      'statusCode': e.statusCode,
      'requestId': e.requestId,
      'code': e.code,
      'data': e.data,
    };
  } catch (e) {
    return <String, Object?>{
      'error': 'Invalid response from server',
      'statusCode': jsonInt(args['status']),
    };
  }
}

ApiEnvelope _parseEnvelopePayload(String body, int statusCode) {
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw ApiException(
        'Unexpected response from server',
        statusCode: statusCode,
      );
    }
    json = Map<String, dynamic>.from(decoded);
  } catch (e) {
    if (e is ApiException) rethrow;
    throw ApiException(
      'Invalid response from server ($statusCode)',
      statusCode: statusCode,
    );
  }

  final requestId = jsonStr(json['requestId']);
  final success = jsonBool(json['success']) ?? false;
  final message = (jsonStr(json['message']))?.trim();

  if (statusCode >= 400 || !success) {
    Map<String, dynamic>? errData;
    final rawData = json['data'];
    if (rawData is Map) {
      errData = Map<String, dynamic>.from(rawData);
    }
    throw ApiException(
      (message != null && message.isNotEmpty)
          ? message
          : 'Request failed ($statusCode)',
      statusCode: statusCode,
      requestId: requestId,
      code: jsonStr(json['code']),
      data: errData,
    );
  }

  Map<String, dynamic>? meta;
  final rawMeta = json['meta'];
  if (rawMeta is Map) {
    meta = Map<String, dynamic>.from(rawMeta);
  }

  final data = json['data'];
  if (data == null) return ApiEnvelope(data: null, meta: meta);
  if (data is Map<String, dynamic>) {
    return ApiEnvelope(data: data, meta: meta);
  }
  if (data is Map) {
    return ApiEnvelope(data: Map<String, dynamic>.from(data), meta: meta);
  }
  return ApiEnvelope(data: {'_': data}, meta: meta);
}
