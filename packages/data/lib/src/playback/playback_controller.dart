import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../diag/diag.dart';
import 'app_mpv_playback.dart';
import 'playback_phase.dart';

/// Owns playback phase + optional PERF degradation watchdog (brief §5.5).
class PlaybackController extends ChangeNotifier {
  PlaybackUiState _ui = const PlaybackUiState();
  PlaybackUiState get ui => _ui;

  String? sessionId;
  DateTime? tapAt;
  Timer? _watchdog;
  int _degradedSeconds = 0;
  void Function()? onDegraded;

  int msSinceTap() {
    final t = tapAt;
    if (t == null) return 0;
    return DateTime.now().difference(t).inMilliseconds;
  }

  void beginSession(String sid) {
    sessionId = sid;
    tapAt = DateTime.now();
    _set(const PlaybackUiState(phase: PlaybackPhase.resolvingLease));
  }

  void setPhase(PlaybackPhase phase, {String? error, bool? retryable}) {
    _set(
      _ui.copyWith(
        phase: phase,
        errorMessage: error,
        clearError: error == null && phase != PlaybackPhase.error,
        retryable: retryable,
      ),
    );
  }

  void setLeaseAtRisk(bool v) {
    _set(_ui.copyWith(leaseAtRisk: v));
  }

  void setError(String message, {bool conflict = false, bool retryable = true}) {
    _set(
      PlaybackUiState(
        phase: conflict ? PlaybackPhase.conflict : PlaybackPhase.error,
        errorMessage: message,
        retryable: retryable,
      ),
    );
  }

  void startWatchdog(Player player) {
    _watchdog?.cancel();
    _degradedSeconds = 0;
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tickWatchdog(player));
    });
  }

  void stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _tickWatchdog(Player player) async {
    try {
      final src = double.tryParse(await appMpvGet(player, 'container-fps'));
      final dropDec =
          double.tryParse(await appMpvGet(player, 'decoder-frame-drop-count'));
      final dropVo =
          double.tryParse(await appMpvGet(player, 'frame-drop-count'));
      if (src == null || src <= 0) return;
      // Approximate drop rate using cumulative counters delta is hard without
      // prior sample; use vf-fps vs src as primary signal.
      final fps = double.tryParse(await appMpvGet(player, 'estimated-vf-fps'));
      if (fps == null || fps <= 0) return;
      final ratio = fps / src;
      if (ratio < 0.9) {
        _degradedSeconds += 2;
      } else {
        _degradedSeconds = 0;
      }
      if (_degradedSeconds >= 5) {
        Diag.perf(
          's=${sessionId ?? '?'} degraded fps=$fps srcFps=$src '
          'dropDec=${dropDec ?? '?'} dropVo=${dropVo ?? '?'}',
        );
        onDegraded?.call();
        _degradedSeconds = 0;
      }
    } catch (_) {}
  }

  void _set(PlaybackUiState next) {
    _ui = next;
    final sid = sessionId;
    if (sid != null) {
      next.logTransition(sid, msSinceTap());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stopWatchdog();
    super.dispose();
  }
}
