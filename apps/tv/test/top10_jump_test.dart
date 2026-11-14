import 'package:player_tv/features/home/tv_home_screen.dart';
import 'package:player_tv/widgets/focus_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Friday Top 10 notification (Usman 12 Nov): Home scrolls to the Top 10 row,
/// built lazily far down the list, and the focus lands on its first card.
void main() {
  testWidgets('scrolls down to the lazily built Top 10 row and focuses it', (tester) async {
    final scroll = ScrollController();
    final first = FocusNode(debugLabel: 'top10-first');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, i) => i == 30
              ? KeyedSubtree(
                  key: tvTop10Key,
                  child: Row(children: [
                    FocusTile(focusNode: first, onTap: () {}, child: const SizedBox(width: 80, height: 120)),
                  ]),
                )
              : SizedBox(height: 200, child: Text('row $i')),
        ),
      ),
    ));
    expect(tvTop10Key.currentContext, isNull); // not built yet
    final done = tvJumpToTop10(scroll);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await done;
    expect(tvTop10Key.currentContext, isNotNull);
    expect(first.hasFocus, isTrue);
  });

  testWidgets('Top 10 hidden: the list goes back to where it was', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 200, child: Text('row $i')),
        ),
      ),
    ));
    scroll.jumpTo(300);
    await tester.pump();
    final done = tvJumpToTop10(scroll);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await done;
    expect(scroll.offset, 300);
  });
}
