import 'package:flutter/services.dart';

/// When the remote was last pressed. Background work that would compete
/// with scrolling (hero auto-slide, catalog prefetch) waits until the user
/// has paused (TCL scroll lag, 16 Oct).
abstract final class TvInputActivity {
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _on = false;

  static void ensureStarted() {
    if (_on) return;
    _on = true;
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent || e is KeyRepeatEvent) _last = DateTime.now();
      return false;
    });
  }

  static Duration get sinceLastKey => DateTime.now().difference(_last);

  static bool idleFor(Duration d) => sinceLastKey >= d;
}
