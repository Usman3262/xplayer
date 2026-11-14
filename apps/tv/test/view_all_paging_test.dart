import 'package:player_tv/core/providers.dart';
import 'package:player_tv/features/browse/tv_view_all_screen.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offset-cursor paging like the backend (`cursor` = offset, `nextCursor`).
class _FakeCatalog implements CatalogRepository {
  _FakeCatalog(this.total);
  final int total;
  final calls = <({MediaKind kind, String? categoryId, String? cursor})>[];

  @override
  Future<CatalogPage<MediaItem>> browse({
    required MediaKind kind,
    String? categoryId,
    String? cursor,
    int limit = 10,
  }) async {
    calls.add((kind: kind, categoryId: categoryId, cursor: cursor));
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final end = (offset + limit).clamp(0, total);
    final items = [
      for (var i = offset; i < end; i++)
        MediaItem(id: 'm$i', title: 'Title $i', kind: kind),
      // The provider sometimes repeats a row across pages.
      if (offset > 0) MediaItem(id: 'm0', title: 'Title 0', kind: kind),
    ];
    return CatalogPage(
      items: items,
      nextCursor: end < total ? '$end' : null,
      total: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeCatalog> _pump(
  WidgetTester tester, {
  required MediaKind kind,
  required String categoryId,
  int total = 130,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = _FakeCatalog(total);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: TvViewAllScreen(
          kind: kind,
          categoryId: categoryId,
          title: 'All',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 60; i++) {
    await tester.drag(scrollable, const Offset(0, -900));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('"all" asks for the whole catalog, not one category',
      (tester) async {
    final fake = await _pump(
      tester,
      kind: MediaKind.movie,
      categoryId: tvAllCategory,
    );
    expect(fake.calls.first.categoryId, isNull);
    expect(fake.calls.first.kind, MediaKind.movie);
  });

  testWidgets('a category id is passed through for series', (tester) async {
    final fake = await _pump(
      tester,
      kind: MediaKind.series,
      categoryId: '77',
    );
    expect(fake.calls.first.categoryId, '77');
    expect(fake.calls.first.kind, MediaKind.series);
  });

  testWidgets('scrolling loads every page, beyond the first, with no duplicates',
      (tester) async {
    final fake = await _pump(
      tester,
      kind: MediaKind.movie,
      categoryId: '5',
    );
    await _scrollToEnd(tester);
    // 130 titles at 48 per page = 3 requests: offsets null, 48, 96.
    expect(fake.calls.map((c) => c.cursor).toList(), [null, '48', '96']);
    expect(find.text('Title 129'), findsOneWidget);
    // 130 unique titles in the grid: the repeated "m0" row is not added twice.
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect((grid.delegate as SliverChildBuilderDelegate).childCount, 130);
  });
}
