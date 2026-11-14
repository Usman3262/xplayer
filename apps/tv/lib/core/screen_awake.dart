import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device awake while anything plays.
///
/// Counted holders (survives route replacement). Re-asserts every minute and
/// via [ensure] on resume. Also sets the native keep-screen-on flag (TCL / some
/// phones ignore wakelock alone after ~10 minutes).
class ScreenAwake {
  ScreenAwake._();

  static const _native = MethodChannel('app/screen_secure');
  static final Set<Object> _holders = <Object>{};
  static Timer? _guard;

  static int get holders => _holders.length;

  static void acquire(Object holder) {
    final wasEmpty = _holders.isEmpty;
    _holders.add(holder);
    if (!wasEmpty) {
      _apply(true);
      return;
    }
    _apply(true);
    _guard?.cancel();
    _guard = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_holders.isNotEmpty) _apply(true);
    });
  }

  static void release(Object holder) {
    if (!_holders.remove(holder)) return;
    if (_holders.isNotEmpty) return;
    _guard?.cancel();
    _guard = null;
    _apply(false);
  }

  /// Re-applies the lock now if anything still plays (app resumed: the OS
  /// may have dropped it while in the background).
  static void ensure() {
    if (_holders.isNotEmpty) _apply(true);
  }

  /// Test hook: records enable/disable instead of calling the plugin.
  @visibleForTesting
  static void Function(bool on)? applyOverride;

  @visibleForTesting
  static void resetForTest() {
    _holders.clear();
    _guard?.cancel();
    _guard = null;
  }

  static void _apply(bool on) {
    final o = applyOverride;
    if (o != null) {
      o(on);
      return;
    }
    final f = on ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(f.catchError((Object e) {
      debugPrint('[ScreenAwake] ${on ? 'enable' : 'disable'} failed: $e');
    }));
    unawaited(() async {
      try {
        await _native.invokeMethod<void>('setKeepScreenOn', {'enabled': on});
      } catch (_) {}
    }());
  }
}
