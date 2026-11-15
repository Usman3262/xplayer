import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/catalog.dart';
import '../core/library_controller.dart';
import '../core/media_nav.dart';
import '../core/providers.dart';
import '../core/session_controller.dart';
import '../core/ui_sound.dart';
import 'arrange_packages_sheet.dart';
import 'main_app_bar.dart';
import 'nav_loader.dart';

/// Live / Sports: one expandable categorical row trail per channel group
/// (screenshot: ALWAN TV, beIN, SSC… with horizontal channel cards).
class CategoryChannelTrailsScreen extends ConsumerStatefulWidget {
  const CategoryChannelTrailsScreen({
    super.key,
    required this.kind,
    required this.eyebrow,
    this.searchHint,
    this.sportsOnly = false,
    this.kidsOnly = false,
    this.header,
    this.showAppBar = true,
  });

  final MediaKind kind;
  final String eyebrow;
  final String? searchHint;
  /// When true, only live categories whose names look like sports networks.
  final bool sportsOnly;

  /// Kids → Live TV: the same layout limited to children's packages, with
  /// its own favourites (client 21 Oct).
  final bool kidsOnly;

  /// Above the search field (Sports: Matches & Lineups entry; Kids: tabs).
  final Widget? header;

  /// False when embedded in a screen that has its own app bar.
  final bool showAppBar;

  @override
  ConsumerState<CategoryChannelTrailsScreen> createState() =>
      _CategoryChannelTrailsScreenState();
}

class _CategoryChannelTrailsScreenState
    extends ConsumerState<CategoryChannelTrailsScreen> {
  final _scroll = ScrollController();
  Timer? _searchDebounce;
  String _query = '';
  List<CatalogCategory> _categories = const [];
  List<CatalogCategory> _providerCategories = const [];
  final Map<String, List<MediaItem>> _itemsByCat = {};
  final Map<String, bool> _loadingCat = {};
  /// Packages whose load failed: shown with Retry, never as "0 channels".
  final Set<String> _failedCat = {};
  /// Channel count per package from the server's total, not rows loaded.
  final Map<String, int> _totalByCat = {};
  final List<String> _queue = [];
  int _active = 0;
  /// 3 at a time (client 6 Nov: sections load very slowly one by one); a
  /// 429 still pauses the queue (device log 19 Oct on SM-G988U).
  static const _maxParallel = 3;
  /// Client 20 Oct: all packages expanded by default (was 2 — do not regress).
  /// Pause the queue after a 429 so retries do not keep hammering.
  DateTime? _rateLimitedUntil;
  final Set<String> _expanded = {};
  /// How many package rows are on the current UI page (paginated).
  int _shownCatCount = CatalogPaging.categoriesPageSize;
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
    final filtered = _filteredCategories;
    if (_shownCatCount >= filtered.length) return;
    final prev = _shownCatCount;
    setState(() {
      _shownCatCount = (_shownCatCount + CatalogPaging.categoriesPageSize)
          .clamp(0, filtered.length);
      for (final c in filtered.skip(prev).take(_shownCatCount - prev)) {
        _expanded.add(c.id);
      }
    });
    for (final c in filtered.skip(prev).take(_shownCatCount - prev)) {
      unawaited(_loadCategory(c.id));
    }
  }

  Future<void> _boot() async {
    setState(() {
      _loadingCats = true;
      _error = null;
    });
    try {
      final repo = ref.read(catalogRepositoryProvider);
      var cats = await repo.getCategories(MediaKind.live);
      // Every sports package id, before the Live / Sports split below: the
      // Live TV tab dropped them and then could not tell a sports favourite
      // (one added on the TV, no "sport" in its name) from a Live TV one, so
      // it showed in both (client 23 Oct).
      _sportsIds = {
        for (final c in cats)
          if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
      };
      _kidsIds = {
        for (final c in cats)
          if (!RemoteCatalogRepository.isSportsCategory(c) &&
              KidsPanelCategories.looksKids(c.name))
            c.id,
      };
      if (widget.kidsOnly) {
        cats = [for (final c in cats) if (_kidsIds.contains(c.id)) c];
      }
      // Sports packages only in Sports, never in general Live TV (client
      // 17 Oct #13: the phone Live TV listed ALWAN SPORT, beIN SPORTS…; it
      // only filtered for the Sports tab). Same rule as the TV app.
      cats = [
        for (final c in cats)
          if (RemoteCatalogRepository.isSportsCategory(c) == widget.sportsOnly)
            c,
      ];
      // Unique by id: two packages with the same name are different
      // packages (merging by name hid one of them and its channels).
      final unique = <CatalogCategory>[];
      final seen = <String>{};
      for (final c in cats) {
        if (seen.add(c.id)) unique.add(c);
      }
      var ordered = unique;
      final pid = ref.read(sessionProvider).activeProfileId;
      if (pid != null && pid.isNotEmpty) {
        final ids = await ref.read(categoryOrderStoreProvider).load(pid, 'live');
        ordered = applyCategoryOrder(unique, ids);
      }
      if (!mounted) return;
      setState(() {
        _providerCategories = unique;
        _categories = ordered;
        _loadingCats = false;
        _shownCatCount = CatalogPaging.categoriesPageSize;
        _queue.clear();
        // All packages expanded by default (client 20 Oct — was first 2 only).
        _expanded
          ..clear()
          ..addAll(ordered.map((c) => c.id));
      });
      // Serial-load the visible page; expanded UI shows loaders until filled.
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

  /// Synced data arrived (3× per sync): nothing shown yet → load; otherwise
  /// only the packages on screen that are still empty or failed reload
  /// (no spinner, rows already shown stay).
  void _refreshQuiet() {
    if (!mounted || _loadingCats) return;
    if (_categories.isEmpty || _error != null) {
      unawaited(_boot());
      return;
    }
    for (final c in _pagedCategories) {
      final items = _itemsByCat[c.id];
      if ((items == null || items.isEmpty) && _loadingCat[c.id] != true) {
        _itemsByCat.remove(c.id);
        _failedCat.remove(c.id);
        unawaited(_loadCategory(c.id));
      }
    }
  }

  /// Queues a package load; at most [_maxParallel] run at once.
  Future<void> _loadCategory(String categoryId) async {
    if (_itemsByCat.containsKey(categoryId) ||
        _loadingCat[categoryId] == true ||
        _queue.contains(categoryId)) {
      return;
    }
    setState(() {
      _failedCat.remove(categoryId);
      _loadingCat[categoryId] = true;
    });
    _queue.add(categoryId);
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

  Future<void> _fetchCategory(String categoryId, {int attempt = 0}) async {
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
        final page = await ref.read(catalogRepositoryProvider).browse(
              kind: MediaKind.live,
              categoryId: categoryId,
              limit: _trailLimit,
              cursor: cursor,
            );
        if (!mounted) return;
        for (final m in page.items) {
          if (isProviderAdOrHeaderChannel(m.title)) {
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
      setState(() {
        _itemsByCat[categoryId] = kept;
        if (total != null) {
          _totalByCat[categoryId] = (total - removed).clamp(0, total);
        } else if (cursor == null) {
          _totalByCat[categoryId] = kept.length;
        }
        _loadingCat[categoryId] = false;
        _failedCat.remove(categoryId);
      });
    } catch (e) {
      Diag.dev(
        'LIVE package load failed id=$categoryId attempt=$attempt '
        'type=${e.runtimeType} err=$e',
      );
      if (!mounted) return;
      if (_isRateLimited(e)) {
        // Back off the whole queue; do not immediate-retry into another 429.
        _rateLimitedUntil = DateTime.now().add(const Duration(seconds: 4));
        setState(() {
          _failedCat.add(categoryId);
          _loadingCat[categoryId] = false;
        });
        return;
      }
      if (attempt < 1) {
        await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
        if (!mounted) return;
        return _fetchCategory(categoryId, attempt: attempt + 1);
      }
      setState(() {
        _failedCat.add(categoryId);
        _loadingCat[categoryId] = false;
      });
    }
  }

  void _retry(String categoryId) => unawaited(_loadCategory(categoryId));

  /// Live TV and Sports share one channel-package order ('live').
  Future<void> _arrange(AppCopy copy) async {
    final ids = await showArrangePackagesSheet(
      context,
      categories: _categories,
      label: copy.catalogCategoryLabel,
      copy: copy,
    );
    if (ids == null || !mounted) return;
    final pid = ref.read(sessionProvider).activeProfileId;
    var saved = ids;
    if (pid != null && pid.isNotEmpty && ids.isNotEmpty) {
      // Keep the positions of packages not shown here (Sports vs Live TV).
      final store = ref.read(categoryOrderStoreProvider);
      final previous = await store.load(pid, 'live');
      final shown = ids.toSet();
      saved = [...ids, for (final id in previous) if (!shown.contains(id)) id];
    }
    if (!mounted) return;
    setState(() {
      _categories = applyCategoryOrder(_providerCategories, ids);
    });
    if (pid != null && pid.isNotEmpty) {
      await ref.read(categoryOrderStoreProvider).save(pid, 'live', saved);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
        unawaited(_loadCategory(id));
      }
    });
  }

  Future<void> _open(MediaItem item) async {
    await withPageLoader(context, () async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    if (!mounted) return;
    openMediaBrowse(context, item);
  }

  List<CatalogCategory> get _filteredCategories {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return [
      for (final c in _categories)
        if (c.name.toLowerCase().contains(q)) c,
    ];
  }

  /// Current UI page of packages (15 at a time).
  List<CatalogCategory> get _pagedCategories {
    final all = _filteredCategories;
    final n = _shownCatCount.clamp(0, all.length);
    return all.take(n).toList(growable: false);
  }

  static const _favCatId = '__my_favorites__';

  /// Children's live packages (Kids favourites live only in Kids).
  Set<String> _kidsIds = const {};

  /// All sports package ids (Live and Sports tabs alike).
  Set<String> _sportsIds = const {};

  /// Top rail: favorited live channels for this tab (Live vs Sports).
  List<MediaItem> _favoriteChannels() {
    final lib = ref.read(libraryProvider);
    final sportsIds = _sportsIds;
    final seen = <String>{};
    final out = <MediaItem>[];
    void take(MediaItem m) {
      if (m.kind != MediaKind.live && m.kind != MediaKind.sports) return;
      final sports = RemoteCatalogRepository.isSportsHit(m, sportsIds);
      final cat = m.categoryId ?? FavoriteCategories.categoryOf(m.id);
      // No category from the server or this device: the channel name decides,
      // as for Sports (MBC TOON, Spacetoon…; TCL 21 Oct showed it nowhere).
      final kids = !sports &&
          (cat != null
              ? _kidsIds.contains(cat)
              : KidsPanelCategories.looksKids(m.title));
      // Kids favourites only in Kids, sports ones only in Sports.
      if (widget.kidsOnly ? !kids : (kids || sports != widget.sportsOnly)) {
        return;
      }
      if (seen.add(m.id)) out.add(m);
    }
    for (final m in lib.myList) {
      take(m);
    }
    for (final m in lib.liked) {
      take(m);
    }
    // Also pick hearts still in loaded package rows (fresh toggle).
    final saved = {
      ...lib.myList.map((e) => e.id),
      ...lib.liked.map((e) => e.id),
    };
    for (final items in _itemsByCat.values) {
      for (final m in items) {
        if (saved.contains(m.id)) take(m);
      }
    }
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? out
        : [
            for (final m in out)
              if (m.displayTitle.toLowerCase().contains(q) ||
                  m.title.toLowerCase().contains(q))
                m,
          ];
    return filtered.take(CatalogPaging.pageSize).toList(growable: false);
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
    // Provider changes can arrive while widgets build: act after the frame.
    void later(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) f();
        });
    ref.listen<int>(catalogRevisionProvider, (_, _) => later(_refreshQuiet));
    // Another main panel: the package list changes.
    ref.listen(catalogRepositoryProvider, (_, _) => later(() {
          _itemsByCat.clear();
          _totalByCat.clear();
          unawaited(_boot());
        }));

    final filtered = _filteredCategories;
    final paged = _pagedCategories;
    final hasMore = _shownCatCount < filtered.length;
    // Watch library so the My Favorites rail updates on heart/star toggles.
    ref.watch(libraryProvider);
    final favs = _favoriteChannels();
    final favOffset = favs.isEmpty ? 0 : 1;

    return Scaffold(
      appBar: widget.showAppBar ? const MainAppBar() : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              style: TextStyle(color: AppColors.textPrimary),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 280), () {
                  if (!mounted) return;
                  setState(() {
                    _query = v.trim();
                    _shownCatCount = CatalogPaging.categoriesPageSize;
                  });
                  // Only expand/load a few search hits — never the full catalog.
                  if (_query.isEmpty) return;
                  final hits = _pagedCategories.take(4);
                  for (final c in hits) {
                    _expanded.add(c.id);
                    unawaited(_loadCategory(c.id));
                  }
                });
              },
              decoration: InputDecoration(
                hintText: widget.searchHint ?? copy.searchInSection,
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                prefixIcon: Icon(Icons.search, color: AppColors.cyan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Row(
              children: [
                Expanded(
                  child: SectionEyebrow(
                    label: widget.eyebrow,
                    accent: widget.sportsOnly
                        ? AppColors.cyan
                        : AppColors.live,
                  ),
                ),
                // Total channels in this section (client 23 Oct #4).
                Builder(builder: (context) {
                  final counts =
                      ref.watch(catalogCountsProvider).valueOrNull?.live.byCategory;
                  var total = 0;
                  for (final c in _categories) {
                    total += counts?[c.id] ?? _totalByCat[c.id] ?? 0;
                  }
                  if (total == 0) return const SizedBox.shrink();
                  return Text(
                    copy.channelsTotal(total),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                }),
                IconButton(
                  tooltip: copy.arrangePackages,
                  onPressed:
                      _categories.length < 2 ? null : () => _arrange(copy),
                  icon: const Icon(Icons.swap_vert_rounded),
                ),
                CategoryChip(
                  label: copy.all,
                  selected: paged.isNotEmpty &&
                      paged.every((c) => _expanded.contains(c.id)),
                  onTap: () {
                    setState(() {
                      final allOpen =
                          paged.every((c) => _expanded.contains(c.id));
                      if (allOpen) {
                        for (final c in paged) {
                          _expanded.remove(c.id);
                        }
                      } else {
                        // Expand + queue-load every package on this page.
                        for (final c in paged) {
                          _expanded.add(c.id);
                        }
                      }
                    });
                    final allOpen =
                        paged.every((c) => _expanded.contains(c.id));
                    if (allOpen) {
                      for (final c in paged) {
                        unawaited(_loadCategory(c.id));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingCats
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppShimmer.block(
                        height: 160,
                        radius: BorderRadius.circular(14),
                      ),
                      const SizedBox(height: 16),
                      AppShimmer.block(
                        height: 160,
                        radius: BorderRadius.circular(14),
                      ),
                    ],
                  )
                : _error != null
                    // Client 9 Nov: reload here after reconnecting, without
                    // restarting the app (was the raw error).
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
                    : filtered.isEmpty && favs.isEmpty
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
                            child: ListView.builder(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 28),
                              itemCount:
                                  paged.length + favOffset + (hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (favOffset == 1 && i == 0) {
                                  return _CategoryTrail(
                                    category: const CatalogCategory(
                                      id: _favCatId,
                                      name: 'My Favorites',
                                    ),
                                    label: copy.myFavorites,
                                    expanded: true,
                                    loading: false,
                                    failed: false,
                                    onRetry: () {},
                                    items: favs,
                                    channelLabel:
                                        copy.channelsCount(favs.length),
                                    onToggle: () {},
                                    // The whole list (Live TV or Sports
                                    // favourites only, as the rail).
                                    onOpenCategory: () => context.push(
                                      '/browse/${widget.kind.name}/$_favCatId'
                                      '?title=${Uri.encodeQueryComponent(copy.myFavorites)}',
                                      extra: favs,
                                    ),
                                    onOpen: _open,
                                    hideExpandChevron: true,
                                  );
                                }
                                final slot = i - favOffset;
                                if (hasMore && slot == paged.length) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      16,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: _revealNextCategoryPage,
                                      child: Text(copy.loadMorePackages),
                                    ),
                                  );
                                }
                                final cat = paged[slot];
                                final open = _expanded.contains(cat.id);
                                final items = _itemsByCat[cat.id];
                                final loading = _loadingCat[cat.id] == true;
                                final failed = _failedCat.contains(cat.id);
                                // Load only when expanded and in this page.
                                if (open &&
                                    items == null &&
                                    !loading &&
                                    !failed) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) {
                                      unawaited(_loadCategory(cat.id));
                                    }
                                  });
                                }
                                final total = ref
                                        .watch(catalogCountsProvider)
                                        .valueOrNull
                                        ?.live
                                        .byCategory[cat.id] ??
                                    _totalByCat[cat.id];
                                final label =
                                    copy.catalogCategoryLabel(cat.name);
                                return _CategoryTrail(
                                  category: cat,
                                  label: label,
                                  expanded: open,
                                  loading: loading,
                                  failed: failed,
                                  onRetry: () => _retry(cat.id),
                                  items: items ?? const [],
                                  channelLabel: failed
                                      ? copy.couldNotLoad
                                      : total != null
                                          ? copy.channelsCount(total)
                                          : '',
                                  onToggle: () => _toggle(cat.id),
                                  onOpenCategory: () {
                                    context.push(
                                      '/browse/${widget.kind.name}/'
                                      '${Uri.encodeComponent(cat.id)}'
                                      '?title=${Uri.encodeQueryComponent(label)}',
                                    );
                                  },
                                  onOpen: _open,
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

class _CategoryTrail extends ConsumerWidget {
  const _CategoryTrail({
    required this.category,
    required this.label,
    required this.expanded,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.items,
    required this.channelLabel,
    required this.onToggle,
    required this.onOpenCategory,
    required this.onOpen,
    this.hideExpandChevron = false,
  });

  final CatalogCategory category;
  final String label;
  final bool expanded;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final List<MediaItem> items;
  final String channelLabel;
  final VoidCallback onToggle;
  final VoidCallback onOpenCategory;
  final ValueChanged<MediaItem> onOpen;
  final bool hideExpandChevron;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final headerPoster =
        items.isNotEmpty ? (items.first.posterUrl ?? items.first.backdropUrl) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (!hideExpandChevron) ...[
                  InkWell(
                    onTap: onToggle,
                    child: Icon(
                      expanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: InkWell(
                    onTap: onOpenCategory,
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: headerPoster != null &&
                                    headerPoster.isNotEmpty
                                ? RemoteImage(
                                    url: headerPoster,
                                    fit: BoxFit.cover,
                                  )
                                : ColoredBox(
                                    color: AppColors.surfaceElevated,
                                    child: Icon(
                                      Icons.live_tv_rounded,
                                      color: AppColors.cyan
                                          .withValues(alpha: 0.8),
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
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                channelLabel,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      if (loading && items.isEmpty)
                        SizedBox(
                          height: 132,
                          child: Center(child: AppLoader.inline(size: 28)),
                        )
                      else if (failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  copy.packageLoadFailed,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(copy.retry),
                              ),
                            ],
                          ),
                        )
                      else if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            copy.noChannelsInPackage,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 118,
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
                              return NeonTap(
                                onTap: () => onOpen(item),
                                child: _ChannelCard(item: item),
                              );
                            },
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

class _ChannelCard extends ConsumerWidget {
  const _ChannelCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final saved = lib.isFavoriteChannel(item.id);
    return SizedBox(
        width: 102,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          AppColors.surfaceElevated,
                        ],
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RemoteImage(
                        url: item.posterUrl ?? item.backdropUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: () {
                        playUiTap(ref);
                        final n = ref.read(libraryProvider.notifier);
                        final inList = lib.myList.any((e) => e.id == item.id);
                        if (saved) {
                          if (inList) n.toggleMyList(item.id, item: item);
                          if (lib.ratingFor(item.id) == 1 ||
                              lib.liked.any((e) => e.id == item.id)) {
                            n.setRating(item.id, 0, item: item);
                          }
                        } else {
                          // Server Favourites, shared with the TV.
                          n.setRating(item.id, 1, item: item);
                        }
                      },
                      child: Icon(
                        saved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: saved ? AppColors.magenta : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            // Task #143 #9: quality / variant badges (beIN A/F, HD…).
            if (item.badges.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final b in item.badges.take(2))
                    TechBadge(b, compact: true),
                ],
              ),
            ],
          ],
        ),
    );
  }
}
