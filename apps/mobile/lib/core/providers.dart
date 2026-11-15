import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'catalog.dart';
import 'panels.dart';
import 'remote_config.dart';

import 'demo_mode.dart';
import 'library_controller.dart';
import 'session_controller.dart';

/// Bumped when the backend catalog version changes (package edited in the
/// Control Panel): a new repository drops every in-memory list.
final catalogEpochProvider = StateProvider<int>((ref) => 0);

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  // Demo: the real screens over the openly licensed demo catalog only.
  if (ref.watch(demoModeProvider)) {
    return ref.watch(demoCatalogRepositoryProvider);
  }
  ref.watch(catalogEpochProvider);
  // Phase 6.4: with a panel connected, every screen reads the user's panel
  // (local catalog + panel details + global-catalog artwork). The admin's
  // Home config decides the rails; content always comes from the panel.
  ref.watch(catalogRevisionProvider);
  final panel = ref.watch(panelsProvider).where((c) => c.isPrimary && c.enabled).firstOrNull;
  if (panel != null) {
    final config = ref.watch(remoteConfigProvider);
    return PanelCatalogRepository(
      store: CatalogService.store,
      panelId: panel.id,
      adapter: () => PanelsService.manager.adapterFor(panel.id),
      layout: () => config.home,
      metadata: CatalogService.metadata,
      artwork: ArtworkUrls.fromConfig(config),
      onMetadataArrived: CatalogService.bumpSoon,
    );
  }
  // Only what the catalog depends on. Watching the whole session rebuilt
  // the repository (dropping every cached list and reloading Home) on any
  // session change, e.g. a device-list refresh (19 Oct, live server).
  final key = ref.watch(sessionProvider.select(
    (s) => (s.isLoggedIn, s.user?.id, s.activeProfileId),
  ));
  final media = ref.watch(mediaRepositoryProvider);
  return RemoteCatalogRepository(media, profileId: key.$3);
});

/// Movie details from the provider (plot, cast, director, runtime). Null on
/// older backends or when the provider has none.
final vodInfoProvider = FutureProvider.autoDispose.family<VodInfoDto?, String>((
  ref,
  id,
) async {
  if (ref.watch(demoModeProvider)) return null;
  try {
    return await ref.read(mediaRepositoryProvider).extras.vodInfo(id);
  } catch (_) {
    return null;
  }
});

/// Now / next for a live channel (empty without a guide).
final liveEpgProvider = FutureProvider.autoDispose
    .family<List<EpgProgramDto>, String>((ref, streamId) async {
      if (ref.watch(demoModeProvider)) return const [];
      try {
        return await ref.read(mediaRepositoryProvider).extras.liveEpg(streamId);
      } catch (_) {
        return const [];
      }
    });

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  return ref.watch(catalogRepositoryProvider).getHomeFeed();
});

final moviesProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getMovies();
});

final seriesProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getSeries();
});

/// Weekly Movie and Series Picks (client 18 Oct #15 / TV #8): one source for
/// Home and New & Popular, so the numbered lists match on every screen.
final weeklyPicksProvider = FutureProvider<
    ({List<MediaItem> movies, List<MediaItem> series})>((ref) async {
  // "Recently Added" (client 2 Nov #4, was "Top Movies of the Week"): newest
  // first from the whole catalog, not only 4K. Same source as LG 6.1.11.
  final repo = ref.watch(catalogRepositoryProvider);
  Future<List<MediaItem>> newest(Future<List<MediaItem>> Function() load) async {
    try {
      return (await load()).take(10).toList();
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  final r = await Future.wait([
    newest(repo.getNewReleases),
    newest(repo.getNewSeries),
  ]);
  return (movies: r[0], series: r[1]);
});

/// Top 10 Movies / Series with numbers: the same titles in the same order on
/// every platform and every device. The server's weekly list
/// (`GET /catalog/top10`, Usman 12 Nov), else the app's own [Top10] rule.
/// Reloads by itself when the next week's list is due (Friday 00:00 Saudi
/// time), so an app left open over Friday does not keep last week's list.
final top10Provider = FutureProvider<
    ({List<MediaItem> movies, List<MediaItem> series})>((ref) async {
  final repo = ref.watch(catalogRepositoryProvider);

  Future<List<MediaItem>> pick(MediaKind kind) async {
    try {
      if (repo is RemoteCatalogRepository) return await repo.top10(kind);
      // Demo catalog: same rule on its sample titles.
      final newest = kind == MediaKind.series
          ? await repo.getNewSeries()
          : await repo.getNewReleases();
      return Top10.pick(newest);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  final r = await Future.wait([pick(MediaKind.movie), pick(MediaKind.series)]);
  if (repo is RemoteCatalogRepository) {
    // A minute after the change, so the server has the new list ready.
    final wait = repo.top10NextUpdate
        .add(const Duration(minutes: 1))
        .difference(DateTime.now().toUtc());
    if (wait > Duration.zero && wait < const Duration(days: 8)) {
      final timer = Timer(wait, ref.invalidateSelf);
      ref.onDispose(timer.cancel);
    }
  }
  return (movies: r[0], series: r[1]);
});

/// Set (> 0) by the Friday Top 10 notification (push tap / inbox, `TOP10`,
/// Usman 12 Nov); Home scrolls to the Top 10 row and sets it back to 0.
final top10JumpProvider = StateProvider<int>((ref) => 0);

final liveChannelsProvider = FutureProvider<List<LiveChannel>>((ref) {
  return ref.watch(catalogRepositoryProvider).getLiveChannels();
});

final sportsProvider = FutureProvider<List<SportsMatch>>((ref) {
  return ref.watch(catalogRepositoryProvider).getSportsMatches();
});

/// Prefer local library My List when ready.
final myListProvider = Provider<AsyncValue<List<MediaItem>>>((ref) {
  final lib = ref.watch(libraryProvider);
  if (!lib.ready) return const AsyncValue.loading();
  return AsyncValue.data(lib.myList);
});

final myListItemsProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(libraryProvider).myList;
});

final continueWatchingProvider = Provider<List<MediaItem>>((ref) {
  final lib = ref.watch(libraryProvider);
  if (lib.ready && lib.continueWatching.isNotEmpty) {
    return lib.continueWatching;
  }
  return const [];
});

final downloadsProvider = Provider<List<MediaItem>>((ref) {
  return ref.watch(libraryProvider).downloads;
});

/// Kids-safe slice from panel category rails.
/// Kids home (client 21 Oct): banner, Top 10 Kids Series / Movies (weekly).
final kidsHomeProvider = FutureProvider<KidsHome>((ref) async {
  final rails = await ref.watch(kidsPanelFeedProvider.future);
  return KidsHome.from(
    [
      for (final r in rails)
        (kind: r.kind, categoryId: r.categoryId, items: r.items),
    ],
    now: DateTime.now(),
  );
});

final kidsCatalogProvider = FutureProvider<List<MediaItem>>((ref) async {
  final rails = await ref.watch(kidsPanelFeedProvider.future);
  return [for (final r in rails) ...r.items];
});

class KidsRail {
  const KidsRail({
    required this.title,
    required this.items,
    required this.kind,
    this.categoryId,
  });
  final String title;
  final List<MediaItem> items;
  final MediaKind kind;
  final String? categoryId;
}

/// Resolved Kids panel chip (always listed; [categoryId] null if API has no match).
class KidsCategoryRef {
  const KidsCategoryRef({
    required this.panelName,
    required this.kind,
    this.categoryId,
    this.apiName,
  });

  final String panelName;
  final MediaKind kind;
  final String? categoryId;
  final String? apiName;

  String get displayName => apiName ?? panelName;
  bool get resolved => categoryId != null && categoryId!.isNotEmpty;
}

CatalogCategory? _matchKidsCategory(List<CatalogCategory> cats, String want) {
  for (final c in cats) {
    if (KidsPanelCategories.matches(want, c.name)) return c;
  }
  return null;
}

/// Chips for Kids hub — series, then movies, then live (panel order).
final kidsResolvedCategoriesProvider = FutureProvider<List<KidsCategoryRef>>((
  ref,
) async {
  final repo = ref.watch(catalogRepositoryProvider);

  Future<List<KidsCategoryRef>> resolve(
    MediaKind kind,
    List<String> wanted,
  ) async {
    final cats = await repo.getCategories(kind);
    final out = <KidsCategoryRef>[];
    final used = <String>{};
    // The client's panel names first, in his order; only those that exist.
    for (final want in wanted) {
      final match = _matchKidsCategory(cats, want);
      if (match == null || !used.add(match.id)) continue;
      out.add(KidsCategoryRef(
        panelName: want,
        kind: kind,
        categoryId: match.id,
        apiName: match.name,
      ));
    }
    // Then every other children's category the provider has (client 20 Oct:
    // empty chips and no kids channels).
    for (final c in cats) {
      if (!KidsPanelCategories.looksKids(c.name) || !used.add(c.id)) continue;
      out.add(KidsCategoryRef(
        panelName: c.name,
        kind: kind,
        categoryId: c.id,
        apiName: c.name,
      ));
    }
    return out;
  }

  // All three kinds at once (they ran one after another).
  final parts = await Future.wait([
    resolve(MediaKind.series, KidsPanelCategories.seriesNames),
    resolve(MediaKind.movie, KidsPanelCategories.movieNames),
    resolve(MediaKind.live, KidsPanelCategories.liveNames),
  ]);
  return [for (final p in parts) ...p];
});

/// Kids hub rails — match panel category names from [KidsPanelCategories].
final kidsPanelFeedProvider = FutureProvider<List<KidsRail>>((ref) async {
  final resolved = await ref.watch(kidsResolvedCategoriesProvider.future);
  final repo = ref.watch(catalogRepositoryProvider);
  // All categories at once, as on TV (client 23 Oct #1: one at a time took
  // ~0.5 s per category, ~7 s for Home). A failing category is skipped
  // instead of failing the whole Kids feed.
  final loaded = await Future.wait([
    for (final cat in resolved)
      if (cat.resolved)
        () async {
          try {
            final page = await repo.browse(
              kind: cat.kind,
              categoryId: cat.categoryId,
              limit: 24,
            );
            final items = page.items
                .where((m) => !isProviderAdOrHeaderChannel(m.title))
                .toList();
            if (items.isEmpty) return null;
            return KidsRail(
              title: cat.displayName,
              items: items,
              kind: cat.kind,
              categoryId: cat.categoryId,
            );
          } catch (_) {
            return null;
          }
        }(),
  ]);
  return [for (final r in loaded) if (r != null) r];
});

/// Browse one Kids panel category by index into [kidsResolvedCategoriesProvider].
final kidsCategoryItemsProvider = FutureProvider.family<List<MediaItem>, int>((
  ref,
  index,
) async {
  final cats = await ref.watch(kidsResolvedCategoriesProvider.future);
  if (index < 0 || index >= cats.length) return const [];
  final cat = cats[index];
  if (!cat.resolved) return const [];
  final page = await ref
      .watch(catalogRepositoryProvider)
      .browse(kind: cat.kind, categoryId: cat.categoryId, limit: 48);
  return page.items
      .where((m) => !isProviderAdOrHeaderChannel(m.title))
      .toList();
});

/// Search scoped to Kids panel category IDs (falls back to local kids rails).
final kidsSearchProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  query,
) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final cats = await ref.watch(kidsResolvedCategoriesProvider.future);
  final ids = <String>{
    for (final c in cats)
      if (c.resolved) c.categoryId!,
  };
  final repo = ref.watch(catalogRepositoryProvider);
  final out = <MediaItem>[];
  final seen = <String>{};

  for (final kind in [MediaKind.series, MediaKind.movie, MediaKind.live]) {
    final found = await repo.search(q, kind: kind);
    for (final m in found) {
      final cid = m.categoryId;
      final ok = cid != null && ids.contains(cid);
      if (ok && seen.add(m.id)) out.add(m);
    }
  }

  if (out.isNotEmpty) return out;

  final local = await ref.watch(kidsCatalogProvider.future);
  final needle = q.toLowerCase();
  return [
    for (final m in local)
      if (m.displayTitle.toLowerCase().contains(needle) ||
          m.title.toLowerCase().contains(needle))
        m,
  ];
});

final mediaByIdProvider = FutureProvider.family<MediaItem?, String>((ref, id) {
  return ref.watch(catalogRepositoryProvider).getById(id);
});

final episodesProvider =
    FutureProvider.family<List<Episode>, ({String id, int season})>((
      ref,
      args,
    ) {
      return ref
          .watch(catalogRepositoryProvider)
          .getEpisodes(args.id, season: args.season);
    });

/// Where to continue a series (client 18 Oct #13): the episode last watched
/// from Continue Watching, or the next one when it was finished.
typedef SeriesResume = ({Episode episode, int? startSec});

final seriesResumeProvider = FutureProvider.autoDispose
    .family<
      SeriesResume?,
      ({String seriesId, String episodeId, double progress, int? startSec})
    >((ref, a) async {
      final seasons = await ref.watch(seasonCountProvider(a.seriesId).future);
      for (var s = 1; s <= (seasons < 1 ? 1 : seasons); s++) {
        final eps = await ref.watch(
          episodesProvider((id: a.seriesId, season: s)).future,
        );
        final i = eps.indexWhere((e) => e.id == a.episodeId);
        if (i < 0) continue;
        if (a.progress < 0.95) return (episode: eps[i], startSec: a.startSec);
        if (i + 1 < eps.length) return (episode: eps[i + 1], startSec: null);
        if (s < seasons) {
          final next = await ref.watch(
            episodesProvider((id: a.seriesId, season: s + 1)).future,
          );
          if (next.isNotEmpty) return (episode: next.first, startSec: null);
        }
        return (episode: eps[i], startSec: null);
      }
      return null;
    });

final seasonCountProvider = FutureProvider.family<int, String>((ref, id) {
  return ref.watch(catalogRepositoryProvider).getSeasonCount(id);
});

final relatedProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  id,
) {
  return ref.watch(catalogRepositoryProvider).getRelated(id);
});

final genresProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(catalogRepositoryProvider).getGenres();
});

final byGenreProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  genre,
) {
  return ref.watch(catalogRepositoryProvider).getByGenre(genre);
});

final trendingProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getTrending();
});

final newReleasesProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getNewReleases();
});

final newSeriesProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getNewSeries();
});

final comingSoonProvider = FutureProvider<List<MediaItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).getComingSoon();
});

/// Account subscriptions from `GET /me/subscriptions`.
/// Fetched again each time a screen shows it (autoDispose), and after a
/// catalog version change, so a package renamed in the Control Panel
/// shows its new name without an app restart (client 20 Oct).
final subscriptionsProvider = FutureProvider.autoDispose<List<SubscriptionDto>>((
  ref,
) async {
  ref.watch(catalogEpochProvider);
  final session = ref.watch(sessionProvider);
  if (!session.isLoggedIn) return const [];
  return ref.watch(mediaRepositoryProvider).subscriptions();
});

/// Sports package gate from `GET /features/sports`.
/// Match centre (fixtures, lineups): hidden until the server enables it.
final matchCentreOnProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.isLoggedIn) return false;
  // Matches and lineups only with the Sports package (client 5 Nov: an
  // account without Sports still saw matches). The server switch alone
  // turned the match centre on for every package.
  final sportsOn = await ref.watch(sportsEnabledProvider.future);
  if (!sportsOn) return false;
  return ref.watch(mediaRepositoryProvider).sports.enabled();
});

/// One day of matches; key = YYYY-MM-DD.
final matchDayProvider =
    FutureProvider.autoDispose.family<MatchDay, String>((ref, date) async {
  final sports = ref.watch(mediaRepositoryProvider).sports;
  final days = matchThreeDays();
  if (date != days[1]) return sports.fixtures(date: date);
  // Today also lists yesterday's matches that are still live after midnight
  // (client 5 Nov, as on LG).
  final results = await Future.wait([
    sports.fixtures(date: date),
    sports.fixtures(date: days[0]).then<MatchDay?>((d) => d, onError: (_) => null),
  ]);
  final today = results[0]!;
  final late = results[1]?.fixtures.where((f) => f.status.live).toList() ?? const <MatchFixture>[];
  if (late.isEmpty) return today;
  final seen = {for (final f in today.fixtures) f.id};
  return MatchDay(
    date: today.date,
    fixtures: [...late.where((f) => !seen.contains(f.id)), ...today.fixtures],
    stale: today.stale,
    fetchedAt: today.fetchedAt,
  );
});

final matchDetailProvider =
    FutureProvider.autoDispose.family<MatchDetail, int>((ref, id) {
  return ref.watch(mediaRepositoryProvider).sports.match(id);
});

/// League table for the match screen's Standings tab (cached 12 h server side).
final matchStandingsProvider =
    FutureProvider.autoDispose.family<LeagueTable, int>((ref, league) {
  return ref.watch(mediaRepositoryProvider).sports.standings(league);
});

/// Sports tab/sections: the admin's "sports" feature flag (remote config).
final sportsEnabledProvider = FutureProvider<bool>(
  (ref) async => ref.watch(featureEnabledProvider('sports')),
);

/// Watch history for the active profile (deduped: one row per title).
final historyProvider = FutureProvider<List<MediaItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  final pid = session.activeProfileId;
  if (!session.isLoggedIn || pid == null || pid.isEmpty) return const [];
  try {
    final list = await ref.watch(mediaRepositoryProvider).history(pid);
    final mapped = list.map(AppMediaRepository.mediaFromContinue).toList();
    return _dedupeHistory(mapped);
  } catch (_) {
    return const [];
  }
});

/// Keep first occurrence per content key (API returns newest-first).
List<MediaItem> _dedupeHistory(List<MediaItem> items) {
  final seen = <String>{};
  final out = <MediaItem>[];
  for (final item in items) {
    final series = item.seriesId?.trim();
    final key = (series != null && series.isNotEmpty)
        ? 'series:$series'
        : '${item.kind.name}:${item.id}';
    if (seen.add(key)) out.add(item);
  }
  return out;
}

final catalogCategoriesProvider =
    FutureProvider.family<List<CatalogCategory>, MediaKind>((ref, kind) {
      return ref.watch(catalogRepositoryProvider).getCategories(kind);
    });

final searchProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  query,
) async {
  final items = await ref.watch(catalogRepositoryProvider).search(query);
  return _withoutLockedSports(ref, items);
});

/// Section-scoped search (Movies / Series / …). Home search stays global.
final sectionSearchProvider =
    FutureProvider.family<List<MediaItem>, ({String query, MediaKind kind})>((
      ref,
      args,
    ) async {
      final items = await ref
          .watch(catalogRepositoryProvider)
          .search(args.query, kind: args.kind);
      if (args.kind == MediaKind.live) return _withoutLockedSports(ref, items);
      return items;
    });

Future<List<MediaItem>> _withoutLockedSports(
  Ref ref,
  List<MediaItem> items,
) async {
  final sportsOn = await ref.watch(sportsEnabledProvider.future);
  if (sportsOn) return items;
  final cats = await ref
      .watch(catalogRepositoryProvider)
      .getCategories(MediaKind.live);
  final sportsIds = {
    for (final c in cats)
      if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
  };
  return [
    for (final item in items)
      if (!RemoteCatalogRepository.isSportsHit(item, sportsIds)) item,
  ];
}

/// Installed app version for Settings ("6.0.14"); it said "v6.0.0".
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Version with the build number for About ("6.0.32 (132)"), read from the
/// installed app.
final appVersionBuildProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';
});

/// Real totals of the user's package per section and package (server
/// `GET /catalog/counts`); null on older servers or when it failed, so the
/// screens never show 0 for an unknown count. Refreshes with the catalog.
final catalogCountsProvider = FutureProvider<CatalogCountsDto?>((ref) async {
  if (ref.watch(demoModeProvider)) return null;
  ref.watch(catalogEpochProvider);
  ref.watch(sessionProvider.select((s) => s.activeProfileId));
  return ref.read(mediaRepositoryProvider).extras.catalogCounts();
});

/// Package order per profile (client 17 Oct).
final categoryOrderStoreProvider = Provider<CategoryOrderStore>((ref) {
  return CategoryOrderStore(ref.watch(mediaRepositoryProvider).extras);
});

/// Series cast for the details "Cast" button (client 20 Oct). Null when the
/// server does not send it yet (backend #16).
/// Series cast: provider names, and TMDB photos when the server has them
/// (client 23 Oct).
final seriesCastProvider = FutureProvider.autoDispose
    .family<({String? names, List<CastPhotoDto> photos}), String>((ref, id) async {
  if (ref.watch(demoModeProvider)) {
    return (names: null, photos: const <CastPhotoDto>[]);
  }
  try {
    final d = await ref.watch(mediaRepositoryProvider).seriesDetail(id);
    return (names: d.cast, photos: d.castPhotos);
  } catch (_) {
    return (names: null, photos: const <CastPhotoDto>[]);
  }
});

/// Whether the device itself is online (offline messages say "server" vs
/// "No internet", client 5 Nov). Re-read with `ref.invalidate`.
final deviceInternetProvider = FutureProvider<bool>((ref) => deviceHasInternet());
