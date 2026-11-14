import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 4 Nov: every platform uses the LG numbering — a Bebas Neue numeral
/// with a white outline, see-through inside, over the poster's bottom-left.
void main() {
  Future<void> pump(WidgetTester t, int rank, {TextDirection dir = TextDirection.ltr}) => t.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: RankedRailItem(
                  rank: rank,
                  child: PosterCard(title: 'X', width: PosterCard.standardWidth),
                ),
              ),
            ),
          ),
        ),
      );

  Text number(WidgetTester t) => t.widget<Text>(find.byKey(RankedRailItem.strokeKey));

  testWidgets('white outline, no fill, Bebas Neue (as on LG)', (t) async {
    await pump(t, 1);
    final style = number(t).style!;
    expect(style.foreground!.style, PaintingStyle.stroke);
    expect(style.foreground!.color.toARGB32(), Colors.white.toARGB32());
    expect(style.fontFamily, AppFonts.rankLgFamily);
    expect(t.widgetList<Text>(find.text('1')), hasLength(1), reason: 'no solid fill layer');
  });

  for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('number over the poster\'s bottom-left (${dir.name})', (t) async {
      await pump(t, 10, dir: dir);
      final card = t.getRect(find.byType(PosterCard));
      final poster = Rect.fromLTWH(card.left, card.top, card.width, PosterCard.imageHeightFor(card.width));
      final n = t.getRect(find.byKey(RankedRailItem.strokeKey));
      // On the poster, left half, not beside it.
      expect(n.left, greaterThanOrEqualTo(poster.left));
      expect(n.left, lessThan(poster.left + poster.width * 0.15));
      // Foot at the poster's bottom edge (LG: a few px below it).
      expect((n.bottom - poster.bottom).abs(), lessThan(8), reason: 'foot=${n.bottom - poster.bottom}');
    });
  }

  testWidgets('poster is not pushed aside by the number', (t) async {
    await pump(t, 3);
    final card = t.getRect(find.byType(PosterCard));
    final item = t.getRect(find.byType(RankedRailItem));
    expect(card.left, item.left);
  });
}
