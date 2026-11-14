import 'dart:async';

/// Provider lines allow one connection. Before any online playback (fullscreen
/// or Live preview) opens a stream, the active download must close its
/// connection. The download manager registers [onBeforePlayback]; the players
/// await [beforePlayback]. Bounded so playback never hangs on it.
///
/// Client 18 Oct #2: players also call [afterPlayback] when they close, so a
/// download paused for playback continues by itself (it used to stay paused,
/// and the queue stayed blocked, until the user pressed Resume).
abstract final class PlaybackArbiter {
  /// Returns the title of the download it paused, or null.
  static Future<String?> Function()? onBeforePlayback;
  static void Function()? onAfterPlayback;

  static Future<String?> beforePlayback() async {
    final hook = onBeforePlayback;
    if (hook == null) return null;
    try {
      return await hook().timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  static void afterPlayback() {
    try {
      onAfterPlayback?.call();
    } catch (_) {}
  }
}
