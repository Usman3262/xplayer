import 'package:flutter/material.dart';

import '../theme/app_fonts.dart';

/// Ranked row number as on the LG app (client 4 Nov: "match the numbering
/// style and placement across all platforms to the LG version"): a tall
/// Bebas Neue numeral, white outline, see-through inside, drawn over the
/// poster's bottom-left corner with its foot just below the poster's edge.
/// LG draws 110 px digits on a 236 px poster (3 px outline, 10 px from the
/// left, 6 px below the edge); the phone and TV posters are 118 px, so the
/// defaults are half of that.
///
/// The number stays on the left in Arabic too, as on LG (digits read left
/// to right).
class RankedRailItem extends StatelessWidget {
  const RankedRailItem({
    super.key,
    required this.rank,
    required this.child,
    this.fontSize = 55,
    this.inset,
    // PosterCard.footerHeight (40) minus the 3 px the foot hangs below.
    this.bottom = 37,
    this.strokeWidth = 1.6,
    this.overlap = 0,
    this.color = Colors.white,
  });

  final int rank;

  /// The poster card (without its own rank badge).
  final Widget child;
  final double fontSize;

  /// Ignored (kept for call sites).
  final double? inset;

  /// Distance of the number's box from the bottom of the card (title line
  /// included): the poster footer minus the 3 px the foot hangs below.
  final double bottom;
  final double strokeWidth;

  /// Ignored (kept for call sites): the number sits on the poster.
  final double overlap;

  /// Outline colour of the numeral (white as on LG; the iPhone Top 10 uses

  final Color color;

  static const strokeKey = ValueKey('rank-stroke');

  /// [bottom] that keeps the number on the poster, clear of the title line
  /// below it (phone / iPhone, client 9 Nov: the numbers overlapped titles).
  static const bottomClearOfTitle = 46.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: fontSize * 0.09,
          bottom: bottom,
          child: RankNumberLg(
            rank: rank,
            fontSize: fontSize,
            strokeWidth: strokeWidth,
            textKey: strokeKey,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// The LG numeral on its own (white outline, transparent inside).
class RankNumberLg extends StatelessWidget {
  const RankNumberLg({
    super.key,
    required this.rank,
    this.fontSize = 55,
    this.strokeWidth = 1.6,
    this.textKey,
    this.color = Colors.white,
  });

  final int rank;
  final double fontSize;
  final double strokeWidth;
  final Key? textKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        '$rank',
        key: textKey,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontFamily: AppFonts.rankLgFamily,
          fontSize: fontSize,
          height: 1,
          letterSpacing: 0,
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 4))],
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = color,
        ),
      ),
    );
  }
}
