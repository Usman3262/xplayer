import 'dart:async';

import 'package:data/data.dart' show Diag;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/library_controller.dart';
import '../core/providers.dart';
import '../core/row_cache.dart';
import '../core/tv_input_activity.dart';
import '../core/tv_locale.dart';
import '../core/tv_session.dart';
import '../core/tv_media_nav.dart';
import '../features/browse/tv_view_all_screen.dart';
import 'content_rail.dart';
import 'focus_tile.dart';
import 'tv_arrange_packages.dart';
import 'tv_feed_loading.dart';
import 'tv_genre_chip_bar.dart';
import 'tv_poster.dart';
import 'tv_ui.dart';

/// Figma "TV Movies Browse" / "TV Series Browse V2": featured banner,
/// category chips, then one row per provider category with a title count
/// and a View All card that opens the whole category.
class TvCatalogBrowse extends ConsumerStatefulWidget {
  const TvCatalogBrowse({super.key, required this.kind});

  /// [MediaKind.movie] or [MediaKind.series].
  final MediaKind kind;

  @override
  ConsumerState<TvCatalogBrowse> createState() => _TvCatalogBrowseState();
}

class _TvCatalogBrowseState extends ConsumerState<TvCatalogBrowse> {
  static const _rowLimit = 12;

  List<CatalogCategory> _categories = const [];
  List<CatalogCategory> _providerCategories = const [];

  String get _section => widget.kind == MediaKind.series ? 'series' : 'vod';

  Future<void> _arrange(AppCopy copy) async {
    final ids = await showTvArrangePackages(
      context,
      categories: _categories,
      label: copy.catalogCategoryLabel,
      copy: copy,
    );
    if (ids == null || !mounted) return;
    setState(() => _categories = applyCategoryOrder(_providerCategories, ids));
    final pid = ref.read(tvSessionProvider).activeProfileId;
    if (pid != null && pid.isNotEmpty) {
      await ref.read(categoryOrderStoreProvider).save(pid, _section, ids);
    }
  }
  final Map<String, CatalogPage<MediaItem>> _pages = {};
  final Set<String> _loadingCat = {};
  /// Failed loads stay visible with Retry. They used to become an empty
  /// page, and empty categories are hidden, so a failure hid the category
  /// (client 17 Oct "categories showing zero").
  final Set<String> _failedCat = {};
  /// Rows shown from the saved copy, refreshed from the server behind (as on
  /// LG 6.1.16 / 6.1.19: saved rows at once; the last list kept on failure).
  final Set<String> _staleCat = {};
  Timer? _saveRows;
  bool _loading = true;
  Object? _error;

  /// Loaded rows wait here and land in one rebuild (TCL scroll lag 16 Oct:
  /// one setState per category rebuilt the whole page dozens of times while
  /// the user was scrolling).
  final Map<String, CatalogPage<MediaItem>> _pending = {};
  Timer? _flush;

  @override
  void dispose() {
    _saveRows?.cancel();
    _flush?.cancel();
    super.dispose();
  }

  void _queue(String id, CatalogPage<MediaItem> page) {
    _pending[id] = page;
    _flush ??= Timer(const Duration(milliseconds: 250), () {
      _flush = null;
      if (!mounted || _pending.isEmpty) return;
      setState(() {
        _pages.addAll(_pending);
        _pending.clear();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final cats = await ref
          .read(catalogRepositoryProvider)
          .getCategories(widget.kind);
      var ordered = cats;
      final pid = ref.read(tvSessionProvider).activeProfileId;
      if (pid != null && pid.isNotEmpty) {
        final ids =
            await ref.read(categoryOrderStoreProvider).load(pid, _section);
        ordered = applyCategoryOrder(cats, ids);
      }
      // The last rows saved on this TV show at once (LG 6.1.16 / 6.1.19).
      final saved = (pid != null && pid.isNotEmpty)
          ? await RowCache.load(pid, _section)
          : null;
      if (!mounted) return;
      setState(() {
        _providerCategories = cats;
        _categories = ordered;
        _loading = false;
        if (saved != null) {
          for (final c in cats) {
            final rows = saved.rows[c.id];
            if (rows == null || _pages.containsKey(c.id)) continue;
            _pages[c.id] = CatalogPage(items: rows, total: saved.totals[c.id]);
            _staleCat.add(c.id);
          }
        }
      });
      // Every package is still loaded (so empty ones can be hidden), but
      // 3 at a time instead of all at once: dozens of parallel requests and
      // poster decodes froze navigation on 2 GB TVs (client 16 Oct #1).
      unawaited(_loadAllThrottled(cats));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Off-screen rows (to hide empty categories) load in the background,
  /// 2 at a time, and only while the remote is idle: a request + poster
  /// decode in the middle of a D-pad scroll is what stuttered on the TCL.
  /// Rows on screen still load at once (the list builder asks for them).
  Future<void> _loadAllThrottled(List<CatalogCategory> cats) async {
    var next = 0;
    Future<void> worker() async {
      while (mounted && next < cats.length) {
        while (mounted &&
            !TvInputActivity.idleFor(const Duration(milliseconds: 900))) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        if (!mounted) return;
        final c = cats[next++];
        await _loadCategory(c.id);
      }
    }

    // 3 at a time (client 6 Nov: sections slow), still only while the remote rests.
    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
  }

  Future<void> _loadCategory(String id) async {
    if ((_pages.containsKey(id) && !_staleCat.contains(id)) ||
        _pending.containsKey(id) ||
        !_loadingCat.add(id)) {
      return;
    }
    if (_failedCat.remove(id) && mounted) setState(() {});
    try {
      final page = await ref.read(catalogRepositoryProvider).browse(
            kind: widget.kind,
            categoryId: id,
            limit: _rowLimit,
          );
      if (!mounted) return;
      final filtered = page.items
          .where((m) => !isProviderAdOrHeaderChannel(m.title))
          .toList(growable: false);
      _staleCat.remove(id);
      _queue(
        id,
        CatalogPage(
          items: filtered,
          nextCursor: page.nextCursor,
          total: page.total,
        ),
      );
      _scheduleSaveRows();
    } catch (e) {
      Diag.dev('BROWSE package load failed id=$id type=${e.runtimeType}');
      if (!mounted) return;
      // A saved row stays on screen when its refresh fails (LG keeps the last list).
      if (_staleCat.contains(id)) return;
      setState(() => _failedCat.add(id));
    } finally {
      _loadingCat.remove(id);
    }
  }

  void _scheduleSaveRows() {
    _saveRows?.cancel();
    _saveRows = Timer(const Duration(seconds: 3), () {
      final pid = ref.read(tvSessionProvider).activeProfileId;
      if (!mounted || pid == null || pid.isEmpty) return;
      final rows = <String, List<MediaItem>>{};
      final totals = <String, int>{};
      for (final e in {..._pages, ..._pending}.entries) {
        if (_staleCat.contains(e.key) || e.value.items.isEmpty) continue;
        rows[e.key] = e.value.items;
        if (e.value.total != null) totals[e.key] = e.value.total!;
      }
      unawaited(RowCache.save(pid, _section, rows, totals));
    });
  }

  void _openCategory(CatalogCategory c, String label) {
    context.push(
      '/browse/${widget.kind.name}/${Uri.encodeComponent(c.id)}'
      '?title=${Uri.encodeQueryComponent(label)}',
    );
  }

  MediaItem? get _featured {
    final list = _featuredList;
    return list.isEmpty ? null : list.first;
  }

  /// Banner slides: the first title with art from each package (up to 6),
  /// rotated like the Home hero (client 1 Nov #10: banners rotate in every
  /// section).
  List<MediaItem> get _featuredList {
    final out = <MediaItem>[];
    final seen = <String>{};
    // Clean TMDB art first, as on LG (client 5 Nov photo: the banner poster
    // carried the provider's "8K" stamp): per package the first title with a
    // TMDB backdrop or poster, else the first title with any art.
    bool hasArt(MediaItem m) => (m.backdropUrl ?? m.posterUrl)?.isNotEmpty ?? false;
    bool clean(MediaItem m) => isTmdbImage(m.backdropUrl) || isTmdbImage(m.posterUrl);
    for (final c in _categories) {
      final items = _pages[c.id]?.items ?? const <MediaItem>[];
      final pick = items.where((m) => hasArt(m) && clean(m) && !seen.contains(m.id)).firstOrNull ??
          items.where((m) => hasArt(m) && !seen.contains(m.id)).firstOrNull;
      if (pick != null && seen.add(pick.id)) out.add(pick);
      if (out.length >= 6) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final isMovies = widget.kind == MediaKind.movie;

    if (_loading) {
      return const TvFeedLoading(heroHeight: 300, railCount: 2);
    }
    if (_error != null) return Center(child: Text('$_error'));
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          copy.noTitlesInCategory,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    // Every package of the user's catalog (client 18 Oct #6): packages with
    // the same label are no longer dropped (the catalog numbers them). Only
    // a package that loaded and is really empty is left out.
    final visible = [
      for (final c in _categories)
        if (!(_pages[c.id]?.items.isEmpty ?? false)) c,
    ];
    final featured = _featured;
    final cw = ref
        .watch(continueWatchingProvider)
        .where((m) => m.kind == widget.kind)
        .take(CatalogPaging.pageSize)
        .toList();
    final fav = ref
        .watch(myListItemsProvider)
        .where((m) => m.kind == widget.kind)
        .take(CatalogPaging.pageSize)
        .toList();
    final extras = <Widget>[
      if (cw.isNotEmpty)
        ContinueRail(
          title: copy.continueWatching,
          items: cw,
          accent: AppColors.cyan,
          onViewAll: () => context.push('/library?tab=continue'),
          viewAllLabel: copy.viewAll,
        ),
      if (fav.isNotEmpty)
        _CategoryRow(
          title: copy.myList,
          page: CatalogPage(items: fav),
          accent: AppColors.magenta,
          onViewAll: () => context.push('/my-list'),
          titlesLabel: copy.titlesCount,
          viewAllLabel: copy.viewAll,
        ),
    ];
    final headerCount = 2 + extras.length;

    return ListView.builder(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 48),
      scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
      itemCount: visible.length + headerCount,
      itemBuilder: (context, i) {
        if (i == 0) {
          return featured == null
              ? const SizedBox(height: 8)
              : _RotatingBrowseHero(
                  items: _featuredList,
                  isMovies: isMovies,
                );
        }
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: TvGenreChipBar(
              // Client 2 Nov: Sort first, with its icon and the word
              // "Sort" / "رتب" beside it, so it is visible in Movies and
              // Series (it used to be the last chip, off screen).
              labels: [
                copy.sortLabel,
                isMovies ? copy.allMovies : copy.allSeries,
                ...visible.map((c) => copy.catalogCategoryLabel(c.name)),
              ],
              icons: const {0: Icons.swap_vert_rounded},
              selectedIndex: 1,
              escapeFirstChipToSidebar: featured == null,
              onSelected: (idx) {
                if (idx == 0) {
                  unawaited(_arrange(copy));
                  return;
                }
                // "All Movies" / "All Series": the whole catalog, paged
                // (it used to do nothing).
                if (idx == 1) {
                  context.push(
                    tvViewAllRoute(
                      widget.kind,
                      tvAllCategory,
                      isMovies ? copy.allMovies : copy.allSeries,
                    ),
                  );
                  return;
                }
                final c = visible[idx - 2];
                _openCategory(c, copy.catalogCategoryLabel(c.name));
              },
            ),
          );
        }
        if (i < headerCount) {
          return extras[i - 2];
        }
        final cat = visible[i - headerCount];
        final page = _pages[cat.id];
        final failed = _failedCat.contains(cat.id);
        if (page == null && !failed) unawaited(_loadCategory(cat.id));
        final label = copy.catalogCategoryLabel(cat.name);
        final counts = ref.watch(catalogCountsProvider).valueOrNull;
        return _CategoryRow(
          title: label,
          page: page,
          totalOverride: (widget.kind == MediaKind.series
                  ? counts?.series
                  : counts?.vod)
              ?.byCategory[cat.id],
          failed: failed,
          failedLabel: copy.packageLoadFailed,
          retryLabel: copy.retry,
          onRetry: () => unawaited(_loadCategory(cat.id)),
          accent: i.isEven ? AppColors.cyan : AppColors.gold,
          onViewAll: () => _openCategory(cat, label),
          titlesLabel: copy.titlesCount,
          viewAllLabel: copy.viewAll,
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.page,
    this.totalOverride,
    this.failed = false,
    this.failedLabel = '',
    this.retryLabel = '',
    this.onRetry,
    required this.accent,
    required this.onViewAll,
    required this.titlesLabel,
    required this.viewAllLabel,
  });

  final String title;
  final CatalogPage<MediaItem>? page;
  /// Real total from the server's counts, preferred over the page total.
  final int? totalOverride;
  final bool failed;
  final String failedLabel;
  final String retryLabel;
  final VoidCallback? onRetry;
  final Color accent;
  final VoidCallback onViewAll;
  final String Function(int) titlesLabel;
  final String viewAllLabel;

  @override
  Widget build(BuildContext context) {
    final items = page?.items ?? const <MediaItem>[];
    if (page != null && items.isEmpty) return const SizedBox.shrink();
    final total = totalOverride ?? page?.total;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Client 18 Oct TV #10: the package name opens the package, as on
          // Home. It was plain text here; only a "View all" card after the
          // posters opened it.
          TvSectionTitle(
            title,
            // "View All ›" beside every package heading, as on LG (client
            // 5 Nov: "أفلام هندية حديثة" had nothing beside it when the
            // count was unknown).
            // Client 9 Nov: "Name | View All | 25 titles" on one line.
            trailing: (total != null && total > 0)
                ? '|  $viewAllLabel  |  ${titlesLabel(total)}'
                : '|  $viewAllLabel',
            trailingBesideTitle: true,
            accent: accent,
            onTap: onViewAll,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: failed
                ? Row(
                    children: [
                      Text(
                        failedLabel,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      TvButton(
                        label: retryLabel,
                        icon: Icons.refresh_rounded,
                        onTap: onRetry ?? () {},
                      ),
                    ],
                  )
                : page == null
                ? Center(child: AppLoader.inline(size: 28))
                : FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, j) {
                        if (j == items.length) {
                          return _ViewAllCard(
                            label: viewAllLabel,
                            onTap: onViewAll,
                          );
                        }
                        final m = items[j];
                        return TvPoster.fromMedia(
                          m,
                          escapeToSidebar: j == 0,
                          onTap: () => openTvMedia(context, m),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ViewAllCard extends StatelessWidget {
  const _ViewAllCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TvPoster.standardWidth,
      height: TvPoster.cardHeightFor(),
      child: FocusTile(
        borderRadius: 14,
        onTap: onTap,
        child: TvGlass(
          radius: 14,
          tint: AppColors.cyan,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withValues(alpha: 0.2),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Featured title banner (Figma Series/Movies Browse V2).
/// Cross-fades the banner every 6 s, also while it has focus. The widget
/// tree stays the same (only the item changes), so a focused button keeps
/// focus. Waits while the user is pressing keys or the banner is scrolled
/// away, like the Home hero.
class _RotatingBrowseHero extends StatefulWidget {
  const _RotatingBrowseHero({required this.items, required this.isMovies});
  final List<MediaItem> items;
  final bool isMovies;

  @override
  State<_RotatingBrowseHero> createState() => _RotatingBrowseHeroState();
}

class _RotatingBrowseHeroState extends State<_RotatingBrowseHero> {
  static const _interval = Duration(seconds: 6);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || widget.items.length < 2) return;
      if (!TvInputActivity.idleFor(const Duration(seconds: 5))) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      final outer = Scrollable.maybeOf(context)?.position;
      if (outer != null && outer.pixels > 150) return;
      setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: 8);
    final item = widget.items[_index % widget.items.length];
    return _BrowseHero(item: item, isMovies: widget.isMovies);
  }
}

class _BrowseHero extends ConsumerWidget {
  const _BrowseHero({required this.item, required this.isMovies});
  final MediaItem item;
  final bool isMovies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final inList = ref.watch(libraryProvider).contains(item.id);
    final arabic = (item.titleArabic ?? '').trim();
    final metaRest = [
      if (item.year != null) '${item.year}',
      if (item.durationLabel != null) copy.durationText(item.durationLabel),
      if (item.genres.isNotEmpty) copy.genres(item.genres).take(2).join(' / '),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 300,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: TvHeroArt(
                  key: ValueKey(item.id),
                  url: pickWideArt([item.backdropUrl], poster: item.posterUrl),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerEnd,
                    end: AlignmentDirectional.centerStart,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.94),
                    ],
                    stops: const [0.15, 0.5, 1],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 22, 32, 22),
                child: Align(
                  // Start edge (right in Arabic), like the home hero.
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TechBadge(
                              isMovies
                                  ? copy.featuredMovie
                                  : copy.featuredSeries,
                              tone: BadgeTone.magenta,
                              compact: true,
                            ),
                            for (final b in item.badges.take(3))
                              TechBadge(b, compact: true),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                            if (arabic.isNotEmpty)
                              Text(
                                arabic,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TvUi.titleArabic,
                                textDirection: TextDirection.rtl,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
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
                                if (metaRest.isNotEmpty)
                                  const TextSpan(text: '  •  '),
                              ],
                              if (metaRest.isNotEmpty)
                                TextSpan(text: metaRest.join('  •  ')),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((item.synopsis ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.synopsis!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TvUi.body,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: TvUi.buttonGap,
                          runSpacing: TvUi.buttonGap,
                          children: [
                            _HeroButton(
                              primary: true,
                              autofocus: true,
                              icon: Icons.play_arrow_rounded,
                              label: copy.watchNow,
                              onTap: () => isMovies
                                  ? context.push(item.playbackRoute())
                                  : openTvMedia(context, item),
                            ),
                            _HeroButton(
                              icon: inList
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                              label: copy.myList,
                              onTap: () => ref
                                  .read(libraryProvider.notifier)
                                  .toggleMyList(item.id, item: item),
                            ),
                            _HeroButton(
                              icon: Icons.info_outline_rounded,
                              // Opens the details page (cast + episodes there).
                              label: copy.details,
                              onTap: () => openTvMedia(context, item),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvButton(
        icon: icon,
        label: label,
        onTap: onTap,
        primary: primary,
        autofocus: autofocus,
        escapeUpToSidebar: true,
        escapeToSidebar: primary,
      );
}
