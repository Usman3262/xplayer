import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Stalker-like portal: category "c" has 30 movies in pages of 14.
class PagedPortal implements ProviderAdapter, PagedLists {
  final requests = <String>[];
  static const total = 30, per = 14;

  ProviderMovie _mv(int i) => ProviderMovie(
      id: 'm$i', name: 'Movie $i', stream: StreamRef(kind: MediaKind.movie, id: 'm$i'), categoryId: 'c');

  @override
  Future<ProviderPage<ProviderMovie>> moviesPage(String categoryId, int page) async {
    requests.add('movie:$categoryId:p$page');
    final from = (page - 1) * per;
    final to = (from + per).clamp(0, total);
    return ProviderPage([for (var i = from; i < to; i++) _mv(i)], page: page, pages: (total / per).ceil());
  }

  @override
  Future<ProviderPage<ProviderSeries>> seriesPage(String categoryId, int page) async =>
      ProviderPage(const [], page: page, pages: 1);
  @override
  Future<ProviderPage<ProviderChannel>> liveChannelsPage(String categoryId, int page) async =>
      ProviderPage(const [], page: page, pages: 1);

  @override
  Future<List<ProviderMovie>> movies({String? categoryId, bool priority = false}) async {
    requests.add('movie:$categoryId:ALL');
    return [for (var i = 0; i < total; i++) _mv(i)];
  }

  @override
  ProviderKind get kind => ProviderKind.stalker;
  @override
  ProviderCapabilities get capabilities =>
      const ProviderCapabilities(live: false, movies: true, series: false, lists: {MediaKind.movie: ListStrategy.onDemand});
  @override
  Future<List<ProviderCategory>> movieCategories() async => const [ProviderCategory(id: 'c', name: 'Action')];
  @override
  Future<List<ProviderCategory>> liveCategories() async => const [];
  @override
  Future<List<ProviderCategory>> seriesCategories() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;
  late PagedPortal portal;
  final now = DateTime.utc(2026, 11, 19, 12);

  setUp(() {
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    portal = PagedPortal();
  });
  tearDown(() => store.close());

  PanelCatalogRepository repo() =>
      PanelCatalogRepository(store: store, panelId: 'p', adapter: () async => portal, clock: () => now);

  test('a category row (10 titles) asks the portal for page 1 only — never the whole category', () async {
    final page = await repo().browse(kind: MediaKind.movie, categoryId: 'c', limit: 10);
    expect(page.items.map((m) => m.id).take(3), ['m0', 'm1', 'm2']);
    expect(portal.requests, ['movie:c:p1']);
  });

  test('scrolling past what is stored fetches the next pages, in order, no duplicates', () async {
    final r = repo();
    final first = await r.browse(kind: MediaKind.movie, categoryId: 'c', limit: 10);
    final second = await r.browse(kind: MediaKind.movie, categoryId: 'c', limit: 10, cursor: first.nextCursor);
    expect(second.items.map((m) => m.id).first, 'm10');
    expect(portal.requests, ['movie:c:p1', 'movie:c:p2']);
    // The See-all grid (48): the rest at once, then nothing more to ask.
    final all = await r.browse(kind: MediaKind.movie, categoryId: 'c', limit: 48);
    expect(all.items, hasLength(30));
    expect(all.items.map((m) => m.id).toSet(), hasLength(30));
    expect(portal.requests, ['movie:c:p1', 'movie:c:p2', 'movie:c:p3']);
    await r.browse(kind: MediaKind.movie, categoryId: 'c', limit: 48);
    expect(portal.requests, hasLength(3));
  });

  test('where we are survives an app restart (new repository)', () async {
    await repo().browse(kind: MediaKind.movie, categoryId: 'c', limit: 10);
    final again = await repo().browse(kind: MediaKind.movie, categoryId: 'c', limit: 20);
    expect(again.items, hasLength(20));
    expect(portal.requests, ['movie:c:p1', 'movie:c:p2']);
  });

  test('the background sync takes page 1 of a paged category, not every page', () async {
    final s = CatalogSyncer(store: store, clock: () => now,
        policy: const SyncPolicy(gap: Duration.zero, failureBackoff: Duration.zero));
    await s.sync('p', portal);
    expect(portal.requests, ['movie:c:p1']);
  });
}
