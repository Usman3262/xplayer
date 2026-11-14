import 'dart:async';

import 'package:data/data.dart'
    show Diag, OfflineDownloadPolicy, OfflineRefusal;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/screen_awake.dart';
import '../../core/tv_downloads.dart';
import '../../core/tv_frame_stats.dart';
import '../../core/tv_locale.dart';

/// Plays a completed download from app-private storage. No provider
/// connection and no lease: the file is already on the TV.
/// OK = play/pause, Left/Right = seek 10 s, Back = leave.
class TvOfflinePlayerScreen extends ConsumerStatefulWidget {
  const TvOfflinePlayerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TvOfflinePlayerScreen> createState() =>
      _TvOfflinePlayerScreenState();
}

class _TvOfflinePlayerScreenState extends ConsumerState<TvOfflinePlayerScreen> {
  VideoPlayerController? _c;
  String? _error;
  final _focus = FocusNode();
  bool _showBar = true;
  Timer? _hide;
  Timer? _stats;

  @override
  void initState() {
    super.initState();
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
    final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
    final ctl = ref.read(tvDownloadsProvider.notifier);
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
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.play();
      Diag.pb('OFFLINE playing id=${widget.id}');
      TvFrameStats.instance
        ..ensureStarted()
        ..take();
      _stats = Timer.periodic(const Duration(seconds: 5), (_) {
        Diag.pb(
          'OFFLINE health pos=${c.value.position.inSeconds}s '
          'playing=${c.value.isPlaying} ${TvFrameStats.instance.take()}',
        );
      });
      setState(() => _c = c);
      _bump();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = copy.offlineCannotPlay);
    }
  }

  void _bump() {
    _hide?.cancel();
    if (!_showBar) {
      setState(() => _showBar = true);
      final t0 = DateTime.now();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        Diag.pb(
          'OFFLINE bar frame '
          '+${DateTime.now().difference(t0).inMilliseconds}ms',
        );
      });
    }
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showBar = false);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final c = _c;
    final k = e.logicalKey;
    Diag.pb('OFFLINE key ${k.keyLabel} bar=$_showBar');
    if (c == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      c.value.isPlaying ? c.pause() : c.play();
      _bump();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      final step = Duration(
        seconds: k == LogicalKeyboardKey.arrowLeft ? -10 : 10,
      );
      var to = c.value.position + step;
      if (to < Duration.zero) to = Duration.zero;
      if (to > c.value.duration) to = c.value.duration;
      c.seekTo(to);
      _bump();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    _stats?.cancel();
    _focus.dispose();
    unawaited(_c?.dispose());
    ScreenAwake.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final title = ref.read(tvDownloadsProvider.notifier).byId(widget.id)?.title;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null)
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              )
            else if (_error != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      autofocus: true,
                      onPressed: () => context.pop(),
                      child: Text(AppCopy.ofLanguage(ref.watch(tvLanguageProvider)).back),
                    ),
                  ],
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
            if (c != null)
              // Client 18 Oct #5: same logo watermark as online playback,
              // bottom-left of the picture in both languages.
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final size = box.biggest;
                      final ar = c.value.aspectRatio;
                      var w = size.width, h = size.width / ar;
                      if (h > size.height) {
                        h = size.height;
                        w = h * ar;
                      }
                      final left = (size.width - w) / 2;
                      final bottom = (size.height + h) / 2;
                      final logoH = (h * 0.075).clamp(18.0, 40.0);
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
            if (c != null && _showBar)
              Positioned(
                left: 48,
                right: 48,
                bottom: 36,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (_, v, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Client 18 Oct #5: timeline runs left to right in
                      // Arabic too (Left = back 10 s, Right = forward).
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VideoProgressIndicator(
                              c,
                              allowScrubbing: false,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF22D3EE),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_fmt(v.position)} / ${_fmt(v.duration)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if (!v.isPlaying)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.pause_rounded,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
