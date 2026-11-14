import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../diag/diag.dart';
import '../security/config_keys.dart';
import '../security/signed_app_config.dart';

/// Ordered API bases (`https://host/v1`): the built-in one first, then any
/// backups from a verified signed config (client security points 5 and 7).
///
/// Only a config that passed Ed25519 verification can add a backup, so a
/// tampered response or edited storage cannot point the app elsewhere.
/// With no trusted key configured the list is just the built-in base and
/// behaviour is unchanged.
class ApiEndpoints {
  ApiEndpoints._();
  static final ApiEndpoints instance = ApiEndpoints._();

  /// After this long on a backup, try the primary again.
  static const primaryRetryAfter = Duration(minutes: 5);

  final List<String> _bases = [];
  int _index = 0;
  DateTime? _leftPrimaryAt;

  void ensurePrimary(String base) {
    final b = _norm(base);
    if (_bases.isEmpty) {
      _bases.add(b);
    } else if (_bases.first != b) {
      _bases
        ..remove(b)
        ..insert(0, b);
      _index = 0;
    }
  }

  /// Built-in backups (e.g. the Railway address behind the Cloudflare one):
  /// added after the primary, never ahead of it, no duplicates.
  void addBackups(Iterable<String> backups) {
    for (final b in backups.map(_norm)) {
      if (!_bases.contains(b)) _bases.add(b);
    }
  }

  List<String> get bases => List.unmodifiable(_bases);

  String current(String fallback) {
    if (_bases.isEmpty) return _norm(fallback);
    if (_index != 0 &&
        _leftPrimaryAt != null &&
        DateTime.now().difference(_leftPrimaryAt!) > primaryRetryAfter) {
      Diag.api('endpoints: retrying primary ${_bases.first}');
      _index = 0;
      _leftPrimaryAt = null;
    }
    return _bases[_index.clamp(0, _bases.length - 1)];
  }

  bool get hasAlternative => _bases.length > 1;

  /// Called when every known base has failed (or only the primary exists):
  /// the config mirrors may know a working base. Throttled by the caller.
  void Function()? onAllBasesFailing;

  /// A network-level failure on [base]: move to the next one.
  /// Returns the new base, or null if there is nothing else to try.
  String? reportNetworkFailure(String base) {
    if (_bases.length < 2) {
      onAllBasesFailing?.call();
      return null;
    }
    final i = _bases.indexOf(_norm(base));
    if (i != _index) return _bases[_index]; // someone already moved on
    _index = (_index + 1) % _bases.length;
    if (_index != 0) _leftPrimaryAt ??= DateTime.now();
    if (_index == 0) _leftPrimaryAt = null;
    Diag.api('endpoints: ${_bases[i]} unreachable → ${_bases[_index]}');
    if (_index == 0) onAllBasesFailing?.call();
    return _bases[_index];
  }

  /// Add backup origins from a verified config (keeps the primary first).
  void adopt(AppConfig cfg) {
    for (final origin in cfg.apiBaseUrls) {
      final b = _norm('$origin/v1');
      if (!_bases.contains(b)) _bases.add(b);
    }
    debugPrint('[ApiEndpoints] ${_bases.length} base(s) available');
  }

  @visibleForTesting
  void resetForTest() {
    _bases.clear();
    _index = 0;
    _leftPrimaryAt = null;
  }

  static String _norm(String b) => b.replaceAll(RegExp(r'/+$'), '');
}

/// Load the last good signed config, then fetch a fresh one from the API;
/// if the API cannot provide one, try the static mirrors. Never throws.
Future<void> syncSignedAppConfig(
  Future<Map<String, dynamic>?> Function() fetch, {
  SignedAppConfigStore? store,
  List<String>? mirrors,
  http.Client? client,
}) async {
  final s = store ?? SignedAppConfigStore();
  try {
    final last = await s.lastGood();
    if (last != null) ApiEndpoints.instance.adopt(last);
  } catch (e) {
    debugPrint('[ApiEndpoints] last good config unreadable: $e');
  }
  try {
    final env = await fetch();
    if (env != null) {
      final cfg = await s.accept(env);
      if (cfg != null) {
        ApiEndpoints.instance.adopt(cfg);
        return;
      }
    }
  } catch (e) {
    debugPrint('[ApiEndpoints] config from API failed: $e');
  }
  await syncFromConfigMirrors(store: s, mirrors: mirrors, client: client);
}

DateTime? _lastMirrorTry;

/// Fetch the signed config from the first mirror that serves a valid one.
/// Returns true when a config was accepted. Throttled to once per 5 min.
Future<bool> syncFromConfigMirrors({
  SignedAppConfigStore? store,
  List<String>? mirrors,
  http.Client? client,
  bool force = false,
}) async {
  final list = mirrors ?? kConfigMirrorUrls;
  if (list.isEmpty) return false;
  final now = DateTime.now();
  if (!force &&
      _lastMirrorTry != null &&
      now.difference(_lastMirrorTry!) < const Duration(minutes: 5)) {
    return false;
  }
  _lastMirrorTry = now;
  final s = store ?? SignedAppConfigStore();
  final c = client ?? http.Client();
  try {
    for (final url in list) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') continue;
      try {
        final res = await c.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body);
        // Raw envelope, or the API's { data: envelope } shape.
        final env = body is Map<String, dynamic> && body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : body;
        if (env is! Map<String, dynamic>) continue;
        final cfg = await s.accept(env);
        if (cfg != null) {
          ApiEndpoints.instance.adopt(cfg);
          Diag.api('endpoints: config from mirror ${uri.host} accepted');
          return true;
        }
      } catch (e) {
        Diag.api('endpoints: mirror ${uri.host} failed: $e');
      }
    }
    return false;
  } finally {
    if (client == null) c.close();
  }
}
