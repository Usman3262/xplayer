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
  Map<MediaKind, ListStrategy> lists = const {};
  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(live: true, movies: true, series: true, lists: lists);

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
  Future<List<ProviderChannel>> liveChannels({String? categoryId, bool priority = false}) => _call('live:$categoryId', () => [
        for (var i = 0; i < perCat; i++)
          ProviderChannel(id: '$categoryId-$i', name: 'ch', stream: StreamRef(kind: MediaKind.live, id: '$categoryId-$i'), categoryId: categoryId),
      ]);
  @override
  Future<List<ProviderMovie>> movies({String? categoryId, bool priority = false}) => _call('movie:$categoryId', () => [
        for (var i = 0; i < perCat; i++)
          ProviderMovie(id: '$categoryId-$i', name: 'mv', stream: StreamRef(kind: MediaKind.movie, id: '$categoryId-$i'),
              categoryId: categoryId, addedSec: 1000 + i),
      ]);
  @override
  Future<List<ProviderSeries>> series({String? categoryId, bool priority = false}) => _call('series:$categoryId', () => [
        for (var i = 0; i < perCat; i++) ProviderSeries(id: '$categoryId-$i', name: 'sr', categoryId: categoryId),
      ]);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const fast = SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 2);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;
  var now = DateTime.utc(2026, 11, 15, 12);

  setUp(() {
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    now = DateTime.utc(2026, 11, 15, 12);
  });
  tearDown(() => store.close());

  CatalogSyncer syncer({SyncPolicy policy = fast}) => CatalogSyncer(store: store, policy: policy, clock: () => now);

  test('full run: categories first, then every category; everything saved', () async {
    final panel = FakePanel();
    final s = syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 1));
    final r = await s.sync('p', panel);
    expect(r.phase, SyncPhase.done);
    expect(panel.calls.take(3), ['cats:live', 'cats:movie', 'cats:series']);
    // Home warm-up first (2 movie, 2 series, 1 live category), then movies →
    // series → live.
    expect(panel.calls.skip(3).toList(), [
      'movie:M0', 'movie:M1', 'series:S0', 'series:S1', 'live:L0',
      'movie:M2', 'movie:M3', 'live:L1', 'live:L2',
    ]);
    expect(r.items, (3 + 4 + 2) * 5);
    final c = await store.counts('p');
    expect([c.live, c.movies, c.series], [15, 20, 10]);
    expect(await store.categories('p', CatalogKind.movie), hasLength(4));
    expect((await store.syncInfo('p', 'movie:cat:M0'))!.maxAddedSec, 1004);
    expect(s.progress.value['p']!.phase, SyncPhase.done);
  });

  test('resumable: fresh categories are skipped; after the admin TTL they refresh; force refreshes all', () async {
    final panel = FakePanel();
    final s = syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, ttl: Duration(hours: 6)));
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
    final s = syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 1));
    // Cancel exactly after 3 live categories finished (no timing guesses).
    void onProgress() {
      final p = s.progress.value['p'];
      if (p != null && p.phase == SyncPhase.items && p.done == 3) s.cancel('p', reason: 'test');
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
    final panel = FakePanel()..failCats['M0'] = const ProviderFailure(ProviderFailureKind.expired);
    final r = await syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 1)).sync('p', panel);
    expect(r.phase, SyncPhase.failed);
    expect(r.failure!.kind, ProviderFailureKind.expired);
    // The first category failed → nothing after it was asked.
    expect(panel.calls.where((c) => !c.startsWith('cats:')), ['movie:M0']);
  });

  test('panel down (many failures in a row) stops instead of hammering it', () async {
    final panel = FakePanel(liveCats: 20, movieCats: 0, seriesCats: 0);
    for (var i = 0; i < 20; i++) {
      panel.failCats['L$i'] = const ProviderFailure(ProviderFailureKind.network);
    }
    final r = await syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 1, maxConsecutiveFailures: 3)).sync('p', panel);
    expect(r.phase, SyncPhase.failed);
    expect(panel.calls.where((c) => c.startsWith('live:')), hasLength(3));
  });

  test('never more categories at once than the admin allows', () async {
    final panel = FakePanel(liveCats: 12, movieCats: 0, seriesCats: 0)..delay = const Duration(milliseconds: 5);
    await syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 3)).sync('p', panel);
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
      'settings': {'cache.catalog_ttl_hours': 3, 'cache.sync_parallel_categories': 50, 'cache.epg_retention_hours': 0, 'cache.sync_gap_ms': 99999},
    })!;
    final p = SyncPolicy.fromConfig(c);
    expect(p.ttl, const Duration(hours: 3));
    expect(p.parallelCategories, 6);
    expect(p.epgRetention, const Duration(hours: 1));
    expect(p.gap, const Duration(seconds: 5));
    // Defaults are gentle: one category at a time, 300 ms apart.
    expect(SyncPolicy.fromConfig(RemoteConfig.empty).parallelCategories, 1);
    expect(SyncPolicy.fromConfig(RemoteConfig.empty).gap, const Duration(milliseconds: 300));
  });

  test('pause between category requests is respected', () async {
    final panel = FakePanel(liveCats: 4, movieCats: 0, seriesCats: 0);
    final sw = Stopwatch()..start();
    await syncer(policy: const SyncPolicy(gap: Duration(milliseconds: 50), failureBackoff: Duration.zero)).sync('p', panel);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(200)); // 4 categories × 50 ms, one at a time
  });

  group('request budget', () {
    test('bulk: the whole kind in ONE request, saved into its categories', () async {
      final panel = FakePanel(liveCats: 3, movieCats: 4, seriesCats: 2)
        ..lists = const {MediaKind.movie: ListStrategy.bulkIfSmall, MediaKind.live: ListStrategy.bulk};
      final r = await syncer().sync('p', panel);
      expect(r.phase, SyncPhase.done);
      final requests = panel.calls.where((c) => !c.startsWith('cats:')).toList();
      // movies 1 + series 2 (per category) + live 1 = 4 requests instead of 9.
      expect(requests.where((c) => c == 'movie:null'), hasLength(1));
      expect(requests.where((c) => c == 'live:null'), hasLength(1));
      expect(requests.where((c) => c.startsWith('series:')), hasLength(2));
      expect(requests, hasLength(4));
      expect((await store.syncInfo('p', 'movie:cat:M2')), isNotNull); // categories marked fresh
      // Fresh → a second run sends nothing but the category lists.
      panel.calls.clear();
      await syncer().sync('p', panel);
      expect(panel.calls.where((c) => !c.startsWith('cats:')), isEmpty);
    });

    test('bulkIfSmall: a huge panel goes category by category', () async {
      final panel = FakePanel(liveCats: 0, movieCats: 5, seriesCats: 0)..lists = const {MediaKind.movie: ListStrategy.bulkIfSmall};
      await syncer(policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, bulkMaxCategories: 3)).sync('p', panel);
      expect(panel.calls.where((c) => c.startsWith('movie:')), hasLength(5));
      expect(panel.calls, isNot(contains('movie:null')));
    });

    test('onDemand (Stalker VOD): only the Home warm-up categories in the background', () async {
      final panel = FakePanel(liveCats: 0, movieCats: 10, seriesCats: 10)
        ..lists = const {MediaKind.movie: ListStrategy.onDemand, MediaKind.series: ListStrategy.onDemand};
      await syncer().sync('p', panel);
      expect(panel.calls.where((c) => c.startsWith('movie:')).toList(), ['movie:M0', 'movie:M1']);
      expect(panel.calls.where((c) => c.startsWith('series:')).toList(), ['series:S0', 'series:S1']);
    });

    test('blocked panel → cool-down: no requests on the next runs (even after restart) until it ends', () async {
      final panel = FakePanel(liveCats: 6, movieCats: 0, seriesCats: 0);
      for (var i = 0; i < 6; i++) {
        panel.failCats['L$i'] = const ProviderFailure(ProviderFailureKind.timeout);
      }
      final policy = const SyncPolicy(
          gap: Duration.zero, failureBackoff: Duration.zero, maxConsecutiveFailures: 2, cooldown: Duration(minutes: 30));
      expect((await syncer(policy: policy).sync('p', panel)).phase, SyncPhase.failed);
      panel.calls.clear();
      // "App restart": a new syncer on the same database.
      final again = await syncer(policy: policy).sync('p', panel);
      expect(again.phase, SyncPhase.stopped);
      expect(panel.calls, isEmpty);
      // Pull-to-refresh (force) still tries.
      panel.failCats.clear();
      expect((await syncer(policy: policy).sync('p', panel, force: true)).phase, SyncPhase.done);
      // Success cleared the cool-down.
      now = now.add(const Duration(days: 1));
      panel.calls.clear();
      await syncer(policy: policy).sync('p', panel);
      expect(panel.calls, isNotEmpty);
    });
  });
}
