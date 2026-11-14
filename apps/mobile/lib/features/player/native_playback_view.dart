import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_screen_mode.dart';

/// Video surface for the Android ExoPlayer engine after an mpv fallback.
///
/// Chrome lives on [PlayerScreen] — this widget only paints the [VideoPlayer]
/// so both engines share the same overlay UI.
class NativePlaybackView extends StatefulWidget {
  const NativePlaybackView({
    super.key,
    required this.controller,
    this.mode = VideoScreenMode.fit,
  });

  final VideoPlayerController controller;

  /// Fit / Fill screen / Zoom / forced 16:9 or 4:3.
  final VideoScreenMode mode;

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
    // Task #143 #13: do not pause native ExoPlayer when app backgrounds.
    if (state == AppLifecycleState.resumed &&
        !widget.controller.value.isPlaying &&
        widget.controller.value.isInitialized) {
      // Resume only if we were playing before OS interrupted — leave as-is.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final ar =
              widget.mode.forcedAspect ??
              (value.aspectRatio > 0 ? value.aspectRatio : 16 / 9);
          final player = VideoPlayer(widget.controller);
          // Same viewport for every mode — only BoxFit changes (C3).
          return ClipRect(
            child: SizedBox.expand(
              child: Transform.scale(
                scale: widget.mode.extraScale,
                child: FittedBox(
                  fit: widget.mode.boxFit,
                  alignment: Alignment.center,
                  child: SizedBox(width: ar * 720, height: 720, child: player),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
