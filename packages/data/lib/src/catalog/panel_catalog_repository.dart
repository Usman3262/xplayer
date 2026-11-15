import 'dart:async';

import 'package:domain/domain.dart';

import '../backend/catalog_models.dart';
import '../backend/home_layout.dart';
import '../diag/diag.dart';
import '../providers/provider_adapter.dart';
import '../providers/provider_mappers.dart';
import '../providers/provider_models.dart';
import 'catalog_store.dart';
import 'home_content.dart';
import 'metadata_resolver.dart';

/// Phase 6.4 — the screens' existing [CatalogRepository], backed by the
/// user's panel: lists from the local catalog (filled by the sync), details /
/// episodes from the panel on first open (then stored), posters / plots from
/// the global catalog (cache first, missing ones fetched for what is on
/// screen). Home follows the admin's config, resolved against this panel.
class PanelCatalogRepository implements CatalogRepository {
  PanelCatalogRepository({
    required this.store,
    required this.panelId,
    required Future<ProviderAdapter?> Function() adapter,
    HomeLayout Function()? layout,
    this.metadata,
    this.artwork = const ArtworkUrls(),
    this.onMetadataArrived,
    this.adultOnly = false,
    DateTime Function()? clock,
  })  : _adapter = adapter,
        _layout = layout ?? (() => HomeLayout.empty),
        _home = HomeContentResolver(store: store, panelId: panelId, clock: clock);

  final CatalogStore store;
  final String panelId;
  final MetadataResolver? metadata;
  final ArtworkUrls artwork;

  /// New posters / plots arrived → screens may reload once.
  final void Function()? onMetadataArrived;

  /// The 18+ view (after the PIN): categories / browse / search show only
  /// adult content. The normal view (false) never shows it anywhere.
  final bool adultOnly;

  /// Does the panel have 18+ categories of [kind]? (shows the Adult button)
  Future<bool> hasAdult(MediaKind kind) async =>
      (await store.categories(panelId, _kind(kind), adult: true)).isNotEmpty;

  /// The same repository, 18+ only (for the adult screen after the PIN).
  PanelCatalogRepository adultView() => PanelCatalogRepository(
        store: store,
        panelId: panelId,
        adapter: _adapter,
        layout: _layout,
        metadata: metadata,
        artwork: artwork,
        onMetadataArrived: onMetadataArrived,
        adultOnly: true,
      );

  final Future<ProviderAdapter?> Function() _adapter;
  final HomeLayout Function() _layout;
  final HomeContentResolver _home;

  static const _page = 40;
  final _ext = <String, String>{};
  final _seriesOfEpisode = <String, String>{};
  final _details = <String, Future<ProviderMovieDetails?>>{};

  // ── Mapping + enrichment ─────────────────────────────────────────────────

  MediaItem _movie(ProviderMovie m) {
    if (m.stream.extension != null) _ext[m.id] = m.stream.extension!;
    if (m.tmdbId != null) _home.tmdbIds['movie:${m.id}'] = m.tmdbId!;
    return providerMovieToDomain(m);
  }

  MediaItem _series(ProviderSeries s) {
    if (s.tmdbId != null) _home.tmdbIds['series:${s.id}'] = s.tmdbId!;
    return providerSeriesToDomain(s);
  }

  static MediaItem _channelItem(ProviderChannel c) => MediaItem(
        id: c.id,
        title: c.name,
        kind: MediaKind.live,
        isLive: true,
        posterUrl: c.logoUrl,
        categoryId: c.categoryId,
        addedSec: c.addedSec,
      );

  MetadataQuery? _query(MediaItem m) {
    if (m.kind != MediaKind.movie && m.kind != MediaKind.series) return null;
    final kind = m.kind == MediaKind.series ? CatalogKind.series : CatalogKind.movie;
    final tmdb = _home.tmdbIds['${m.kind.name}:${m.id}'];
    if (tmdb == null && m.title.trim().length < 2) return null;
    return MetadataQuery(kind: kind, tmdbId: tmdb, title: tmdb == null ? m.title : null, year: m.year);
  }

  /// Applies cached metadata now; asks for the missing ones in the
  /// background (only these on-screen titles, ≤25 per call).
  Future<List<MediaItem>> _enrich(List<MediaItem> items, {int fetchFirst = 25}) async {
    final meta = metadata;
    if (meta == null || items.isEmpty) return items;
    final queries = <int, MetadataQuery>{};
    for (var i = 0; i < items.length; i++) {
      final q = _query(items[i]);
      if (q != null) queries[i] = q;
    }
    if (queries.isEmpty) return items;
    final cached = await meta.cached(queries.values.toList());
    final missing = [
      for (final e in queries.entries.take(fetchFirst))
        if (!cached.containsKey(MetadataResolver.keyOf(e.value))) e.value,
    ];
    if (missing.isNotEmpty) {
      unawaited(meta.resolve(missing).then((got) {
        if (got.values.any((m) => m != null)) onMetadataArrived?.call();
      }));
    }
    return [
      for (var i = 0; i < items.length; i++)
        queries[i] == null ? items[i] : enrichMedia(items[i], cached[MetadataResolver.keyOf(queries[i]!)], artwork),
    ];
  }

  // ── Home ─────────────────────────────────────────────────────────────────

  @override
  Future<HomeFeed> getHomeFeed() async {
    final sw = Stopwatch()..start();
    final layout = _layout();
    final top10List = layout.top10.firstOrNull;
    final results = await Future.wait([
      top10List != null ? _home.top10(top10List) : _home.newest(ContentKind.mixed, limit: 20),
      _home.newest(ContentKind.movie, limit: 40),
      _home.newest(ContentKind.series, limit: 40),
    ]);
    final channels = [for (final r in await store.channels(panelId, limit: CatalogPaging.pageSize)) r.$1];
    final rawTop = results[0].isNotEmpty ? results[0] : [...results[1].take(20), ...results[2].take(20)];
    // One enrichment pass (one background fetch, one reload) for the rails
    // that show artwork first: top list, then the series rail.
    final enriched = await _enrich([...rawTop, ...results[2]], fetchFirst: 25);
    final top = enriched.sublist(0, rawTop.length);
    final series = enriched.sublist(rawTop.length);
    final movies = results[1];
    final hero = top.firstOrNull ?? movies.firstOrNull ?? series.firstOrNull ?? _emptyHero();
    _prefetchDetailsOnce([...top, ...series.take(10)]);
    Diag.event('HOME', 'home from panel in ${sw.elapsedMilliseconds}ms: top ${top.length}'
        '${top10List != null ? ' (admin list "${top10List.title}", ${top10List.source.wire})' : ' (newest)'}, '
        'movies ${movies.length}, series ${series.length}, live ${channels.length}');
    return HomeFeed(
      hero: hero,
      matches: const [],
      continueWatching: const [], // library (Phase 7.7)
      top10: [...top, ...movies.where((m) => !top.any((t) => t.id == m.id)).take(20)],
      arabicOriginals: series.isNotEmpty ? series : movies,
      liveChannels: [for (final c in channels) providerChannelToDomain(c)],
    );
  }

  bool _prefetched = false;

  /// Details of what Home shows, one at a time in the background (movie plot /
  /// runtime, series episodes), so they are ready when opened. Only Home
  /// items: fetching details for the whole catalog would be one request per
  /// title (thousands) and gets the user's connection blocked.
  void _prefetchDetailsOnce(List<MediaItem> items) {
    if (_prefetched || items.isEmpty) return;
    _prefetched = true;
    unawaited(() async {
      final sw = Stopwatch()..start();
      var movies = 0, series = 0;
      for (final m in items.take(30)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (m.kind == MediaKind.movie && await _movieDetails(m.id) != null) movies++;
        if (m.kind == MediaKind.series && await _seriesDetails(m.id) != null) series++;
      }
      Diag.event('PANEL', 'home details ready in background: $movies movies, $series series '
          '(${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)}s)');
    }());
  }

  /// Items for one admin Home section (dynamic Home, Phase 7.1).
  Future<List<MediaItem>> homeSection(HomeSection s) async => _enrich(await _home.section(s, _layout()));

  MediaItem _emptyHero() => MediaItem(id: 'empty', title: AppBrand.name, kind: MediaKind.movie);

  // ── Lists ────────────────────────────────────────────────────────────────

  @override
  Future<List<MediaItem>> getMovies() async => _enrich(await _home.newest(ContentKind.movie, limit: 200), fetchFirst: 0);

  @override
  Future<List<MediaItem>> getSeries() async => _enrich(await _home.newest(ContentKind.series, limit: 200), fetchFirst: 0);

  @override
  Future<List<LiveChannel>> getLiveChannels() async =>
      [for (final r in await store.channels(panelId, limit: 200)) providerChannelToDomain(r.$1)];

  @override
  Future<List<MediaItem>> getNewReleases() async => _enrich(await _home.newest(ContentKind.movie, limit: _page));

  @override
  Future<List<MediaItem>> getNewSeries() async => _enrich(await _home.newest(ContentKind.series, limit: _page));

  @override
  Future<List<MediaItem>> getTrending() async => _enrich(await _home.topRated(ContentKind.mixed, limit: 20));

  @override
  Future<List<MediaItem>> getComingSoon() async => const [];

  @override
  Future<List<MediaItem>> getMyList() async => const []; // library (Phase 7.7)

  @override
  Future<List<String>> getGenres() async => const [];

  @override
  Future<List<MediaItem>> getByGenre(String genre) async => const [];

  // ── Categories / browse ──────────────────────────────────────────────────

  @override
  Future<List<CatalogCategory>> getCategories(MediaKind kind) async =>
      [for (final c in await store.categories(panelId, _kind(kind), adult: adultOnly)) providerCategoryToDomain(c)];

  static CatalogKind _kind(MediaKind k) => switch (k) {
        MediaKind.movie => CatalogKind.movie,
        MediaKind.series => CatalogKind.series,
        MediaKind.live || MediaKind.sports => CatalogKind.live,
      };

  /// Keyset pages in panel order; cursor = the last row's position. A
  /// category the background sync hasn't reached yet (or never syncs, like
  /// Stalker VOD) is fetched right now with priority — the user is waiting.
  @override
  Future<CatalogPage<MediaItem>> browse({required MediaKind kind, String? categoryId, String? cursor, int limit = 10}) async {
    var page = await _browse(kind, categoryId, cursor, limit);
    if (page.items.isEmpty && cursor == null && categoryId != null && await _fetchCategoryNow(kind, categoryId)) {
      page = await _browse(kind, categoryId, cursor, limit);
    }
    return page;
  }

  final _categoryLoads = <String, Future<bool>>{};

  /// True when the category was fetched (or another call just did).
  Future<bool> _fetchCategoryNow(MediaKind kind, String categoryId) {
    final scope = '${_kind(kind).name}:cat:$categoryId';
    return _categoryLoads[scope] ??= () async {
      try {
        if (await store.syncInfo(panelId, scope) != null) return false; // synced, really empty
        final a = await _adapter();
        if (a == null) return false;
        final sw = Stopwatch()..start();
        int n;
        switch (kind) {
          case MediaKind.movie:
            final items = await a.movies(categoryId: categoryId, priority: true);
            await store.saveMovies(panelId, categoryId, items);
            n = items.length;
          case MediaKind.series:
            final items = await a.series(categoryId: categoryId, priority: true);
            await store.saveSeries(panelId, categoryId, items);
            n = items.length;
          case MediaKind.live:
          case MediaKind.sports:
            final items = await a.liveChannels(categoryId: categoryId, priority: true);
            await store.saveChannels(panelId, categoryId, items);
            n = items.length;
        }
        await store.markSynced(panelId, scope, at: DateTime.now(), count: n);
        Diag.event('PANEL', 'opened $scope: $n titles fetched now (${sw.elapsedMilliseconds}ms, ahead of the sync)');
        return true;
      } catch (e) {
        Diag.event('PANEL', 'opened $scope: fetch failed: ${e.runtimeType}: $e');
        return false;
      } finally {
        _categoryLoads.remove(scope);
      }
    }();
  }

  Future<CatalogPage<MediaItem>> _browse(MediaKind kind, String? categoryId, String? cursor, int limit) async {
    final after = int.tryParse(cursor ?? '');
    final List<(MediaItem, int)> rows = switch (kind) {
      MediaKind.movie => [
          for (final r in await store.movies(panelId, categoryId: categoryId, limit: limit, afterSort: after, adult: adultOnly)) (_movie(r.$1), r.$2),
        ],
      MediaKind.series => [
          for (final r in await store.series(panelId, categoryId: categoryId, limit: limit, afterSort: after, adult: adultOnly)) (_series(r.$1), r.$2),
        ],
      MediaKind.live || MediaKind.sports => [
          for (final r in await store.channels(panelId, categoryId: categoryId, limit: limit, afterSort: after, adult: adultOnly)) (_channelItem(r.$1), r.$2),
        ],
    };
    final items = await _enrich([for (final r in rows) r.$1], fetchFirst: limit);
    return CatalogPage(items: items, nextCursor: rows.length < limit ? null : '${rows.last.$2}');
  }

  // ── Search ───────────────────────────────────────────────────────────────

  @override
  Future<List<MediaItem>> search(String query, {MediaKind? kind}) async =>
      (await searchPage(query, kind: kind, limit: _page)).items;

  @override
  Future<CatalogPage<MediaItem>> searchPage(String query, {MediaKind? kind, String? cursor, int limit = 40, String? categoryId}) async {
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final per = kind == null ? (limit / 3).ceil() : limit;
    final items = <MediaItem>[
      if (kind == null || kind == MediaKind.movie)
        ...(await store.searchMovies(panelId, query, limit: per, offset: offset, categoryId: categoryId, adult: adultOnly)).map(_movie),
      if (kind == null || kind == MediaKind.series)
        ...(await store.searchSeries(panelId, query, limit: per, offset: offset, categoryId: categoryId, adult: adultOnly)).map(_series),
      if (kind == null || kind == MediaKind.live || kind == MediaKind.sports)
        ...(await store.searchChannels(panelId, query, limit: per, offset: offset, categoryId: categoryId, adult: adultOnly)).map(_channelItem),
    ];
    return CatalogPage(items: await _enrich(items, fetchFirst: 10), nextCursor: items.length < per ? null : '${offset + per}');
  }

  // ── Details ──────────────────────────────────────────────────────────────

  @override
  Future<MediaItem?> getById(String id, {MediaKind? kind}) async {
    if (kind == null || kind == MediaKind.movie) {
      final m = await store.movie(panelId, id);
      if (m != null) {
        final d = await _movieDetails(id);
        final base = d == null ? _movie(m) : providerMovieToDomain(m, details: d);
        _movie(m);
        return (await _enrich([base])).first;
      }
    }
    if (kind == null || kind == MediaKind.series) {
      final s = await store.seriesItem(panelId, id);
      if (s != null) return (await _enrich([_series(s)])).first;
    }
    if (kind == null || kind == MediaKind.live || kind == MediaKind.sports) {
      final c = await store.channel(panelId, id);
      if (c != null) return _channelItem(c);
    }
    return null;
  }

  /// Panel details (plot, cast, runtime) once per movie per session.
  Future<ProviderMovieDetails?> _movieDetails(String id) => _details[id] ??= () async {
        try {
          final a = await _adapter();
          return await a?.movieDetails(id).timeout(const Duration(seconds: 30));
        } catch (e) {
          Diag.event('PANEL', 'movie details $id unavailable: ${e.runtimeType}: $e');
          _details.remove(id); // try again next time it's opened
          return null;
        }
      }();

  @override
  String? knownContainerExtension(String streamId) => _ext[streamId];

  @override
  String? knownSeriesIdForEpisode(String episodeId) => _seriesOfEpisode[episodeId];

  final _seriesLoads = <String, Future<ProviderSeriesDetails?>>{};

  /// Seasons/episodes: stored copy, else fetched from the panel (once, even
  /// when the season list and the episode list ask at the same time).
  Future<ProviderSeriesDetails?> _seriesDetails(String seriesId) {
    final running = _seriesLoads[seriesId];
    if (running != null) return running;
    final f = _loadSeriesDetails(seriesId);
    _seriesLoads[seriesId] = f;
    f.whenComplete(() => _seriesLoads.remove(seriesId));
    return f;
  }

  Future<ProviderSeriesDetails?> _loadSeriesDetails(String seriesId) async {
    final cached = await store.seriesDetails(panelId, seriesId);
    if (cached != null) return cached;
    final sw = Stopwatch()..start();
    try {
      final a = await _adapter();
      final d = await a?.seriesDetails(seriesId).timeout(const Duration(seconds: 30));
      if (d == null) return null;
      await store.saveSeriesDetails(panelId, d);
      Diag.event('PANEL', 'series $seriesId: ${d.seasonNumbers.length} seasons, '
          '${d.episodes.values.fold<int>(0, (n, l) => n + l.length)} episodes fetched + stored in ${sw.elapsedMilliseconds}ms');
      return d;
    } catch (e) {
      Diag.event('PANEL', 'series $seriesId episodes unavailable after ${sw.elapsedMilliseconds}ms: ${e.runtimeType}: $e');
      return null;
    }
  }

  @override
  Future<List<Episode>> getEpisodes(String seriesId, {int season = 1}) async {
    final d = await _seriesDetails(seriesId);
    final list = d?.episodes[season] ?? const [];
    for (final e in list) {
      _seriesOfEpisode[e.id] = seriesId;
      if (e.stream.extension != null) _ext[e.id] = e.stream.extension!;
    }
    return [for (final e in list) providerEpisodeToDomain(e)];
  }

  @override
  Future<int> getSeasonCount(String seriesId) async => (await _seriesDetails(seriesId))?.seasonNumbers.length ?? 0;

  @override
  Future<List<int>> getSeasonNumbers(String seriesId) async => (await _seriesDetails(seriesId))?.seasonNumbers ?? const [];

  @override
  Future<List<MediaItem>> getRelated(String id) async {
    final m = await store.movie(panelId, id);
    if (m?.categoryId != null) {
      return _enrich([
        for (final r in await store.movies(panelId, categoryId: m!.categoryId, limit: 21))
          if (r.$1.id != id) _movie(r.$1),
      ].take(20).toList(), fetchFirst: 10);
    }
    final s = await store.seriesItem(panelId, id);
    if (s?.categoryId != null) {
      return _enrich([
        for (final r in await store.series(panelId, categoryId: s!.categoryId, limit: 21))
          if (r.$1.id != id) _series(r.$1),
      ].take(20).toList(), fetchFirst: 10);
    }
    return const [];
  }

  // ── Sports (Supabase matches = Phase 7.8) ────────────────────────────────

  @override
  Future<List<SportsMatch>> getSportsMatches() async => const [];

  @override
  Future<CatalogPage<SportsMatch>> browseSports({String? cursor, int limit = 10}) async => const CatalogPage(items: []);

  @override
  Future<List<SportsMatch>> searchSports(String query) async => const [];
}
