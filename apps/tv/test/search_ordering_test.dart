import 'dart:async';

import 'package:player_tv/core/providers.dart';
import 'package:player_tv/features/search/tv_search_screen.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Search results arrive out of order: the first query is slow.
class _SlowFirstCatalog implements CatalogRepository {
  final slow = Completer<void>();
  final queries = <String>[];

  @override
  Future<CatalogPage<MediaItem>> searchPage(
    String query, {
    MediaKind? kind,
    String? cursor,
    int limit = 40,
    String? categoryId,
  }) async {
    queries.add(query);
    if (query == 'ab') await slow.future;
    if (query == 'boom') throw Exception('network');
    return CatalogPage(
      items: [MediaItem(id: 'id-$query', title: 'Result $query', kind: MediaKind.movie)],
    );
  }

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_SlowFirstCatalog> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = _SlowFirstCatalog();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(fake),
        searchProvider.overrideWith((ref, q) async => const <MediaItem>[]),
        sportsEnabledProvider.overrideWith((ref) async => true),
      ],
      child: const MaterialApp(home: Scaffold(body: TvSearchScreen())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return fake;
}

Finder _result(String q) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').toLowerCase() == 'result $q',
    );

void main() {
  testWidgets('a slow older query never replaces newer results', (tester) async {
    final fake = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 300)); // debounce -> 'ab' in flight
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 300)); // 'abc' must still run
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.queries, ['ab', 'abc']);
    expect(_result('abc'), findsWidgets);
    fake.slow.complete(); // old response arrives last
    await tester.pump(const Duration(milliseconds: 50));
    expect(_result('ab'), findsNothing);
    expect(_result('abc'), findsWidgets);
  });

  testWidgets('a failed search shows Retry, not "no results"', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'boom');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Retry'), findsOneWidget);
  });
}
