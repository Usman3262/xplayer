import 'package:player_tv/widgets/focus_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 26 Oct: holding Left / Right on the TV moved the focus to another
/// row (a single press stayed). Two rows of tiles; hold Left on the first
/// tile of the top row and Right on the last one.
void main() {
  // The top row starts further right than the one below (a section title /
  // number beside it on the real screens), so the nearest card to the left
  // of its first card is in the row below.
  Widget row(String id, List<FocusNode> nodes, {double lead = 0}) => SizedBox(
        height: 120,
        child: ListView(
          padding: EdgeInsets.only(left: lead),
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < nodes.length; i++)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FocusTile(
                  focusNode: nodes[i],
                  child: SizedBox(width: 100, height: 100, child: Text('$id$i')),
                ),
              ),
          ],
        ),
      );

  Future<(List<FocusNode>, List<FocusNode>)> pump(WidgetTester t) async {
    final top = List.generate(3, (_) => FocusNode());
    final bottom = List.generate(3, (_) => FocusNode());
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [row('a', top, lead: 240), row('b', bottom)]),
      ),
    ));
    return (top, bottom);
  }

  Future<void> hold(WidgetTester t, LogicalKeyboardKey key, int repeats) async {
    await t.sendKeyDownEvent(key);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < repeats; i++) {
      await t.sendKeyRepeatEvent(key);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.sendKeyUpEvent(key);
    await t.pumpAndSettle();
  }

  testWidgets('holding Left on the first card stays on it', (t) async {
    final (top, bottom) = await pump(t);
    top[0].requestFocus();
    await t.pumpAndSettle();
    await hold(t, LogicalKeyboardKey.arrowLeft, 10);
    expect(top[0].hasFocus, isTrue);
    expect(bottom.any((n) => n.hasFocus), isFalse);
  });

  testWidgets('holding Right runs to the last card of the row and stays there', (t) async {
    final (top, bottom) = await pump(t);
    top[0].requestFocus();
    await t.pumpAndSettle();
    await hold(t, LogicalKeyboardKey.arrowRight, 10);
    expect(top[2].hasFocus, isTrue);
    expect(bottom.any((n) => n.hasFocus), isFalse);
  });

  // Client 26 Oct (TCL): holding Right through a long row (cards built as it
  // scrolls) must stay in that row the whole way; the page must not scroll.
  testWidgets('holding Right through a long lazy row never leaves it', (t) async {
    final top = List.generate(20, (_) => FocusNode());
    final bottom = List.generate(20, (_) => FocusNode());
    final page = ScrollController();
    Widget lazy(String id, List<FocusNode> nodes, {double lead = 0}) => SizedBox(
          height: 120,
          child: ListView.builder(
            padding: EdgeInsets.only(left: lead),
            scrollDirection: Axis.horizontal,
            itemCount: nodes.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.all(8),
              child: FocusTile(focusNode: nodes[i], child: SizedBox(width: 100, height: 100, child: Text('$id$i'))),
            ),
          ),
        );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(controller: page, children: [
          lazy('b', bottom),
          lazy('a', top, lead: 60),
          const SizedBox(height: 900),
        ]),
      ),
    ));
    top[0].requestFocus();
    await t.pumpAndSettle();
    final pageAt = page.offset;
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 30; i++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 40));
      expect(bottom.any((n) => n.hasFocus), isFalse, reason: 'left the row at repeat $i');
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(top.last.hasFocus, isTrue, reason: 'reached the end of the row');
    expect(page.offset, closeTo(pageAt, 1));
  });
}
