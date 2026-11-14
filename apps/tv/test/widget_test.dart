import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player_tv/main.dart';

void main() {
  testWidgets('TV app boots', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: TvRootApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TvRootApp), findsOneWidget);
  });
}
