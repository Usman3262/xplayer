import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Draggable / tappable video progress bar for player scrubbing.
/// Seeks on tap or drag **release** only (not every drag update — avoids
/// dozens of flush/rebuffer cycles while scrubbing 4K).
class AppSeekBar extends StatefulWidget {
  const AppSeekBar({
    super.key,
    required this.progress,
    required this.onSeekFraction,
    this.height = 4,
    this.enabled = true,
    this.thumbSize = 14,
    this.gutter = 4,
    this.touchHeight = 40,
    this.thumbShadowBlur = 6,
  });

  final double progress;
  final ValueChanged<double> onSeekFraction;
  final double height;
  final bool enabled;

  /// Knob diameter, inset of the track from the ends, height of the whole
  /// widget and knob shadow. Defaults are the phone values; Android TV passes
  /// the LG sizes.
  final double thumbSize;
  final double gutter;
  final double touchHeight;
  final double thumbShadowBlur;

  @override
  State<AppSeekBar> createState() => _AppSeekBarState();
}

class _AppSeekBarState extends State<AppSeekBar> {
  double get _thumb => widget.thumbSize;
  double get _gutter => widget.gutter;

  double? _dragFraction;

  double _fractionFromLocal(Offset local, double width) {
    final inset = (_thumb / 2) + _gutter;
    final track = (width - inset * 2).clamp(1.0, width);
    final dx = (local.dx - inset).clamp(0.0, track);
    return dx / track;
  }

  void _commit(double fraction) {
    if (!widget.enabled) return;
    widget.onSeekFraction(fraction.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final value = (_dragFraction ?? widget.progress).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final inset = (_thumb / 2) + _gutter;
        final trackW = (w - inset * 2).clamp(0.0, w);
        final thumbLeft =
            (inset + trackW * value - _thumb / 2).clamp(0.0, w - _thumb);

        // A touch that starts on the bar is a seek, whatever way the finger
        // drifts (iPhone, 17 Oct): the player's up/down swipe for volume
        // and brightness used to win any slightly vertical drag, so the bar
        // changed the volume instead of seeking. The eager recognizer claims
        // the gesture on touch-down; raw pointer events drive the scrub.
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            if (widget.enabled)
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
          },
          child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.enabled
              ? (e) => setState(
                    () => _dragFraction =
                        _fractionFromLocal(e.localPosition, w),
                  )
              : null,
          onPointerMove: widget.enabled
              ? (e) => setState(
                    () => _dragFraction =
                        _fractionFromLocal(e.localPosition, w),
                  )
              : null,
          onPointerUp: widget.enabled
              ? (e) {
                  final f = _fractionFromLocal(e.localPosition, w);
                  setState(() => _dragFraction = null);
                  _commit(f);
                }
              : null,
          onPointerCancel: (_) => setState(() => _dragFraction = null),
          child: SizedBox(
            // Taller touch area (the track itself stays thin).
            height: widget.touchHeight,
            width: w,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: inset,
                  right: inset,
                  top: (widget.touchHeight - widget.height) / 2,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(widget.height),
                    ),
                  ),
                ),
                Positioned(
                  left: inset,
                  top: (widget.touchHeight - widget.height) / 2,
                  child: Container(
                    height: widget.height,
                    width: trackW * value,
                    // Solid cyan fill, as on LG (client 5 Nov: same progress bar
                    // on every platform).
                    decoration: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(widget.height),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbLeft,
                  top: (widget.touchHeight - _thumb) / 2,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    // White knob with a soft shadow, as on LG.
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x80000000),
                          blurRadius: widget.thumbShadowBlur,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}
