import 'dart:async';

import 'package:data/data.dart' show ContentKind, HomeSection, HomeSectionType, SectionLayout, matchTodayTomorrow;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/account.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../core/library_controller.dart';
import '../../core/media_nav.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/nav_loader.dart';
import '../browse/catalog_view_all_screen.dart' show catalogNewestRoute;
import '../sports/match_centre_screen.dart' show HomeMatchesRail;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();
  final _moviesKey = GlobalKey();
  final _seriesKey = GlobalKey();
  final _liveKey = GlobalKey();
  final _sportsKey = GlobalKey();
  final _top10Key = GlobalKey();
  int _chip = 0;
  bool _retryBusy = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Offline / feed-error Retry: restore session then reload home
  /// (invalidate alone left offline mode stuck — button looked dead).
  Future<void> _retryHome(AppCopy copy) async {
    if (_retryBusy) return;
    setState(() => _retryBusy = true);
    try {
      final ok = await ref.read(sessionProvider.notifier).retryOnline();
      ref.invalidate(homeFeedProvider);
      ref.invalidate(sportsProvider);
      try {
        await ref.read(homeFeedProvider.future);
      } catch (_) {}
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copy.backOnline)),
        );
      }
    } finally {
      if (mounted) setState(() => _retryBusy = false);
    }
  }

  Future<void> _scrollTo(GlobalKey key, int chip) async {
    setState(() => _chip = chip);
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  /// Friday Top 10 notification: bring the Top 10 row into view. Rows far
  /// down are built only when near, so scroll down a screen at a time until
  /// it exists (at most 10 steps).
  Future<void> _jumpToTop10() async {
    // Top 10 hidden in Customize Home: nothing to find; go back to where
    // the page was instead of leaving it at the bottom.
    final start = _scroll.hasClients ? _scroll.offset : 0.0;
    for (var i = 0; i < 10 && mounted; i++) {
      final ctx = _top10Key.currentContext;
      if (ctx != null) {
        if (!ctx.mounted) return;
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.08,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final next = (pos.pixels + pos.viewportDimension * 0.9)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (next <= pos.pixels + 1) break;
      await _scroll.animateTo(
        next,
        duration: const Duration(milliseconds: 140),
        curve: Curves.linear,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted && _scroll.hasClients && _top10Key.currentContext == null) {
      _scroll.jumpTo(start);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A Top 10 notification asked for the row: it stays asked until Home has
    // the list and handles it once (also when Home opens after the tap).
    final jumpAsked = ref.watch(top10JumpProvider) > 0;
    final top10Now = ref.watch(top10Provider).valueOrNull;
    final top10Ready = (top10Now?.movies.isNotEmpty ?? false) ||
        (top10Now?.series.isNotEmpty ?? false);
    if (jumpAsked && top10Ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(top10JumpProvider) == 0) return;
        ref.read(top10JumpProvider.notifier).state = 0;
        _jumpToTop10();
      });
    }
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);
    final feed = ref.watch(homeFeedProvider);
    final cw = ref.watch(continueWatchingProvider);
    final myList = ref.watch(myListItemsProvider);
    final sections = ref.watch(sessionProvider.select((s) => s.homeSections));
    final kids = ref.watch(sessionProvider).activeProfile?.isKids == true;
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: const MainAppBar(),
      body: feed.when(
        loading: () => AppShimmer.homeSkeleton(),
        // Client 18 Oct #16: connection loss gets a way forward, not a
        // raw error.
        error: (e, _) {
          final copy = AppCopy.ofContext(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 44,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ref.watch(deviceInternetProvider).valueOrNull == true
                        ? copy.homeServerUnavailable
                        : copy.homeOffline,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton(
                        onPressed:
                            _retryBusy ? null : () => unawaited(_retryHome(copy)),
                        child: _retryBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(copy.retry),
                      ),
                      OutlinedButton(
                        onPressed: _retryBusy
                            ? null
                            : () => context.push('/downloads'),
                        child: Text(copy.downloads),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        data: (data) {
          final movies = data.top10
              .where((e) => e.kind == MediaKind.movie)
              .toList();
          final series = data.arabicOriginals.isNotEmpty
              ? data.arabicOriginals
              : data.top10
                  .where((e) => e.kind == MediaKind.series)
                  .toList();
          final movieRail =
              movies.isNotEmpty ? movies : data.top10.take(10).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            // Client 24 Oct: pull down refreshes all of Home, including
            // Continue Watching and today's / tomorrow's matches.
            onRefresh: () async {
              // The catalog keeps its movie / series / channel lists for the
              // session, so invalidating the feed returned the same lists
              // (client 24 Oct: pull-to-refresh "does not work"). A new
              // catalog epoch rebuilds the repository and loads them fresh,
              // as a Control Panel catalog change does.
              ref.read(catalogEpochProvider.notifier).state++;
              ref.invalidate(homeFeedProvider);
              ref.invalidate(sportsProvider);
              ref.invalidate(continueWatchingProvider);
              ref.invalidate(homeSectionItemsProvider);
              for (final d in matchTodayTomorrow()) {
                ref.invalidate(matchDayProvider(d));
              }
              await ref.read(libraryProvider.notifier).syncFromRemote();
              await ref.read(homeFeedProvider.future);
            },
            child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (kids)
                SliverToBoxAdapter(
                  child: NeonTap(
                    onTap: () => context.push('/kids'),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.magenta.withValues(alpha: 0.25),
                            AppColors.surface,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.magenta.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.child_care_rounded,
                            color: AppColors.magenta,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              copy.kidsProfileOpenHub,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.magenta,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _TopChips(
                  copy: copy,
                  selected: _chip,
                  onSelect: (i) {
                    switch (i) {
                      case 0:
                        setState(() => _chip = 0);
                        _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                        );
                      case 1:
                        _scrollTo(_moviesKey, 1);
                      case 2:
                        _scrollTo(_seriesKey, 2);
                      case 3:
                        _scrollTo(_liveKey, 3);
                      case 4:
                        _scrollTo(_sportsKey, 4);
                      case 5:
                        context.push('/new');
                      case 6:
                        context.push('/kids');
                    }
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: HomeHeroCarousel(
                  items: _heroCarouselItems(data),
                  copy: copy,
                ),
              ),
              // Retest #12: honor Customize Home order (same ids as TV).
              ..._homeSectionSlivers(
                sections: sections,
                copy: copy,
                data: data,
                continueItems: (cw.isNotEmpty ? cw : data.continueWatching)
                    .take(CatalogPaging.pageSize)
                    .toList(),
                favorites: myList
                    .where((m) => m.kind != MediaKind.live)
                    .take(CatalogPaging.pageSize)
                    .toList(),
                movieRail: movieRail,
                series: series,
                sportsOn: sportsOn,
                sports: (sports.isNotEmpty ? sports : data.matches)
                    .take(CatalogPaging.pageSize)
                    .toList(),
              ),
              SliverToBoxAdapter(child: _VaultBanner(copy: copy)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
            ),
          );
        },
      ),
    );
  }

  /// Home from the admin Home builder (7.1): the admin's sections, order and
  /// titles; each drawn with the app's existing rails (design unchanged).
  /// Empty sections are hidden. The top chips scroll to the first movie /
  /// series / live / matches section.
  List<Widget> _adminSectionSlivers(
    List<HomeSection> sections, {
    required AppCopy copy,
    required HomeFeed data,
    required List<MediaItem> continueItems,
    required List<MediaItem> favorites,
  }) {
    final out = <Widget>[];
    final used = <GlobalKey>{};
    GlobalKey? anchorFor(HomeSection s) {
      final k = switch (s.type) {
        HomeSectionType.liveNow => _liveKey,
        HomeSectionType.matchesLive || HomeSectionType.matchesUpcoming => _sportsKey,
        HomeSectionType.top10 => _top10Key,
        _ => switch (s.kind) {
            ContentKind.movie => _moviesKey,
            ContentKind.series => _seriesKey,
            _ => null,
          },
      };
      return k != null && used.add(k) ? k : null;
    }

    Widget header(HomeSection s, {GlobalKey? anchor, Color? accent, VoidCallback? onAction, String? action}) {
      final h = SectionHeader(title: s.title, accent: accent, actionLabel: action, onAction: onAction);
      return anchor == null ? h : KeyedSubtree(key: anchor, child: h);
    }

    final signedIn = AccountService.signedIn;
    for (final s in sections) {
      if (s.requiresLogin && !signedIn) continue;
      switch (s.type) {
        case HomeSectionType.heroBanners:
          continue; // the hero carousel at the top
        case HomeSectionType.continueWatching:
        case HomeSectionType.recentlyWatched:
          if (continueItems.isEmpty) continue;
          out.add(SliverToBoxAdapter(
            child: header(s, action: copy.seeAll, onAction: () => context.push('/library?tab=continue')),
          ));
          out.add(SliverToBoxAdapter(child: ContinueRow(items: continueItems)));
        case HomeSectionType.favorites:
          if (favorites.isEmpty) continue;
          out.add(SliverToBoxAdapter(
            child: header(s, action: copy.seeAll, onAction: () => context.push('/my-list')),
          ));
          out.add(SliverToBoxAdapter(child: _PosterRail(items: favorites)));
        case HomeSectionType.liveNow:
          if (data.liveChannels.isEmpty) continue;
          out.add(SliverToBoxAdapter(
            child: header(s,
                anchor: anchorFor(s),
                accent: AppColors.live,
                action: copy.seeAll,
                onAction: () => context.go('/live')),
          ));
          out.add(SliverToBoxAdapter(child: _LiveRail(channels: data.liveChannels, copy: copy)));
        case HomeSectionType.matchesLive:
        case HomeSectionType.matchesUpcoming:
          if (ref.watch(matchCentreOnProvider).valueOrNull != true) continue;
          out.add(SliverToBoxAdapter(child: HomeMatchesRail(headerKey: anchorFor(s))));
        default:
          final anchor = anchorFor(s);
          final ranked = s.type == HomeSectionType.top10 || s.layout == SectionLayout.ranked;
          final newest = s.type == HomeSectionType.newReleases || s.type == HomeSectionType.recentlyAdded;
          final kind = switch (s.kind) {
            ContentKind.movie => MediaKind.movie,
            ContentKind.series => MediaKind.series,
            _ => null,
          };
          out.add(SliverToBoxAdapter(
            child: _AdminSectionRail(
              section: s,
              ranked: ranked,
              header: header(
                s,
                anchor: anchor,
                accent: ranked ? AppColors.magenta : null,
                action: newest && kind != null ? copy.seeAll : null,
                onAction: newest && kind != null ? () => context.push(catalogNewestRoute(kind, s.title)) : null,
              ),
            ),
          ));
      }
    }
    return out;
  }

  List<Widget> _homeSectionSlivers({
    required List<String> sections,
    required AppCopy copy,
    required HomeFeed data,
    required List<MediaItem> continueItems,
    required List<MediaItem> favorites,
    required List<MediaItem> movieRail,
    required List<MediaItem> series,
    required bool sportsOn,
    required List<SportsMatch> sports,
  }) {
    final admin = ref.watch(adminHomeSectionsProvider);
    if (admin.isNotEmpty) {
      return _adminSectionSlivers(
        admin,
        copy: copy,
        data: data,
        continueItems: continueItems,
        favorites: favorites,
      );
    }
    final out = <Widget>[];
    final seen = <String>{};
    final weekly = ref.watch(weeklyPicksProvider).valueOrNull;
    final top10 = ref.watch(top10Provider).valueOrNull;

    void addSection(String id) {
      if (!seen.add(id)) return;
      switch (id) {
        case 'Continue Watching':
          if (continueItems.isEmpty) return;
          out.add(
            SliverToBoxAdapter(
              child: SectionHeader(
                title: copy.continueWatching,
                actionLabel: copy.seeAll,
                onAction: () => context.push('/library?tab=continue'),
              ),
            ),
          );
          out.add(SliverToBoxAdapter(child: ContinueRow(items: continueItems)));
        case 'Favorites':
        case 'My List':
          if (favorites.isEmpty) return;
          out.add(
            SliverToBoxAdapter(
              child: SectionHeader(
                title: copy.myList,
                actionLabel: copy.seeAll,
                onAction: () => context.push('/my-list'),
              ),
            ),
          );
          out.add(SliverToBoxAdapter(child: _PosterRail(items: favorites)));
        // Client 18 Oct #15: Weekly Picks for Series as well as Movies,
        // numbered, the same weekly selection as the TV app.
        case 'Top 10 in Your Region':
          final picks = weekly;
          final moviePicks = picks?.movies ?? const <MediaItem>[];
          final seriesPicks = picks?.series ?? const <MediaItem>[];
          if (moviePicks.isNotEmpty) {
            out.add(
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: copy.weeklyMoviePicks,
                  accent: AppColors.magenta,
                  actionLabel: copy.seeAll,
                  // The whole newest list, as on TV (client 10 Nov: See All
                  // opened New & Popular, another list).
                  onAction: () => context.push(
                    catalogNewestRoute(MediaKind.movie, copy.weeklyMoviePicks),
                  ),
                ),
              ),
            );
            out.add(SliverToBoxAdapter(child: _PosterRail(items: moviePicks)));
          }
          if (seriesPicks.isNotEmpty) {
            out.add(
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: copy.weeklySeriesPicks,
                  accent: AppColors.magenta,
                  actionLabel: copy.seeAll,
                  // The whole newest list, as on TV (client 10 Nov: See All
                  // opened New & Popular, another list).
                  onAction: () => context.push(
                    catalogNewestRoute(MediaKind.series, copy.weeklySeriesPicks),
                  ),
                ),
              ),
            );
            out.add(SliverToBoxAdapter(child: _PosterRail(items: seriesPicks)));
          }
          // Top 10 with the numbers, as on LG / Android TV (client 6 Nov).
          var top10Keyed = false;
          for (final (title, items) in [
            (copy.top10Movies, top10?.movies ?? const <MediaItem>[]),
            (copy.top10Series, top10?.series ?? const <MediaItem>[]),
          ]) {
            if (items.isEmpty) continue;
            final header = SectionHeader(
              title: title,
              accent: AppColors.magenta,
            );
            out.add(
              SliverToBoxAdapter(
                // A plain heading, no See All (client 10 Nov: it opened
                // another list; Top 10 is the whole list). The first one is
                // where the Friday Top 10 notification scrolls to.
                child: top10Keyed
                    ? header
                    : KeyedSubtree(key: _top10Key, child: header),
              ),
            );
            top10Keyed = true;
            out.add(SliverToBoxAdapter(child: Top10Row(items: items)));
          }
        case 'Arabic Originals':
          if (data.arabicOriginals.isEmpty) return;
          out.add(
            SliverToBoxAdapter(
              child: SectionHeader(
                title: copy.homeSectionLabel(id),
                actionLabel: copy.seeAll,
                onAction: () => context.go('/series'),
              ),
            ),
          );
          out.add(
            SliverToBoxAdapter(child: _PosterRail(items: data.arabicOriginals)),
          );
        case 'Movies & 4K Blockbusters':
          out.add(
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _moviesKey,
                child: SectionHeader(
                  title: copy.movies,
                  actionLabel: copy.seeAll,
                  onAction: () => context.go('/movies'),
                ),
              ),
            ),
          );
          out.add(SliverToBoxAdapter(child: _PosterRail(items: movieRail)));
        case 'Series & Exclusive Seasons':
          out.add(
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _seriesKey,
                child: SectionHeader(
                  title: copy.series,
                  actionLabel: copy.exploreAll,
                  accent: AppColors.gold,
                  onAction: () => context.go('/series'),
                ),
              ),
            ),
          );
          out.add(SliverToBoxAdapter(child: _PosterRail(items: series)));
        case 'Kids':
          out.add(SliverToBoxAdapter(child: _KidsHomeSection(copy: copy)));
        case 'Live TV & Channels':
          out.add(
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _liveKey,
                child: SectionHeader(
                  title: copy.liveTv,
                  actionLabel: copy.seeAll,
                  accent: AppColors.live,
                  onAction: () => context.go('/live'),
                ),
              ),
            ),
          );
          out.add(
            SliverToBoxAdapter(
              child: _LiveRail(channels: data.liveChannels, copy: copy),
            ),
          );
        case "Today's Matches":
          // Client 20 Oct: when the match centre is on, this slot shows
          // Today's & Tomorrow's matches (Continue Watching right below).
          if (ref.watch(matchCentreOnProvider).valueOrNull == true) {
            out.add(SliverToBoxAdapter(child: HomeMatchesRail(headerKey: _sportsKey)));
            return;
          }
          if (!sportsOn || sports.isEmpty) return;
          out.add(
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _sportsKey,
                child: SectionHeader(
                  title: copy.homeSectionLabel("Today's Matches"),
                  actionLabel: copy.seeAll,
                  accent: AppColors.magenta,
                  onAction: () => context.go('/sports'),
                ),
              ),
            ),
          );
          out.add(
            SliverToBoxAdapter(
              child: _MatchesRow(copy: copy, matches: sports),
            ),
          );
        default:
          return;
      }
    }

    for (final id in sections) {
      addSection(id);
    }
    // (built-in order below is used only without an admin Home layout)
    // Ensure core rails still appear if Customize Home omitted them.
    for (final fallback in const [
      "Today's Matches",
      'Continue Watching',
      'Top 10 in Your Region',
      'Kids',
      'Favorites',
      'Movies & 4K Blockbusters',
      'Series & Exclusive Seasons',
      'Live TV & Channels',
    ]) {
      addSection(fallback);
    }
    return out;
  }
}

class _TopChips extends StatelessWidget {
  const _TopChips({
    required this.copy,
    required this.selected,
    required this.onSelect,
  });

  final AppCopy copy;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = [
      copy.all,
      copy.movies,
      copy.series,
      copy.liveTv,
      copy.sports,
      copy.neu,
      copy.kids,
    ];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        itemBuilder: (_, i) => CategoryChip(
          label: labels[i],
          selected: selected == i,
          showDot: i == 3,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _LiveRail extends StatelessWidget {
  const _LiveRail({required this.channels, required this.copy});
  final List<LiveChannel> channels;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          copy.noLiveChannels,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      height: PosterCard.railHeightFor(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: channels.length.clamp(0, CatalogPaging.pageSize),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final c = channels[i];
          return PosterCard(
            title: c.name,
            badges: c.badge == null ? const [] : [c.badge!],
            imageUrl: c.imageUrl,
            seed: i,
            onTap: () => context.push('/player/${c.id}?kind=live'),
          );
        },
      ),
    );
  }
}

class HomeHeroCarousel extends ConsumerStatefulWidget {
  const HomeHeroCarousel({required this.items, required this.copy});
  final List<MediaItem> items;
  final AppCopy copy;

  @override
  ConsumerState<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends ConsumerState<HomeHeroCarousel> {
  static const _autoInterval = Duration(seconds: 5);
  late final PageController _page;
  Timer? _auto;
  int _index = 0;
  bool _userHolding = false;

  int get _n => widget.items.length;

  int get _loopStart => _n < 2 ? 0 : _n * 500;

  @override
  void initState() {
    super.initState();
    _page = PageController(initialPage: _loopStart);
    _armAuto();
  }

  @override
  void didUpdateWidget(covariant HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _index = 0;
      if (_page.hasClients && _n >= 2) {
        _page.jumpToPage(_loopStart);
      }
      _armAuto();
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _armAuto() {
    _auto?.cancel();
    if (_n < 2) return;
    _auto = Timer.periodic(_autoInterval, (_) {
      if (!mounted || _userHolding || !_page.hasClients) return;
      final cur = _page.page?.round() ?? _loopStart;
      _page.animateToPage(
        cur + 1,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _watch(MediaItem item) async {
    if (item.kind == MediaKind.series) {
      final path = await withPageLoader(context, () async {
        final eps =
            await ref.read(catalogRepositoryProvider).getEpisodes(item.id);
        if (eps.isEmpty) return '/series/${item.id}';
        return '/player/${eps.first.id}?kind=series&seriesId=${item.id}';
      });
      if (!mounted) return;
      context.push(path);
      return;
    }
    await withPageLoader(context, () async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    if (!mounted) return;
    openMediaPlayback(context, item);
  }

  Widget _dots() {
    if (_n < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _n; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: i == _index
                    ? AppColors.cyan
                    : Colors.white.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final copy = widget.copy;
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 0.92,
              child: Listener(
                onPointerDown: (_) {
                  _userHolding = true;
                  _auto?.cancel();
                },
                onPointerUp: (_) {
                  _userHolding = false;
                  _armAuto();
                },
                onPointerCancel: (_) {
                  _userHolding = false;
                  _armAuto();
                },
                child: PageView.builder(
                  controller: _page,
                  // Infinite both directions via modulo.
                  itemBuilder: (context, i) {
                    final logical = _n < 2 ? i : i % _n;
                    final item = items[logical];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        RemoteImage(
                          url: pickWideArt([item.backdropUrl], poster: item.posterUrl),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.55),
                                Colors.black.withValues(alpha: 0.92),
                              ],
                            ),
                          ),
                        ),
                        // Client design: VIP + quality (e.g. 4K ULTRA) top-end.
                        PositionedDirectional(
                          top: 12,
                          end: 12,
                          child: const _HeroCornerBadges(),
                        ),
                        if (_n > 1) ...[
                          PositionedDirectional(
                            start: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _HeroArrowButton(
                                icon: Icons.chevron_left_rounded,
                                onTap: () {
                                  if (!_page.hasClients) return;
                                  final cur =
                                      _page.page?.round() ?? _loopStart;
                                  _page.animateToPage(
                                    cur - 1,
                                    duration:
                                        const Duration(milliseconds: 360),
                                    curve: Curves.easeInOutCubic,
                                  );
                                },
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            end: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _HeroArrowButton(
                                icon: Icons.chevron_right_rounded,
                                onTap: () {
                                  if (!_page.hasClients) return;
                                  final cur =
                                      _page.page?.round() ?? _loopStart;
                                  _page.animateToPage(
                                    cur + 1,
                                    duration:
                                        const Duration(milliseconds: 360),
                                    curve: Curves.easeInOutCubic,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Only badges the catalog reports ("Top 10
                              // #n" was the slide position; there is no
                              // ranking data — removed on TV too).
                              Text(
                                item.displayTitle.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                              ),
                              if (item.subtitle != null)
                                Text(
                                  item.subtitle!.toUpperCase(),
                                  style: TextStyle(
                                    color: AppColors.cyan,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              if (item.titleArabic != null)
                                Text(
                                  item.titleArabic!,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                // Real metadata only (the fixed 4K Ultra
                                // HD / Dolby Atmos / 18+ were not data).
                                [
                                  if (item.year != null) '${item.year}',
                                  if (item.durationLabel != null)
                                    item.durationLabel!,
                                  ...copy.genres(item.genres).take(2),
                                ].join(' • '),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Client 20 Oct #8 (Strong app): Watch Now and
                              // Details as two separate boxes side by side.
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.cyan
                                                .withValues(alpha: 0.35),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                      child: PrimaryButton(
                                        label: copy.watchNow,
                                        onPressed: () => _watch(item),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 52,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                              Colors.white.withValues(alpha: 0.08),
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          side: const BorderSide(color: Colors.white24),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: () =>
                                            openMediaBrowse(context, item),
                                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                                        // One line in every language (Arabic
                                        // "التفاصيل" wrapped on narrow phones).
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            copy.details,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                  onPageChanged: (i) {
                    setState(() => _index = _n < 2 ? i : i % _n);
                    if (!_userHolding) _armAuto();
                  },
                ),
              ),
            ),
          ),
          _dots(),
        ],
      ),
    );
  }
}

/// Main banner: 2 movies + 2 series from 4K / recent (rotates daily).
List<MediaItem> _heroCarouselItems(HomeFeed data) {
  final movies = [
    for (final m in [data.hero, ...data.top10])
      if (m.kind == MediaKind.movie) m,
  ];
  final series = [
    for (final m in [...data.arabicOriginals, ...data.top10, data.hero])
      if (m.kind == MediaKind.series) m,
  ];
  final picks = pickHeroCarousel(movies: movies, series: series);
  if (picks.isNotEmpty) return picks;
  final art = pickWideArt([data.hero.backdropUrl], poster: data.hero.posterUrl);
  if (art != null && art.isNotEmpty) return [data.hero];
  return const [];
}

class _HeroArrowButton extends StatelessWidget {
  const _HeroArrowButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // C25 Strong look: dark disc + light rim (matches TV banner arrows).
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.55),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// VIP + 4K ULTRA — top-end of banner (client design).
class _HeroCornerBadges extends StatelessWidget {
  const _HeroCornerBadges();

  @override
  Widget build(BuildContext context) {
    // Design always pairs VIP with 4K ULTRA on the main banner.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroSolidBadge(
          label: 'VIP',
          background: AppColors.gold,
        ),
        SizedBox(width: 6),
        _HeroSolidBadge(
          label: '4K ULTRA',
          background: Color(0xFFC8CCD2),
        ),
      ],
    );
  }
}

class _HeroSolidBadge extends StatelessWidget {
  const _HeroSolidBadge({
    required this.label,
    required this.background,
  });
  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
          height: 1.1,
        ),
      ),
    );
  }
}

class _MatchesRow extends StatelessWidget {
  const _MatchesRow({required this.copy, required this.matches});
  final AppCopy copy;
  final List<SportsMatch> matches;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final m = matches[i];
          return Container(
            width: 224,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // The whole picture opens the channel, not only the
                  // Watch button (client 19 Oct: hard to select).
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/player/${m.id}?kind=live'),
                    child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RemoteImage(url: m.imageUrl),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                TechBadge(
                                  copy.live,
                                  tone: BadgeTone.live,
                                  compact: true,
                                ),
                                const Spacer(),
                                Text(
                                  m.minute,
                                  style: TextStyle(
                                    color: AppColors.magenta,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              // A channel (no opponent): name only.
                              m.awayTeam.isEmpty
                                  ? m.homeTeam
                                  : '${m.homeTeam}  ${m.homeScore} - ${m.awayScore}  ${m.awayTeam}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [m.stadium, m.broadcaster]
                                  .where((e) => e.isNotEmpty)
                                  .join(' • '),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ContinueRow extends StatelessWidget {
  const ContinueRow({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    // Client 24 Oct: landscape cards for movies and series; the episode
    // still / backdrop fills the card.
    const w = 208.0;
    return SizedBox(
      height: ContinueCard.heightFor(w),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _ContinueTile(item: items[i], width: w),
      ),
    );
  }
}

class _ContinueTile extends ConsumerWidget {
  const _ContinueTile({required this.item, required this.width});
  final MediaItem item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = item.kind == MediaKind.series || item.seriesId != null;
    // Movies: the wide backdrop from the movie details (cached), so the
    // card is not a cropped poster (client 24 Oct).
    // Episode still / movie scene from Continue Watching (looked up by the
    // library), else the movie's backdrop; TMDB first (no provider logo).
    final backdrop = pickCleanArt([
      item.backdropUrl,
      if (!series) ref.watch(vodInfoProvider(item.id)).valueOrNull?.backdropUrl,
    ]);
    final copy = AppCopy.ofContext(context);
    // Long-press: remove from Continue Watching (client 10 Nov). The "more"
    // button shows the same choice for anyone who does not know the
    // long-press (client 12 Nov: "option to remove a title"); a swipe would
    // fight the row's own sideways scroll and the page's scroll.
    return GestureDetector(
      onLongPress: () => confirmRemoveContinue(context, ref, item),
      child: Stack(
        children: [
          ContinueCard(
            width: width,
            title: item.displayTitle,
            imageUrl: item.posterUrl,
            wideImageUrl: backdrop,
            caption: copy.continueLabel(
                  positionSec: item.resumePositionSec,
                  title: item.title,
                  series: series,
                  progress: item.progress,
                ) ??
                item.progressLabel,
            progress: item.progress,
            onTap: () => openMediaBrowse(context, item),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => confirmRemoveContinue(context, ref, item),
                child: Tooltip(
                  message: copy.removeFromContinue,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Remove from Continue Watching?" for [item]; true when it was removed.
/// Home row (long-press / more button) and the full list in Library (swipe /
/// long-press, client 12 Nov).
Future<bool> confirmRemoveContinue(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) async {
  final copy = AppCopy.ofContext(context);
  final remove = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
            title: Text(
              copy.removeFromContinue,
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
          ListTile(
            leading: const Icon(Icons.close_rounded),
            title: Text(copy.cancel),
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (remove != true || !context.mounted) return false;
  final ok = await ref.read(libraryProvider.notifier).removeFromContinue(item);
  if (!ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(copy.removeFromContinueFailed)),
    );
  }
  return ok;
}

class Top10Row extends StatelessWidget {
  const Top10Row({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    final page = items.take(CatalogPaging.pageSize).toList();
    // Same numbering as "New & Popular" on every ranked row (client 21 Oct A12).
    return SizedBox(
      height: PosterCard.railHeightFor() + 20,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: page.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final item = page[i];
          return RankedRailItem(
            rank: i + 1,
            // Same blue on iPhone and Android, clear of the title (client 9 Nov).
            color: AppColors.cyan,
            bottom: RankedRailItem.bottomClearOfTitle,
            child: PosterCard(
              title: item.displayTitle,
              rating: item.posterRating,
              subtitle: item.genres.isEmpty ? null : item.genres.first,
              badges: item.badges,
              imageUrl: item.posterUrl,
              seed: item.posterSeed ?? i,
              onTap: () => openMediaBrowse(context, item),
            ),
          );
        },
      ),
    );
  }
}

class _VaultBanner extends StatelessWidget {
  const _VaultBanner({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surfaceElevated,
                      Colors.black.withValues(alpha: 0.92),
                      AppColors.cyan.withValues(alpha: 0.18),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TechBadge(copy.curatedVaultBadge, compact: true),
                      const SizedBox(width: 8),
                      TechBadge(
                        copy.imaxEnhancedBadge,
                        tone: BadgeTone.magenta,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.cinemaVaultTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.cinemaVaultBlurb,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: copy.exploreVault,
                    icon: Icons.auto_awesome,
                    onPressed: () => context.push('/vault'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final page = items.take(CatalogPaging.pageSize).toList();
    return SizedBox(
      height: PosterCard.railHeightFor(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: page.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final item = page[i];
          return PosterCard(
            title: item.displayTitle,
            subtitle: item.titleArabic,
            badges: item.badges,
            rating: item.posterRating,
            matchPercent: item.matchPercent,
            imageUrl: item.posterUrl,
            seed: item.posterSeed ?? i,
            onTap: () => openMediaBrowse(context, item),
          );
        },
      ),
    );
  }
}

class _KidsHomeSection extends ConsumerWidget {
  const _KidsHomeSection({required this.copy});
  final AppCopy copy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kids = ref.watch(kidsCatalogProvider);
    return kids.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          AppShimmer.posterRail(count: 5),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: copy.kids,
              actionLabel: copy.seeAll,
              accent: AppColors.magenta,
              onAction: () => context.push('/kids'),
            ),
            _PosterRail(items: items),
          ],
        );
      },
    );
  }
}

/// One admin Home section filled from the user's panel (hidden while empty).
class _AdminSectionRail extends ConsumerWidget {
  const _AdminSectionRail({required this.section, required this.ranked, required this.header});
  final HomeSection section;
  final bool ranked;
  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeSectionItemsProvider(section.id)).valueOrNull ?? const <MediaItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (ranked) Top10Row(items: items.take(10).toList()) else _PosterRail(items: items),
      ],
    );
  }
}
