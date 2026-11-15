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
      [for (final c in await store.categories(panelId, _kind(kind))) providerCategoryToDomain(c)];

  static CatalogKind _kind(MediaKind k) => switch (k) {
        MediaKind.movie => CatalogKind.movie,
        MediaKind.series => CatalogKind.series,
        MediaKind.live || MediaKind.sports => CatalogKind.live,
      };

  /// Keyset pages in panel order; cursor = the last row's position.
  @override
  Future<CatalogPage<MediaItem>> browse({required MediaKind kind, String? categoryId, String? cursor, int limit = 10}) async {
    final after = int.tryParse(cursor ?? '');
    final List<(MediaItem, int)> rows = switch (kind) {
      MediaKind.movie => [
          for (final r in await store.movies(panelId, categoryId: categoryId, limit: limit, afterSort: after)) (_movie(r.$1), r.$2),
        ],
      MediaKind.series => [
          for (final r in await store.series(panelId, categoryId: categoryId, limit: limit, afterSort: after)) (_series(r.$1), r.$2),
        ],
      MediaKind.live || MediaKind.sports => [
          for (final r in await store.channels(panelId, categoryId: categoryId, limit: limit, afterSort: after)) (_channelItem(r.$1), r.$2),
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
        ...(await store.searchMovies(panelId, query, limit: per, offset: offset, categoryId: categoryId)).map(_movie),
      if (kind == null || kind == MediaKind.series)
        ...(await store.searchSeries(panelId, query, limit: per, offset: offset, categoryId: categoryId)).map(_series),
      if (kind == null || kind == MediaKind.live || kind == MediaKind.sports)
        ...(await store.searchChannels(panelId, query, limit: per, offset: offset, categoryId: categoryId)).map(_channelItem),
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
          return await a?.movieDetails(id).timeout(const Duration(seconds: 10));
        } catch (e) {
          Diag.event('PANEL', 'movie details $id unavailable: ${e.runtimeType}');
          return null;
        }
      }();

  @override
  String? knownContainerExtension(String streamId) => _ext[streamId];

  @override
  String? knownSeriesIdForEpisode(String episodeId) => _seriesOfEpisode[episodeId];

  /// Seasons/episodes: stored copy, else fetched from the panel and stored.
  Future<ProviderSeriesDetails?> _seriesDetails(String seriesId) async {
    final cached = await store.seriesDetails(panelId, seriesId);
    if (cached != null) return cached;
    try {
      final a = await _adapter();
      final d = await a?.seriesDetails(seriesId).timeout(const Duration(seconds: 15));
      if (d == null) return null;
      await store.saveSeriesDetails(panelId, d);
      Diag.event('PANEL', 'series $seriesId: ${d.seasonNumbers.length} seasons, '
          '${d.episodes.values.fold<int>(0, (n, l) => n + l.length)} episodes fetched + stored');
      return d;
    } catch (e) {
      Diag.event('PANEL', 'series $seriesId episodes unavailable: ${e.runtimeType}');
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
