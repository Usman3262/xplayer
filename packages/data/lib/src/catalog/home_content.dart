import 'dart:math';

import 'package:domain/domain.dart';

import '../backend/home_layout.dart';
import '../providers/provider_mappers.dart';
import '../providers/provider_models.dart';
import 'catalog_store.dart';

/// Phase 6.4 — resolves the admin's Home config (sections, banners, Top 10)
/// against the user's own panel catalog. What to show always comes from the
/// panel (newest by the panel's `added`, panel rating, panel category) or
/// from admin picks matched to the user's panel — never from TMDB lists.
/// Items the user's panel doesn't have are simply left out.
class HomeContentResolver {
  HomeContentResolver({required this.store, required this.panelId, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final CatalogStore store;
  final String panelId;
  final DateTime Function() _clock;

  /// Panel tmdb ids of the items handed out (for metadata lookups).
  final Map<String, int> tmdbIds = {};

  MediaItem _movie(ProviderMovie m) {
    if (m.tmdbId != null) tmdbIds['movie:${m.id}'] = m.tmdbId!;
    return providerMovieToDomain(m);
  }

  MediaItem _series(ProviderSeries s) {
    if (s.tmdbId != null) tmdbIds['series:${s.id}'] = s.tmdbId!;
    return providerSeriesToDomain(s);
  }

  /// Items for one Home section ([layout] for its Top 10 list).
  Future<List<MediaItem>> section(HomeSection s, HomeLayout layout) async {
    final limit = s.limit;
    if (s.items.isNotEmpty && (s.source == SectionSource.manual || s.type == HomeSectionType.custom || s.type == HomeSectionType.collection)) {
      return refs(s.items, limit: limit);
    }
    if (s.source == SectionSource.random && s.type != HomeSectionType.top10) {
      return dailyPicks(s.kind, limit: limit);
    }
    switch (s.type) {
      case HomeSectionType.top10:
        final list = layout.top10ById(s.top10ListId);
        return list == null ? newest(s.kind, limit: 10) : top10(list);
      case HomeSectionType.newReleases:
      case HomeSectionType.recentlyAdded:
        return newest(s.kind, limit: limit, days: s.intParam('days'));
      case HomeSectionType.popular:
      case HomeSectionType.trending:
      case HomeSectionType.recommended:
        return s.source == SectionSource.providerAdded
            ? newest(s.kind, limit: limit, days: s.intParam('days'))
            : topRated(s.kind, limit: limit);
      case HomeSectionType.category:
        final cat = s.strParam('category_id') ?? s.strParam('category');
        return cat == null ? const [] : category(s.kind, cat, limit: limit);
      case HomeSectionType.heroBanners:
        return newest(ContentKind.mixed, limit: limit);
      // Personal (library) and sports rails come from elsewhere (Phase 7).
      case HomeSectionType.continueWatching:
      case HomeSectionType.favorites:
      case HomeSectionType.recentlyWatched:
      case HomeSectionType.liveNow:
      case HomeSectionType.genre:
      case HomeSectionType.collection:
      case HomeSectionType.custom:
      case HomeSectionType.matchesLive:
      case HomeSectionType.matchesUpcoming:
      case HomeSectionType.unknown:
        return const [];
    }
  }

  /// A Top 10 list: admin picks in rank order (ones the panel lacks are
  /// skipped), or computed from the panel.
  Future<List<MediaItem>> top10(Top10List l) async {
    switch (l.source) {
      case Top10Source.manual:
        return refs([for (final e in l.items) e.ref], limit: 10);
      case Top10Source.providerRating:
        return topRated(l.kind, limit: 10);
      case Top10Source.providerAdded:
      case Top10Source.watchStats: // watch stats not collected yet → newest
      case Top10Source.unknown:
        return newest(l.kind, limit: 10, days: _int(l.params['days']));
    }
  }

  /// Newest by the panel's `added` date (optionally only the last [days]).
  Future<List<MediaItem>> newest(ContentKind kind, {required int limit, int? days}) async {
    final since = days == null || days <= 0 ? null : _clock().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;
    bool fresh(int? added) => since == null || (added != null && added >= since);
    final movies = kind == ContentKind.series ? const <ProviderMovie>[] : await store.newestMovies(panelId, limit: limit);
    final series = kind == ContentKind.movie ? const <ProviderSeries>[] : await store.newestSeries(panelId, limit: limit);
    final out = <(int, MediaItem)>[
      for (final m in movies)
        if (fresh(m.addedSec)) (m.addedSec ?? 0, _movie(m)),
      for (final s in series)
        if (fresh(s.addedSec)) (s.addedSec ?? 0, _series(s)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in out.take(limit)) e.$2];
  }

  Future<List<MediaItem>> topRated(ContentKind kind, {required int limit}) async {
    final half = kind == ContentKind.mixed ? (limit / 2).ceil() : limit;
    return [
      if (kind != ContentKind.series) ...(await store.topRatedMovies(panelId, limit: half)).map(_movie),
      if (kind != ContentKind.movie) ...(await store.topRatedSeries(panelId, limit: half)).map(_series),
    ].take(limit).toList();
  }

  /// "Picked for you": a mix from the panel's better-rated titles that
  /// changes once a day (same picks all day, so Home doesn't jump).
  Future<List<MediaItem>> dailyPicks(ContentKind kind, {required int limit}) async {
    final pool = await topRated(kind, limit: limit * 4);
    final d = _clock();
    pool.shuffle(Random(d.year * 1000 + d.month * 40 + d.day));
    return pool.take(limit).toList();
  }

  Future<List<MediaItem>> category(ContentKind kind, String categoryId, {required int limit}) async {
    if (kind == ContentKind.series) {
      return [for (final r in await store.series(panelId, categoryId: categoryId, limit: limit)) _series(r.$1)];
    }
    return [for (final r in await store.movies(panelId, categoryId: categoryId, limit: limit)) _movie(r.$1)];
  }

  /// Admin picks → the user's panel items, in the given order.
  Future<List<MediaItem>> refs(List<ContentRef> refs, {required int limit}) async {
    final out = <MediaItem>[];
    final seen = <String>{};
    for (final r in refs) {
      if (out.length >= limit) break;
      final m = await ref(r);
      if (m != null && seen.add('${m.kind.name}:${m.id}')) out.add(m);
    }
    return out;
  }

  /// Match order: TMDB id (exact everywhere) → the reference panel's item id
  /// (only if the title agrees, ids differ between panels) → title.
  Future<MediaItem?> ref(ContentRef r) async {
    final kinds = switch (r.kind) {
      ContentKind.movie => const [ContentKind.movie],
      ContentKind.series => const [ContentKind.series],
      ContentKind.mixed || ContentKind.unknown => const [ContentKind.movie, ContentKind.series],
      ContentKind.live || ContentKind.link => const <ContentKind>[],
    };
    for (final k in kinds) {
      if (r.tmdbId != null) {
        final hit = k == ContentKind.movie ? await store.movieByTmdb(panelId, r.tmdbId!) : await store.seriesByTmdb(panelId, r.tmdbId!);
        if (hit != null) return hit is ProviderMovie ? _movie(hit) : _series(hit as ProviderSeries);
      }
      if (r.panelItemId != null) {
        final hit = k == ContentKind.movie
            ? (await store.moviesByIds(panelId, [r.panelItemId!])).firstOrNull
            : (await store.seriesByIds(panelId, [r.panelItemId!])).firstOrNull;
        final name = hit is ProviderMovie ? hit.name : (hit is ProviderSeries ? hit.name : null);
        if (hit != null && _sameTitle(name, r.title ?? r.matchTitle)) {
          return hit is ProviderMovie ? _movie(hit) : _series(hit as ProviderSeries);
        }
      }
      final title = r.matchTitle ?? r.title;
      if (title != null && title.trim().length >= 2) {
        final hit = k == ContentKind.movie ? await store.movieByName(panelId, title) : await store.seriesByName(panelId, title);
        if (hit != null) return hit is ProviderMovie ? _movie(hit) : _series(hit as ProviderSeries);
      }
    }
    return null;
  }

  /// No title to compare → trust the id (same panel family by design).
  static bool _sameTitle(String? panelName, String? refTitle) {
    if (refTitle == null || refTitle.trim().isEmpty) return true;
    if (panelName == null) return false;
    String norm(String s) => cleanDisplayName(s).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
    final a = norm(panelName), b = norm(refTitle);
    return a.isNotEmpty && b.isNotEmpty && (a.contains(b) || b.contains(a));
  }

  static int? _int(Object? v) => v is int ? v : int.tryParse('$v');
}
