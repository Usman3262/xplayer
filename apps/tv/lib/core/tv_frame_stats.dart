import 'dart:async';
import 'dart:math' as math;

import 'package:data/data.dart' show Diag;
import 'package:flutter/scheduler.dart';

/// UI frame cost (client 16 Oct #01/#03 "freezes", TCL scroll lag).
/// Collects Flutter frame timings; each reader has its own [FrameWindow]
/// so the player's health log and the browse log do not reset each other.
class FrameWindow {
  int _frames = 0;
  int _slow = 0;
  int _maxBuildMs = 0;
  int _maxRasterMs = 0;

  int get slow => _slow;

  void _add(int build, int raster) {
    _frames++;
    if (build > 33 || raster > 33) _slow++;
    _maxBuildMs = math.max(_maxBuildMs, build);
    _maxRasterMs = math.max(_maxRasterMs, raster);
  }

  /// Summary since the last call, then reset.
  String take() {
    final s = 'frames=$_frames slow=$_slow '
        'maxBuildMs=$_maxBuildMs maxRasterMs=$_maxRasterMs';
    _frames = 0;
    _slow = 0;
    _maxBuildMs = 0;
    _maxRasterMs = 0;
    return s;
  }
}

class TvFrameStats {
  TvFrameStats._();
  static final instance = TvFrameStats._();

  bool _on = false;
  final _windows = <FrameWindow>[];

  /// Shared window for the player health log.
  late final FrameWindow player = newWindow();

  FrameWindow newWindow() {
    final w = FrameWindow();
    _windows.add(w);
    return w;
  }

  void ensureStarted() {
    if (_on) return;
    _on = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final b = t.buildDuration.inMilliseconds;
        final r = t.rasterDuration.inMilliseconds;
        for (final w in _windows) {
          w._add(b, r);
        }
      }
    });
  }

  /// Every 10 s, one `UI` line in the app log when frames were slow (so a
  /// TCL log shows where scrolling stutters; quiet when smooth).
  Timer startUiLog(String Function() where) {
    ensureStarted();
    final w = newWindow();
    return Timer.periodic(const Duration(seconds: 10), (_) {
      if (w.slow == 0) {
        w.take();
        return;
      }
      Diag.perf('UI ${w.take()} at=${where()}');
    });
  }

  /// Back-compat for the player: summary of [player] since the last call.
  String take() => player.take();
}
