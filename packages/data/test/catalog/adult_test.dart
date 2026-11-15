import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Series categories like a real panel: one adult by name, one by flag.
class AdultPanel implements ProviderAdapter {
  @override
  ProviderKind get kind => ProviderKind.xtream;
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(live: true, movies: true, series: true);
  @override
  Future<List<ProviderCategory>> liveCategories() async => const [
        ProviderCategory(id: 'l1', name: 'UK | Sussex & Essex Local'),
        ProviderCategory(id: 'l2', name: 'XXX | Night'),
      ];
  @override
  Future<List<ProviderCategory>> movieCategories() async => const [ProviderCategory(id: 'm1', name: 'Movies')];
  @override
  Future<List<ProviderCategory>> seriesCategories() async => const [
        ProviderCategory(id: 's1', name: 'Drama'),
        ProviderCategory(id: 's2', name: 'FOR ADULTS 18+'),
        ProviderCategory(id: 's3', name: 'Night shows', adult: true), // panel flag (Stalker censored)
      ];
  @override
  Future<List<ProviderChannel>> liveChannels({String? categoryId, bool priority = false}) async => [
        ProviderChannel(id: '${categoryId}c', name: 'Ch $categoryId', stream: StreamRef(kind: MediaKind.live, id: '${categoryId}c'), categoryId: categoryId),
      ];
  @override
  Future<List<ProviderMovie>> movies({String? categoryId, bool priority = false}) async => [
        ProviderMovie(id: 'mv1', name: 'Family film', stream: const StreamRef(kind: MediaKind.movie, id: 'mv1'), categoryId: categoryId, addedSec: 10, rating: 6),
        // Item flagged adult inside a normal category (Xtream is_adult).
        ProviderMovie(id: 'mv2', name: 'Late film', stream: const StreamRef(kind: MediaKind.movie, id: 'mv2'), categoryId: categoryId, addedSec: 20, rating: 9, adult: true),
      ];
  @override
  Future<List<ProviderSeries>> series({String? categoryId, bool priority = false}) async => [
        ProviderSeries(id: '${categoryId}x', name: 'Show $categoryId', categoryId: categoryId, addedSec: 100, rating: 8),
      ];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('classifier: whole words, symbols, Arabic; not Sussex / Essex', () {
    final c = AdultClassifier();
    expect(c.isAdultName('UK | Sussex & Essex Local'), isFalse);
    expect(c.isAdultName('Middlesex News'), isFalse);
    expect(c.isAdultName('XXX | Night'), isTrue);
    expect(c.isAdultName('FOR ADULTS 18+'), isTrue);
    expect(c.isAdultName('+18 Channels'), isTrue);
    expect(c.isAdultName('Sex Education (2019)'), isTrue); // conservative: word "sex"
    expect(c.isAdultName('أفلام للكبار'), isTrue);
    expect(c.isAdultName('Kids'), isFalse);
    expect(AdultClassifier(const ['nightlife']).isAdultName('XXX'), isFalse); // admin list replaces defaults
    expect(c.isAdultCategory('Drama', panelFlag: true), isTrue);
  });

  group('catalog with adult content', () {
    late CatalogStore store;
    late PanelCatalogRepository repo;

    setUp(() async {
      store = CatalogStore(CatalogDb(NativeDatabase.memory()));
      await CatalogSyncer(store: store, policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero))
          .sync('p', AdultPanel());
      repo = PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => null);
    });
    tearDown(() => store.close());

    test('normal screens never show 18+ categories or items', () async {
      expect((await repo.getCategories(MediaKind.series)).map((c) => c.id), ['s1']);
      expect((await repo.getCategories(MediaKind.live)).map((c) => c.id), ['l1']); // Sussex stays
      expect((await repo.getMovies()).map((m) => m.id), ['mv1']); // flagged item hidden
      expect((await repo.getTrending()).map((m) => m.id), isNot(contains('mv2'))); // top rated
      expect((await repo.getSeries()).map((m) => m.id), ['s1x']);
      expect(await repo.search('Show'), hasLength(1));
      expect(await repo.search('Late film'), isEmpty);
      final feed = await repo.getHomeFeed();
      expect(feed.top10.map((m) => m.id), isNot(contains('mv2')));
      expect(feed.liveChannels.map((c) => c.id), ['l1c']);
    });

    test('adult view (after the PIN) shows only 18+', () async {
      expect(await repo.hasAdult(MediaKind.series), isTrue);
      expect(await repo.hasAdult(MediaKind.movie), isFalse); // no adult movie category
      final adult = repo.adultView();
      expect((await adult.getCategories(MediaKind.series)).map((c) => c.id), ['s2', 's3']);
      final page = await adult.browse(kind: MediaKind.series, categoryId: 's2');
      expect(page.items.single.id, 's2x');
      expect((await adult.search('Show')).map((m) => m.id).toSet(), {'s2x', 's3x'});
      expect(await adult.browse(kind: MediaKind.series, categoryId: 's1'), isA<CatalogPage<MediaItem>>());
      expect((await adult.browse(kind: MediaKind.series, categoryId: 's1')).items, isEmpty);
    });

    test('a category that becomes adult hides the items already stored (no re-sync needed)', () async {
      await store.saveCategories('p', CatalogKind.series, const [
        ProviderCategory(id: 's1', name: 'Drama now XXX'),
      ], isAdult: (c) => AdultClassifier().isAdultName(c.name));
      expect(await repo.getSeries(), isEmpty);
    });
  });

  test('Stalker: the panel PIN (parent_password) is read at login', () async {
    final profile = jsonDecode(File('test/fixtures/stalker/get_profile.json').readAsStringSync());
    final a = StalkerAdapter(
      const StalkerCredentials(portal: 'http://portal.example/c/', mac: '00:1A:79:F0:06:3B'),
      http: ProviderHttp(client: MockClient((r) async {
        final action = r.url.queryParameters['action'];
        final body = switch (action) {
          'handshake' => {'js': {'token': 'T'}},
          'get_profile' => profile,
          _ => {'js': {'phone': 'December 1, 2030, 9:00 am'}},
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      })),
    );
    expect(a.parentalPin, isNull);
    await a.authenticate();
    expect(a.parentalPin, '0000');
  });
}
