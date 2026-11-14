import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_decoder_health.dart';
import 'decoder_mode.dart';
export 'app_decoder_health.dart';
export 'surface_frame_gate.dart';

import '../device/device_capabilities.dart';
import '../device/device_capabilities_store.dart';
import '../diag/diag.dart';

/// Shared media_kit / libmpv settings for the app (mobile + TV).
/// Tier-based buffer sizes (brief §7). Falls back to MID before caps load.
PlayerConfiguration appPlayerConfiguration({TierMpvConfig? tier}) {
  final cfg = tier ?? DeviceCapabilitiesStore.instance.mpv;
  return PlayerConfiguration(
    bufferSize: cfg.bufferSizeBytes,
    logLevel: MPVLogLevel.warn,
  );
}

/// Apply after [Player] is constructed, before or right after [Player.open].
Future<void> applyAppMpvTuning(
  Player player, {
  TierMpvConfig? tier,
  String? sessionId,
  int? resumeStartSec,
  AppDecoderMode decoderMode = AppDecoderMode.auto,
  /// When true, keep mobile's A/V lock and add cheaper TV-safe GPU paths
  /// (bilinear scale, no interpolation). Do not diverge on latency-hacks or
  /// audio-buffer — those made picture lag behind sound on living-room boxes.
  bool forTv = false,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  final native = player.platform;
  if (native == null) return;
  final cfg = tier ?? DeviceCapabilitiesStore.instance.mpv;
  Future<void> set(String key, String value) async {
    try {
      await (native as dynamic).setProperty(key, value)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // An unsupported optional property must not skip all remaining tuning.
      // Do not log exception strings: native errors may contain source URLs.
      Diag.pb('mpv option unavailable: $key');
    }
  }
  // Faster start on phones (17 Oct, client asked): the provider's server is
  // slow to send the first bytes, so every byte read before the first frame
  // costs seconds.
  // - Identify the file from ~1 MB instead of lavf's 5 MB / 5 s probe
  //   (MKV/MP4 headers already list the tracks).
  // - Open a resume point at the nearest keyframe instead of decoding up to
  //   the exact second (that downloaded up to several seconds of 4K first).
  //   The player screen turns exact seeking back on after the first frame.
  Future<void> fastStart() async {
    await set('demuxer-lavf-probesize', '1000000');
    await set('demuxer-lavf-analyzeduration', '1');
    // A resume opens at the exact second (client 12 Nov: the 1-2 s before
    // the saved point played again, then it jumped back). A start from the
    // beginning keeps the cheaper keyframe seek.
    final resume = resumeStartSec != null && resumeStartSec > 5;
    await set('hr-seek', resume ? 'yes' : 'no');
  }
  if (Platform.isIOS) {
    // iPhone (17 Oct logs): this tuning used to be Android-only, so iOS ran
    // on media_kit defaults: 'cache-on-disk=yes' fails in the iOS sandbox
    // ("Failed to create file cache"), no stream reconnect, a 5 s network
    // timeout. A provider connection that stalled held the first frame for
    // 15-28 s, and 4K rebuffered every few seconds. Memory cache, read-ahead
    // and reconnect as on Android; the decoder stays VideoToolbox (mpv's own
    // choice there, already hardware).
    try {
      await set('cache', 'yes');
      await set('cache-on-disk', 'no');
      await set('demuxer-max-bytes', '${cfg.demuxerMaxBytes}');
      await set('demuxer-max-back-bytes', '${cfg.demuxerMaxBackBytes}');
      await set('demuxer-readahead-secs', '${cfg.demuxerReadaheadSecs}');
      await set('cache-secs', '${cfg.cacheSecs}');
      // Resume after a stall only with a few seconds in hand: fewer, shorter
      // stops on a connection slower than the 4K bitrate. (Lowered to 1.5 s
      // on 17 Oct for a faster restart; restored: the client saw more
      // interruptions and asked for the cause to be fixed, not the threshold.)
      await set('cache-pause-wait', '3');
      await set('network-timeout', '15');
      await fastStart();
      // A stalled read (no bytes for 8 s) reconnects at the same offset
      // instead of waiting for the server to drop the connection.
      await set(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
            'reconnect_delay_max=2,rw_timeout=8000000',
      );
      final sid = sessionId != null ? 's=$sessionId ' : '';
      Diag.pb('${sid}mpv ios tuning cache=memory fastStart=on '
          'demuxerMax=${cfg.demuxerMaxBytes ~/ (1024 * 1024)}MiB '
          'readahead=${cfg.demuxerReadaheadSecs}s reconnect=on');
    } catch (e, st) {
      Diag.err('mpv ios tuning skipped', e, st);
    }
    return;
  }
  try {
    await set('hwdec', decoderMode.mpvValue);
    // Probe the actual stream. A failed 4K capability probe must not blacklist
    // all HEVC, including supported 1080p profiles. mpv owns native fallback.
    await set('hwdec-codecs', cfg.hwdecCodecs ?? 'all');
    await set('cache-pause-wait', '1');
    // Keep video locked to the audio clock so the picture cannot drift behind
    // while sound stays smooth (common on under-powered Android TV SoCs).
    await set('video-sync', 'audio');
    await set('demuxer-readahead-secs', '${cfg.demuxerReadaheadSecs}');
    await set('cache-secs', '${cfg.cacheSecs}');
    await set('demuxer-max-bytes', '${cfg.demuxerMaxBytes}');
    await set('demuxer-max-back-bytes', '${cfg.demuxerMaxBackBytes}');
    // Same as mobile: Android presentation path needs these for A/V lock.
    await set('video-latency-hacks', 'yes');
    // Drop late frames so the picture stays with audio instead of dragging.
    await set('framedrop', forTv ? 'decoder+vo' : 'vo');
    if (forTv) {
      await set('interpolation', 'no');
      await set('video-timing-offset', '0');
      await set('scale', 'bilinear');
      await set('cscale', 'bilinear');
      await set('dscale', 'bilinear');
    }
    await set('network-timeout', '15');
    // HTTP reconnect (brief §3.5). Unsupported keys are ignored by mpv.
    await set(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
    );
    if (cfg.vdLavcThreads != null) {
      await set('vd-lavc-threads', '${cfg.vdLavcThreads}');
    }
    if (!forTv) await fastStart();
    await set('sub-visibility', 'yes');
    await set('sub-auto', 'fuzzy');
    final sid = sessionId != null ? 's=$sessionId ' : '';
    final start = resumeStartSec != null ? ' start=$resumeStartSec' : '';
    final codecs = cfg.hwdecCodecs != null
        ? ' hwdec-codecs=${cfg.hwdecCodecs}'
        : '';
    final configLine = cfg.pbLine.replaceFirst(
      'hwdec=${cfg.hwdec}', 'hwdec=${decoderMode.mpvValue}');
    Diag.pb('$sid$configLine$codecs$start '
        'decoderMode=${decoderMode.key} requestedHwdec=${decoderMode.mpvValue} '
        'requestedVo=${decoderMode.videoOutputFor(android: true) ?? 'default'}');
  } catch (e, st) {
    Diag.err('mpv tuning skipped', e, st);
  }
}

/// Prefetch a short demuxer window before audible playback.
/// Uses mpv `demuxer-cache-duration` (not only media_kit [PlayerState.buffer],
/// which can disagree with progressive MKV). Exits early once a video frame
/// exists and either ~[minDemuxerCache] is buffered or a soft deadline hits.
Future<void> waitForAppPlaybackBuffer(
  Player player, {
  Duration minDemuxerCache = const Duration(seconds: 3),
  bool requireVideoFrame = true,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  // Soft: once we have a frame, do not wait forever for 3s of cache on
  // progressive MKVs that report cacheSec≈0 until play starts.
  final softDeadline = DateTime.now().add(
    Duration(milliseconds: (timeout.inMilliseconds * 0.55).round()),
  );
  var sawVideo = !requireVideoFrame;
  final minSec = minDemuxerCache.inMilliseconds / 1000.0;

  while (DateTime.now().isBefore(deadline)) {
    if ((player.state.width ?? 0) > 0) sawVideo = true;

    var cacheSec = 0.0;
    final raw = await appMpvGet(player, 'demuxer-cache-duration');
    cacheSec = double.tryParse(raw) ?? 0.0;
    if (cacheSec <= 0) {
      final buf = player.state.buffer;
      cacheSec = buf.inMilliseconds / 1000.0;
    }

    if (sawVideo && cacheSec >= minSec) return;
    if (sawVideo && DateTime.now().isAfter(softDeadline) && cacheSec >= 0.2) {
      return;
    }
    if (sawVideo && DateTime.now().isAfter(softDeadline)) {
      // Frame ready but cache still empty (common on progressive 4K MKV).
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// First-frame / ready wait without a fixed 2s delay.
/// Checks current [Player.state] first (streams often already emitted during
/// bufferGate, so [Stream.firstWhere] would wait for the *next* event).
Future<void> waitUntilAppFirstFrame(
  Player player, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  bool ready() {
    final w = player.state.width ?? 0;
    return w > 0 ||
        player.state.playing ||
        player.state.duration > Duration.zero;
  }

  if (ready()) return;

  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// iOS tears down the VideoToolbox session while the app is in the
/// background ("invalid session -12903"); mpv then falls back to software
/// decoding, which cannot keep up with 1080p/4K. Toggling hwdec makes mpv
/// open a fresh hardware session in the foreground.
Future<void> resetAppHardwareDecoder(Player player, String hwdec) async {
  // Non-blocking and in order (Play Console ANRs 6.0.23 / 6.0.32 / 6.0.33:
  // a blocking write waited on a stuck decoder on the main thread).
  await appMpvSet(player, 'hwdec', 'no');
  await appMpvSet(player, 'hwdec', hwdec);
}

/// One line comparing the server's download speed with what the file needs
/// ("NET speed=6.1Mbit/s need=18.4Mbit/s cache=2.3s"). A speed below the
/// need means the source cannot keep up and pauses are unavoidable at that
/// quality; a speed above it with pauses points at the app or the device.
Future<String> appNetworkLine(Player player) async {
  final speed = double.tryParse(await appMpvGet(player, 'cache-speed'));
  final video = double.tryParse(await appMpvGet(player, 'video-bitrate'));
  final audio = double.tryParse(await appMpvGet(player, 'audio-bitrate'));
  final cache =
      double.tryParse(await appMpvGet(player, 'demuxer-cache-duration'));
  String mbit(double? bitsPerSec) =>
      bitsPerSec == null ? '?' : (bitsPerSec / 1e6).toStringAsFixed(1);
  final need = (video == null && audio == null)
      ? null
      : (video ?? 0) + (audio ?? 0);
  return 'NET speed=${mbit(speed == null ? null : speed * 8)}Mbit/s '
      'need=${mbit(need)}Mbit/s '
      'cache=${cache?.toStringAsFixed(1) ?? '?'}s';
}

/// Set one mpv property; unsupported keys are ignored.
///
/// Play Console ANRs (Honor X9b, 6.0.23 / 6.0.32 / 6.0.33): a property write
/// is a synchronous native call that waits for mpv's core; when the hardware
/// decoder hangs (MediaCodec.dequeueOutputBuffer), the app's main thread
/// waited past Android's 5 s limit ("isn't responding", and the background
/// playback service could not start). The write is now queued with
/// mpv_set_property_async: it returns at once and mpv applies requests in
/// the order sent. The blocking write is only a fallback.
Future<void> appMpvSet(Player player, String key, String value) async {
  final native = player.platform;
  if (native == null) return;
  if (_appMpvSetAsync(native, key, value)) return;
  try {
    await (native as dynamic).setProperty(key, value)
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    Diag.pb('mpv option unavailable: $key');
  }
}

/// Reply ids far above media_kit's own async request counter (it starts at
/// 0), so a reply can never complete one of media_kit's requests.
int _appAsyncReplyId = 1 << 52;

/// Test hook for [_appMpvSetAsync] with a stand-in native player.
@visibleForTesting
bool appMpvSetAsyncForTest(Object native, String key, String value) =>
    _appMpvSetAsync(native, key, value);

/// Queues [key] = [value] on mpv without waiting; false when the native
/// player does not expose libmpv (then the caller writes the blocking way).
bool _appMpvSetAsync(Object native, String key, String value) {
  Pointer<Utf8>? name;
  Pointer<Utf8>? text;
  Pointer<Pointer<Utf8>>? data;
  try {
    final dyn = native as dynamic;
    if (dyn.disposed == true) return true; // nothing to set any more
    final Pointer ctx = dyn.ctx as Pointer;
    if (ctx.address == 0) return false;
    final mpv = dyn.mpv;
    name = key.toNativeUtf8();
    text = value.toNativeUtf8();
    data = calloc<Pointer<Utf8>>()..value = text;
    // MPV_FORMAT_STRING = 1; mpv copies the name and the value before it
    // returns, so they are freed right after.
    final rc = mpv.mpv_set_property_async(
      ctx,
      _appAsyncReplyId++,
      name.cast<Char>(),
      1,
      data.cast<Void>(),
    ) as int;
    return rc >= 0;
  } catch (_) {
    return false;
  } finally {
    if (data != null) calloc.free(data);
    if (text != null) calloc.free(text);
    if (name != null) calloc.free(name);
  }
}

/// Client 18 Oct #10 (ANR "the app isn't responding", reproduced on the
/// phone emulator 18 Oct 16:41): an mpv property read is a synchronous
/// native call on the app's main thread, and it waits for mpv's core. While
/// mpv opens a stream or waits on a slow server, that wait ran past
/// Android's 5 s input limit (trace: main thread in
/// mpv_get_property_string). A Dart timeout cannot interrupt it. Read native
/// properties only while the picture is playing; otherwise callers get '?'
/// and use the values media_kit already streams to the app (player.state).
///
/// Play Console ANR 6.0.33 (Honor X9b): the read still blocked while the
/// player counted as "playing", because the hardware decoder had hung. A
/// read now also needs the picture clock to have moved in the last 1.5 s
/// (a hung decoder stops it), and a read that took over 300 ms switches reads
/// off for 30 s for that player.
bool appMpvSafeToQuery(Player player) {
  if (!player.state.playing ||
      player.state.buffering ||
      (player.state.width ?? 0) <= 0) {
    return false;
  }
  final probe = _appProbes[player] ??= _AppProbe(player.state.position);
  return probe.allows(player.state.position, DateTime.now());
}

/// Per player: when its clock last moved and whether reads are switched off.
final Expando<_AppProbe> _appProbes = Expando<_AppProbe>();

class _AppProbe {
  _AppProbe(this._lastPos);

  Duration _lastPos;
  DateTime? _lastMove; // null until the clock is seen moving
  DateTime? _offUntil;

  static const moveWindow = Duration(milliseconds: 1500);
  static const slowRead = Duration(milliseconds: 300);
  static const offFor = Duration(seconds: 30);

  bool allows(Duration pos, DateTime now) {
    final off = _offUntil;
    if (off != null && now.isBefore(off)) return false;
    if (pos != _lastPos) {
      _lastPos = pos;
      _lastMove = now;
    }
    final moved = _lastMove;
    return moved != null && now.difference(moved) < moveWindow;
  }

  void tookLong(Duration took, DateTime now) {
    if (took > slowRead) _offUntil = now.add(offFor);
  }
}

/// Test hook: the read guard's decision for [pos] at [now] (no player).
@visibleForTesting
class AppReadGuard {
  AppReadGuard(Duration start) : _probe = _AppProbe(start);
  final _AppProbe _probe;
  bool allows(Duration pos, DateTime now) => _probe.allows(pos, now);
  void tookLong(Duration took, DateTime now) => _probe.tookLong(took, now);
}

/// Read mpv property safely.
Future<String> appMpvGet(Player player, String key) async {
  final platform = player.platform;
  if (platform == null) return '?';
  if (!appMpvSafeToQuery(player)) return '?';
  final watch = Stopwatch()..start();
  try {
    final v = await (platform as dynamic)
        .getProperty(key)
        .timeout(const Duration(milliseconds: 500));
    if (v == null) return '?';
    final s = '$v'.trim();
    return s.isEmpty ? '?' : s;
  } catch (_) {
    return '?';
  } finally {
    final took = watch.elapsed;
    if (took > _AppProbe.slowRead) {
      _appProbes[player]?.tookLong(took, DateTime.now());
      Diag.pb('mpv read slow ${took.inMilliseconds}ms key=$key; reads off 30 s');
    }
  }
}

/// Issue one seek, then confirm position instead of retrying while buffering.
Future<bool> seekAppPlayback(
  Player player,
  Duration target, {
  required bool Function() isCurrent,
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (!isCurrent()) return false;
  final watch = Stopwatch()..start();
  await player.seek(target).timeout(timeout);
  return confirmAppPlaybackPosition(
    player,
    target,
    isCurrent: isCurrent,
    timeout: timeout - watch.elapsed,
  );
}

Future<bool> confirmAppPlaybackPosition(
  Player player,
  Duration target, {
  required bool Function() isCurrent,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final watch = Stopwatch()..start();
  Duration? stableSince;
  Duration? firstPosition;
  while (isCurrent() && watch.elapsed < timeout) {
    final offset = (player.state.position - target).inMilliseconds;
    final nearTarget = offset >= -5000 &&
        offset <= watch.elapsed.inMilliseconds + 5000;
    // Native seek() may optimistically publish the target before output has
    // caught up. Require a stable window and advancing playback, not one sample.
    if (nearTarget && !player.state.buffering) {
      stableSince ??= watch.elapsed;
      firstPosition ??= player.state.position;
      final progressed = player.state.position - firstPosition;
      if (watch.elapsed - stableSince >= const Duration(seconds: 2) &&
          (!player.state.playing ||
              progressed >= const Duration(milliseconds: 500)))
        return true;
    } else {
      stableSince = null;
      firstPosition = null;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Opt-in, allowlisted values only: never log stream URLs or authentication.
Future<void> logAppPlaybackDiagnostics(Player player) async {
  final native = player.platform;
  if (native == null) return;
  if (!appMpvSafeToQuery(player)) return;
  final values = <String, String>{};
  for (final key in const [
    'hwdec-current',
    'current-vo',
    'video-codec',
    'video-format',
    'video-params/pixelformat',
    'container-fps',
    'avsync',
    'decoder-frame-drop-count',
    'frame-drop-count',
    'demuxer-cache-duration',
    'paused-for-cache',
  ]) {
    if (!appMpvSafeToQuery(player)) return;
    values[key] = await appMpvGet(player, key);
  }
  debugPrint(
    '[PlaybackDiagnostics] pos=${player.state.position.inSeconds}s '
    'buffering=${player.state.buffering} playing=${player.state.playing} '
    'size=${player.state.width}x${player.state.height} $values',
  );
}

/// Runtime health checks run independently of verbose diagnostics.
Future<AppDecoderSample?> readAppDecoderSample(Player player) async {
  final native = player.platform;
  if (native == null) return null;
  if (!appMpvSafeToQuery(player)) return null;
  try {
    // One guarded read at a time (a stuck decoder stops the rest).
    final values = <String>[
      for (final key in const [
        'hwdec-current',
        'video-codec',
        'frame-drop-count',
        'demuxer-cache-duration',
      ])
        await appMpvGet(player, key),
    ];
    final drops = int.tryParse(values[2]);
    final cache = double.tryParse(values[3]);
    if (drops == null || cache == null) return null;
    return AppDecoderSample(
      width: player.state.width ?? 0,
      height: player.state.height ?? 0,
      hardware: values[0],
      codec: values[1],
      droppedFrames: drops,
      cacheSeconds: cache,
      position: player.state.position,
    );
  } catch (_) {
    // Missing native properties are unknown, not evidence of decoder failure.
    return null;
  }
}

/// Post-start check that video is actually reaching the output, not only that
/// video parameters are known. On Android, media_kit_video completes
/// `waitUntilFirstFrameRendered` when non-zero video params arrive, which
/// happens before a frame is presented. Diagnostic only: it never fails
/// playback, because these properties alone do not prove a black screen.
Future<void> logAppVideoOutputCheck(
  Player player, {
  required String sessionId,
  required Duration positionAtReady,
  required bool Function() isCurrent,
}) async {
  final fields = <String, String>{};
  for (final key in const [
    'vo-configured',
    'current-vo',
    'hwdec-current',
    'estimated-vf-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
  ]) {
    if (!isCurrent()) return;
    fields[key] = await appMpvGet(player, key);
  }
  if (!isCurrent()) return;
  final advanced = player.state.position - positionAtReady;
  final audioOnlySuspect = player.state.playing &&
      advanced >= const Duration(seconds: 2) &&
      (fields['vo-configured'] == 'no' || fields['current-vo'] == 'null');
  Diag.pb('s=$sessionId VIDEO_OUTPUT_CHECK advancedMs=${advanced.inMilliseconds} '
      'w=${player.state.width} h=${player.state.height} $fields');
  if (audioOnlySuspect) {
    Diag.pb('s=$sessionId BLACK_SCREEN_SUSPECT position advancing without a '
        'configured video output');
  }
}

/// Allowlisted stream metadata and advertised decoder capabilities only.
/// Never includes source URLs, media titles, headers, or credentials.
Future<void> logAppDecoderDetails(Player player, {bool Function()? isCurrent}) async {
  final fields = <String, String>{};
  for (final key in const [
    'hwdec-current', 'current-vo', 'video-codec', 'video-format',
    'video-params/pixelformat', 'video-params/w', 'video-params/h',
    'video-params/primaries', 'video-params/gamma', 'container-fps',
  ]) {
    if (isCurrent != null && !isCurrent()) return;
    fields[key] = await appMpvGet(player, key);
  }
  if (isCurrent != null && !isCurrent()) return;
  Diag.pb('DECODER_DETAILS $fields');
  if (!Platform.isAndroid) return;
  try {
    final details = await const MethodChannel('app/device')
        .invokeMethod<Object>('getDecoderDiagnostics', {
          'width': player.state.width ?? 0,
          'height': player.state.height ?? 0,
          'fps': double.tryParse(fields['container-fps'] ?? '') ?? 30.0,
        }).timeout(const Duration(seconds: 3));
    if (isCurrent != null && !isCurrent()) return;
    Diag.pb('ANDROID_DECODER_CAPS $details');
  } catch (_) {
    Diag.pb('ANDROID_DECODER_CAPS unavailable');
  }
}
