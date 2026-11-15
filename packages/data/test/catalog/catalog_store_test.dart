import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderMovie mv(String id, {String? cat, int? added, String? name}) => ProviderMovie(
      id: id,
      name: name ?? 'Movie $id',
      stream: StreamRef(kind: MediaKind.movie, id: id, extension: 'mkv'),
      categoryId: cat,
      addedSec: added,
      tmdbId: int.tryParse(id),
    );

ProviderChannel ch(String id, String cat, {String? cmd}) => ProviderChannel(
      id: id,
      name: 'Ch $id',
      stream: StreamRef(kind: MediaKind.live, id: id, command: cmd),
      categoryId: cat,
      number: int.parse(id),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;

  setUp(() => store = CatalogStore(CatalogDb(NativeDatabase.memory())));
  tearDown(() => store.close());

  test('categories: replaced per kind, panel order kept', () async {
    await store.saveCategories('p1', CatalogKind.movie, const [
      ProviderCategory(id: '9', name: 'Action'),
      ProviderCategory(id: '2', name: 'Drama'),
    ]);
    await store.saveCategories('p1', CatalogKind.live, const [ProviderCategory(id: '1', name: 'News')]);
    expect((await store.categories('p1', CatalogKind.movie)).map((c) => c.name), ['Action', 'Drama']);
    await store.saveCategories('p1', CatalogKind.movie, const [ProviderCategory(id: '3', name: 'Kids')]);
    expect((await store.categories('p1', CatalogKind.movie)).map((c) => c.id), ['3']);
    expect(await store.categories('p1', CatalogKind.live), hasLength(1)); // other kind untouched
  });

  test('saving one category replaces only that category; items removed on the panel disappear', () async {
    await store.saveMovies('p1', 'a', [mv('1', cat: 'a'), mv('2', cat: 'a')]);
    await store.saveMovies('p1', 'b', [mv('3', cat: 'b')]);
    await store.saveMovies('p1', 'a', [mv('2', cat: 'a', name: 'Renamed'), mv('4', cat: 'a')]);
    final a = (await store.movies('p1', categoryId: 'a')).map((r) => r.$1).toList();
    expect(a.map((m) => m.id), ['2', '4']);
    expect(a.first.name, 'Renamed');
    expect((await store.movies('p1', categoryId: 'b')).single.$1.id, '3');
    expect((await store.movie('p1', '1')), isNull);
    final back = (await store.movie('p1', '4'))!;
    expect(back.stream.extension, 'mkv');
    expect(back.tmdbId, 4);
  });

  test('keyset paging in panel order', () async {
    await store.saveChannels('p1', 'news', [for (var i = 1; i <= 25; i++) ch('$i', 'news', cmd: 'ffmpeg http://x/$i')]);
    final p1 = await store.channels('p1', categoryId: 'news', limit: 10);
    final p2 = await store.channels('p1', categoryId: 'news', limit: 10, afterSort: p1.last.$2);
    final p3 = await store.channels('p1', categoryId: 'news', limit: 10, afterSort: p2.last.$2);
    expect([...p1, ...p2, ...p3].map((r) => r.$1.id), [for (var i = 1; i <= 25; i++) '$i']);
    expect(p3, hasLength(5));
    expect(p1.first.$1.stream.command, 'ffmpeg http://x/1');
  });

  test('newest movies from the panel "added" date, keyset across equal dates', () async {
    await store.saveMovies('p1', 'a', [
      mv('1', cat: 'a', added: 100),
      mv('2', cat: 'a', added: 300),
      mv('3', cat: 'a', added: 300),
      mv('4', cat: 'a'), // no date → not in "newest"
      mv('5', cat: 'a', added: 200),
    ]);
    final first = await store.newestMovies('p1', limit: 2);
    expect(first.map((m) => m.id), ['3', '2']);
    final next = await store.newestMovies('p1', limit: 5, after: first.last);
    expect(next.map((m) => m.id), ['5', '1']);
  });

  test('series details: episodes saved when opened, read back by season/number', () async {
    await store.saveSeries('p1', 'drama', const [ProviderSeries(id: 's1', name: 'Show', categoryId: 'drama', genres: ['Drama', 'Comedy'])]);
    expect(await store.seriesDetails('p1', 's1'), isNull); // never opened yet
    ProviderEpisode ep(String id, int s, int n) => ProviderEpisode(
          id: id, seriesId: 's1', season: s, number: n, title: 'E$n',
          stream: StreamRef(kind: MediaKind.series, id: id, extension: 'mp4'),
        );
    await store.saveSeriesDetails('p1', ProviderSeriesDetails(
      series: const ProviderSeries(id: 's1', name: 'Show', plot: 'Now with plot'),
      episodes: {2: [ep('e3', 2, 1)], 1: [ep('e2', 1, 2), ep('e1', 1, 1)]},
    ));
    final d = (await store.seriesDetails('p1', 's1'))!;
    expect(d.seasonNumbers, [1, 2]);
    expect(d.episodes[1]!.map((e) => e.id), ['e1', 'e2']);
    expect(d.series.plot, 'Now with plot');
    // The series stays in its category after details refresh.
    expect((await store.series('p1', categoryId: 'drama')).single.$1.id, 's1');
  });

  test('EPG: only programmes not yet ended; prune old ones', () async {
    final t0 = DateTime.utc(2026, 11, 15, 20);
    EpgEntry e(int h, String title) => EpgEntry(title: title, start: t0.add(Duration(hours: h)), end: t0.add(Duration(hours: h + 1)));
    await store.saveEpg('p1', '7', [e(-2, 'Old'), e(0, 'Now'), e(1, 'Next')]);
    await store.saveEpg('p1', '7', [e(1, 'Next (updated)')]);
    final list = await store.epg('p1', '7', from: t0.add(const Duration(minutes: 30)));
    expect(list.map((x) => x.title), ['Now', 'Next (updated)']);
    expect(await store.pruneEpg('p1', t0), 1);
  });

  test('sync bookkeeping', () async {
    final at = DateTime.utc(2026, 11, 15, 12);
    await store.markSynced('p1', 'movie:cat:a', at: at, count: 657, maxAddedSec: 1794417540);
    final i = (await store.syncInfo('p1', 'movie:cat:a'))!;
    expect(i.syncedAt, at);
    expect(i.itemCount, 657);
    expect(i.maxAddedSec, 1794417540);
    expect(await store.syncInfo('p1', 'nope'), isNull);
  });

  test('panels never mix; clearing one leaves the other', () async {
    await store.saveMovies('p1', 'a', [mv('1', cat: 'a')]);
    await store.saveMovies('p2', 'a', [mv('1', cat: 'a', name: 'Other panel')]);
    await store.saveChannels('p1', 'n', [ch('5', 'n')]);
    expect((await store.movie('p2', '1'))!.name, 'Other panel');
    await store.clearPanel('p1');
    expect((await store.counts('p1')).movies, 0);
    expect((await store.counts('p1')).live, 0);
    expect((await store.counts('p2')).movies, 1);
  });

  test('big panel: 60k movies in 90 categories — write and page fast', () async {
    final sw = Stopwatch()..start();
    for (var c = 0; c < 90; c++) {
      await store.saveMovies('big', 'c$c', [
        for (var i = 0; i < 667; i++) mv('${c * 1000 + i}', cat: 'c$c', added: 1700000000 + c * 1000 + i),
      ]);
    }
    final writeMs = sw.elapsedMilliseconds;
    sw.reset();
    final page = await store.movies('big', categoryId: 'c45', limit: 60);
    final newest = await store.newestMovies('big', limit: 20);
    final readMs = sw.elapsedMilliseconds;
    expect((await store.counts('big')).movies, 90 * 667);
    expect(page, hasLength(60));
    expect(newest.first.id, '89666');
    // ignore: avoid_print
    print('60k movies: write ${writeMs}ms (90 category transactions), category page + newest read ${readMs}ms');
    expect(readMs, lessThan(500));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
