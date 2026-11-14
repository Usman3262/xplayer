import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('poster title and subtitle centred under the card (client 24 Oct)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: PosterCard(title: 'الحشاشين', subtitle: 'Drama', width: 140),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final t in ['الحشاشين', 'Drama']) {
      final text = tester.widget<Text>(find.text(t));
      expect(text.textAlign, TextAlign.center);
      expect(tester.getRect(find.text(t)).width, 140);
    }
  });

  testWidgets('phone Continue Watching title centred under the card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Align(alignment: Alignment.topLeft, child: ContinueCard(title: 'Tyson', width: 240))),
    );
    expect(tester.widget<Text>(find.text('Tyson')).textAlign, TextAlign.center);
    expect(tester.getRect(find.text('Tyson')).width, 240);
  });
}
