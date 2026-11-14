import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 23 Oct check: in Arabic the match page showed Man Utd 4 - 1 Como for
// a Como 4 - 1 win (home team on the right, its goals on the left).
void main() {
  Widget card(TextDirection dir) => MaterialApp(
        home: Directionality(
          textDirection: dir,
          child: const Scaffold(
            body: MpScoreCard(
              leagueName: 'UEFA Champions League',
              homeName: 'Como',
              awayName: 'Manchester United',
              homeGoals: 4,
              awayGoals: 1,
              statusText: 'FT',
            ),
          ),
        ),
      );

  double centreX(WidgetTester t, String text) => t.getCenter(find.text(text)).dx;

  testWidgets('English: home on the left, home goals first', (t) async {
    await t.pumpWidget(card(TextDirection.ltr));
    expect(find.text('4 - 1'), findsOneWidget);
    expect(centreX(t, 'Como'), lessThan(centreX(t, 'Manchester United')));
  });

  testWidgets('Arabic: home on the right, home goals on the right', (t) async {
    await t.pumpWidget(card(TextDirection.rtl));
    expect(find.text('1 - 4'), findsOneWidget);
    expect(centreX(t, 'Como'), greaterThan(centreX(t, 'Manchester United')));
  });

  testWidgets('running score follows the same order', (t) async {
    late String ltr, rtl;
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (c) {
        ltr = mpRunningScore(c, '2 - 1');
        return const SizedBox();
      }),
    ));
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: Builder(builder: (c) {
        rtl = mpRunningScore(c, '2 - 1');
        return const SizedBox();
      }),
    ));
    expect(ltr, '2 - 1');
    expect(rtl, '1 - 2');
  });
}
