import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'app_mpv_playback.dart';

/// Stream quality sent with each playback heartbeat (client 23 Oct: bitrate,
/// buffering and dropped frames in the Control Panel). Counts are since the
/// current playback started; a new lease calls [reset].
///
/// Buffering comes from the player's own buffering flag (no native call).
/// Bitrate and dropped frames are read from mpv only through [appMpvGet],
/// which returns nothing while mpv is busy (18 Oct ANR), so a heartbeat never
/// blocks the main thread. The native engine reports size and buffering only.
class PlaybackStatsCollector {
  PlaybackStatsCollector({DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  Player? _mpv;
  StreamSubscription<bool>? _mpvBuffering;
  bool _native = false;
  int? _nativeWidth;
  int? _nativeHeight;

  bool _started = false;
  int _bufferingCount = 0;
  int _bufferingMs = 0;
  DateTime? _bufferingSince;

  /// New playback (new lease): counts start from zero.
  void reset() {
    _started = false;
    _bufferingCount = 0;
    _bufferingMs = 0;
    _bufferingSince = null;
  }

  /// The mpv (media_kit) player now on screen.
  void attachMpv(Player player) {
    detach();
    _mpv = player;
    _mpvBuffering = player.stream.buffering.listen(
      (b) => reportBuffering(b, playing: (player.state.width ?? 0) > 0),
    );
  }

  /// The native engine is on screen; it reports through [reportBuffering]
  /// and [reportNativeSize] from its own listener.
  void attachNative() {
    detach();
    _native = true;
  }

  void reportNativeSize(int width, int height) {
    _nativeWidth = width > 0 ? width : null;
    _nativeHeight = height > 0 ? height : null;
  }

  /// Player buffering flag. The first load is not counted: only buffering
  /// after the picture has played once ([playing]).
  void reportBuffering(bool buffering, {required bool playing}) {
    if (buffering) {
      if (_started && _bufferingSince == null) {
        _bufferingCount++;
        _bufferingSince = _now();
      }
    } else {
      final since = _bufferingSince;
      if (since != null) {
        _bufferingMs += _now().difference(since).inMilliseconds;
        _bufferingSince = null;
      }
      if (playing) _started = true;
    }
  }

  /// The player was closed (retry, engine switch, leaving); counts are kept
  /// until [reset].
  void detach() {
    unawaited(_mpvBuffering?.cancel());
    _mpvBuffering = null;
    _mpv = null;
    _native = false;
    _nativeWidth = null;
    _nativeHeight = null;
    final since = _bufferingSince;
    if (since != null) {
      _bufferingMs += _now().difference(since).inMilliseconds;
      _bufferingSince = null;
    }
  }

  /// Body for the heartbeat `stats` field, or null when no player is attached.
  Future<Map<String, Object?>?> snapshot() async {
    final mpv = _mpv;
    if (mpv == null && !_native) return null;
    final since = _bufferingSince;
    final bufferingMs = _bufferingMs +
        (since == null ? 0 : _now().difference(since).inMilliseconds);
    final out = <String, Object?>{
      'engine': mpv != null ? 'mpv' : 'native',
      'bufferingCount': _bufferingCount,
      'bufferingMs': bufferingMs,
    };
    if (mpv != null) {
      final w = mpv.state.width ?? 0;
      final h = mpv.state.height ?? 0;
      if (w > 0 && h > 0) {
        out['width'] = w;
        out['height'] = h;
      }
      final bitrate = double.tryParse(await appMpvGet(mpv, 'video-bitrate'));
      if (bitrate != null && bitrate > 0) {
        out['bitrateKbps'] = (bitrate / 1000).round();
      }
      final vo = int.tryParse(await appMpvGet(mpv, 'frame-drop-count'));
      final dec =
          int.tryParse(await appMpvGet(mpv, 'decoder-frame-drop-count'));
      if (vo != null || dec != null) {
        out['droppedFrames'] = (vo ?? 0) + (dec ?? 0);
      }
    } else {
      if (_nativeWidth != null && _nativeHeight != null) {
        out['width'] = _nativeWidth;
        out['height'] = _nativeHeight;
      }
    }
    return out;
  }
}
