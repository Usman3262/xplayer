import 'package:player_tv/widgets/focus_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Continue Watching on Android TV (client 12 Nov): a short OK opens the
/// title; holding OK offers to remove it (most remotes have no Red / Menu).
void main() {
  Future<(List<String>, FocusNode)> pump(WidgetTester tester) async {
    final calls = <String>[];
    final node = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: FocusTile(
          focusNode: node,
          autofocus: true,
          onTap: () => calls.add('tap'),
          onLongSelect: () => calls.add('long'),
          child: const SizedBox(width: 100, height: 60),
        ),
      ),
    ));
    node.requestFocus();
    await tester.pump();
    return (calls, node);
  }

  testWidgets('short OK opens on release', (tester) async {
    final (calls, _) = await pump(tester);
    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    expect(calls, isEmpty);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    expect(calls, ['tap']);
  });

  testWidgets('holding OK offers remove on release, once, and does not open',
      (tester) async {
    final (calls, _) = await pump(tester);
    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    // Nothing while still held: a dialog would get the repeats.
    expect(calls, isEmpty);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    expect(calls, ['long']);
  });

  testWidgets('a release without a press here does nothing', (tester) async {
    final (calls, _) = await pump(tester);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    expect(calls, isEmpty);
  });
}
