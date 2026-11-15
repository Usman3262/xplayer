import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:shared_preferences/shared_preferences.dart';

enum AdultPinResult { ok, wrong, locked }

/// The 18+ lock. Where the PIN comes from:
/// * Stalker / MAG portals: the account's parental password from the panel
///   (`parent_password`), exactly as a MAG box does;
/// * Xtream / M3U: the Xtream API doesn't share the panel's PIN, so the user
///   sets an XPlayer adult PIN once (stored only as a salted SHA-256).
/// 5 wrong tries ⇒ locked for a minute. An unlock lasts [unlockFor] or
/// until [lock] (the app calls it when going to the background).
class AdultPinLock {
  AdultPinLock({DateTime Function()? clock, this.unlockFor = const Duration(minutes: 30), this.maxTries = 5})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration unlockFor;
  final int maxTries;

  static const _hashKey = 'xp.adult_pin.hash';
  static const _saltKey = 'xp.adult_pin.salt';

  DateTime? _unlockedUntil;
  int _wrong = 0;
  DateTime? _lockedUntil;

  bool get isUnlocked => _unlockedUntil != null && _clock().isBefore(_unlockedUntil!);

  void lock() => _unlockedUntil = null;

  /// An XPlayer PIN exists (Xtream / M3U case).
  Future<bool> hasAppPin() async => (await SharedPreferences.getInstance()).getString(_hashKey) != null;

  Future<void> setAppPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final r = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(salt, pin));
    _unlock();
  }

  /// Checks [pin] against the panel PIN when there is one, else the app PIN.
  Future<AdultPinResult> verify(String pin, {String? panelPin}) async {
    final now = _clock();
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) return AdultPinResult.locked;
    bool ok;
    if (panelPin != null) {
      ok = pin == panelPin;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final salt = prefs.getString(_saltKey), hash = prefs.getString(_hashKey);
      ok = salt != null && hash != null && _hash(salt, pin) == hash;
    }
    if (ok) {
      _wrong = 0;
      _lockedUntil = null;
      _unlock();
      return AdultPinResult.ok;
    }
    _wrong++;
    if (_wrong >= maxTries) {
      _wrong = 0;
      _lockedUntil = now.add(const Duration(minutes: 1));
      return AdultPinResult.locked;
    }
    return AdultPinResult.wrong;
  }

  /// Forget the XPlayer PIN (device sign-out).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    lock();
  }

  void _unlock() => _unlockedUntil = _clock().add(unlockFor);

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('xplayer-adult:$salt:$pin')).toString();
}
