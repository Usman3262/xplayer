// LIVE (opt-in): the device problem of 2026-11-15 — opening a series while the
// background sync is busy timed out. Reproduce: sync series categories and,
// at the same time, open a series (seasons + episodes together, like the
// screen) and a movie's details. Gentle: 6 categories per kind.
//   XPLAYER_LIVE_TESTS=1 XPLAYER_LIVE_PANEL=trial flutter test test/catalog/busy_panel_live_test.dart
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../providers/live_panel.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final panel = livePanel();

  test('LIVE: user requests stay fast while the sync is busy', () async {
    final store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    final adapter = XtreamAdapter(panel!, http: ProviderHttp(limits: const ProviderLimits(concurrency: 4)));
    await adapter.authenticate();
    // A first small sync so there are series/movies to open.
    final syncer = CatalogSyncer(store: store, policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 2));
    await syncer.sync('t', adapter, maxCategoriesPerKind: 2);
    final repo = PanelCatalogRepository(store: store, panelId: 't', adapter: () async => adapter);
    final seriesCats = await repo.getCategories(MediaKind.series);
    final series = (await repo.browse(kind: MediaKind.series, categoryId: seriesCats.first.id, limit: 3)).items;
    final movie = (await repo.browse(kind: MediaKind.movie, limit: 1)).items.first;

    // Busy: a forced sync of 6 categories per kind runs in the background...
    final busy = syncer.sync('t', adapter, force: true, maxCategoriesPerKind: 6);
    await Future<void>.delayed(const Duration(seconds: 2));
    // ...while the user opens a series (both calls at once) and a movie.
    final sw = Stopwatch()..start();
    final opened = await Future.wait([
      repo.getSeasonNumbers(series.first.id),
      repo.getEpisodes(series.first.id, season: 1),
      repo.getById(movie.id, kind: MediaKind.movie),
    ]);
    final userMs = sw.elapsedMilliseconds;
    final seasons = opened[0] as List<int>;
    final eps = opened[1] as List<Episode>;
    final details = opened[2] as MediaItem?;
    final sync = await busy;
    // ignore: avoid_print
    print('LIVE busy panel: series "${series.first.title}" seasons $seasons, episodes ${eps.length}, '
        'movie details ${details?.durationLabel ?? '-'} — user waited ${userMs}ms while sync was '
        '${sync.phase.name} (${sync.items} items, ${sync.failedCategories} failed)');
    expect(seasons, isNotEmpty);
    expect(userMs, lessThan(20000));
    adapter.dispose();
    await store.close();
  }, skip: panel == null ? liveSkip : false, timeout: const Timeout(Duration(minutes: 5)));
}
