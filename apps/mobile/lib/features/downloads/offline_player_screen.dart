import 'dart:async';

import 'package:data/data.dart'
    show Diag, OfflineDownloadPolicy, OfflineRefusal;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/screen_awake.dart';
import '../../core/session_controller.dart';
import '../player/video_screen_mode.dart';
import '../../core/downloads_controller.dart';
import '../../core/orientation_policy.dart';

/// Plays a finished download from app storage: no network, no lease.
/// Tap toggles the controls; the bar scrubs; ±10 s buttons.
///
/// media_kit (mpv), as online playback: provider files are mostly MKV, which
/// the iPhone's system player cannot open ("This file cannot be played",
/// 18 Oct iPhone test).
class OfflinePlayerScreen extends ConsumerStatefulWidget {
  const OfflinePlayerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<OfflinePlayerScreen> createState() =>
      _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends ConsumerState<OfflinePlayerScreen> {
  Player? _player;
  VideoController? _video;
  String? _error;
  bool _ready = false;
  bool _showBar = true;
  /// Movies / episodes open in Fit, like the main player (client 6 Nov).
  VideoScreenMode _mode = VideoScreenMode.fit;

  String _modeLabel(VideoScreenMode m) {
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    return switch (m) {
      VideoScreenMode.fit => copy.videoModeFit,
      VideoScreenMode.stretch => copy.videoModeStretchFull,
      VideoScreenMode.fill => copy.videoModeStretch,
      VideoScreenMode.zoom => copy.videoModeZoom,
      _ => copy.videoModeFit,
    };
  }

  IconData _modeIcon(VideoScreenMode m) => switch (m) {
        VideoScreenMode.fit => Icons.fit_screen_rounded,
        VideoScreenMode.stretch => Icons.aspect_ratio_rounded,
        VideoScreenMode.fill => Icons.settings_overscan_rounded,
        VideoScreenMode.zoom => Icons.crop_free_rounded,
        _ => Icons.aspect_ratio_rounded,
      };
  Timer? _hide;
  double? _dragSec;
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Counted keep-awake: survives route replacement (see ScreenAwake).
    ScreenAwake.acquire(this);
    unawaited(_open());
  }

  /// Offline refusal in the app's language (the data package's text is
  /// English only).
  String _refusalText(AppCopy copy, OfflineRefusal r) => switch (r) {
        OfflineRefusal.subscriptionEnded => copy.offlineSubscriptionEnded,
        OfflineRefusal.checkInNeeded => copy.offlineCheckInNeeded,
        OfflineRefusal.clockChanged => copy.offlineClockChanged,
      };

  Future<void> _open() async {
    final copy = AppCopy.ofLanguage(ref.read(sessionProvider).language);
    final ctl = ref.read(appDownloadsProvider.notifier);
    final d = ctl.byId(widget.id);
    final f = d == null ? null : await ctl.fileFor(d);
    if (!mounted) return;
    if (f == null) {
      setState(() => _error = copy.offlineFileMissing);
      return;
    }
    // Subscription ended / no online check for too long / clock moved back (P17).
    final refusal = await OfflineDownloadPolicy.check();
    if (!mounted) return;
    if (refusal != null) {
      setState(() => _error = _refusalText(copy, refusal));
      return;
    }
    final player = Player();
    final video = VideoController(player);
    _subs.add(player.stream.error.listen((e) {
      Diag.pb('OFFLINE error id=${widget.id}');
      if (mounted && !_ready) setState(() => _error = copy.offlineCannotPlay);
    }));
    _subs.add(player.stream.width.listen((w) {
      if ((w ?? 0) > 0 && mounted && !_ready) {
        setState(() => _ready = true);
        _bump();
      }
    }));
    setState(() {
      _player = player;
      _video = video;
    });
    try {
      await player.open(Media(f.uri.toString()));
      Diag.pb('OFFLINE playing id=${widget.id}');
    } catch (_) {
      if (mounted) setState(() => _error = copy.offlineCannotPlay);
    }
  }

  void _bump() {
    _hide?.cancel();
    if (!_showBar) setState(() => _showBar = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showBar = false);
    });
  }

  void _seek(int seconds) {
    final p = _player;
    if (p == null) return;
    var to = p.state.position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > p.state.duration) to = p.state.duration;
    unawaited(p.seek(to));
    _bump();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _hide?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    ScreenAwake.release(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    applyAppOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final video = _video;
    final title = ref.read(appDownloadsProvider.notifier).byId(widget.id)?.title;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_showBar) {
            setState(() => _showBar = false);
          } else {
            _bump();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null && _error == null)
              // Same picture sizes as the main player (client 6 Nov: the
              // downloads player's size / full-screen controls did not work):
              // opens in Fit (largest size, own proportions), size button cycles.
              ClipRect(
                child: SizedBox.expand(
                  child: Transform.scale(
                    scale: _mode.extraScale,
                    child: Video(
                      controller: video,
                      controls: NoVideoControls,
                      fill: Colors.black,
                      fit: _mode.boxFit,
                      wakelock: false,
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              )
            else if (!_ready)
              const Center(child: CircularProgressIndicator()),
            if (p != null && _ready)
              // Client 18 Oct #5: same logo watermark as online playback,
              // bottom-left of the picture in both languages.
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final size = box.biggest;
                      final vw = (p.state.width ?? 16).toDouble();
                      final vh = (p.state.height ?? 9).toDouble();
                      final ar = vh <= 0 ? 16 / 9 : vw / vh;
                      var w = size.width, h = size.width / ar;
                      if (h > size.height) {
                        h = size.height;
                        w = h * ar;
                      }
                      final left = (size.width - w) / 2;
                      final bottom = (size.height + h) / 2;
                      final logoH = (h * 0.075).clamp(18.0, 34.0);
                      return Stack(
                        children: [
                          Positioned(
                            left: left + w * 0.025,
                            top: bottom - logoH - h * 0.045,
                            child: Opacity(
                              opacity: 0.6,
                              child: AppLogo(
                                height: logoH,
                                showWordmark: false,
                                alignToStart: false,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            if (_showBar || !_ready)
              PositionedDirectional(
                top: 8,
                start: 8,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const BackButtonIcon(),
                  ),
                ),
              ),
            if (_ready && _showBar && _error == null)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: SafeArea(
                  child: IconButton(
                    tooltip: _modeLabel(_mode.next),
                    onPressed: () {
                      setState(() => _mode = _mode.next);
                      _bump();
                    },
                    icon: Icon(_modeIcon(_mode), color: Colors.white),
                  ),
                ),
              ),
            if (p != null && _ready && _showBar)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: SafeArea(
                  child: StreamBuilder<Duration>(
                    stream: p.stream.position,
                    builder: (_, _) {
                      final pos = p.state.position;
                      final dur = p.state.duration;
                      final maxSec = dur.inMilliseconds / 1000.0;
                      final cur = (_dragSec ?? pos.inMilliseconds / 1000.0)
                          .clamp(0.0, maxSec <= 0 ? 0.0 : maxSec);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          // Client 18 Oct #5: timeline runs left to right
                          // in Arabic too, like the online player.
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Slider(
                                  value: cur.toDouble(),
                                  max: maxSec <= 0 ? 1 : maxSec,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) {
                                    setState(() => _dragSec = v);
                                    _bump();
                                  },
                                  onChangeEnd: (v) {
                                    unawaited(p.seek(Duration(
                                      milliseconds: (v * 1000).round(),
                                    )));
                                    setState(() => _dragSec = null);
                                  },
                                ),
                                Row(
                                  children: [
                                    // Clear of the logo watermark (bottom-left).
                                    const SizedBox(width: 56),
                                    Text(
                                      '${_fmt(pos)} / ${_fmt(dur)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _seek(-10),
                                      icon: const Icon(Icons.replay_10_rounded),
                                    ),
                                    IconButton.filled(
                                      onPressed: () {
                                        unawaited(p.playOrPause());
                                        _bump();
                                      },
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.cyan,
                                        foregroundColor: Colors.black,
                                      ),
                                      icon: Icon(
                                        p.state.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _seek(10),
                                      icon: const Icon(
                                        Icons.forward_10_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
