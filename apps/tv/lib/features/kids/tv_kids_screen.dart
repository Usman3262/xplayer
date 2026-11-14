import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/tv_feed_loading.dart';
import '../../core/tv_section_back.dart';
import '../../widgets/tv_genre_chip_bar.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_ui.dart';
import '../browse/tv_view_all_screen.dart' show tvViewAllRoute;
import '../home/tv_home_screen.dart' show TvHeroCarousel;
import '../live/tv_live_screen.dart';

/// TV Kids hub (client 21 Oct layout):
/// 1. Movies / Series / Live TV at the top;
/// 2. rotating banner of the best recently added kids titles;
/// 3. Continue Watching (kids titles only);
/// 4. Top 10 Kids Series and 5. Top 10 Kids Movies — a random 10 that stays
///    the same all week and changes every Monday ([WeeklyPicks]), with the
///    Top 10 numbers.
/// Movies / Series / Live TV open that type's kids categories; pressing the
/// selected one again returns to the Kids home.
class TvKidsScreen extends ConsumerStatefulWidget {
  const TvKidsScreen({super.key});

  @override
  ConsumerState<TvKidsScreen> createState() => _TvKidsScreenState();
}

class _TvKidsScreenState extends ConsumerState<TvKidsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  /// null = Kids home; otherwise the type whose categories are shown.
  MediaKind? _kind;

  /// 0 = All; otherwise index+1 into this type's kids categories.
  int _chipIndex = 0;

  final Map<MediaKind, FocusNode> _kindFocus = {
    for (final k in const [MediaKind.movie, MediaKind.series, MediaKind.live])
      k: FocusNode(debugLabel: 'kids-${k.name}'),
  };

  @override
  void initState() {
    super.initState();
    tvSectionBack = _backToKidsHome;
  }

  /// Back inside a Kids section returns to the Kids landing page, on the
  /// button that opened it (client 9 Nov). False on the landing page, or when
  /// Kids is not the visible section, so the shell handles Back as usual.
  bool _backToKidsHome() {
    final kind = _kind;
    if (kind == null || !mounted || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    setState(() {
      _kind = null;
      _chipIndex = 0;
      _clearSearchField();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _kindFocus[kind]?.requestFocus();
    });
    return true;
  }

  @override
  void dispose() {
    if (tvSectionBack == _backToKidsHome) tvSectionBack = null;
    for (final n in _kindFocus.values) {
      n.dispose();
    }
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearchField() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _query = '';
  }

  void _selectKind(MediaKind kind) => setState(() {
        _kind = _kind == kind ? null : kind;
        _chipIndex = 0;
        _clearSearchField();
      });

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final ar = AppCopy.ofLanguage('ar');
    final totalTitles = ref.watch(kidsCatalogProvider).valueOrNull?.length ?? 0;

    Widget option(MediaKind kind, String label, IconData icon) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: TvButton(
            label: label,
            icon: icon,
            selected: _kind == kind,
            focusNode: _kindFocus[kind],
            // First stop below the top menu, so Down from "Kids" always
            // lands on Movies / Series / Live TV (TCL 21 Oct: it went back
            // to the last row used and skipped them).
            autofocus: kind == MediaKind.movie && _kind == null,
            escapeUpToSidebar: true,
            onTap: () => _selectKind(kind),
          ),
        );

    final options = Row(
      children: [
        option(MediaKind.movie, copy.movies, Icons.movie_outlined),
        option(MediaKind.series, copy.series, Icons.video_library_outlined),
        option(MediaKind.live, copy.liveTv, Icons.live_tv_outlined),
      ],
    );

    // Kids → Live TV: the main Live TV layout (preview, channel list,
    // categories, Favourites) limited to children's channels (client 21 Oct).
    if (_kind == MediaKind.live) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 16, 36, 8),
            child: options,
          ),
          const Expanded(child: TvLiveScreen(kidsOnly: true)),
        ],
      );
    }

    return ListView(
      clipBehavior: Clip.none,
      scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
      children: [
        TvPageHeader(
          title: copy.kids,
          arabicTitle: ar.kids,
          titleChip: totalTitles > 0 ? copy.titlesCount(totalTitles) : null,
          subtitle: copy.kidsMaturitySubtitle,
          trailing: TechBadge(
            copy.kidsSafeBadge,
            tone: BadgeTone.magenta,
            compact: true,
          ),
        ),
        options,
        const SizedBox(height: 18),
        if (_kind == null) _home(copy) else ..._section(copy, _kind!),
      ],
    );
  }

  Widget _home(AppCopy copy) {
    final cw = ref.watch(continueWatchingProvider);
    return ref.watch(kidsHomeProvider).when(
          loading: () => const TvFeedLoading(
            showHero: true,
            railCount: 2,
            padding: EdgeInsets.zero,
          ),
          error: (e, _) => Text(copy.couldNotLoad),
          data: (home) {
            final continueItems = home.continueWatching(cw);
            if (home.banner.isEmpty &&
                home.topSeries.isEmpty &&
                home.topMovies.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(copy.noKidsTitlesYet, style: TvUi.meta),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (home.banner.isNotEmpty)
                  TvHeroCarousel(
                    items: home.banner,
                    height: TvHeroCarousel.kidsHeight,
                  ),
                if (continueItems.isNotEmpty)
                  ContinueRail(
                    title: copy.continueWatching,
                    items: continueItems,
                    accent: AppColors.cyan,
                    viewAllLabel: copy.viewAll,
                    onViewAll: () => context.push('/library?tab=continue'),
                  ),
                if (home.topSeries.isNotEmpty)
                  ContentRail(
                    title: copy.top10KidsSeries,
                    items: home.topSeries,
                    ranked: true,
                    accent: AppColors.magenta,
                    viewAllLabel: copy.viewAll,
                    onViewAll: () => _selectKind(MediaKind.series),
                  ),
                if (home.topMovies.isNotEmpty)
                  ContentRail(
                    title: copy.top10KidsMovies,
                    items: home.topMovies,
                    ranked: true,
                    accent: AppColors.cyan,
                    viewAllLabel: copy.viewAll,
                    onViewAll: () => _selectKind(MediaKind.movie),
                  ),
              ],
            );
          },
        );
  }

  /// One type's kids categories: search, chips, then the rails.
  List<Widget> _section(AppCopy copy, MediaKind kind) {
    final all = ref.watch(kidsResolvedCategoriesProvider).valueOrNull ??
        const <KidsCategoryRef>[];
    final cats = [for (final c in all) if (c.kind == kind) c];
    final searching = _query.trim().isNotEmpty;
    final chip = _chipIndex.clamp(0, cats.length);
    final globalIndex = chip == 0 ? null : all.indexOf(cats[chip - 1]);
    final accent = switch (kind) {
      MediaKind.live => AppColors.live,
      MediaKind.series => AppColors.magenta,
      _ => AppColors.cyan,
    };

    Widget rail(String title, List<MediaItem> items, {bool focus = false, String? categoryId}) =>
        ContentRail(
          title: copy.catalogCategoryLabel(title),
          trailing: copy.titlesCount(items.length),
          items: items,
          autofocusFirst: focus,
          accent: accent,
          viewAllLabel: categoryId == null ? null : copy.viewAll,
          onViewAll: categoryId == null
              ? null
              : () => context.push(tvViewAllRoute(kind, categoryId, copy.catalogCategoryLabel(title))),
        );

    Widget empty(String text) => Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(text, style: TvUi.meta),
        );

    const loading = TvFeedLoading(
      showHero: false,
      railCount: 1,
      padding: EdgeInsets.zero,
    );

    final Widget body;
    if (searching) {
      body = ref.watch(kidsSearchProvider(_query)).when(
            loading: () => loading,
            error: (e, _) => Text(copy.couldNotLoad),
            data: (items) {
              final hits = [for (final m in items) if (m.kind == kind) m];
              return hits.isEmpty
                  ? empty(copy.noKidsTitlesYet)
                  : rail(copy.searchKids, hits, focus: true);
            },
          );
    } else if (globalIndex != null && globalIndex >= 0) {
      body = ref.watch(kidsCategoryItemsProvider(globalIndex)).when(
            loading: () => loading,
            error: (e, _) => Text(copy.couldNotLoad),
            data: (items) => items.isEmpty
                ? empty(copy.noTitlesInCategory)
                : rail(cats[chip - 1].displayName, items, focus: true, categoryId: cats[chip - 1].categoryId),
          );
    } else {
      body = ref.watch(kidsPanelFeedProvider).when(
            loading: () => loading,
            error: (e, _) => Text(copy.couldNotLoad),
            data: (rails) {
              final mine = [for (final r in rails) if (r.kind == kind) r];
              if (mine.isEmpty) return empty(copy.noKidsTitlesYet);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < mine.length; i++)
                    rail(mine[i].title, mine[i].items, focus: i == 0, categoryId: mine[i].categoryId),
                ],
              );
            },
          );
    }

    return [
      Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.magenta.withValues(alpha: 0.28),
          ),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: copy.searchKids,
            hintStyle: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            filled: false,
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: AppColors.magenta),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              setState(() => _query = v.trim());
            });
          },
        ),
      ),
      const SizedBox(height: 16),
      if (cats.isNotEmpty)
        TvGenreChipBar(
          labels: [
            copy.all,
            for (final c in cats) copy.catalogCategoryLabel(c.displayName),
          ],
          selectedIndex: searching ? 0 : chip,
          onSelected: (i) => setState(() {
            _chipIndex = i;
            _clearSearchField();
          }),
        ),
      const SizedBox(height: 8),
      body,
    ];
  }
}
