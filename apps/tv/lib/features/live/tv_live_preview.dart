import 'dart:async';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../core/screen_awake.dart';

/// Live preview in the Live TV / Sports preview window (client 16 Oct #12).
///
/// One provider connection: the preview is a normal backend lease + the
/// Android player, so the one-active-connection rule still applies across
/// devices (another device playing -> CONFLICT -> the static image stays).
/// Rules:
/// - a stream opens only after focus rests on a channel for [settle]; moving
///   through the list opens nothing;
/// - the newest selection wins (generation counter); a slower older open is
///   closed as soon as it finishes;
/// - [release] closes the player first (frees the provider connection) and
///   is awaited before fullscreen playback starts; it is also tracked by
///   [PlayerLifecycleGate] so the player's lease waits for it.
class TvLivePreviewController extends ChangeNotifier {
  TvLivePreviewController({
    required this.auth,
    required this.media,
    this.profileId,
    this.settle = const Duration(milliseconds: 1200),
  });

  final AppAuthRepository auth;
  final AppMediaRepository media;
  final String? profileId;
  final Duration settle;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Android TV) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  VideoPlayerController? _controller;
  LeaseManager? _lease;
  Timer? _timer;

  /// Closes a preview nobody is browsing. The preview holds the account's
  /// one stream (provider 1/1); a TV left on Live TV blocked every phone in
  /// the home with "another device is playing" (19 Oct, live server).
  Timer? _idle;
  static const idleStop = Duration(seconds: 90);
  int _gen = 0;
  bool _enabled = true;
  bool _disposed = false;
  String? _selectedId;
  String? _settledId;
  String? _playingId;
  Future<void>? _releasing;

  /// The player showing [channelId], or null (show the static image).
  VideoPlayerController? controllerFor(String? channelId) {
    final c = _controller;
    if (c == null || channelId == null || _playingId != channelId) return null;
    return c.value.isInitialized ? c : null;
  }

  bool get loading =>
      !TvPlatformProfile.lowPowerUi &&
      _selectedId != null &&
      _playingId != _selectedId;

  /// Channel focus has rested on (after [settle]); the guide loads for it
  /// only, not for every channel scrolled past.
  String? get settledId => _settledId;

  /// Focus moved to [channel] (null = nothing focused).
  void select(MediaItem? channel) {
    if (_disposed) return;
    final id = channel?.id;
    if (id == _selectedId) return;
    _selectedId = id;
    _settledId = null;
    _timer?.cancel();
    _idle?.cancel();
    if (channel == null) return;
    _timer = Timer(settle, () {
      _settledId = channel.id;
      if (!_disposed) notifyListeners();
      // Slow TVs: no stream on focus; the channel plays on OK only.
      if (_enabled && !TvPlatformProfile.lowPowerUi) unawaited(_open(channel));
    });
    notifyListeners();
  }

  /// Screen hidden / app paused: close and stop opening until [resume].
  void suspend() {
    _enabled = false;
    _timer?.cancel();
    _idle?.cancel();
    unawaited(release());
  }

  void resume(MediaItem? current) {
    if (_disposed) return;
    _enabled = true;
    final keep = current;
    _selectedId = null;
    select(keep);
  }

  /// Closes the preview player (provider connection), then its lease.
  Future<void> release() {
    _gen++;
    _timer?.cancel();
    final existing = _releasing;
    if (existing != null) return existing;
    final c = _controller;
    final lease = _lease;
    _controller = null;
    _lease = null;
    _playingId = null;
    ScreenAwake.release(this);
    if (c == null && lease == null) return Future.value();
    if (!_disposed) notifyListeners();
    final close = () async {
      try {
        await c?.dispose().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }();
    PlayerLifecycleGate.track(close);
    final done = () async {
      await close;
      Diag.pb('PREVIEW release');
      // The provider connection is closed; the server-side stop can finish
      // in the background. Waiting for it delayed fullscreen play by up to
      // 5 s (19 Oct, 5.2 s on the live server). Safe: the server only
      // deletes a lease whose playbackId and deviceId both match, so a late
      // stop cannot end the fullscreen lease that follows.
      if (lease != null) {
        unawaited(() async {
          try {
            await lease.stop().timeout(const Duration(seconds: 8));
          } catch (_) {}
          lease.dispose();
        }());
      }
    }();
    final tracked = done.whenComplete(() => _releasing = null);
    _releasing = tracked;
    return tracked;
  }

  Future<void> _open(MediaItem channel) async {
    await release();
    if (_disposed || !_enabled || _selectedId != channel.id) return;
    final gen = ++_gen;
    bool current() =>
        !_disposed && _enabled && gen == _gen && _selectedId == channel.id;
    // The fullscreen player (or an older preview) must have closed its
    // provider connection first.
    await PlayerLifecycleGate.settle(const Duration(seconds: 6));
    if (!current()) return;
    await PlaybackArbiter.beforePlayback();
    if (!current()) return;
    final t0 = DateTime.now();
    LeaseManager? lease;
    VideoPlayerController? c;
    try {
      final deviceId = await auth.ensurePlaybackDeviceId(
        name: TvPlatformProfile.deviceName,
        platform: TvPlatformProfile.backendPlatform,
      );
      if (!current()) return;
      lease = LeaseManager(media: media, deviceId: deviceId);
      final session = await lease
          .start(contentType: 'live', streamId: channel.id, profileId: profileId)
          .timeout(const Duration(seconds: 20));
      if (!current()) {
        await lease.stop();
        lease.dispose();
        return;
      }
      c = VideoPlayerController.networkUrl(
        Uri.parse(session.playUrl),
        httpHeaders: _headers,
      );
      _controller = c;
      _lease = lease;
      await c.initialize().timeout(const Duration(seconds: 20));
      if (!current()) {
        if (identical(_controller, c)) unawaited(release());
        return;
      }
      await c.setVolume(0);
      await c.play();
      _playingId = channel.id;
      // A playing preview keeps the TV awake too (until idle stop / release).
      ScreenAwake.acquire(this);
      _idle?.cancel();
      _idle = Timer(idleStop, () {
        if (_disposed || _playingId != channel.id) return;
        Diag.pb('PREVIEW idle stop after ${idleStop.inSeconds}s');
        unawaited(release());
      });
      Diag.pb(
        'PREVIEW playing ms=${DateTime.now().difference(t0).inMilliseconds} '
        'size=${c.value.size.width.round()}x${c.value.size.height.round()}',
      );
      notifyListeners();
    } catch (e) {
      // Busy line, other device playing, or a dead channel: keep the image.
      Diag.pb('PREVIEW unavailable ${e.runtimeType}');
      if (identical(_controller, c) || _controller == null) {
        _controller = c;
        _lease = lease;
        unawaited(release());
      } else {
        try {
          await lease?.stop();
        } catch (_) {}
        lease?.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _idle?.cancel();
    unawaited(release());
    PlaybackArbiter.afterPlayback();
    super.dispose();
  }
}
