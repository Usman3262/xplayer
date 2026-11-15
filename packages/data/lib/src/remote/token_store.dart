import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diag/diag.dart';
import '../security/token_vault.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.sessionId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? sessionId;

  bool get isAccessExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 45)));
}

/// Persists auth tokens.
///
/// Uses SharedPreferences as the source of truth. Several Android devices
/// (KeyStore code 7) break flutter_secure_storage; that caused "no access
/// token" after successful login/refresh.
///
/// Access and refresh tokens are sealed with [TokenVault] (Keystore /
/// Keychain key) before they are written; devices where the vault fails keep
/// plain values as before. Plain values from older builds are sealed the
/// first time they are read.
class TokenStore {
  TokenStore({Map<String, String>? memory}) : _memory = memory;

  final Map<String, String>? _memory;

  bool get _useVault => _memory == null && TokenVault.available;
  static bool _migrationTried = false;

  Future<String?> _readSecret(String key) async {
    final raw = await _read(key);
    if (raw == null || raw.isEmpty) return raw;
    if (!TokenVault.isSealed(raw)) return raw;
    final plain = await TokenVault.open(raw);
    if (plain == null) {
      debugPrint('[TokenStore] sealed $key could not be opened on this device');
    }
    return plain;
  }

  Future<void> _writeSecret(String key, String value) async {
    if (_useVault) {
      final sealed = await TokenVault.seal(value);
      if (sealed != null) {
        await _write(key, sealed);
        return;
      }
    }
    await _write(key, value);
  }

  Future<void> _migratePlainOnce(String access, String refresh) async {
    if (_migrationTried || !_useVault) return;
    final rawAccess = await _read(_kAccess);
    final rawRefresh = await _read(_kRefresh);
    if (rawAccess == null || rawRefresh == null) return;
    if (TokenVault.isSealed(rawAccess) && TokenVault.isSealed(rawRefresh)) return;
    _migrationTried = true;
    await _writeSecret(_kAccess, access);
    await _writeSecret(_kRefresh, refresh);
    final sealedNow = TokenVault.isSealed(await _read(_kAccess) ?? '');
    debugPrint('[TokenStore] migrated plain tokens sealed=$sealedNow');
  }

  static const _kAccess = 'app_access_token';
  static const _kRefresh = 'app_refresh_token';
  static const _kExpires = 'app_expires_at';
  static const _kSession = 'app_session_id';
  static const _kDevice = 'app_device_id';

  Future<String?> _read(String key) async {
    if (_memory != null) return _memory[key];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    if (_memory != null) {
      _memory[key] = value;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _delete(String key) async {
    if (_memory != null) {
      _memory.remove(key);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<AuthTokens?> read() async {
    final access = await _readSecret(_kAccess);
    final refresh = await _readSecret(_kRefresh);
    final expiresRaw = await _read(_kExpires);
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty ||
        expiresRaw == null) {
      if (DiagConfig.legacyBackend) debugPrint(
        '[TokenStore] read miss access=${access != null} refresh=${refresh != null} expires=${expiresRaw != null}',
      );
      return null;
    }
    final expiresMs = int.tryParse(expiresRaw);
    if (expiresMs == null) return null;
    final sessionId = await _read(_kSession);
    await _migratePlainOnce(access, refresh);
    // Success path is silent — polling /me or challenges would spam every few
    // seconds. Miss / save / clear still log.
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresMs),
      sessionId: sessionId,
    );
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int expiresInSec,
    String? sessionId,
  }) async {
    final expiresAt =
        DateTime.now().add(Duration(seconds: expiresInSec.clamp(60, 86400)));
    await _writeSecret(_kAccess, accessToken);
    await _writeSecret(_kRefresh, refreshToken);
    await _write(_kExpires, expiresAt.millisecondsSinceEpoch.toString());
    if (sessionId != null) {
      await _write(_kSession, sessionId);
    }
    // Verify write immediately (catches prefs failures early).
    final verify = await read();
    if (verify == null || verify.accessToken != accessToken) {
      debugPrint('[TokenStore] WARNING: save verify failed');
    }
    if (_memory == null) {
      final sealed = TokenVault.isSealed(await _read(_kAccess) ?? '');
      debugPrint('[TokenStore] saved tokens sealed=$sealed');
    }
    // Success path silent — auth + every API auth header would otherwise spam.
  }

  Future<void> clear() async {
    await Future.wait([
      _delete(_kAccess),
      _delete(_kRefresh),
      _delete(_kExpires),
      _delete(_kSession),
    ]);
    debugPrint('[TokenStore] cleared auth tokens');
  }

  Future<String?> readDeviceId() => _read(_kDevice);

  Future<void> saveDeviceId(String id) => _write(_kDevice, id);

  Future<void> clearDeviceId() => _delete(_kDevice);
}
