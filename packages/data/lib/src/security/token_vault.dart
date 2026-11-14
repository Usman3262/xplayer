import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hardware-backed sealing for login tokens (client security point 3).
///
/// Android: AES-256-GCM key in the Android Keystore (phone and TV).
/// iOS: AES-256-GCM key in the Keychain, this-device-only.
/// The sealed value is what goes into SharedPreferences, so a copied prefs
/// file (backup, rooted device, adb) does not contain a usable token.
///
/// If the platform side is missing or the Keystore fails (some Android
/// devices broke flutter_secure_storage with KeyStore code 7), [seal]
/// returns null and the caller keeps the old plain storage, so sign-in
/// keeps working on those devices.
class TokenVault {
  TokenVault._();

  static const _channel = MethodChannel('app/token_vault');
  static const prefix = 'v1:';
  static bool _unavailable = false;

  /// Decrypted values by stored value, so each API call does not hit the
  /// Keystore again.
  static final Map<String, String> _openCache = {};

  static bool isSealed(String stored) => stored.startsWith(prefix);

  static bool get available => !kIsWeb && !_unavailable;

  static Future<String?> seal(String plain) async {
    if (!available) return null;
    try {
      final out = await _channel.invokeMethod<Uint8List>(
        'seal',
        {'data': Uint8List.fromList(utf8.encode(plain))},
      );
      if (out == null || out.isEmpty) return null;
      final stored = '$prefix${base64.encode(out)}';
      _openCache[stored] = plain;
      return stored;
    } catch (e) {
      _unavailable = true;
      debugPrint('[TokenVault] seal unavailable, keeping plain storage: $e');
      return null;
    }
  }

  /// Null if the value cannot be opened on this device.
  static Future<String?> open(String stored) async {
    if (!isSealed(stored)) return stored;
    final cached = _openCache[stored];
    if (cached != null) return cached;
    if (kIsWeb) return null;
    try {
      final out = await _channel.invokeMethod<Uint8List>(
        'open',
        {'data': base64.decode(stored.substring(prefix.length))},
      );
      if (out == null) return null;
      final plain = utf8.decode(out);
      if (_openCache.length > 16) _openCache.clear();
      _openCache[stored] = plain;
      return plain;
    } catch (e) {
      debugPrint('[TokenVault] open failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _unavailable = false;
    _openCache.clear();
  }
}
