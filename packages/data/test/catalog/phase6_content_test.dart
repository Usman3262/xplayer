import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderMovie mv(String id, {String cat = 'c1', int? added, double? rating, int? tmdb, String? name, String ext = 'mkv'}) => ProviderMovie(
      id: id,
      name: name ?? 'Movie $id',
      stream: StreamRef(kind: MediaKind.movie, id: id, extension: ext),
      categoryId: cat,
      addedSec: added,
      rating: rating,
      tmdbId: tmdb,
    );

ProviderSeries sr(String id, {String cat = 's1', int? added, double? rating, int? tmdb, String? name}) =>
    ProviderSeries(id: id, name: name ?? 'Series $id', categoryId: cat, addedSec: added, rating: rating, tmdbId: tmdb);

class FakeAdapter implements ProviderAdapter {
  int seriesCalls = 0;
  final movieCalls = <String>[];
  @override
  Future<List<ProviderMovie>> movies({String? categoryId, bool priority = false}) async {
    movieCalls.add('$categoryId priority=$priority');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return [mv('n1', cat: categoryId!, added: 5), mv('n2', cat: categoryId, added: 6)];
  }
  @override
  ProviderKind get kind => ProviderKind.xtream;
  @override
  Future<ProviderMovieDetails> movieDetails(String id) async => ProviderMovieDetails(
        movie: mv(id), plot: 'Panel plot', durationSec: 5400, genres: const ['Drama']);
  @override
  Future<ProviderSeriesDetails> seriesDetails(String id) async {
    seriesCalls++;
    ProviderEpisode ep(int s, int n) => ProviderEpisode(
        id: '$id-$s-$n', seriesId: id, season: s, number: n, title: 'E$n',
        stream: StreamRef(kind: MediaKind.series, id: '$id-$s-$n', extension: 'mp4'));
    return ProviderSeriesDetails(series: sr(id), episodes: {1: [ep(1, 1), ep(1, 2)], 2: [ep(2, 1)]});
  }
  int epgCalls = 0;
  DateTime epgBase = DateTime.utc(2026, 11, 15, 12);
  @override
  Future<List<EpgEntry>> shortEpg(ProviderChannel channel, {int limit = 4}) async {
    epgCalls++;
    return [
      EpgEntry(title: 'News', start: epgBase.subtract(const Duration(minutes: 30)), end: epgBase.add(const Duration(minutes: 30))),
      EpgEntry(title: 'Sport', start: epgBase.add(const Duration(minutes: 30)), end: epgBase.add(const Duration(hours: 2))),
    ];
  }
  final resolved = <StreamRef>[];
  @override
  Future<ResolvedStream> resolveStream(StreamRef ref) async {
    resolved.add(ref);
    return ResolvedStream(url: Uri.parse('http://panel.test/${ref.kind.name}/${ref.id}.${ref.extension ?? 'ts'}'));
  }
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;
  final now = DateTime.utc(2026, 11, 15, 12);
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;

  setUp(() async {
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    await store.saveMovies('p', 'c1', [
      mv('1', added: nowSec - 86400 * 10, rating: 7, tmdb: 550),
      mv('2', added: nowSec - 3600, rating: 9.1, name: 'Dune (2021)'),
      mv('3', added: nowSec - 86400 * 2, rating: 5),
    ]);
    await store.saveMovies('p', 'c2', [mv('4', cat: 'c2', added: nowSec - 60, name: 'Interstellar')]);
    await store.saveSeries('p', 's1', [sr('s1', added: nowSec - 120, rating: 8.5, tmdb: 1399), sr('s2', added: nowSec - 86400 * 30)]);
    await store.saveChannels('p', 'n', [
      ProviderChannel(id: '100', name: 'News HD', stream: const StreamRef(kind: MediaKind.live, id: '100'), categoryId: 'n'),
    ]);
  });
  tearDown(() async {
    // Background metadata fetches finish before the database closes.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await store.close();
  });

  group('HomeContentResolver (6.4: rails from the panel, never TMDB lists)', () {
    HomeContentResolver home() => HomeContentResolver(store: store, panelId: 'p', clock: () => now);

    test('random source = daily picks: same all day, within the limit, from the panel', () async {
      const s = HomeSection(id: 'p', title: 'Picked for you', type: HomeSectionType.recommended,
          source: SectionSource.random, layout: SectionLayout.rail, limit: 3);
      final a = await home().section(s, HomeLayout.empty);
      final b = await home().section(s, HomeLayout.empty);
      expect(a.length, 3);
      expect(a.map((m) => m.id), b.map((m) => m.id));
      expect(a.every((m) => ['1', '2', '3', '4', 's1', 's2'].contains(m.id)), isTrue);
    });

    test('newest = panel "added" date, mixed kinds interleaved by date, days filter', () async {
      final all = await home().newest(ContentKind.mixed, limit: 10);
      expect(all.map((m) => m.id), ['4', 's1', '2', '3', '1', 's2']);
      final week = await home().newest(ContentKind.movie, limit: 10, days: 7);
      expect(week.map((m) => m.id), ['4', '2', '3']);
    });

    test('top rated from the panel rating', () async {
      expect((await home().topRated(ContentKind.movie, limit: 2)).map((m) => m.id), ['2', '1']);
    });

    test('admin picks: tmdb id → panel id (title must agree) → title; missing ones skipped', () async {
      final got = await home().refs(const [
        ContentRef(kind: ContentKind.movie, tmdbId: 550), // → 1
        ContentRef(kind: ContentKind.movie, panelItemId: '3', title: 'Something else entirely'), // id of another film → no
        ContentRef(kind: ContentKind.movie, panelItemId: '2', title: 'Dune'), // id + same title → 2
        ContentRef(kind: ContentKind.mixed, matchTitle: 'interstellar'), // by title → 4
        ContentRef(kind: ContentKind.series, tmdbId: 1399), // → s1
        ContentRef(kind: ContentKind.movie, tmdbId: 999999), // not on this panel
      ], limit: 10);
      expect(got.map((m) => m.id), ['1', '2', '4', 's1']);
    });

    test('sections from the admin config', () async {
      HomeSection s(Map<String, dynamic> j) => HomeSection.tryParse({'id': 'x', 'title': 'T', ...j})!;
      final layout = HomeLayout.fromJson({
        'top10': [
          {'id': 't1', 'title': 'Top', 'kind': 'movie', 'source': 'manual', 'items': [
            {'rank': 2, 'kind': 'movie', 'panel_id': '4', 'title': 'Interstellar'},
            {'rank': 1, 'kind': 'movie', 'tmdb': 550},
          ]},
        ],
      });
      final h = home();
      expect((await h.section(s({'type': 'top10', 'top10': 't1'}), layout)).map((m) => m.id), ['1', '4']);
      expect((await h.section(s({'type': 'recently_added', 'kind': 'series', 'limit': 5}), layout)).map((m) => m.id), ['s1', 's2']);
      expect((await h.section(s({'type': 'category', 'kind': 'movie', 'params': {'category_id': 'c2'}}), layout)).single.id, '4');
      expect((await h.section(s({'type': 'popular', 'kind': 'movie', 'source': 'provider_rating', 'limit': 1}), layout)).single.id, '2');
      expect(await h.section(s({'type': 'continue_watching'}), layout), isEmpty);
    });
  });

  group('MetadataResolver (6.3: on demand, cached, ≤25 per call)', () {
    late List<Map<String, dynamic>> calls;
    late bool down;
    MetadataResolver resolver({DateTime? at}) => MetadataResolver(
          store: store,
          clock: () => at ?? now,
          missRetry: const Duration(days: 7),
          fetch: (body) async {
            if (down) throw StateError('offline');
            calls.add(body);
            final items = body['items'] as List;
            return {
              'results': [
                for (final i in items)
                  (i as Map)['tmdb_id'] == 550
                      ? {'id': 'g1', 'kind': 'movie', 'title': 'Fight Club', 'tmdb_id': 550, 'overview': 'Global plot',
                         'poster_path': '/p.jpg', 'backdrop_path': '/b.jpg', 'rating': 8.4}
                      : null,
              ],
            };
          },
        );

    setUp(() {
      calls = [];
      down = false;
    });

    test('asks once, then answers from the cache (also "no match")', () async {
      const q1 = MetadataQuery(kind: CatalogKind.movie, tmdbId: 550);
      const q2 = MetadataQuery(kind: CatalogKind.movie, title: 'Unknown Film', year: 2001);
      final r = resolver();
      final first = await r.resolve([q1, q2]);
      expect(first[MetadataResolver.keyOf(q1)]!.overview, 'Global plot');
      expect(first[MetadataResolver.keyOf(q2)], isNull);
      expect(calls.single['action'], 'resolve');
      await r.resolve([q1, q2]);
      expect(calls, hasLength(1)); // cached, incl. the miss
      // After the retry period the miss is asked again (the hit is not).
      await resolver(at: now.add(const Duration(days: 8))).resolve([q1, q2]);
      expect(calls, hasLength(2));
      expect((calls.last['items'] as List).single, {'kind': 'movie', 'title': 'Unknown Film', 'year': 2001});
    });

    test('many screens at once: one queue, ≤2 calls in flight, each title asked once', () async {
      var inFlight = 0, peak = 0;
      final asked = <String>[];
      final r = MetadataResolver(
        store: store,
        clock: () => now,
        fetch: (body) async {
          inFlight++;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(const Duration(milliseconds: 15));
          inFlight--;
          final items = body['items'] as List;
          asked.addAll(items.map((i) => '${(i as Map)['title']}'));
          return {'results': [for (final _ in items) null]};
        },
      );
      // 12 screens, overlapping titles (0..59), all at the same moment.
      await Future.wait([
        for (var s = 0; s < 12; s++)
          r.resolve([for (var i = s * 4; i < s * 4 + 15; i++) MetadataQuery(kind: CatalogKind.movie, title: 'Film $i')]),
      ]);
      expect(peak, lessThanOrEqualTo(2));
      expect(asked.toSet().length, asked.length); // no title asked twice
      expect(asked.toSet().length, 59);
    });

    test('batches of at most 25', () async {
      await resolver().resolve([for (var i = 0; i < 60; i++) MetadataQuery(kind: CatalogKind.movie, title: 'Film $i')]);
      expect(calls.map((c) => (c['items'] as List).length), [25, 25, 10]);
    });

    test('server down → no throw, nothing cached, asked again next time', () async {
      down = true;
      const q = MetadataQuery(kind: CatalogKind.movie, tmdbId: 550);
      expect((await resolver().resolve([q]))[MetadataResolver.keyOf(q)], isNull); // unknown, not cached
      down = false;
      expect((await resolver().resolve([q]))[MetadataResolver.keyOf(q)], isNotNull);
    });

    test('global catalog (incl. admin edits) wins for plot / art / rating; panel title stays', () {
      final m = providerMovieToDomain(mv('1', name: 'AR: Fight Club 4K', rating: 6));
      final e = enrichMedia(m, const TitleMetadata(kind: CatalogKind.movie, id: 'g', title: 'Fight Club',
          overview: 'Admin-edited plot', posterPath: '/p.jpg', backdropPath: '/b.jpg', rating: 8.8), const ArtworkUrls());
      expect(e.title, 'AR: Fight Club 4K');
      expect(e.synopsis, 'Admin-edited plot');
      expect(e.posterUrl, 'https://image.tmdb.org/t/p/w342/p.jpg');
      expect(e.backdropUrl, 'https://image.tmdb.org/t/p/w1280/b.jpg');
      expect(e.rating, 8.8);
      expect(e.badges, isEmpty); // nothing internal leaks into what the UI shows
    });
  });

  group('PanelCatalogRepository (6.4: the screens\' data from the panel)', () {
    late FakeAdapter adapter;
    late List<Map<String, dynamic>> metaCalls;
    var arrived = 0;

    PanelCatalogRepository repo({HomeLayout layout = HomeLayout.empty}) => PanelCatalogRepository(
          store: store,
          panelId: 'p',
          adapter: () async => adapter,
          layout: () => layout,
          clock: () => now,
          onMetadataArrived: () => arrived++,
          metadata: MetadataResolver(
            store: store,
            clock: () => now,
            fetch: (b) async {
              metaCalls.add(b);
              return {'results': [for (final _ in b['items'] as List) {'id': 'g', 'kind': 'movie', 'title': 'X', 'overview': 'From global'}]};
            },
          ),
        );

    setUp(() {
      adapter = FakeAdapter();
      metaCalls = [];
      arrived = 0;
    });

    test('home feed: top from the admin list, newest movies/series, live; metadata fetched for on-screen titles', () async {
      final layout = HomeLayout.fromJson({
        'top10': [
          {'id': 't', 'title': 'Admin Top', 'kind': 'movie', 'source': 'provider_rating'},
        ],
      });
      final r = repo(layout: layout);
      final feed = await r.getHomeFeed();
      expect(feed.top10.first.id, '2'); // best rated first (admin chose "panel rating")
      expect(feed.liveChannels.single.name, 'News HD');
      expect(feed.arabicOriginals.map((s) => s.id), ['s1', 's2']);
      expect(feed.hero.id, '2');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(metaCalls, isNotEmpty);
      expect(arrived, 1);
      // Second load uses the cached metadata, no new call for the same titles.
      final calls = metaCalls.length;
      final again = await r.getHomeFeed();
      expect(again.top10.first.synopsis, 'From global');
      expect(metaCalls.length, calls);
    });

    test('browse: categories and keyset pages for movies / series / live', () async {
      final r = repo();
      expect((await r.getCategories(MediaKind.movie)), isEmpty); // categories saved by the sync, not here
      final p1 = await r.browse(kind: MediaKind.movie, categoryId: 'c1', limit: 2);
      final p2 = await r.browse(kind: MediaKind.movie, categoryId: 'c1', limit: 2, cursor: p1.nextCursor);
      expect([...p1.items, ...p2.items].map((m) => m.id), ['1', '2', '3']);
      expect(p2.hasMore, isFalse);
      final live = await r.browse(kind: MediaKind.live, categoryId: 'n');
      expect(live.items.single.isLive, isTrue);
    });

    test('details: panel plot + runtime, container extension known for playback', () async {
      final r = repo();
      final m = (await r.getById('1', kind: MediaKind.movie))!;
      expect(m.durationLabel, '1h 30m');
      expect(m.genres, ['Drama']);
      expect(r.knownContainerExtension('1'), 'mkv');
      expect((await r.getById('100'))!.isLive, isTrue);
      expect(await r.getById('nope'), isNull);
    });

    test('episodes fetched from the panel once, then stored', () async {
      final r = repo();
      expect(await r.getSeasonNumbers('s1'), [1, 2]);
      expect((await r.getEpisodes('s1', season: 1)).map((e) => e.number), [1, 2]);
      expect(r.knownSeriesIdForEpisode('s1-1-2'), 's1');
      expect(r.knownContainerExtension('s1-1-2'), 'mp4');
      await repo().getEpisodes('s1', season: 2); // new repository, same store
      expect(adapter.seriesCalls, 1);
    });

    test('opening a category the sync has not reached: fetched now with priority, once', () async {
      final r = repo();
      final pages = await Future.wait([
        r.browse(kind: MediaKind.movie, categoryId: 'new-cat'),
        r.browse(kind: MediaKind.movie, categoryId: 'new-cat'), // screen asks twice
      ]);
      expect(pages.first.items.map((m) => m.id), ['n1', 'n2']);
      expect(adapter.movieCalls, ['new-cat priority=true']);
      // Now stored + marked synced: no more requests.
      await r.browse(kind: MediaKind.movie, categoryId: 'new-cat');
      expect(adapter.movieCalls, hasLength(1));
    });

    test('search across movies / series / live', () async {
      final res = await repo().search('inter');
      expect(res.map((m) => m.id), ['4']);
      expect((await repo().search('news')).single.kind, MediaKind.live);
      expect(await repo().search('%'), isEmpty);
    });

    test('related = same panel category', () async {
      expect((await repo().getRelated('1')).map((m) => m.id), ['2', '3']);
    });
  });

  group('7.6 playback straight from the panel', () {
    late FakeAdapter adapter;
    setUp(() => adapter = FakeAdapter());
    PanelCatalogRepository repo() =>
        PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => adapter, layout: () => HomeLayout.empty, clock: () => now);

    test('movie: stored stream (with its container) → adapter link', () async {
      final s = await repo().resolvePlayback('2', kind: MediaKind.movie);
      expect(s!.url.toString(), 'http://panel.test/movie/2.mkv');
      expect(adapter.resolved.single.kind, MediaKind.movie);
    });

    test('live channel, also when the kind is unknown', () async {
      expect((await repo().resolvePlayback('100', kind: MediaKind.live))!.url.path, '/live/100.ts');
      expect((await repo().resolvePlayback('100'))!.url.path, '/live/100.ts');
    });

    test('episode: found in the series episode list (fetched once, then stored)', () async {
      final r = repo();
      final s = await r.resolvePlayback('s1-2-1', kind: MediaKind.series, seriesId: 's1');
      expect(s!.url.path, '/series/s1-2-1.mp4');
      await r.resolvePlayback('s1-1-2', kind: MediaKind.series, seriesId: 's1');
      expect(adapter.seriesCalls, 1);
    });

    test('episode id alone works after its list was opened (Continue Watching)', () async {
      final r = repo();
      await r.getEpisodes('s1', season: 1);
      expect((await r.resolvePlayback('s1-1-1', kind: MediaKind.series))!.url.path, '/series/s1-1-1.mp4');
    });

    test('unknown id → null, no request to the panel', () async {
      expect(await repo().resolvePlayback('nope', kind: MediaKind.movie), isNull);
      expect(adapter.resolved, isEmpty);
    });
  });

  group('7.2 live guide', () {
    test('asks the panel once, then the stored guide (no request per open)', () async {
      final adapter = FakeAdapter();
      final r = PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => adapter, clock: () => now);
      final a = await r.liveGuide('100');
      expect(a.map((e) => e.title), ['News', 'Sport']);
      expect(a.first.isOnAt(now), isTrue);
      final b = await r.liveGuide('100');
      expect(b.map((e) => e.title), ['News', 'Sport']);
      expect(adapter.epgCalls, 1);
    });

    test('a channel without a guide is not asked again for 15 minutes', () async {
      final adapter = FakeAdapter()..epgBase = DateTime.utc(2020);
      final r = PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => adapter, clock: () => now);
      expect(await r.liveGuide('100'), isEmpty);
      expect(await r.liveGuide('100'), isEmpty);
      expect(adapter.epgCalls, 1);
    });
  });
}
