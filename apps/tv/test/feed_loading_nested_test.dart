import 'package:player_tv/widgets/tv_feed_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TvFeedLoading with hero lays out inside a vertical ListView',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            clipBehavior: Clip.none,
            children: const [
              SizedBox(height: 40),
              TvFeedLoading(railCount: 2, padding: EdgeInsets.zero),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(TvFeedLoading), findsOneWidget);
  });

  testWidgets('TvFeedLoading still fills a bounded body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TvFeedLoading())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
