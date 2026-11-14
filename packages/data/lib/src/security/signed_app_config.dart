import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_keys.dart';

/// Verified contents of `GET /v1/config/app` (client security point 5).
///
/// The server signs the exact payload bytes with Ed25519; the app holds only
/// public keys ([kConfigPublicKeys]), so nothing in the APK/IPA can forge a
/// config. A config is accepted only if:
///  - its key id is trusted and the signature matches,
///  - `typ` is right and `exp` is in the future,
///  - `seq` is not older than the newest config already accepted (rollback),
///  - `seq` is not below the highest `minSeq` seen (revocation).
class AppConfig {
  const AppConfig({
    required this.seq,
    required this.minSeq,
    required this.expiresAt,
    required this.apiBaseUrls,
    required this.downloads,
    required this.devicePop,
  });

  final int seq;
  final int minSeq;
  final DateTime expiresAt;

  /// Origins only (`https://host`), primary first.
  final List<String> apiBaseUrls;
  final bool downloads;
  final bool devicePop;
}

class ConfigCheckState {
  const ConfigCheckState({this.lastSeq = 0, this.lastMinSeq = 0});
  final int lastSeq;
  final int lastMinSeq;
}

const _type = 'app.app-config';

/// Pure verification (unit-tested). Returns null if anything is wrong.
Future<AppConfig?> verifyAppConfig(
  Map<String, dynamic> envelope, {
  required Map<String, String> trustedKeys,
  required ConfigCheckState state,
  DateTime? now,
}) async {
  try {
    if (envelope['alg'] != 'Ed25519') return null;
    final kid = envelope['kid'];
    final pub = kid is String ? trustedKeys[kid] : null;
    if (pub == null || pub.isEmpty) return null;
    final payloadB64 = envelope['payload'];
    final sigB64 = envelope['sig'];
    if (payloadB64 is! String || sigB64 is! String) return null;

    final bytes = base64Url.decode(base64Url.normalize(payloadB64));
    final sig = base64Url.decode(base64Url.normalize(sigB64));
    final ok = await Ed25519().verify(
      bytes,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(base64.decode(pub), type: KeyPairType.ed25519),
      ),
    );
    if (!ok) return null;

    final p = jsonDecode(utf8.decode(bytes));
    if (p is! Map<String, dynamic>) return null;
    if (p['typ'] != _type) return null;
    final seq = (p['seq'] as num).toInt();
    final minSeq = (p['minSeq'] as num).toInt();
    final exp = (p['exp'] as num).toInt();
    final nowSec = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (exp <= nowSec) return null;
    if (seq < state.lastSeq) return null;
    if (seq < (minSeq > state.lastMinSeq ? minSeq : state.lastMinSeq)) {
      return null;
    }
    final urls = <String>[];
    for (final u in (p['apiBaseUrls'] as List? ?? const [])) {
      final uri = Uri.tryParse('$u');
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final origin = uri.origin;
      if (!urls.contains(origin)) urls.add(origin);
    }
    final features = (p['features'] as Map?) ?? const {};
    return AppConfig(
      seq: seq,
      minSeq: minSeq,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      apiBaseUrls: urls,
      downloads: features['downloads'] == true,
      devicePop: features['devicePop'] == true,
    );
  } catch (e) {
    debugPrint('[AppConfig] rejected: $e');
    return null;
  }
}

/// Keeps the rollback counters and the last good envelope on the device.
/// The envelope is re-verified on every load, so editing storage cannot
/// inject URLs; deleting storage only resets to the built-in defaults.
class SignedAppConfigStore {
  SignedAppConfigStore({Map<String, String>? trustedKeys, this.clock})
      : _keys = trustedKeys ?? kConfigPublicKeys;

  final Map<String, String> _keys;

  /// Test hook; null = system time.
  final DateTime Function()? clock;

  static const _kEnvelope = 'app_cfg_envelope';
  static const _kSeq = 'app_cfg_last_seq';
  static const _kMinSeq = 'app_cfg_last_min_seq';

  Future<ConfigCheckState> _state(SharedPreferences prefs) async =>
      ConfigCheckState(
        lastSeq: prefs.getInt(_kSeq) ?? 0,
        lastMinSeq: prefs.getInt(_kMinSeq) ?? 0,
      );

  /// Verify a freshly fetched envelope; persist it only if accepted.
  Future<AppConfig?> accept(Map<String, dynamic> envelope) async {
    if (_keys.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final cfg = await verifyAppConfig(
      envelope,
      trustedKeys: _keys,
      state: await _state(prefs),
      now: clock?.call(),
    );
    if (cfg == null) {
      debugPrint('[AppConfig] fetched config rejected');
      return null;
    }
    await prefs.setString(_kEnvelope, jsonEncode(envelope));
    await prefs.setInt(_kSeq, cfg.seq);
    final prevMin = prefs.getInt(_kMinSeq) ?? 0;
    if (cfg.minSeq > prevMin) await prefs.setInt(_kMinSeq, cfg.minSeq);
    return cfg;
  }

  /// Last accepted config, if it still verifies and has not expired.
  Future<AppConfig?> lastGood() async {
    if (_keys.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEnvelope);
    if (raw == null) return null;
    final env = jsonDecode(raw);
    if (env is! Map<String, dynamic>) return null;
    final st = await _state(prefs);
    // Same envelope as lastSeq is allowed (seq == lastSeq).
    return verifyAppConfig(env, trustedKeys: _keys, state: st, now: clock?.call());
  }
}
