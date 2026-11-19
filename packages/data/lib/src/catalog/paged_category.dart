import '../backend/catalog_models.dart' show CatalogKind;
import '../providers/provider_adapter.dart';
import 'catalog_store.dart';

/// A paged panel's category (Stalker: 14 titles a page), loaded one page at
/// a time: page 1 when the category is shown, the next page when a screen
/// scrolls past what is stored. Never the whole category at once — that
/// burst (~100 requests per category) made portals answer HTTP 429.
///
/// Where we are is kept in the sync bookkeeping (scope `<cat scope>:pages`:
/// item count = pages stored, maxAddedSec = pages on the panel), so it
/// survives app restarts.
class PagedCategory {
  PagedCategory._();

  /// Rows of page n are stored with sort = (n-1) × [pageStride] + index.
  static const pageStride = 1000;

  static String stateScope(String scope) => '$scope:pages';

  /// (pages stored, pages on the panel), or null before page 1.
  static Future<(int, int)?> state(CatalogStore store, String panelId, String scope) async {
    final s = await store.syncInfo(panelId, stateScope(scope));
    if (s == null) return null;
    return (s.itemCount, s.maxAddedSec ?? s.itemCount);
  }

  static Future<bool> hasMore(CatalogStore store, String panelId, String scope) async {
    final s = await state(store, panelId, scope);
    return s == null || s.$1 < s.$2;
  }

  /// Fetches page [page] of [categoryId] and stores it (page 1 replaces the
  /// category, later pages are added after it). Returns the titles stored.
  static Future<int> fetch(
    CatalogStore store,
    String panelId,
    PagedLists a,
    CatalogKind kind,
    String categoryId,
    int page, {
    required DateTime now,
  }) async {
    final scope = '${kind.name}:cat:$categoryId';
    final at = page == 1 ? null : (page - 1) * pageStride;
    var n = 0;
    var pages = 1;
    switch (kind) {
      case CatalogKind.live:
        final p = await a.liveChannelsPage(categoryId, page);
        await store.saveChannels(panelId, categoryId, p.items, appendAt: at);
        (n, pages) = (p.items.length, p.pages);
      case CatalogKind.movie:
        final p = await a.moviesPage(categoryId, page);
        await store.saveMovies(panelId, categoryId, p.items, appendAt: at);
        (n, pages) = (p.items.length, p.pages);
      case CatalogKind.series:
        final p = await a.seriesPage(categoryId, page);
        await store.saveSeries(panelId, categoryId, p.items, appendAt: at);
        for (final d in p.details) {
          await store.saveSeriesDetails(panelId, d);
        }
        (n, pages) = (p.items.length, p.pages);
    }
    await store.markSynced(panelId, stateScope(scope), at: now, count: page, maxAddedSec: pages);
    if (page == 1) await store.markSynced(panelId, scope, at: now, count: n);
    return n;
  }
}
