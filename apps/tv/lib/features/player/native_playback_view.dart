import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Video surface for the Android ExoPlayer engine after an mpv fallback.
///
/// Chrome (seek bar, transport, close) lives on [TvPlayerScreen] — this widget
/// only paints the [VideoPlayer] so both engines share the same overlay UI.
class NativePlaybackView extends StatefulWidget {
  const NativePlaybackView({
    super.key,
    required this.controller,
    this.fill = false,
  });

  final VideoPlayerController controller;

  /// When true, crop to fill the screen (edge-to-edge).
  final bool fill;

  @override
  State<NativePlaybackView> createState() => _NativePlaybackViewState();
}

class _NativePlaybackViewState extends State<NativePlaybackView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Task #143 #13: do not pause when app backgrounds.
  }

  @override
  Widget build(BuildContext context) {
    // Web (LG webOS): the TV shows video on a hardware layer behind the page,
    // so nothing opaque may sit under the <video>, and clipping / scaling it
    // can hide the picture (sound only on a 2022 LG TV). The <video> element
    // itself fits the picture (object-fit: contain).
    if (kIsWeb) return SizedBox.expand(child: VideoPlayer(widget.controller));
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final ar = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
          final player = VideoPlayer(widget.controller);
          // Same viewport for Fit and Fill — only BoxFit changes (C3).
          return ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fill ? BoxFit.cover : BoxFit.contain,
                alignment: Alignment.center,
                child: SizedBox(
                  width: ar * 720,
                  height: 720,
                  child: player,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
