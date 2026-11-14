import 'package:player_tv/widgets/tv_arrange_packages.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Client 18 Oct TV #1: OK picks a package up, Down moves it, OK drops it,
// Save returns the new order.
void main() {
  testWidgets('remote moves a package and Save returns the order',
      (tester) async {
    final copy = AppCopy.ofLanguage('en');
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showTvArrangePackages(
                    context,
                    categories: const [
                      CatalogCategory(id: 'a', name: 'Alpha'),
                      CatalogCategory(id: 'b', name: 'Beta'),
                      CatalogCategory(id: 'c', name: 'Gamma'),
                    ],
                    label: (s) => s,
                    copy: copy,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select); // pick up Alpha
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // Alpha below Beta
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // below Gamma
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select); // drop
    await tester.pumpAndSettle();

    await tester.tap(find.text(copy.save));
    await tester.pumpAndSettle();
    expect(result, ['b', 'c', 'a']);
  });

  // As on LG 6.1.24: Back after a change asks "Save changes?"; Save keeps
  // the new order, Discard throws it away; Back with no change just closes.
  Future<List<String>?> backFlow(WidgetTester tester, {required bool move, String? answer}) async {
    final copy = AppCopy.ofLanguage('en');
    List<String>? result = const ['unset'];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showTvArrangePackages(
                    context,
                    categories: const [
                      CatalogCategory(id: 'a', name: 'Alpha'),
                      CatalogCategory(id: 'b', name: 'Beta'),
                    ],
                    label: (s) => s,
                    copy: copy,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (move) {
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }
    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    await nav.maybePop();
    await tester.pumpAndSettle();
    if (answer != null) {
      expect(find.text(copy.saveOrderTitle), findsOneWidget, reason: 'asks before closing');
      await tester.tap(find.text(answer).last);
      await tester.pumpAndSettle();
    }
    return result;
  }

  testWidgets('Back after a change asks; Save keeps the new order', (tester) async {
    final copy = AppCopy.ofLanguage('en');
    expect(await backFlow(tester, move: true, answer: copy.save), ['b', 'a']);
  });

  testWidgets('Back after a change asks; Discard keeps the old order', (tester) async {
    final copy = AppCopy.ofLanguage('en');
    expect(await backFlow(tester, move: true, answer: copy.discard), isNull);
  });

  testWidgets('Back with no change closes without asking', (tester) async {
    expect(await backFlow(tester, move: false), isNull);
  });

  // Client 21 Oct A10 / TV 4: a held package moved past the bottom edge
  // stayed off-screen; the list now scrolls with it and Save keeps the move.
  testWidgets('list scrolls with a held package past the visible edge', (tester) async {
    final copy = AppCopy.ofLanguage('en');
    List<String>? result;
    final cats = [for (var i = 0; i < 40; i++) CatalogCategory(id: 'p$i', name: 'Package $i')];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showTvArrangePackages(context, categories: cats, label: (s) => s, copy: copy);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select); // pick up Package 0
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final row = find.text('Package 0');
    expect(row, findsOneWidget, reason: 'held row is still built');
    final list = tester.getRect(find.byType(ListView));
    final r = tester.getRect(row);
    expect(r.top >= list.top && r.bottom <= list.bottom, isTrue, reason: 'held row is on screen');
    await tester.sendKeyEvent(LogicalKeyboardKey.select); // drop
    await tester.pumpAndSettle();
    await tester.tap(find.text(copy.save));
    await tester.pumpAndSettle();
    expect(result!.indexOf('p0'), 20);
  });
}
