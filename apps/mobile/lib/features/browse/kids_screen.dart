import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/category_channel_trails.dart';
import '../../widgets/main_app_bar.dart';
import '../home/home_screen.dart' show HomeHeroCarousel, Top10Row, ContinueRow;

/// Kids hub (client 21 Oct layout): Movies / Series / Live TV at the top,
/// then a rotating banner of the best recently added kids titles, Continue
/// Watching, Top 10 Kids Series and Top 10 Kids Movies (a random 10 kept for
/// the week, new every Monday — [WeeklyPicks]). Movies / Series / Live TV
/// open that type's kids categories; tapping the selected one again returns
/// to the Kids home.
class KidsScreen extends ConsumerStatefulWidget {
  const KidsScreen({super.key, this.asRootTab = false});

  /// When true (bottom-nav slot replacing Sports), hide the back chevron.
  final bool asRootTab;

  @override
  ConsumerState<KidsScreen> createState() => _KidsScreenState();
}

enum _KidsSection { movies, series, live }

class _KidsScreenState extends ConsumerState<KidsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  /// null = Kids home.
  _KidsSection? _section;
  /// null = All within the active section; otherwise index into filtered cats.
  int? _categoryIndex;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearchField() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _query = '';
  }

  MediaKind get _sectionKind => switch (_section) {
        _KidsSection.live => MediaKind.live,
        _KidsSection.series => MediaKind.series,
        _KidsSection.movies => MediaKind.movie,
        null => MediaKind.movie,
      };

  void _open(BuildContext context, MediaItem item) =>
      openMediaBrowse(context, item);

  List<KidsCategoryRef> _catsForSection(List<KidsCategoryRef> all) => [
        for (final c in all)
          if (c.kind == _sectionKind) c,
      ];

  int? _globalIndex(
    List<KidsCategoryRef> all,
    List<KidsCategoryRef> section,
    int sectionIndex,
  ) {
    if (sectionIndex < 0 || sectionIndex >= section.length) return null;
    final want = section[sectionIndex];
    final i = all.indexWhere(
      (c) => c.kind == want.kind && c.panelName == want.panelName,
    );
    return i >= 0 ? i : null;
  }

  Widget _sectionTabs(AppCopy copy) {
    Widget chip(_KidsSection s, String label, IconData icon) {
      final on = _section == s;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() {
            _section = _section == s ? null : s;
            _categoryIndex = null;
            _clearSearchField();
          }),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.magenta.withValues(alpha: 0.22)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on
                    ? AppColors.magenta.withValues(alpha: 0.7)
                    : AppColors.border,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: on ? AppColors.magenta : AppColors.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color:
                        on ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          chip(_KidsSection.movies, copy.movies, Icons.movie_outlined),
          const SizedBox(width: 8),
          chip(_KidsSection.series, copy.series, Icons.video_library_outlined),
          const SizedBox(width: 8),
          chip(_KidsSection.live, copy.liveTv, Icons.live_tv_outlined),
        ],
      ),
    );
  }

  Widget _posterRail(String title, List<MediaItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionEyebrow(label: title, accent: AppColors.magenta),
        const SizedBox(height: 8),
        SizedBox(
          height: PosterCard.railHeightFor(120),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final item = items[i];
              return PosterCard(
                title: item.displayTitle,
                rating: item.posterRating,
                imageUrl: item.posterUrl,
                seed: item.posterSeed ?? i,
                width: 120,
                onTap: () => _open(context, item),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _posterGrid(List<MediaItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final colW = (constraints.maxWidth - gap) / 2;
        final cellH = PosterCard.railHeightFor(colW);
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: gap,
            childAspectRatio: colW / cellH,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return PosterCard(
              title: item.displayTitle,
              rating: item.posterRating,
              badges: item.badges,
              imageUrl: item.posterUrl,
              seed: item.posterSeed ?? i,
              width: colW,
              onTap: () => _open(context, item),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    final catsAsync = ref.watch(kidsResolvedCategoriesProvider);
    final searching = _query.trim().isNotEmpty;

    if (_section == null) {
      return Scaffold(
        appBar: MainAppBar(showBack: !widget.asRootTab),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTabs(copy),
            const SizedBox(height: 10),
            Expanded(child: _home(copy)),
          ],
        ),
      );
    }

    // Kids → Live TV: the main Live TV layout (favourites, packages, search)
    // limited to children's channels (client 21 Oct).
    if (_section == _KidsSection.live) {
      return Scaffold(
        appBar: MainAppBar(showBack: !widget.asRootTab),
        body: CategoryChannelTrailsScreen(
          kind: MediaKind.live,
          eyebrow: copy.liveTv,
          searchHint: copy.searchLive,
          kidsOnly: true,
          showAppBar: false,
          header: _sectionTabs(copy),
        ),
      );
    }

    return Scaffold(
      appBar: MainAppBar(showBack: !widget.asRootTab),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTabs(copy),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppColors.textPrimary),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) setState(() => _query = v);
                });
              },
              decoration: InputDecoration(
                hintText: copy.searchKids,
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                prefixIcon:
                    Icon(Icons.search, color: AppColors.magenta),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          catsAsync.when(
            loading: () => SizedBox(
              height: 44,
              child: Center(child: AppLoader.inline(size: 22)),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (all) {
              final sectionCats = _catsForSection(all);
              return SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: sectionCats.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return CategoryChip(
                        label: copy.all,
                        selected: _categoryIndex == null && !searching,
                        onTap: () => setState(() {
                          _categoryIndex = null;
                          _clearSearchField();
                        }),
                      );
                    }
                    final c = sectionCats[i - 1];
                    return CategoryChip(
                      label: copy.catalogCategoryLabel(c.displayName),
                      selected: _categoryIndex == i - 1 && !searching,
                      onTap: () => setState(() {
                        _categoryIndex = i - 1;
                        _clearSearchField();
                      }),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(child: _body(copy)),
        ],
      ),
    );
  }

  Widget _home(AppCopy copy) {
    final cw = ref.watch(continueWatchingProvider);
    return ref.watch(kidsHomeProvider).when(
          loading: () => AppShimmer.twoColumnCards(),
          error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(kidsHomeProvider),
        ),
          data: (home) {
            final continueItems = home.continueWatching(cw);
            return RefreshIndicator(
              color: AppColors.magenta,
              onRefresh: () async {
                ref.invalidate(kidsResolvedCategoriesProvider);
                ref.invalidate(kidsPanelFeedProvider);
                await ref.read(kidsHomeProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (home.banner.isEmpty &&
                      home.topSeries.isEmpty &&
                      home.topMovies.isEmpty)
                    AppEmpty(
                      title: copy.noKidsTitlesYet,
                      subtitle: copy.kidsCatalogEmpty,
                      icon: Icons.child_care_outlined,
                    ),
                  if (home.banner.isNotEmpty)
                    HomeHeroCarousel(items: home.banner, copy: copy),
                  if (continueItems.isNotEmpty) ...[
                    SectionHeader(title: copy.continueWatching),
                    ContinueRow(items: continueItems),
                  ],
                  if (home.topSeries.isNotEmpty) ...[
                    SectionHeader(
                      title: copy.top10KidsSeries,
                      accent: AppColors.magenta,
                    ),
                    Top10Row(items: home.topSeries),
                  ],
                  if (home.topMovies.isNotEmpty) ...[
                    SectionHeader(title: copy.top10KidsMovies),
                    Top10Row(items: home.topMovies),
                  ],
                ],
              ),
            );
          },
        );
  }

  Widget _body(AppCopy copy) {
    if (_query.trim().isNotEmpty) {
      final results = ref.watch(kidsSearchProvider(_query.trim()));
      return results.when(
        loading: () => AppShimmer.twoColumnCards(),
        error: (e, _) => AppEmpty(icon: Icons.cloud_off_rounded, title: copy.couldNotLoad),
        data: (items) {
          final filtered = [
            for (final m in items)
              if (m.kind == _sectionKind) m,
          ];
          if (filtered.isEmpty) {
            return AppEmpty(
              title: copy.noKidsTitlesYet,
              subtitle: copy.kidsCatalogEmpty,
              icon: Icons.search_off_rounded,
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _posterGrid(filtered),
          );
        },
      );
    }

    if (_categoryIndex != null) {
      final all = ref.watch(kidsResolvedCategoriesProvider).valueOrNull ?? [];
      final sectionCats = _catsForSection(all);
      final global = _globalIndex(all, sectionCats, _categoryIndex!);
      if (global == null) {
        return AppEmpty(
          title: copy.noTitlesInCategory,
          icon: Icons.child_care_outlined,
        );
      }
      final itemsAsync = ref.watch(kidsCategoryItemsProvider(global));
      final label = sectionCats[_categoryIndex!].displayName;
      return itemsAsync.when(
        loading: () => AppShimmer.twoColumnCards(),
        error: (e, _) => AppEmpty(icon: Icons.cloud_off_rounded, title: copy.couldNotLoad),
        data: (items) {
          if (items.isEmpty) {
            return AppEmpty(
              title: copy.noTitlesInCategory,
              subtitle: copy.catalogCategoryLabel(label),
              icon: Icons.child_care_outlined,
            );
          }
          return RefreshIndicator(
            color: AppColors.magenta,
            onRefresh: () async {
              ref.invalidate(kidsCategoryItemsProvider(global));
              await ref.read(kidsCategoryItemsProvider(global).future);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _posterGrid(items),
            ),
          );
        },
      );
    }

    final feed = ref.watch(kidsPanelFeedProvider);
    return feed.when(
      loading: () => AppShimmer.twoColumnCards(),
      error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(kidsPanelFeedProvider),
        ),
      data: (rails) {
        final sectionRails = [
          for (final r in rails)
            if (r.kind == _sectionKind) r,
        ];
        return RefreshIndicator(
          color: AppColors.magenta,
          onRefresh: () async {
            ref.invalidate(kidsResolvedCategoriesProvider);
            ref.invalidate(kidsPanelFeedProvider);
            await ref.read(kidsPanelFeedProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (sectionRails.isEmpty)
                AppEmpty(
                  title: copy.noKidsTitlesYet,
                  subtitle: copy.kidsCatalogEmpty,
                  icon: Icons.child_care_outlined,
                )
              else
                for (final rail in sectionRails)
                  _posterRail(rail.title, rail.items),
            ],
          ),
        );
      },
    );
  }
}
