import 'package:player_tv/widgets/tv_poster.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rating label: one decimal, nothing when missing or out of range', () {
    expect(TvRatingBadge.label(7.25), '7.3');
    expect(TvRatingBadge.label(8), '8.0');
    expect(TvRatingBadge.label(10), '10.0');
    expect(TvRatingBadge.label(null), isNull);
    expect(TvRatingBadge.label(0), isNull);
    expect(TvRatingBadge.label(-1), isNull);
    expect(TvRatingBadge.label(42), isNull);
    expect(TvRatingBadge.label(double.nan), isNull);
  });

  Future<void> pumpPoster(WidgetTester tester, MediaItem item) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: TvPoster.fromMedia(item))),
        ),
      );

  testWidgets('movie and series posters show the rating; channels do not',
      (tester) async {
    await pumpPoster(
      tester,
      const MediaItem(id: 'm', title: 'M', kind: MediaKind.movie, rating: 6.4),
    );
    expect(find.text('6.4'), findsOneWidget);
    await pumpPoster(
      tester,
      const MediaItem(id: 's', title: 'S', kind: MediaKind.series, rating: 7),
    );
    expect(find.text('7.0'), findsOneWidget);
    await pumpPoster(
      tester,
      const MediaItem(id: 'l', title: 'L', kind: MediaKind.live, rating: 9),
    );
    expect(find.byType(TvRatingBadge), findsNothing);
  });

  testWidgets('no badge without a rating', (tester) async {
    await pumpPoster(
      tester,
      const MediaItem(id: 'm', title: 'M', kind: MediaKind.movie),
    );
    expect(find.byType(TvRatingBadge), findsNothing);
  });
}
