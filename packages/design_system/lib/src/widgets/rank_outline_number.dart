import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Weekly-picks rank digit, per the client's approved reference (20 Oct
/// screenshot: heavy sans-serif numerals, thick cyan outline, dark inside,
/// bottom-right of the poster). The earlier Playfair serif did not match.
///
/// - Font: system sans Black (Roboto Black on Android, SF Heavy on iOS).
/// - Fill: solid black (never covered by the outline).
/// - Outline: primary cyan drawn **outside** only — stroke is painted
///   under the fill so the inward half of the stroke is masked away.
class RankOutlineNumber extends StatelessWidget {
  const RankOutlineNumber({
    super.key,
    required this.rank,
    this.fontSize = 72,
    /// Desired *visible* exterior outline thickness (logical px).
    this.strokeWidth = 3.0,
  });

  final int rank;
  final double fontSize;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final text = '$rank';
    final base = TextStyle(
      fontFamily: 'sans-serif-black',
      fontFamilyFallback: const ['sans-serif'],
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 0.9,
      letterSpacing: -1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Flutter's stroke is centered on the glyph path (half in, half out).
    // Paint stroke first at 2×, then solid black on top → only exterior remains.
    final visible = strokeWidth > fontSize * 0.055 ? strokeWidth : fontSize * 0.055;
    final paintStroke = visible * 2;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = paintStroke
                ..strokeJoin = StrokeJoin.round
                ..strokeMiterLimit = 2
                ..color = AppColors.cyan,
            ),
          ),
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: base.copyWith(color: Colors.black),
          ),
        ],
      ),
    );
  }
}
