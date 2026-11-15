// LIVE (opt-in): Phase 6 end to end with a real panel and the real
// `metadata-tmdb` Edge Function. Gentle: 2 categories per kind.
//   XPLAYER_LIVE_TESTS=1 XPLAYER_LIVE_PANEL=neo flutter test test/catalog/phase6_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../providers/live_panel.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final panel = livePanel();
  final envFile = File('../../env/app.json');

  test('LIVE: sync → home → posters (metadata-tmdb) → browse → details → episodes → search', () async {
    final env = jsonDecode(envFile.readAsStringSync()) as Map;
    final url = '${env['SUPABASE_URL']}', key = '${env['SUPABASE_PUBLISHABLE_KEY']}';
    final store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    final adapter = XtreamAdapter(panel!);
    final sw = Stopwatch()..start();

    final acc = await adapter.authenticate();
    expect(acc.status, ConnectionStatus.active);

    final sync = await CatalogSyncer(store: store, policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero, parallelCategories: 2))
        .sync('live', adapter, maxCategoriesPerKind: 2);
    expect(sync.phase, SyncPhase.done);
    final counts = await store.counts('live');

    var metaCalls = 0;
    final metadata = MetadataResolver(
      store: store,
      fetch: (body) async {
        metaCalls++;
        final res = await http.post(Uri.parse('$url/functions/v1/metadata-tmdb'),
            headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'}, body: jsonEncode(body));
        if (res.statusCode != 200) throw StateError('metadata-tmdb HTTP ${res.statusCode}: ${res.body}');
        return jsonDecode(res.body);
      },
    );
    var arrived = 0;
    final repo = PanelCatalogRepository(
      store: store, panelId: 'live', adapter: () async => adapter, metadata: metadata, onMetadataArrived: () => arrived++);

    final home = await repo.getHomeFeed();
    expect(home.top10, isNotEmpty);
    // Wait for the background poster fetch, then load again (as the app does).
    for (var i = 0; i < 40 && arrived == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final home2 = await repo.getHomeFeed();
    final withPlot = home2.top10.where((m) => (m.synopsis ?? '').isNotEmpty).length;
    final withBackdrop = home2.top10.where((m) => m.backdropUrl != null).length;

    final cats = await repo.getCategories(MediaKind.movie);
    final page = await repo.browse(kind: MediaKind.movie, categoryId: cats.first.id, limit: 20);
    final firstMovie = page.items.first;
    final details = await repo.getById(firstMovie.id, kind: MediaKind.movie);
    final seriesCats = await repo.getCategories(MediaKind.series);
    final seriesPage = await repo.browse(kind: MediaKind.series, categoryId: seriesCats.first.id, limit: 5);
    final seasons = seriesPage.items.isEmpty ? <int>[] : await repo.getSeasonNumbers(seriesPage.items.first.id);
    final eps = seasons.isEmpty ? <Episode>[] : await repo.getEpisodes(seriesPage.items.first.id, season: seasons.first);
    final word = firstMovie.title.split(RegExp(r'[\s:|-]+')).firstWhere((w) => w.length >= 4, orElse: () => firstMovie.title);
    final found = await repo.search(word);
    final liveCh = await repo.browse(kind: MediaKind.live, limit: 5);

    // ignore: avoid_print
    print('LIVE phase 6 (${sw.elapsedMilliseconds}ms): synced ${counts.live} live / ${counts.movies} movies / '
        '${counts.series} series (2 categories each)\n'
        '  home: top ${home2.top10.length} (with plot $withPlot, backdrop $withBackdrop), series rail ${home2.arabicOriginals.length}, live ${home2.liveChannels.length}\n'
        '  metadata-tmdb calls: $metaCalls (cached after)\n'
        '  browse: ${cats.length} movie categories, first page ${page.items.length}, next cursor ${page.nextCursor != null}\n'
        '  details: "${details?.title}" ${details?.durationLabel ?? '-'}, plot ${(details?.synopsis ?? '').isNotEmpty}\n'
        '  series: seasons $seasons, episodes ${eps.length}\n'
        '  search "$word": ${found.length} hits; live page ${liveCh.items.length}');
    expect(page.items, isNotEmpty);
    expect(details, isNotNull);
    expect(found, isNotEmpty);
    await Future<void>.delayed(const Duration(seconds: 1));
    adapter.dispose();
    await store.close();
  },
      skip: panel != null && envFile.existsSync() ? false : liveSkip,
      timeout: const Timeout(Duration(minutes: 4)));
}
