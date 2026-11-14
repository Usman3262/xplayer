import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ECDSA P-256 device binding (backend Phase A): Android Keystore, iOS
/// Keychain / Secure Enclave, Windows TPM (software key storage provider when
/// the PC has no usable TPM). Every platform uses the same channel; any
/// failure means "no key" and never reaches the user.
///
/// Alias `app.device.binding`. Sends SPKI Base64 as `publicKey` on register.
/// [signRawNonce] signs server PoP challenges (see `DevicePop`).
class DeviceBindingKey {
  DeviceBindingKey._();

  static const _channel = MethodChannel('app/device_binding');
  static const alias = 'app.device.binding';

  /// SPKI public key, standard Base64 (no PEM). Null if unavailable (web / error).
  static Future<String?> publicKeySpkiBase64() async {
    if (kIsWeb) return null;
    try {
      final v = await _channel.invokeMethod<String>('getPublicKeySpkiBase64');
      if (v == null || v.isEmpty) return null;
      return v.replaceAll(RegExp(r'\s+'), '');
    } catch (e) {
      debugPrint('[DeviceBinding] getPublicKey failed: $e');
      return null;
    }
  }

  /// Where the key lives, reported to the backend before PoP enforcement:
  /// `strongbox` | `tee` | `software` | `keychain-secure-enclave` |
  /// `keychain` | `none` (Usman, 20 Oct). Windows reports `tee` for a TPM
  /// key and `software` for the software key storage provider.
  static Future<String> popKeyStorage() async {
    if (kIsWeb) return 'none';
    try {
      final v = await _channel.invokeMethod<String>('getPopKeyStorage');
      return (v == null || v.isEmpty) ? 'none' : v;
    } catch (_) {
      return 'none';
    }
  }

  static String? _signer;

  /// SHA-256 (hex) of the APK signing certificate, sent as `X-App-Signer`
  /// so the server can report repackaged copies (client 3.6; report only,
  /// never blocks). Empty on iOS / web / error. Cached for the app run.
  static Future<String> signingCertSha256() async {
    final cached = _signer;
    if (cached != null) return cached;
    // Security test only (client E5/B8, Usman 6 Nov, "test APK B"): a build
    // made with --dart-define=APP_TEST_FAKE_SIGNER=<hex> reports that value
    // instead of its real certificate, to prove the server trusts Android's
    // attestation, not what the app claims. Empty in every normal build.
    const fake = String.fromEnvironment('APP_TEST_FAKE_SIGNER');
    if (fake.isNotEmpty) return _signer = fake;
    var v = '';
    if (!kIsWeb) {
      try {
        v = (await _channel.invokeMethod<String>('getSigningCertSha256')) ?? '';
      } catch (_) {
        v = '';
      }
    }
    _signer = v;
    return v;
  }

  /// Sign raw bytes with SHA256withECDSA (server PoP check). Platforms
  /// answer either an encoded string (iOS: base64 DER, Windows: base64url
  /// raw r||s) or the signature bytes (Android: DER), which are encoded here
  /// as base64url without padding. The server accepts all of these.
  static Future<String?> signRawNonce(Uint8List nonce) async {
    if (kIsWeb || nonce.isEmpty) return null;
    try {
      final v = await _channel.invokeMethod<Object?>('signRawNonce', {
        'nonce': nonce,
      });
      if (v is String) return v.isEmpty ? null : v;
      if (v is Uint8List && v.isNotEmpty) {
        return base64Url.encode(v).replaceAll('=', '');
      }
      return null;
    } catch (e) {
      debugPrint('[DeviceBinding] sign failed: $e');
      return null;
    }
  }
}
