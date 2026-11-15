import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A panel the test controls: categories, items, failures, slowness.
class FakePanel implements ProviderAdapter {
  FakePanel({this.liveCats = 3, this.movieCats = 4, this.seriesCats = 2, this.perCat = 5});

  int liveCats, movieCats, seriesCats, perCat;
  final calls = <String>[];
  final failCats = <String, ProviderFailure>{};
  Duration delay = Duration.zero;
  int inFlight = 0, peak = 0;

  @override
  ProviderKind get kind => ProviderKind.xtream;
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(live: true, movies: true, series: true);

  List<ProviderCategory> _cats(String p, int n) => [for (var i = 0; i < n; i++) ProviderCategory(id: '$p$i', name: '$p $i')];

  Future<T> _call<T>(String what, T Function() result) async {
    calls.add(what);
    inFlight++;
    peak = inFlight > peak ? inFlight : peak;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final cat = what.split(':').last;
      final f = failCats[cat];
      if (f != null) throw f;
      return result();
    } finally {
      inFlight--;
    }
  }

  @override
  Future<List<ProviderCategory>> liveCategories() => _call('cats:live', () => _cats('L', liveCats));
  @override
  Future<List<ProviderCategory>> movieCategories() => _call('cats:movie', () => _cats('M', movieCats));
  @override
  Future<List<ProviderCategory>> seriesCategories() => _call('cats:series', () => _cats('S', seriesCats));

  @override
  Future<List<ProviderChannel>> liveChannels({String? categoryId}) => _call('live:$categoryId', () => [
        for (var i = 0; i < perCat; i++)
          ProviderChannel(id: '$categoryId-$i', name: 'ch', stream: StreamRef(kind: MediaKind.live, id: '$categoryId-$i'), categoryId: categoryId),
      ]);
  @override
  Future<List<ProviderMovie>> movies({String? categoryId}) => _call('movie:$categoryId', () => [
        for (var i = 0; i < perCat; i++)
          ProviderMovie(id: '$categoryId-$i', name: 'mv', stream: StreamRef(kind: MediaKind.movie, id: '$categoryId-$i'),
              categoryId: categoryId, addedSec: 1000 + i),
      ]);
  @override
  Future<List<ProviderSeries>> series({String? categoryId}) => _call('series:$categoryId', () => [
        for (var i = 0; i < perCat; i++) ProviderSeries(id: '$categoryId-$i', name: 'sr', categoryId: categoryId),
      ]);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;
  var now = DateTime.utc(2026, 11, 15, 12);

  setUp(() {
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    now = DateTime.utc(2026, 11, 15, 12);
  });
  tearDown(() => store.close());

  CatalogSyncer syncer({SyncPolicy policy = const SyncPolicy()}) => CatalogSyncer(store: store, policy: policy, clock: () => now);

  test('full run: categories first, then every category; everything saved', () async {
    final panel = FakePanel();
    final s = syncer();
    final r = await s.sync('p', panel);
    expect(r.phase, SyncPhase.done);
    expect(panel.calls.take(3), ['cats:live', 'cats:movie', 'cats:series']);
    expect(r.items, (3 + 4 + 2) * 5);
    final c = await store.counts('p');
    expect([c.live, c.movies, c.series], [15, 20, 10]);
    expect(await store.categories('p', CatalogKind.movie), hasLength(4));
    expect((await store.syncInfo('p', 'movie:cat:M0'))!.maxAddedSec, 1004);
    expect(s.progress.value['p']!.phase, SyncPhase.done);
  });

  test('resumable: fresh categories are skipped; after the admin TTL they refresh; force refreshes all', () async {
    final panel = FakePanel();
    final s = syncer(policy: const SyncPolicy(ttl: Duration(hours: 6)));
    await s.sync('p', panel);
    panel.calls.clear();
    final again = await s.sync('p', panel);
    expect(panel.calls.where((c) => !c.startsWith('cats:')), isEmpty);
    expect(again.skipped, 9);
    now = now.add(const Duration(hours: 7));
    panel.calls.clear();
    await s.sync('p', panel);
    expect(panel.calls.where((c) => !c.startsWith('cats:')), hasLength(9));
    panel.calls.clear();
    await s.sync('p', panel, force: true);
    expect(panel.calls.where((c) => !c.startsWith('cats:')), hasLength(9));
  });

  test('cancel stops the run; the next run continues where it stopped', () async {
    final panel = FakePanel(liveCats: 10, movieCats: 0, seriesCats: 0)..delay = const Duration(milliseconds: 20);
    final s = syncer(policy: const SyncPolicy(parallelCategories: 1));
    // Cancel exactly after 3 live categories finished (no timing guesses).
    void onProgress() {
      final p = s.progress.value['p'];
      if (p != null && p.phase == SyncPhase.live && p.done == 3) s.cancel('p', reason: 'test');
    }
    s.progress.addListener(onProgress);
    final r = await s.sync('p', panel);
    s.progress.removeListener(onProgress);
    expect(r.phase, SyncPhase.stopped);
    final firstDone = panel.calls.where((c) => c.startsWith('live:')).length;
    expect(firstDone, inInclusiveRange(3, 4)); // the one in flight may finish
    panel.calls.clear();
    final r2 = await s.sync('p', panel);
    expect(r2.phase, SyncPhase.done);
    expect(panel.calls.where((c) => c.startsWith('live:')).length, 10 - firstDone);
  });

  test('one bad category is skipped; the rest is saved', () async {
    final panel = FakePanel()..failCats['M1'] = const ProviderFailure(ProviderFailureKind.timeout);
    final r = await syncer().sync('p', panel);
    expect(r.phase, SyncPhase.done);
    expect(r.failedCategories, 1);
    expect((await store.counts('p')).movies, 15);
    // Not marked synced → retried next run.
    expect(await store.syncInfo('p', 'movie:cat:M1'), isNull);
  });

  test('expired line stops at once', () async {
    final panel = FakePanel()..failCats['L0'] = const ProviderFailure(ProviderFailureKind.expired);
    final r = await syncer(policy: const SyncPolicy(parallelCategories: 1)).sync('p', panel);
    expect(r.phase, SyncPhase.failed);
    expect(r.failure!.kind, ProviderFailureKind.expired);
    expect(panel.calls.any((c) => c.startsWith('movie:')), isFalse);
  });

  test('panel down (many failures in a row) stops instead of hammering it', () async {
    final panel = FakePanel(liveCats: 20, movieCats: 0, seriesCats: 0);
    for (var i = 0; i < 20; i++) {
      panel.failCats['L$i'] = const ProviderFailure(ProviderFailureKind.network);
    }
    final r = await syncer(policy: const SyncPolicy(parallelCategories: 1, maxConsecutiveFailures: 3)).sync('p', panel);
    expect(r.phase, SyncPhase.failed);
    expect(panel.calls.where((c) => c.startsWith('live:')), hasLength(3));
  });

  test('never more categories at once than the admin allows', () async {
    final panel = FakePanel(liveCats: 12, movieCats: 0, seriesCats: 0)..delay = const Duration(milliseconds: 5);
    await syncer(policy: const SyncPolicy(parallelCategories: 3)).sync('p', panel);
    expect(panel.peak, 3);
  });

  test('categories removed on the panel disappear with their items', () async {
    final panel = FakePanel(liveCats: 0, movieCats: 4, seriesCats: 0);
    await syncer().sync('p', panel);
    expect((await store.counts('p')).movies, 20);
    panel.movieCats = 2;
    now = now.add(const Duration(days: 2));
    await syncer().sync('p', panel);
    expect((await store.counts('p')).movies, 10);
    expect(await store.categories('p', CatalogKind.movie), hasLength(2));
  });

  test('a second sync call while running joins the same run', () async {
    final panel = FakePanel()..delay = const Duration(milliseconds: 5);
    final s = syncer();
    final a = s.sync('p', panel);
    final b = s.sync('p', panel);
    expect(identical(await a, await b), isTrue);
    expect(panel.calls.where((c) => c == 'cats:live'), hasLength(1));
  });

  test('policy from the admin config, clamped', () {
    final c = RemoteConfig.tryParse({
      'version': 1,
      'settings': {'cache.catalog_ttl_hours': 3, 'cache.sync_parallel_categories': 50, 'cache.epg_retention_hours': 0},
    })!;
    final p = SyncPolicy.fromConfig(c);
    expect(p.ttl, const Duration(hours: 3));
    expect(p.parallelCategories, 6);
    expect(p.epgRetention, const Duration(hours: 1));
  });
}
