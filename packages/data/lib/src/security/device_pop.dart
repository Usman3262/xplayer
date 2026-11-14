import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/api_client.dart';
import '../remote/api_exception.dart';
import 'device_binding_key.dart';

/// Device proof of possession (client security area 5 / APK finding 3.4).
///
/// When the server enforces it (FEATURE_DEVICE_POP), refresh and playback
/// start answer `POP_REQUIRED` unless the request carries a signature from
/// this device's hardware key (Android Keystore / iOS Keychain). The app
/// then asks for a one-time challenge, signs it and repeats the call once.
/// A copied token is useless on another device: it has no private key.
///
/// No extra request is made while enforcement is off.
class DevicePop {
  DevicePop._();

  /// Test hook: replaces the platform signer.
  @visibleForTesting
  static Future<String?> Function(Uint8List data)? signOverride;

  static bool isPopRequired(Object e) =>
      e is ApiException && e.code == 'POP_REQUIRED';

  /// Signs a server challenge; null when this device has no key.
  static Future<Map<String, String>?> _proof(Map<String, dynamic>? ch) async {
    final id = ch?['challengeId'];
    final challenge = ch?['challenge'];
    if (id is! String || challenge is! String) return null;
    final bytes = Uint8List.fromList(utf8.encode(challenge));
    final sig = signOverride != null
        ? await signOverride!(bytes)
        : await DeviceBindingKey.signRawNonce(bytes);
    if (sig == null || sig.isEmpty) return null;
    return {'popChallengeId': id, 'popSignature': sig};
  }

  /// Challenge for token refresh, authorised by the refresh token itself
  /// (the access token has usually expired by then).
  static Future<Map<String, String>?> forRefresh(
    ApiClient client,
    String refreshToken,
  ) async {
    final ch = await client.post(
      '/auth/refresh/challenge',
      body: {'refreshToken': refreshToken},
    );
    return _proof(ch);
  }

  /// Challenge for a signed-in call (playback start / takeover).
  static Future<Map<String, String>?> forDevice(
    ApiClient client,
    String deviceId,
  ) async {
    final ch = await client.post('/devices/$deviceId/pop/challenge', auth: true);
    return _proof(ch);
  }

  /// Test hook: replaces the platform public key.
  @visibleForTesting
  static Future<String?> Function()? publicKeyOverride;

  static final Set<String> _enrolling = {};

  /// Makes sure the server has this device's public key (devices that
  /// registered before they had a key, e.g. iPhones before 6.0.22). Once per
  /// device id and key; re-sending the same key is a no-op on the server.
  /// Never throws; never blocks sign-in.
  static Future<void> ensureEnrolled(ApiClient client, String deviceId) async {
    if (deviceId.isEmpty || !_enrolling.add(deviceId)) return;
    try {
      final key = publicKeyOverride != null
          ? await publicKeyOverride!()
          : await DeviceBindingKey.publicKeySpkiBase64();
      if (key == null || key.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final flag = 'app_pop_key_$deviceId';
      final fingerprint = key.length > 24 ? key.substring(key.length - 24) : key;
      if (prefs.getString(flag) == fingerprint) return;
      await client.post(
        '/devices/$deviceId/pop/key',
        body: {'publicKey': key},
        auth: true,
      );
      await prefs.setString(flag, fingerprint);
    } catch (e) {
      // A different key is on file (reinstall): the server keeps the old one
      // until the device is removed and signs in again as a new device.
      debugPrint('[DevicePop] enrol skipped: $e');
    } finally {
      _enrolling.remove(deviceId);
    }
  }

  /// POST [path]; if the server asks for proof, sign and retry once.
  static Future<Map<String, dynamic>?> post(
    ApiClient client,
    String path, {
    required Map<String, dynamic> body,
    required bool auth,
    required Future<Map<String, String>?> Function() proof,
  }) async {
    try {
      return await client.post(path, body: body, auth: auth);
    } on ApiException catch (e) {
      if (!isPopRequired(e)) rethrow;
      final p = await proof();
      if (p == null) rethrow;
      return client.post(path, body: {...body, ...p}, auth: auth);
    }
  }
}
