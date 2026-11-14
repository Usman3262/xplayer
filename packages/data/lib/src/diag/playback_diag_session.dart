import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../playback/app_mpv_playback.dart' show appMpvGet, appMpvSafeToQuery;
import 'diag.dart';
import 'network_diag.dart';

/// Per-open playback session logging: `[PB]` lifecycle + `[PERF]` samples.
class PlaybackDiagSession {
  PlaybackDiagSession() : sid = Diag.newSessionId();

  final String sid;
  final DateTime tapAt = DateTime.now();
  Timer? _perfTimer;
  Timer? _memTimer;
  Timer? _netTimer;
  bool _wasBuffering = false;
  DateTime? _rebufferStarted;
  int heartbeatConsecutiveFails = 0;

  int msSinceTap() => DateTime.now().difference(tapAt).inMilliseconds;

  void pb(String message) => Diag.pb('s=$sid $message');

  void state(String name) => pb('state $name +${msSinceTap()}');

  void startPerf(Player player) {
    stopPerf();
    unawaited(
      logNetworkDiagnostics(context: 'playback_playing', sessionId: sid),
    );
    _perfTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_samplePerf(player));
    });
    _memTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sampleMem();
    });
    _netTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(
        logNetworkDiagnostics(context: 'playback_tick', sessionId: sid),
      );
    });
    unawaited(_samplePerf(player));
    _sampleMem();
  }

  void stopPerf() {
    _perfTimer?.cancel();
    _perfTimer = null;
    _memTimer?.cancel();
    _memTimer = null;
    _netTimer?.cancel();
    _netTimer = null;
  }

  void onBuffering(bool buffering) {
    if (buffering && !_wasBuffering) {
      _rebufferStarted = DateTime.now();
      pb(
        'rebuffer start pos=? cacheSec=? +${msSinceTap()}',
      );
    } else if (!buffering && _wasBuffering && _rebufferStarted != null) {
      final dur =
          DateTime.now().difference(_rebufferStarted!).inMilliseconds;
      pb('rebuffer end dur=${dur}ms +${msSinceTap()}');
      _rebufferStarted = null;
    }
    _wasBuffering = buffering;
  }

  void heartbeatOk({required int nextSec}) {
    heartbeatConsecutiveFails = 0;
    pb('heartbeat ok next=${nextSec}s');
  }

  void heartbeatFail(Object err) {
    heartbeatConsecutiveFails++;
    pb(
      'heartbeat FAIL err=$err consecutive=$heartbeatConsecutiveFails',
    );
  }

  Future<void> _samplePerf(Player player) async {
    if (!DiagConfig.isOn) return;
    // Native reads block the main thread while mpv is busy (18 Oct ANR).
    if (!appMpvSafeToQuery(player)) return;
    try {
      final platform = player.platform;
      // Guarded, timed reads (Play Console ANR 6.0.33).
      Future<String> g(String key) async =>
          platform == null ? '?' : appMpvGet(player, key);

      final pos = player.state.position.inSeconds;
      final hwdec = await g('hwdec-current');
      final codec = await g('video-codec');
      final w = await g('video-params/w');
      final h = await g('video-params/h');
      final srcFps = await g('container-fps');
      final fps = await g('estimated-vf-fps');
      final dropDec = await g('decoder-frame-drop-count');
      final dropVo = await g('frame-drop-count');
      final cacheSec = await g('demuxer-cache-duration');
      final cacheSpeed = await g('cache-speed');
      final pausedForCache = await g('paused-for-cache');
      final vBitrate = await g('video-bitrate');
      final bufferingPct = player.state.bufferingPercentage;
      final demuxerState = await g('demuxer-cache-state');
      final networkSpeed = await g('network-speed');
      final eof = await g('eof-reached');

      Diag.perf(
        's=$sid pos=${pos}s hwdec=$hwdec codec=$codec '
        'res=${w}x$h srcFps=$srcFps fps=$fps '
        'dropDec=$dropDec dropVo=$dropVo '
        'cacheSec=$cacheSec cacheSpeed=$cacheSpeed '
        'demuxerState=$demuxerState networkSpeed=$networkSpeed eof=$eof '
        'pausedForCache=$pausedForCache vBitrate=$vBitrate '
        'bufferingPct=$bufferingPct',
      );
    } catch (e, st) {
      Diag.err('PERF sample failed', e, st);
    }
  }

  void _sampleMem() {
    if (!DiagConfig.isOn) return;
    try {
      final rss = ProcessInfo.currentRss;
      Diag.perf('s=$sid mem rssBytes=$rss');
    } catch (_) {
      // ProcessInfo may be unavailable on some platforms.
    }
  }
}
