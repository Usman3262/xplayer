// LIVE (opt-in): full sync of a real panel with the request budget — count
// the HTTP requests actually sent.
//   XPLAYER_LIVE_TESTS=1 XPLAYER_LIVE_PANEL=neo flutter test test/catalog/budget_live_test.dart
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../providers/live_panel.dart';

/// Counts every request that leaves the app.
class CountingClient extends http.BaseClient {
  final inner = http.Client();
  final actions = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    actions.add(r.url.queryParameters['action'] ?? 'login');
    return inner.send(r);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final panel = livePanel();

  test('LIVE: full catalog with minimum requests', () async {
    final client = CountingClient();
    final store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    final adapter = XtreamAdapter(panel!, http: ProviderHttp(client: client));
    await adapter.authenticate();
    final sw = Stopwatch()..start();
    final r = await CatalogSyncer(store: store, policy: const SyncPolicy()).sync('b', adapter);
    final syncMs = sw.elapsedMilliseconds;
    final c = await store.counts('b');
    final repo = PanelCatalogRepository(store: store, panelId: 'b', adapter: () async => adapter);
    final feed = await repo.getHomeFeed();
    final cats = await repo.getCategories(MediaKind.movie);
    final page = await repo.browse(kind: MediaKind.movie, categoryId: cats[cats.length ~/ 2].id, limit: 20);
    // ignore: avoid_print
    print('LIVE budget: ${r.phase.name} in ${(syncMs / 1000).toStringAsFixed(1)}s — ${client.actions.length} requests '
        '(${client.actions.join(', ')})\n'
        '  stored: ${c.live} live / ${c.movies} movies / ${c.series} series; home top ${feed.top10.length}, '
        'movie categories ${cats.length}, a middle category page ${page.items.length}');
    expect(r.phase, SyncPhase.done);
    expect(client.actions.length, lessThan(12)); // was ~300 (one per category)
    adapter.dispose();
    await store.close();
  }, skip: panel == null ? liveSkip : false, timeout: const Timeout(Duration(minutes: 5)));
}
