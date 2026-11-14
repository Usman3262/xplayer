import 'package:player_tv/widgets/tv_exit_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a page with one button; pressing it opens the exit dialog.
Future<void> _pumpHost(WidgetTester tester, List<MethodCall> platform) async {
  resetTvExitDialogGuard();
  SharedPreferences.setMockInitialValues({});
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      platform.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('host'),
                autofocus: true,
                onPressed: () => confirmTvExit(context, ref),
                child: const Text('host'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _focusedText(String text) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return find
      .descendant(of: find.byWidget(ctx.widget), matching: find.text(text))
      .evaluate()
      .isNotEmpty;
}

Future<void> _open(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(find.text('Cancel'), findsOneWidget);
}

void main() {
  testWidgets('opens with Cancel focused; Right moves to Exit', (tester) async {
    final platform = <MethodCall>[];
    await _pumpHost(tester, platform);
    await _open(tester);
    expect(_focusedText('Cancel'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusedText('Cancel'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focusedText('Cancel'), isTrue);
  });

  testWidgets('OK on Cancel closes and focus returns to the page',
      (tester) async {
    final platform = <MethodCall>[];
    await _pumpHost(tester, platform);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<Dialog>()),
    );
    expect(_focusedText('host'), isTrue);
    expect(
      platform.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
  });

  testWidgets('Back closes the dialog without exiting', (tester) async {
    final platform = <MethodCall>[];
    await _pumpHost(tester, platform);
    await _open(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(
      platform.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );
  });

  testWidgets('OK on Exit closes the app; dialog can open again later',
      (tester) async {
    final platform = <MethodCall>[];
    await _pumpHost(tester, platform);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      platform.where((c) => c.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
    // Repeated opening (after the short duplicate-Back guard, real clock).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 550)),
    );
    await _open(tester);
    expect(_focusedText('Cancel'), isTrue);
  });
}
