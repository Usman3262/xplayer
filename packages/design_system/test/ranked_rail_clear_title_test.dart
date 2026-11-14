import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 9 Nov (iPhone + Android phone): the numbers overlapped the titles.
void main() {
  testWidgets('phone position keeps the number above the title', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RankedRailItem(
              rank: 2,
              color: AppColors.cyan,
              bottom: RankedRailItem.bottomClearOfTitle,
              child: PosterCard(
                title: 'Long movie title',
                width: PosterCard.standardWidth,
              ),
            ),
          ),
        ),
      ),
    );

    final number = t.getRect(find.byKey(RankedRailItem.strokeKey));
    final title = t.getRect(find.text('Long movie title'));
    expect(
      number.bottom,
      lessThanOrEqualTo(title.top),
      reason: 'number bottom ${number.bottom}, title top ${title.top}',
    );
  });
}
