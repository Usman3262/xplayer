import 'dart:async';

import 'package:data/data.dart' show Diag, PanelCatalogRepository;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/adult.dart';
import '../core/media_nav.dart';
import '../core/catalog.dart';
import '../core/providers.dart';
import '../core/row_cache.dart';
import '../core/session_controller.dart';
import '../features/home/home_screen.dart' show ContinueRow;
import 'main_app_bar.dart';
import 'arrange_packages_sheet.dart';
import 'nav_loader.dart';

/// Movies / Series: vertical category list; tap a row to expand a poster trail
/// (same category-first pattern as Live / Sports).
class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({
    super.key,
    required this.kind,
    required this.eyebrow,
    this.searchHint,
    this.topAction,
    this.sectionKey,
  });

  final MediaKind kind;
  final String eyebrow;
  final String? searchHint;

  /// Shown above the search field (e.g. the "Adult 18+" button on Series).
  final Widget? topAction;

  /// Own row cache / category order (the 18+ view must not share the
  /// normal section's cached rows).
  final String? sectionKey;

  @override
  ConsumerState<CatalogBrowseScreen> createState() =>
      _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  final _scroll = ScrollController();
  Timer? _searchDebounce;
  String _query = '';
  List<CatalogCategory> _categories = const [];
  /// Provider order, for "original order".
  List<CatalogCategory> _providerCategories = const [];
  final Map<String, List<MediaItem>> _itemsByCat = {};
  final Map<String, bool> _loadingCat = {};
  /// Failed loads show Retry, never "0 titles" (client 17 Oct).
  final Set<String> _failedCat = {};
  /// Title count per package from the server's total, not rows loaded.
  final Map<String, int> _totalByCat = {};
  final List<String> _queue = [];
  int _active = 0;
  /// 3 at a time (client 6 Nov: "sections take a very long time"; one at a
  /// time took 10–20 s for the first 15 packages). One screen is still only
  /// ~15 requests, far below the server's limit; a 429 pauses the queue.
  static const _maxParallel = 3;
  /// Rows shown from the saved copy, refreshed from the server behind.
  final Set<String> _staleCat = {};
  Timer? _saveRows;
  /// Client 20 Oct: all packages expanded by default (was first 2 only).
  DateTime? _rateLimitedUntil;
  final Set<String> _expanded = {};
  int _shownCatCount = CatalogPaging.categoriesPageSize;
  List<MediaItem>? _searchHits;
  bool _searching = false;
  bool _loadingCats = true;
  Object? _error;
  bool _started = false;

  static const _trailLimit = CatalogPaging.pageSize;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollNearEnd);
  }

  @override
  void dispose() {
    _saveRows?.cancel();
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScrollNearEnd);
    _scroll.dispose();
    super.dispose();
  }

  void _onScrollNearEnd() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 280) return;
    _revealNextCategoryPage();
  }

  void _revealNextCategoryPage() {
    if (_shownCatCount >= _categories.length) return;
    final prev = _shownCatCount;
    setState(() {
      _shownCatCount = (_shownCatCount + CatalogPaging.categoriesPageSize)
          .clamp(0, _categories.length);
      for (final c in _categories.skip(prev).take(_shownCatCount - prev)) {
        _expanded.add(c.id);
      }
    });
    for (final c in _categories.skip(prev).take(_shownCatCount - prev)) {
      unawaited(_loadCategory(c.id));
    }
  }

  /// After the PIN: Movies/Series list only the 18+ packages (and fetch
  /// their titles now). Mixing them into 400+ packages hid them off-screen
  /// — the first 15 rows never changed, so it looked like the PIN did nothing.
  CatalogRepository _browseRepo() {
    final repo = ref.read(catalogRepositoryProvider);
    if (ref.read(adultUnlockedProvider) && repo is PanelCatalogRepository) {
      return repo.adultView();
    }
    return repo;
  }

  /// [quiet]: new catalog data arrived (sync) — reload the category list
  /// and rows without a spinner; rows on screen stay until their fresh copy
  /// is in. Adult PIN toggle uses [quiet] false so 18+ packages replace the
  /// list at the top.
  Future<void> _boot({bool quiet = false, bool resetForAdult = false}) async {
    if (quiet) {
      _staleCat.addAll(_itemsByCat.keys);
    } else {
      setState(() {
        _loadingCats = true;
        _error = null;
        if (resetForAdult) {
          _itemsByCat.clear();
          _totalByCat.clear();
          _failedCat.clear();
          _queue.clear();
          _shownCatCount = CatalogPaging.categoriesPageSize;
        }
      });
      if (resetForAdult && _scroll.hasClients) _scroll.jumpTo(0);
    }
    try {
      final cats = await _browseRepo().getCategories(widget.kind);
      final unique = <CatalogCategory>[];
      final seen = <String>{};
      // Unique by id: packages with the same name are still different
      // packages (merging by name hid one of them).
      for (final c in cats) {
        if (seen.add(c.id)) unique.add(c);
      }
      // The profile's package order (client 17 Oct), device copy first.
      var ordered = unique;
      final pid = ref.read(sessionProvider).activeProfileId;
      final adultOpen = ref.read(adultUnlockedProvider);
      if (!adultOpen && pid != null && pid.isNotEmpty) {
        final ids =
            await ref.read(categoryOrderStoreProvider).load(pid, _section);
        ordered = applyCategoryOrder(unique, ids);
      }
      if (!mounted) return;
      setState(() {
        _providerCategories = unique;
        _categories = ordered;
        _loadingCats = false;
        // A quiet reload keeps how far the user had scrolled.
        if (!quiet || _shownCatCount < CatalogPaging.categoriesPageSize) {
          _shownCatCount = CatalogPaging.categoriesPageSize;
        }
        _queue.clear();
        // All packages expanded by default (client 20 Oct — was first 2).
        _expanded
          ..clear()
          ..addAll(ordered.map((c) => c.id));
      });
      // The last rows saved on this phone show at once (as on LG); each is
      // replaced as soon as its fresh copy arrives.
      if (pid != null && pid.isNotEmpty) {
        final saved = await RowCache.load(pid, _section);
        if (!mounted) return;
        if (saved.rows.isNotEmpty) {
          setState(() {
            for (final c in ordered) {
              final rows = saved.rows[c.id];
              if (rows == null || _itemsByCat.containsKey(c.id)) continue;
              _itemsByCat[c.id] = rows;
              _staleCat.add(c.id);
              final t = saved.totals[c.id];
              if (t != null) _totalByCat[c.id] = t;
            }
          });
        }
      }
      if (adultOpen) {
        Diag.event(
          'ADULT',
          '${widget.kind.name}: ${unique.length} 18+ categories, loading titles',
        );
      }
      for (final c in ordered.take(_shownCatCount)) {
        unawaited(_loadCategory(c.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingCats = false;
      });
    }
  }

  /// Queues a package load; at most [_maxParallel] run at once (all at
  /// once made some fail, and a failure looked like an empty package).
  Future<void> _loadCategory(String id) async {
    if ((_itemsByCat.containsKey(id) && !_staleCat.contains(id)) ||
        _loadingCat[id] == true ||
        _queue.contains(id)) {
      return;
    }
    setState(() {
      _failedCat.remove(id);
      _loadingCat[id] = true;
    });
    _queue.add(id);
    _pump();
  }

  void _pump() {
    final until = _rateLimitedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final wait = until.difference(DateTime.now());
      Future<void>.delayed(wait, () {
        if (mounted) _pump();
      });
      return;
    }
    while (_active < _maxParallel && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _active++;
      unawaited(_fetchCategory(id).whenComplete(() {
        _active--;
        if (mounted) _pump();
      }));
    }
  }

  bool _isRateLimited(Object e) {
    final s = '$e';
    return s.contains('429') || s.toLowerCase().contains('too many requests');
  }

  Future<void> _fetchCategory(String id, {int attempt = 0}) async {
    try {
      // C17: follow pagination so packages are not stuck on the first page.
      final kept = <MediaItem>[];
      var removed = 0;
      int? total;
      String? cursor;
      var pages = 0;
      // One page: the row shows CatalogPaging.pageSize items and the count
      // comes from page.total. Following up to 8 pages per row (C17) sent
      // 100-130 requests a minute and hit the server's 429 limit (client
      // 21 Oct: "تعذّر التحميل", channel list and downloads failing).
      // The full package is paged on its own screen.
      const maxPages = 1;
      do {
        final page = await _browseRepo().browse(
              kind: widget.kind,
              categoryId: id,
              limit: _trailLimit,
              cursor: cursor,
            );
        if (!mounted) return;
        for (final m in page.items) {
          if (isProviderAdOrHeaderChannel(m.title, rawName: m.title)) {
            removed++;
          } else {
            kept.add(m);
          }
        }
        total = page.total ?? total;
        cursor = page.nextCursor;
        pages++;
      } while (cursor != null &&
          cursor.isNotEmpty &&
          pages < maxPages &&
          kept.length < 200);
      _staleCat.remove(id);
      _scheduleSaveRows();
      setState(() {
        _itemsByCat[id] = kept;
        if (total != null) {
          _totalByCat[id] = (total - removed).clamp(0, total);
        } else if (cursor == null) {
          _totalByCat[id] = kept.length;
        }
        _loadingCat[id] = false;
        _failedCat.remove(id);
      });
    } catch (e) {
      Diag.dev(
        'BROWSE package load failed id=$id attempt=$attempt '
        'type=${e.runtimeType} err=$e',
      );
      if (!mounted) return;
      // A saved row stays on screen when its refresh fails.
      if (_staleCat.contains(id) && attempt >= 1) {
        setState(() => _loadingCat[id] = false);
        return;
      }
      if (_isRateLimited(e)) {
        _rateLimitedUntil = DateTime.now().add(const Duration(seconds: 4));
        setState(() {
          _failedCat.add(id);
          _loadingCat[id] = false;
        });
        return;
      }
      if (attempt < 1) {
        await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
        if (!mounted) return;
        return _fetchCategory(id, attempt: attempt + 1);
      }
      setState(() {
        _failedCat.add(id);
        _loadingCat[id] = false;
      });
    }
  }

  String get _section {
    final base = widget.sectionKey ?? (widget.kind == MediaKind.series ? 'series' : 'vod');
    return ref.read(adultUnlockedProvider) ? '$base-adult' : base;
  }

  void _scheduleSaveRows() {
    _saveRows?.cancel();
    _saveRows = Timer(const Duration(seconds: 2), () {
      final pid = ref.read(sessionProvider).activeProfileId;
      if (!mounted || pid == null || pid.isEmpty) return;
      final fresh = {
        for (final e in _itemsByCat.entries)
          if (!_staleCat.contains(e.key)) e.key: e.value,
      };
      unawaited(RowCache.save(pid, _section, fresh, Map.of(_totalByCat)));
    });
  }

  Future<void> _arrange(AppCopy copy) async {
    final ids = await showArrangePackagesSheet(
      context,
      categories: _categories,
      label: copy.catalogCategoryLabel,
      copy: copy,
    );
    if (ids == null || !mounted) return;
    setState(() {
      _categories = applyCategoryOrder(_providerCategories, ids);
    });
    final pid = ref.read(sessionProvider).activeProfileId;
    if (pid != null && pid.isNotEmpty) {
      await ref.read(categoryOrderStoreProvider).save(pid, _section, ids);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
    if (_expanded.contains(id)) unawaited(_loadCategory(id));
  }

  void _openCategory(CatalogCategory cat, String label) {
    context.push(
      '/browse/${widget.kind.name}/${Uri.encodeComponent(cat.id)}'
      '?title=${Uri.encodeQueryComponent(label)}',
    );
  }

  Future<void> _runSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchHits = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      // Walk cursor pages (backend meta.nextCursor); cap pages so UI stays snappy.
      final found = <MediaItem>[];
      String? cursor;
      for (var pageNo = 0; pageNo < 8; pageNo++) {
        final page = await _browseRepo().searchPage(
              trimmed,
              kind: widget.kind,
              cursor: cursor,
              limit: 40,
            );
        final seen = {for (final m in found) m.id};
        found.addAll(page.items.where((m) => seen.add(m.id)));
        if (!page.hasMore) break;
        cursor = page.nextCursor;
      }
      if (!mounted) return;
      setState(() {
        _searchHits = found;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _searching = false;
      });
    }
  }

  Future<void> _open(MediaItem item) async {
    await withPageLoader(context, () async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    if (!mounted) return;
    openMediaBrowse(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_boot());
      });
    }
    // The screen used to load its categories once: opened before the sync
    // saved anything, it stayed empty (device 2026-11-15). Now it reloads
    // when synced data arrives (3× per sync) or the adult view changes.
    ref.listen(catalogRevisionProvider, (_, _) {
      if (mounted) unawaited(_boot(quiet: true));
    });
    ref.listen(catalogRepositoryProvider, (_, _) {
      if (mounted) unawaited(_boot(quiet: true));
    });
    ref.listen(adultUnlockedProvider, (_, _) {
      if (mounted) unawaited(_boot(quiet: false, resetForAdult: true));
    });

    final searching = _query.trim().isNotEmpty;
    final visible = searching
        ? const <CatalogCategory>[]
        : _categories.take(_shownCatCount).toList(growable: false);
    final hasMoreCats =
        !searching && _shownCatCount < _categories.length;

    return Scaffold(
      appBar: const MainAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?widget.topAction,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              style: TextStyle(color: AppColors.textPrimary),
              onChanged: (v) {
                setState(() => _query = v);
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                  if (mounted) unawaited(_runSearch(v));
                });
              },
              decoration: InputDecoration(
                hintText: widget.searchHint ?? copy.searchInSection,
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                prefixIcon:
                    Icon(Icons.search, color: AppColors.cyan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Builder(builder: (context) {
            final counts = ref.watch(catalogCountsProvider).valueOrNull;
            final section =
                widget.kind == MediaKind.series ? counts?.series : counts?.vod;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SectionEyebrow(
                      label: widget.eyebrow,
                      accent: AppColors.cyan,
                    ),
                  ),
                  // Real total for the section, only when the server sent it.
                  if (section != null && section.total > 0)
                    Text(
                      widget.kind == MediaKind.series
                          ? copy.seriesTitlesCount(section.total)
                          : copy.titlesCount(section.total),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _categories.length < 2
                        ? null
                        : () => _arrange(copy),
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: Text(
                      copy.sortLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cyan,
                    ),
                  ),
                ],
              ),
            );
          }),
          Expanded(
            child: searching
                ? _searchBody(copy)
                : _loadingCats
                    ? Center(child: AppLoader.inline(size: 36))
                    : _error != null && _categories.isEmpty
                        // Client 9 Nov: reload here after reconnecting,
                        // without restarting the app (was the raw error).
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  copy.couldNotLoad,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () => unawaited(_boot()),
                                  child: Text(copy.retry),
                                ),
                              ],
                            ),
                          )
                        : visible.isEmpty
                            ? Center(
                                child: Text(
                                  copy.noTitlesInCategory,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                color: AppColors.cyan,
                                onRefresh: () async {
                                  _itemsByCat.clear();
                                  _expanded.clear();
                                  _queue.clear();
                                  _shownCatCount =
                                      CatalogPaging.categoriesPageSize;
                                  await _boot();
                                },
                                child: _buildCategoryList(
                                  copy,
                                  visible,
                                  hasMoreCats: hasMoreCats,
                                ),
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(
    AppCopy copy,
    List<CatalogCategory> visible, {
    required bool hasMoreCats,
  }) {
    final cw = ref.watch(continueWatchingProvider);
    final fav = ref.watch(myListItemsProvider);
    final kindCw = cw
        .where((m) => m.kind == widget.kind)
        .take(CatalogPaging.pageSize)
        .toList();
    final kindFav = fav
        .where((m) => m.kind == widget.kind)
        .take(CatalogPaging.pageSize)
        .toList();
    final extra = <Widget>[
      if (kindCw.isNotEmpty)
        _CategoryPosterTrail(
          label: copy.continueWatching,
          countLabel: copy.titlesCount(kindCw.length),
          expanded: true,
          loading: false,
          items: kindCw,
          // Client 25 Oct: landscape cards, as on Home.
          continueRow: true,
          onToggle: () {},
          onOpenCategory: () => context.push('/library?tab=continue'),
          onOpen: _open,
        ),
      if (kindFav.isNotEmpty)
        _CategoryPosterTrail(
          label: copy.myList,
          countLabel: copy.titlesCount(kindFav.length),
          expanded: true,
          loading: false,
          items: kindFav,
          onToggle: () {},
          onOpenCategory: () => context.push('/my-list'),
          onOpen: _open,
        ),
    ];
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: extra.length + visible.length + (hasMoreCats ? 1 : 0),
      itemBuilder: (_, i) {
        if (i < extra.length) return extra[i];
        final catIndex = i - extra.length;
        if (hasMoreCats && catIndex == visible.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OutlinedButton(
              onPressed: _revealNextCategoryPage,
              child: Text(copy.loadMorePackages),
            ),
          );
        }
        final cat = visible[catIndex];
        final open = _expanded.contains(cat.id);
        final items = _itemsByCat[cat.id];
        final loading = _loadingCat[cat.id] == true;
        final failed = _failedCat.contains(cat.id);
        if (open && items == null && !loading && !failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_loadCategory(cat.id));
          });
        }
        final counts = ref.watch(catalogCountsProvider).valueOrNull;
        final total = (widget.kind == MediaKind.series
                ? counts?.series
                : counts?.vod)
            ?.byCategory[cat.id] ??
            _totalByCat[cat.id];
        final label = copy.catalogCategoryLabel(cat.name);
        return _CategoryPosterTrail(
          label: label,
          // A count only when the server gave it: never 0 while loading or
          // after a failure.
          countLabel: failed
              ? copy.couldNotLoad
              : total != null
                  ? copy.titlesCount(total)
                  : '',
          expanded: open,
          // Saved rows stay visible while their fresh copy loads.
          loading: loading && items == null,
          failed: failed && items == null,
          failedText: copy.packageLoadFailed,
          retryText: copy.retry,
          emptyText: copy.noTitlesInCategory,
          onRetry: () => unawaited(_loadCategory(cat.id)),
          items: items ?? const [],
          onToggle: () => _toggle(cat.id),
          onOpenCategory: () => _openCategory(cat, label),
          onOpen: _open,
        );
      },
    );
  }

  Widget _searchBody(AppCopy copy) {
    if (_searching) {
      return Center(child: AppLoader.inline(size: 36));
    }
    final hits = _searchHits ?? const <MediaItem>[];
    if (hits.isEmpty) {
      return Center(
        child: Text(
          copy.noTitlesInCategory,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: PosterCard.standardWidth /
            PosterCard.railHeightFor(PosterCard.standardWidth),
      ),
      itemCount: hits.length,
      itemBuilder: (_, i) {
        final item = hits[i];
        return LayoutBuilder(
          builder: (context, c) {
            return PosterCard(
              title: item.displayTitle,
              rating: item.posterRating,
              badges: item.badges,
              imageUrl: item.posterUrl,
              seed: item.posterSeed ?? i,
              width: c.maxWidth,
              onTap: () => _open(item),
            );
          },
        );
      },
    );
  }
}

class _CategoryPosterTrail extends StatelessWidget {
  const _CategoryPosterTrail({
    required this.label,
    required this.countLabel,
    required this.expanded,
    required this.loading,
    this.failed = false,
    this.failedText = '',
    this.retryText = '',
    this.emptyText = '',
    this.onRetry,
    required this.items,
    required this.onToggle,
    required this.onOpenCategory,
    required this.onOpen,
    this.continueRow = false,
  });

  final String label;
  final String countLabel;
  final bool expanded;
  final bool loading;
  final bool failed;
  final String failedText;
  final String retryText;
  final String emptyText;
  final VoidCallback? onRetry;
  final List<MediaItem> items;
  final VoidCallback onToggle;
  final VoidCallback onOpenCategory;
  final ValueChanged<MediaItem> onOpen;

  /// Continue Watching: landscape cards with progress ([ContinueRow]).
  final bool continueRow;

  @override
  Widget build(BuildContext context) {
    final headerPoster = items.isNotEmpty
        ? (items.first.posterUrl ?? items.first.backdropUrl)
        : null;
    final railH = PosterCard.railHeightFor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      expanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: onOpenCategory,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: ColoredBox(
                              color: AppColors.surfaceElevated,
                              child: RemoteImage(
                                url: headerPoster,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                countLabel,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.textSecondary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox.shrink()
                : (loading && items.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: AppLoader.inline(size: 28)),
                      )
                    : failed
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                failedText,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(retryText),
                            ),
                          ],
                        ),
                      )
                    : items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              emptyText,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : continueRow
                        ? ContinueRow(items: items)
                        : SizedBox(
                            height: railH,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount:
                                  items.length.clamp(0, CatalogPaging.pageSize),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) {
                                final item = items[i];
                                return PosterCard(
                                  title: item.displayTitle,
                                  rating: item.posterRating,
                                  badges: item.badges,
                                  imageUrl: item.posterUrl,
                                  seed: item.posterSeed ?? i,
                                  onTap: () => onOpen(item),
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