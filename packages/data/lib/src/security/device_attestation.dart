import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/api_client.dart';
import '../remote/api_exception.dart';

/// Device attestation (client security point 18). iPhone: Apple App Attest
/// (`app_attest`). Android: Google Play Integrity (`play_integrity`) for apps
/// installed from Google Play, Android Key Attestation (`key_attestation`)
/// otherwise (direct download, Fire TV) or when Play gives no token.
/// The server keeps one verdict per device (the last check), so a direct
/// install is never sent to Play Integrity (it would always say "not from Play").
///
/// Proves to the server that this is the real APP 4K app on real Android
/// hardware: the server sends a challenge, the Android Keystore makes a fresh
/// key with that challenge baked into a Google-signed certificate chain, and
/// the app posts the chain back. See backend
/// `Docs/FOR_APP_DEVICE_ATTESTATION_2026-11-02.md`.
///
/// Owner rule: this is invisible. Every failure (no Keystore, old Android,
/// network, server `fail`) is swallowed and logged with [debugPrint] only;
/// the app behaves exactly as before.
class DeviceAttestation {
  DeviceAttestation._();

  static const _channel = MethodChannel('app/device_binding');

  /// A pass is good for this long before the app proves itself again.
  static const passValidFor = Duration(hours: 24);

  /// Max wait for the awaited run at playback start (Block mode).
  static const playbackTimeout = Duration(seconds: 10);

  static String _prefKey(String deviceId) => 'app_attest_pass_$deviceId';

  /// Test hooks.
  @visibleForTesting
  static bool? isAndroidOverride;
  @visibleForTesting
  static Future<List<String>?> Function(String challenge)? chainOverride;
  @visibleForTesting
  static Future<String?> Function()? installerOverride;
  @visibleForTesting
  static Future<String?> Function(String nonce)? playIntegrityOverride;

  static const _playStore = 'com.android.vending';
  @visibleForTesting
  static bool? isIOSOverride;
  @visibleForTesting
  static Future<Map<String, String>?> Function(String challenge)? appAttestOverride;
  @visibleForTesting
  static DateTime Function()? nowOverride;

  static bool get _isAndroid =>
      isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
  static bool get _isIOS => isIOSOverride ?? (!kIsWeb && Platform.isIOS);
  static bool get _supported => _isAndroid || _isIOS;
  static DateTime _now() => (nowOverride ?? DateTime.now)();

  static final Map<String, Future<bool>> _inFlight = {};

  /// Device ids whose verdict was `fail` in this app run: no retry until the
  /// next start (a server/panel fix is picked up then), unless forced.
  static final Set<String> _failedThisRun = {};

  @visibleForTesting
  static void resetForTest() {
    _inFlight.clear();
    _failedThisRun.clear();
  }

  static bool isAttestationRequired(Object e) =>
      e is ApiException && e.code == 'ATTESTATION_REQUIRED';

  /// Fire-and-forget: runs at most once per [passValidFor] per device.
  /// Never throws, never blocks the caller.
  static void runIfDue(ApiClient client, String? deviceId) {
    if (!_supported || deviceId == null || deviceId.isEmpty) return;
    unawaited(run(client, deviceId));
  }

  /// One attestation attempt. True only when the server answered `pass`.
  /// Skips (returns false) while not due, unless [force]. Never throws.
  static Future<bool> run(
    ApiClient client,
    String deviceId, {
    bool force = false,
  }) {
    if (!_supported || deviceId.isEmpty) return Future.value(false);
    final running = _inFlight[deviceId];
    if (running != null) return running;
    final f = _run(client, deviceId, force).whenComplete(() {
      _inFlight.remove(deviceId);
    });
    _inFlight[deviceId] = f;
    return f;
  }

  static Future<bool> _run(ApiClient client, String deviceId, bool force) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        if (_failedThisRun.contains(deviceId)) return false;
        final last = prefs.getInt(_prefKey(deviceId));
        if (last != null) {
          final age = _now().difference(
            DateTime.fromMillisecondsSinceEpoch(last),
          );
          if (!age.isNegative && age < passValidFor) return false;
        }
      }
      final ch = await client.post(
        '/devices/$deviceId/attestation/challenge',
        auth: true,
      );
      final challenge = ch?['challenge'];
      if (challenge is! String || challenge.isEmpty) return false;
      final Map<String, Object> body;
      String? playToken;
      if (_isAndroid) {
        final methods = ch?['methods'];
        final serverTakesPlay = methods is List && methods.contains('play_integrity');
        if (serverTakesPlay && await _installer() == _playStore) {
          playToken = await _playIntegrity(challenge);
          if (playToken == null || playToken.isEmpty) {
            debugPrint('[Attestation] no Play Integrity token; using Key Attestation');
          }
        }
      }
      if (playToken != null && playToken.isNotEmpty) {
        body = {
          'challenge': challenge,
          'method': 'play_integrity',
          'integrityToken': playToken,
        };
      } else if (_isAndroid) {
        final chain = await _chain(challenge);
        if (chain == null || chain.isEmpty) {
          debugPrint('[Attestation] no key chain on this device');
          _failedThisRun.add(deviceId);
          return false;
        }
        body = {
          'challenge': challenge,
          'method': 'key_attestation',
          'certificateChain': chain,
        };
      } else {
        final att = await _appAttest(challenge);
        final keyId = att?['keyId'];
        final attestation = att?['attestation'];
        if (keyId == null || keyId.isEmpty || attestation == null || attestation.isEmpty) {
          debugPrint('[Attestation] App Attest not available on this device');
          _failedThisRun.add(deviceId);
          return false;
        }
        body = {
          'challenge': challenge,
          'method': 'app_attest',
          'keyId': keyId,
          'attestation': attestation,
        };
      }
      final res = await client.post(
        '/devices/$deviceId/attestation',
        body: body,
        auth: true,
      );
      final verdict = res?['verdict'];
      if (verdict == 'pass') {
        _failedThisRun.remove(deviceId);
        await prefs.setInt(_prefKey(deviceId), _now().millisecondsSinceEpoch);
        return true;
      }
      debugPrint('[Attestation] verdict=$verdict reasons=${res?['reasons']}');
      _failedThisRun.add(deviceId);
      return false;
    } on ApiException catch (e) {
      // ATTESTATION_CHALLENGE_INVALID: next run asks for a new challenge.
      // NOT_FOUND: device not on this account; ignore.
      debugPrint('[Attestation] skipped: ${e.code ?? e.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Attestation] skipped: $e');
      return false;
    }
  }

  static Future<List<String>?> _chain(String challenge) async {
    final o = chainOverride;
    if (o != null) return o(challenge);
    final v = await _channel.invokeMethod<List<Object?>>(
      'attestKeyChain',
      {'challenge': challenge},
    );
    if (v == null) return null;
    return v.whereType<String>().where((s) => s.isNotEmpty).toList();
  }

  static Future<String?> _installer() async {
    final o = installerOverride;
    if (o != null) return o();
    try {
      return await _channel.invokeMethod<String>('installerPackage');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _playIntegrity(String nonce) async {
    final o = playIntegrityOverride;
    if (o != null) return o(nonce);
    try {
      return await _channel.invokeMethod<String>('playIntegrityToken', {'nonce': nonce});
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>?> _appAttest(String challenge) async {
    final o = appAttestOverride;
    if (o != null) return o(challenge);
    final v = await _channel.invokeMethod<Map<Object?, Object?>>(
      'appAttest',
      {'challenge': challenge},
    );
    if (v == null) return null;
    final keyId = v['keyId'];
    final attestation = v['attestation'];
    if (keyId is! String || attestation is! String) return null;
    return {'keyId': keyId, 'attestation': attestation};
  }

  /// Playback start in Block mode: on `ATTESTATION_REQUIRED` run the flow
  /// once (awaited, [playbackTimeout]) and retry [call] once. If that still
  /// fails, the caller sees the error exactly as before.
  static Future<T> retryIfRequired<T>(
    ApiClient client,
    String deviceId,
    Future<T> Function() call,
  ) async {
    try {
      return await call();
    } catch (e) {
      if (!isAttestationRequired(e) || !_supported) rethrow;
      try {
        await run(client, deviceId, force: true).timeout(playbackTimeout);
      } catch (_) {
        // Timeout: fall through to the single retry.
      }
      return call();
    }
  }
}
