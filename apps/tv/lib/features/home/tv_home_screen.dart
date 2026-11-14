import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/push_notifications.dart';
import '../../core/tv_input_activity.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_media_nav.dart';
import '../../core/tv_session.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_feed_loading.dart';
import '../../widgets/tv_media_card.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';
import '../browse/tv_view_all_screen.dart';
import '../sports/tv_match_centre_screen.dart' show TvHomeMatchesRail;

/// Figma: the app TV Home (UHD Master Hero)
/// The first Top 10 row on Home (Friday Top 10 notification target).
final tvTop10Key = GlobalKey(debugLabel: 'tvTop10');

/// Home's list scroll, so the Top 10 notification can bring that row in.
final tvHomeScrollProvider = Provider<ScrollController>((ref) {
  final c = ScrollController();
  ref.onDispose(c.dispose);
  return c;
});

/// Friday Top 10 notification (TOP10, Usman 12 Nov): Home shows the Top 10
/// row with the focus on its first card. Rows far down are built only when
/// near, so the list moves down a screen at a time until the row exists.
Future<void> tvJumpToTop10(ScrollController scroll) async {
  // Top 10 hidden in Customize Home: go back to where the page was.
  double? start;
  for (var i = 0; i < 20; i++) {
    await WidgetsBinding.instance.endOfFrame;
    final ctx = tvTop10Key.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        alignment: 0.15,
      );
      if (!ctx.mounted) return;
      FocusNode? first;
      void visit(Element e) {
        if (first != null) return;
        final w = e.widget;
        if (w is Focus &&
            w.focusNode != null &&
            w.focusNode!.canRequestFocus &&
            !w.focusNode!.skipTraversal) {
          first = w.focusNode;
          return;
        }
        e.visitChildren(visit);
      }
      (ctx as Element).visitChildren(visit);
      first?.requestFocus();
      return;
    }
    if (!scroll.hasClients) {
      // Home still loading (feed / Top 10): wait a little, then try again.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      continue;
    }
    final pos = scroll.position;
    start ??= pos.pixels;
    final next = (pos.pixels + pos.viewportDimension * 0.9)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (next <= pos.pixels + 1) break;
    scroll.jumpTo(next);
  }
  if (start != null && scroll.hasClients && tvTop10Key.currentContext == null) {
    scroll.jumpTo(start);
  }
}

class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final cw = ref.watch(continueWatchingProvider);
    final matchCentreOn = ref.watch(matchCentreOnProvider).valueOrNull == true;
    // Client: My List on Home = movies / series only; channels live in
    // Favourites / Live TV.
    final myList = ref
        .watch(myListItemsProvider)
        .where((m) => m.kind != MediaKind.live && !m.isLive)
        .toList();
    final comingSoon = ref.watch(comingSoonProvider);
    final movies = ref.watch(moviesProvider).valueOrNull ?? const [];
    final series = ref.watch(seriesProvider).valueOrNull ?? const [];
    final kidsItems = ref.watch(kidsCatalogProvider).valueOrNull ?? const [];
    final weekly = ref.watch(weeklyPicksProvider).valueOrNull;
    final top10 = ref.watch(top10Provider).valueOrNull;
    // Only the section list: watching the whole session rebuilt every rail
    // on each heartbeat / profile / notification change (TCL lag 21 Oct).
    final sections = ref.watch(tvSessionProvider.select((s) => s.homeSections));
    final language = ref.watch(tvLanguageProvider);
    final copy = AppCopy.ofLanguage(language);

    return feed.when(
      loading: () => const TvFeedLoading(),
      // Client 18 Oct #16: connection loss gets a way forward.
      // Retry must call TvSession.retryOnline (invalidate alone looked dead).
      error: (e, _) => _TvHomeOfflineError(copy: copy),
      data: (data) {
        final continueItems = cw.isNotEmpty ? cw : data.continueWatching;
        final updateBanner = ref.watch(tvUpdateBannerProvider);
        final rails = <Widget>[];
        if (updateBanner != null) {
          rails.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 8, 36, 4),
              child: FocusTile(
                borderRadius: 12,
                onTap: () => context.push('/inbox'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.system_update_alt_rounded,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          updateBanner.title.isNotEmpty
                              ? updateBanner.title
                              : copy.updateAvailableBanner,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        Widget? sectionFor(String id) {
          switch (id) {
            case "Today's Matches":
              // Client 20 Oct: with the match centre on, this slot shows
              // Today's & Tomorrow's matches (Continue Watching right below).
              if (matchCentreOn) return const TvHomeMatchesRail();
              if (data.matches.isEmpty) return null;
              return _MatchesRail(matches: data.matches);
            case 'Continue Watching':
              // Task #143 #10: progress + minutes via TvPoster.fromMedia.
              // P1.9/P1.14: CW resumes in player; View All → full CW list.
              // (Other rails stay details-first per Task #143 #12.)
              if (continueItems.isEmpty) return null;
              // Client 24 Oct: landscape cards, as on the phone.
              return ContinueRail(
                title: copy.homeSectionLabel(id),
                items: continueItems,
                accent: AppColors.cyan,
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push('/library?tab=continue'),
              );
            case 'Favorites':
            case 'My List':
              if (myList.isEmpty) return null;
              return ContentRail(
                title: copy.myList,
                items: myList,
                preferPlay: false,
                accent: AppColors.magenta,
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push('/library?tab=watchlater'),
              );
            // No ranking data from the backend: labelled weekly picks, a
            // stable selection per Riyadh week (WeeklyPicks), not "Top 10".
            case 'Top 10 in Your Region':
              final moviePicks = weekly?.movies ?? const <MediaItem>[];
              final seriesPicks = weekly?.series ?? const <MediaItem>[];
              if (moviePicks.isEmpty && seriesPicks.isEmpty) return null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (moviePicks.isNotEmpty)
                    ContentRail(
                      title: copy.weeklyMoviePicks,
                      items: moviePicks,
                      viewAllLabel: copy.viewAll,
                      // The whole newest list (client 10 Nov: View All
                      // opened New & Popular, another list).
                      onViewAll: () => context.push(
                        tvViewAllRoute(
                          MediaKind.movie,
                          tvNewestCategory,
                          copy.weeklyMoviePicks,
                        ),
                      ),
                    ),
                  if (moviePicks.isNotEmpty && seriesPicks.isNotEmpty)
                    const SizedBox(height: TvUi.sectionGap),
                  if (seriesPicks.isNotEmpty)
                    ContentRail(
                      title: copy.weeklySeriesPicks,
                      items: seriesPicks,
                      viewAllLabel: copy.viewAll,
                      onViewAll: () => context.push(
                        tvViewAllRoute(
                          MediaKind.series,
                          tvNewestCategory,
                          copy.weeklySeriesPicks,
                        ),
                      ),
                    ),
                  // Top 10 with the LG numbers (client 5 Nov). A plain
                  // heading, no View All (client 10 Nov: it opened another
                  // list; Top 10 is the whole list).
                  // The first Top 10 row is where the Friday Top 10
                  // notification goes ([tvJumpToTop10], Usman 12 Nov).
                  if ((top10?.movies ?? const []).isNotEmpty) ...[
                    const SizedBox(height: TvUi.sectionGap),
                    KeyedSubtree(
                      key: tvTop10Key,
                      child: ContentRail(
                        title: copy.top10Movies,
                        items: top10!.movies,
                        ranked: true,
                      ),
                    ),
                  ],
                  if ((top10?.series ?? const []).isNotEmpty) ...[
                    const SizedBox(height: TvUi.sectionGap),
                    KeyedSubtree(
                      key: top10!.movies.isEmpty ? tvTop10Key : null,
                      child: ContentRail(
                        title: copy.top10Series,
                        items: top10.series,
                        ranked: true,
                      ),
                    ),
                  ],
                ],
              );
            case 'Arabic Originals':
              return ContentRail(
                title: copy.homeSectionLabel(id),
                items: data.arabicOriginals,
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push(
                  tvViewAllRoute(
                    MediaKind.series,
                    tvAllCategory,
                    copy.homeSectionLabel(id),
                  ),
                ),
              );
            case 'Live TV & Channels':
              if (data.liveChannels.isEmpty) return null;
              return ContentRail(
                title: copy.homeSectionLabel(id),
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push('/live'),
                items: [
                  for (final c in data.liveChannels.take(
                    CatalogPaging.pageSize,
                  ))
                    MediaItem(
                      id: c.id,
                      title: c.name,
                      kind: MediaKind.live,
                      isLive: true,
                      posterUrl: c.imageUrl,
                      backdropUrl: c.imageUrl,
                      streamUrl: c.streamUrl,
                      subtitle: c.nowTitle,
                    ),
                ],
              );
            case 'Movies & 4K Blockbusters':
              return ContentRail(
                title: copy.homeSectionLabel(id),
                // Home shows a subset; View All opens every movie, paged.
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push(
                  tvViewAllRoute(
                    MediaKind.movie,
                    tvAllCategory,
                    copy.homeSectionLabel(id),
                  ),
                ),
                items: movies.isNotEmpty
                    ? movies.take(CatalogPaging.pageSize).toList()
                    : data.top10
                          .where((e) => e.kind == MediaKind.movie)
                          .toList(),
              );
            case 'Series & Exclusive Seasons':
              return ContentRail(
                title: copy.homeSectionLabel(id),
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push(
                  tvViewAllRoute(
                    MediaKind.series,
                    tvAllCategory,
                    copy.homeSectionLabel(id),
                  ),
                ),
                items: series.isNotEmpty
                    ? series.take(CatalogPaging.pageSize).toList()
                    : data.arabicOriginals,
              );
            case 'Kids':
              if (kidsItems.isEmpty) return null;
              return ContentRail(
                title: copy.homeSectionLabel(id),
                viewAllLabel: copy.viewAll,
                onViewAll: () => context.push('/kids'),
                items: kidsItems.take(CatalogPaging.pageSize).toList(),
              );
            default:
              return null;
          }
        }

        for (final id in sections) {
          final w = sectionFor(id);
          if (w != null) rails.add(w);
        }
        // Append Favorites only if Customize Home did not already place it.
        final hasFavSection = sections.any(
          (id) => id == 'Favorites' || id == 'My List',
        );
        if (!hasFavSection && myList.isNotEmpty) {
          rails.add(
            ContentRail(
              title: copy.myList,
              items: myList,
              preferPlay: false,
              accent: AppColors.magenta,
              viewAllLabel: copy.viewAll,
              onViewAll: () => context.push('/library?tab=watchlater'),
            ),
          );
        }
        comingSoon.when(
          loading: () {},
          error: (_, _) {},
          data: (items) {
            if (items.isNotEmpty) {
              rails.add(
                ContentRail(
                  title: copy.comingSoon,
                  items: items,
                  // No View All (client 10 Nov): it opened New & Popular and
                  // the server has no longer Coming Soon list.
                ),
              );
            }
          },
        );

        // Client 20 Oct Home order: banner, Today's Matches, Continue
        // Watching, Top Movies, Top Series, Kids. The Figma "More Like This"
        // rail under the banner pushed the matches down, so it is gone.
        final heroItems = _heroCarouselItems(data);

        // One list item per rail (TCL scroll lag 16 Oct): every rail used to
        // sit in one Column, so all of them were built, laid out and rebuilt
        // together on any change. Now only rails near the screen exist.
        final body = <Widget>[...rails];
        return ListView.builder(
          controller: ref.watch(tvHomeScrollProvider),
          padding: const EdgeInsets.only(bottom: 48),
          physics: const AlwaysScrollableScrollPhysics(),
          // Keeps the next rail ready for D-pad Down.
          scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
          itemCount: body.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return TvHeroCarousel(items: heroItems);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: body[i - 1],
            );
          },
        );
      },
    );
  }
}

class _MatchesRail extends ConsumerWidget {
  const _MatchesRail({required this.matches});
  final List<SportsMatch> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 8, 10),
          child: TvSectionTitle(
            copy.homeSectionLabel("Today's Matches"),
            accent: AppColors.magenta,
            trailing: copy.viewAll,
            onTap: () => context.push('/match-centre'),
          ),
        ),
        SizedBox(
          height: TvMatchCard.height + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            scrollCacheExtent: const ScrollCacheExtent.pixels(800),
            itemCount: matches.length.clamp(0, CatalogPaging.pageSize),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final m = matches[i];
              return TvMatchCard(
                match: m,
                escapeToSidebar: i == 0,
                onTap: () => context.push('/player/${m.id}?kind=live'),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Home banner; also used at the top of Kids (client 20 Oct).
class TvHeroCarousel extends ConsumerStatefulWidget {
  const TvHeroCarousel({
    super.key,
    required this.items,
    this.height = homeHeight,
  });
  final List<MediaItem> items;

  /// Banner height on Home (client 15 Oct: 372 of a 540-dp-high TV screen).
  static const homeHeight = 372.0;

  /// Kids has its header and Movies / Series / Live TV buttons above the
  /// banner, so a shorter banner keeps its buttons on screen (client 23 Oct:
  /// Watch Now / Details / My List were cut at the bottom).
  static const kidsHeight = 300.0;

  final double height;

  @override
  ConsumerState<TvHeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<TvHeroCarousel> {
  static const _autoInterval = Duration(seconds: 6);
  Timer? _auto;
  int _index = 0;
  bool _playAutofocus = true;

  int get _n => widget.items.length;

  @override
  void initState() {
    super.initState();
    _armAuto();
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  void _armAuto() {
    _auto?.cancel();
    if (_n < 2) return;
    _auto = Timer.periodic(_autoInterval, (_) {
      if (!mounted) return;
      // A slide change is the heaviest frame on the page: not while the
      // user is moving around (TCL scroll lag), not when the hero is
      // scrolled away, not on a hidden tab.
      if (!TvInputActivity.idleFor(const Duration(seconds: 5))) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      final outer = Scrollable.maybeOf(context)?.position;
      if (outer != null && outer.pixels > widget.height * 0.5) return;
      _show(_index + 1);
    });
  }

  /// Cross-fade to slide [i] (client 16 Oct: the sideways slide of the
  /// poster art looked wrong; a fade is calmer and cheaper on 2 GB TVs).
  void _show(int i) {
    if (_n < 2) return;
    _playAutofocus = false;
    setState(() => _index = i % _n < 0 ? i % _n + _n : i % _n);
  }

  void _go(int delta) {
    if (_n < 2) return;
    _show(_index + delta);
    _armAuto();
  }

  Future<void> _watch(MediaItem item) async {
    if (item.kind == MediaKind.series) {
      final eps = await ref
          .read(catalogRepositoryProvider)
          .getEpisodes(item.id);
      if (!mounted) return;
      if (eps.isEmpty) {
        context.push('/details/${item.id}', extra: item);
        return;
      }
      context.push('/player/${eps.first.id}?kind=series&seriesId=${item.id}');
      return;
    }
    if (!mounted) return;
    context.push(item.playbackRoute());
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final item = items[_index.clamp(0, items.length - 1)];

    return Focus(
      // Key handler only: as a focusable node it caught the first Up from
      // the row below (invisible focus, so Up looked dead).
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (items.length < 2) return KeyEventResult.ignored;
        // Left/Right move between the hero buttons first; only past the
        // last (or first) button do they change the slide.
        final primary = FocusManager.instance.primaryFocus;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (tvMoveFocus(primary, TraversalDirection.left)) {
            return KeyEventResult.handled;
          }
          _go(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (tvMoveFocus(primary, TraversalDirection.right)) {
            return KeyEventResult.handled;
          }
          _go(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // Figma v2TV1: cinematic hero, full-bleed art (no poster card).
            // Client 15 Oct: slightly smaller (was 420 of a 540-dp-high TV
            // screen) so the first row shows; title/buttons keep their size.
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fade between slides (was a sideways PageView slide).
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey(_index),
                    child: Builder(
                      builder: (context) {
                        final slide = items[_index.clamp(0, items.length - 1)];
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            TvHeroArt(
                              url: pickWideArt(
                                [slide.backdropUrl],
                                poster: slide.posterUrl,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // As on LG: VIP (+ 4K ULTRA for a 4K title) + Movies / Series.
                PositionedDirectional(
                  top: 20,
                  end: 28,
                  child: _HeroCornerBadges(item: item),
                ),
                // Align (not full-bleed Padding) so side arrows stay tappable /
                // focusable — a full-size Padding was covering C25 arrows.
                Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 24, 56, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              Text(
                                item.displayTitle.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TvUi.titleXL,
                              ),
                              if ((item.titleArabic ?? '').trim().isNotEmpty)
                                Text(
                                  item.titleArabic!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TvUi.titleArabic,
                                  textDirection: TextDirection.rtl,
                                )
                              else if ((item.subtitle ?? '').trim().isNotEmpty)
                                Text(
                                  item.subtitle!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TvUi.titleArabic,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _HeroMetaLine(item: item),
                          if ((item.synopsis ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              item.synopsis!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TvUi.body,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: TvUi.buttonGap,
                            runSpacing: TvUi.buttonGap,
                            children: [
                              TvButton(
                                primary: true,
                                autofocus: _playAutofocus,
                                escapeToSidebar: true,
                                scrollToTopOnFocus: true,
                                icon: Icons.play_arrow_rounded,
                                label: copy.watchNow,
                                onTap: () {
                                  _playAutofocus = false;
                                  _watch(item);
                                },
                              ),
                              // As on LG 6.1.30: Watch Now + More Info only.
                              TvButton(
                                scrollToTopOnFocus: true,
                                icon: Icons.info_outline_rounded,
                                label: copy.moreInfo,
                                onTap: () => openTvMedia(context, item),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Slide dots inside the banner at the bottom end, as on LG (no side arrows).
                if (_n > 1)
                  PositionedDirectional(
                    end: 28,
                    bottom: 30,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _n; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 17 : 6,
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
                  ),
              ],
            ),
          ),
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
  // Clean TMDB art first, as on LG (the provider's posters carry its "8K" stamp).
  int score(MediaItem m) => isTmdbImage(m.backdropUrl) ? 0 : (isTmdbImage(m.posterUrl) ? 1 : 2);
  final ranked = [
    for (var i = 0; i < picks.length; i++) (i, picks[i]),
  ]..sort((a, b) {
      final c = score(a.$2).compareTo(score(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  if (picks.isNotEmpty) return [for (final e in ranked) e.$2];
  final art = pickWideArt([data.hero.backdropUrl], poster: data.hero.posterUrl);
  if (art != null && art.isNotEmpty) return [data.hero];
  return const [];
}

class _HeroCornerBadges extends StatelessWidget {
  const _HeroCornerBadges({required this.item});
  final MediaItem item;

  bool get _is4k {
    final t = [...item.badges, item.title].join(' ').toUpperCase();
    return t.contains('4K') || t.contains('UHD');
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofContext(context);
    // As on LG: VIP, 4K ULTRA only for a 4K title, then the section.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroSolidBadge(label: 'VIP', background: AppColors.gold),
        if (_is4k) ...[
          const SizedBox(width: 8),
          const _HeroSolidBadge(label: '4K ULTRA', background: Color(0xFFC8CCD2)),
        ],
        const SizedBox(width: 8),
        _HeroSolidBadge(
          label: item.kind == MediaKind.series ? copy.series : copy.movies,
          background: const Color(0x1FFFFFFF),
          foreground: Colors.white,
        ),
      ],
    );
  }
}

class _HeroSolidBadge extends StatelessWidget {
  const _HeroSolidBadge({
    required this.label,
    required this.background,
    this.foreground = Colors.black,
  });
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    // Pill as on LG.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Match % in cyan (Figma), then year / runtime / genres from catalog only.
class _HeroMetaLine extends StatelessWidget {
  const _HeroMetaLine({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofContext(context);
    final rest = <String>[
      if (item.year != null) '${item.year}',
      if (item.durationLabel != null) copy.durationText(item.durationLabel),
      if (item.genres.isNotEmpty) copy.genres(item.genres).take(2).join(' / '),
    ];
    return Text.rich(
      TextSpan(
        style: TvUi.meta,
        children: [
          if (item.matchPercent != null) ...[
            TextSpan(
              text: '${item.matchPercent}% Match',
              style: TvUi.meta.copyWith(
                color: AppColors.cyan,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (rest.isNotEmpty) const TextSpan(text: '  •  '),
          ],
          if (rest.isNotEmpty) TextSpan(text: rest.join('  •  ')),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Home feed error: Retry must call [TvSession.retryOnline], not only
/// invalidate (same bug as phone — button looked dead while offline).

/// Home feed error: Retry must call [TvSession.retryOnline], not only
/// invalidate (same bug as phone — button looked dead while offline).
class _TvHomeOfflineError extends ConsumerStatefulWidget {
  const _TvHomeOfflineError({required this.copy});

  final AppCopy copy;

  @override
  ConsumerState<_TvHomeOfflineError> createState() =>
      _TvHomeOfflineErrorState();
}

class _TvHomeOfflineErrorState extends ConsumerState<_TvHomeOfflineError> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(tvSessionProvider.notifier).retryOnline();
      ref.invalidate(homeFeedProvider);
      try {
        await ref.read(homeFeedProvider.future);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 52,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              ref.watch(deviceInternetProvider).valueOrNull == true
                  ? copy.homeServerUnavailable
                  : copy.homeOffline,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvButton(
                primary: true,
                autofocus: true,
                icon: Icons.refresh_rounded,
                label: _busy ? '…' : copy.retry,
                onTap: _busy ? null : () => unawaited(_retry()),
              ),
              const SizedBox(width: 14),
              TvButton(
                label: copy.downloads,
                onTap: _busy ? null : () => context.push('/downloads'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
