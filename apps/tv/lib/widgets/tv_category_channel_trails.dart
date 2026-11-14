import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/tv_live_zap.dart';
import '../../core/tv_locale.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_ui.dart';

/// TV Live / Sports: categorical horizontal channel trails.
class TvCategoryChannelTrails extends ConsumerStatefulWidget {
  const TvCategoryChannelTrails({
    super.key,
    required this.title,
    required this.subtitle,
    this.sportsOnly = false,
    this.showPageHeader = true,
    this.leading,
  });

  final String title;
  final String subtitle;
  final bool sportsOnly;

  /// When false, [title]/[subtitle] header is omitted (parent supplies chrome).
  final bool showPageHeader;

  /// Optional strip above category rails (e.g. Today's Matches on Sports).
  final Widget? leading;

  @override
  ConsumerState<TvCategoryChannelTrails> createState() =>
      _TvCategoryChannelTrailsState();
}

class _TvCategoryChannelTrailsState
    extends ConsumerState<TvCategoryChannelTrails> {
  List<CatalogCategory> _categories = const [];
  final Map<String, List<MediaItem>> _itemsByCat = {};
  final Map<String, bool> _loadingCat = {};
  /// Stop auto-reload loops after a permanent failure (build used to call
  /// `_loadCategory` every frame when items stayed null).
  final Set<String> _failedCat = {};
  final List<String> _queue = [];
  int _active = 0;
  static const _maxParallel = 1;
  /// Load every package on the visible page (client: all open by default).
  DateTime? _rateLimitedUntil;
  int _shownCatCount = CatalogPaging.categoriesPageSize;
  bool _loading = true;
  Object? _error;
  bool _started = false;

  static const _trailLimit = CatalogPaging.pageSize;

  List<CatalogCategory> get _pagedCategories {
    final n = _shownCatCount.clamp(0, _categories.length);
    return _categories.take(n).toList(growable: false);
  }

  /// Top rail: favorited live channels for Live TV or Sports (C20).
  List<MediaItem> _favoriteChannels() {
    final lib = ref.read(libraryProvider);
    final sportsIds = {
      for (final c in _categories)
        if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
    };
    final seen = <String>{};
    final out = <MediaItem>[];
    void take(MediaItem m) {
      if (m.kind != MediaKind.live && m.kind != MediaKind.sports) return;
      final sports = RemoteCatalogRepository.isSportsHit(m, sportsIds);
      if (sports != widget.sportsOnly) return;
      if (seen.add(m.id)) out.add(m);
    }
    for (final m in lib.myList) {
      take(m);
    }
    for (final m in lib.liked) {
      take(m);
    }
    final saved = {
      ...lib.myList.map((e) => e.id),
      ...lib.liked.map((e) => e.id),
    };
    for (final items in _itemsByCat.values) {
      for (final m in items) {
        if (saved.contains(m.id)) take(m);
      }
    }
    return out.take(CatalogPaging.pageSize).toList(growable: false);
  }

  Widget _favoritesRail({
    required AppCopy copy,
    required List<MediaItem> favs,
    required bool autofocus,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvSectionTitle(
            copy.myFavorites,
            trailing: copy.channelsCount(favs.length),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: favs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, j) {
                final item = favs[j];
                return FocusTile(
                  autofocus: autofocus && j == 0,
                  escapeToSidebar: j == 0,
                  borderRadius: 14,
                  focusScale: 1.04,
                  onTap: () => openTvLiveChannel(
                    context,
                    ref,
                    item,
                    favs,
                    title: copy.myFavorites,
                  ),
                  child: TvGlass(
                    radius: 12,
                    child: SizedBox(
                      width: 128,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: AppColors.surfaceElevated,
                                child: RemoteImage(
                                  url: item.posterUrl ?? item.backdropUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
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
                            ),
                          ),
                          if (item.badges.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              children: [
                                for (final b in item.badges.take(2))
                                  TechBadge(b, compact: true),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _revealNextCategoryPage() {
    if (_shownCatCount >= _categories.length) return;
    final prev = _shownCatCount;
    setState(() {
      _shownCatCount = (_shownCatCount + CatalogPaging.categoriesPageSize)
          .clamp(0, _categories.length);
    });
    // Load every package on the newly revealed page.
    final next = _categories.skip(prev).take(_shownCatCount - prev);
    for (final c in next) {
      unawaited(_enqueueCategory(c.id));
    }
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(catalogRepositoryProvider);
      var cats = await repo.getCategories(MediaKind.live);
      if (widget.sportsOnly) {
        cats = [
          for (final c in cats)
            if (RemoteCatalogRepository.isSportsCategory(c)) c,
        ];
      }
      final unique = <CatalogCategory>[];
      final seen = <String>{};
      // Unique by id (name collisions hid whole packages).
      for (final c in cats) {
        if (seen.add(c.id)) unique.add(c);
      }
      if (!mounted) return;
      setState(() {
        _categories = unique;
        _shownCatCount = CatalogPaging.categoriesPageSize;
        _queue.clear();
        _loading = false;
      });
      // Load every trail on page 1 (all expanded — client 20 Oct).
      for (final c in unique.take(_shownCatCount)) {
        unawaited(_enqueueCategory(c.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _enqueueCategory(String id) async {
    if (_itemsByCat.containsKey(id) ||
        _loadingCat[id] == true ||
        _failedCat.contains(id) ||
        _queue.contains(id)) {
      return;
    }
    setState(() {
      _loadingCat[id] = true;
      _failedCat.remove(id);
    });
    _queue.add(id);
    _pump();
  }

  void _pump() {
    final until = _rateLimitedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      Future<void>.delayed(until.difference(DateTime.now()), () {
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
              categoryId: id,
              limit: _trailLimit,
              cursor: cursor,
            );
        if (!mounted) return;
        kept.addAll(
          page.items.where((m) => !isProviderAdOrHeaderChannel(m.title)),
        );
        cursor = page.nextCursor;
        pages++;
      } while (cursor != null &&
          cursor.isNotEmpty &&
          pages < maxPages &&
          kept.length < 200);
      setState(() {
        _itemsByCat[id] = kept;
        _loadingCat[id] = false;
        _failedCat.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      if (_isRateLimited(e)) {
        _rateLimitedUntil = DateTime.now().add(const Duration(seconds: 4));
        setState(() {
          _loadingCat[id] = false;
          _failedCat.add(id);
        });
        return;
      }
      if (attempt < 1) {
        await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
        if (!mounted) return;
        return _fetchCategory(id, attempt: attempt + 1);
      }
      // Do not store an empty list (looked like "0 channels"). Mark failed
      // so build does not re-queue forever.
      setState(() {
        _loadingCat[id] = false;
        _failedCat.add(id);
      });
    }
  }

  void _retryCategory(String id) {
    _failedCat.remove(id);
    unawaited(_enqueueCategory(id));
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_boot());
      });
    }

    if (_loading) {
      return ListView(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          if (widget.showPageHeader) ...[
            TvPageHeader(title: widget.title, subtitle: widget.subtitle),
            const SizedBox(height: 16),
          ],
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(height: 16),
          ],
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppShimmer.block(
                height: 140,
                radius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return Center(child: Text('$_error'));
    }

    if (_categories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          if (widget.showPageHeader)
            TvPageHeader(title: widget.title, subtitle: widget.subtitle),
          if (widget.leading != null) widget.leading!,
          Text(
            copy.noLiveChannels,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    // Order: header → fixtures → My Favorites → category rails (paged).
    ref.watch(libraryProvider);
    final favs = _favoriteChannels();
    final favOffset = favs.isEmpty ? 0 : 1;
    final paged = _pagedCategories;
    final hasMore = _shownCatCount < _categories.length;
    final leadCount = (widget.showPageHeader ? 1 : 0) +
        (widget.leading != null ? 1 : 0) +
        favOffset;
    final hasLeadingFocus = widget.leading != null;
    final favTakesFocus = !hasLeadingFocus && favOffset == 1;

    return ListView.builder(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      itemCount: paged.length + leadCount + (hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        var slot = i;
        if (widget.showPageHeader) {
          if (slot == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: TvPageHeader(
                title: widget.title,
                subtitle: widget.subtitle,
              ),
            );
          }
          slot--;
        }
        if (widget.leading != null) {
          if (slot == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: widget.leading!,
            );
          }
          slot--;
        }
        if (favOffset == 1) {
          if (slot == 0) {
            return _favoritesRail(
              copy: copy,
              favs: favs,
              autofocus: favTakesFocus,
            );
          }
          slot--;
        }
        if (hasMore && slot == paged.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: TvButton(
              label: copy.loadMorePackages,
              onTap: _revealNextCategoryPage,
            ),
          );
        }
        final cat = paged[slot];
        final items = _itemsByCat[cat.id];
        final loading = _loadingCat[cat.id] == true;
        final failed = _failedCat.contains(cat.id);
        // Only auto-load within the current page, and only if not already
        // requested — serial queue caps API pressure.
        if (items == null && !loading && !failed) {
          unawaited(_enqueueCategory(cat.id));
        }
        // Fixtures / My Favorites take first focus when present.
        final trailAutofocus = !hasLeadingFocus && !favTakesFocus && slot == 0;
        final label = copy.catalogCategoryLabel(cat.name);
        final total = ref.watch(catalogCountsProvider).valueOrNull?.live
                .byCategory[cat.id] ??
            items?.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TvSectionTitle(
                label,
                trailing: failed
                    ? copy.packageLoadFailed
                    : total != null
                        ? copy.channelsCount(total)
                        : '',
                onTap: () {
                  if (failed) {
                    _retryCategory(cat.id);
                    return;
                  }
                  context.push(
                    '/browse/${MediaKind.live.name}/'
                    '${Uri.encodeComponent(cat.id)}'
                    '?title=${Uri.encodeQueryComponent(label)}',
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 118,
                child: failed
                    ? Center(
                        child: TvButton(
                          label: copy.retry,
                          onTap: () => _retryCategory(cat.id),
                        ),
                      )
                    : loading && (items == null || items.isEmpty)
                    ? Center(child: AppLoader.inline(size: 32))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: (items ?? const [])
                            .length
                            .clamp(0, CatalogPaging.pageSize),
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, j) {
                          final item = items![j];
                          return FocusTile(
                            autofocus: trailAutofocus && j == 0,
                            escapeToSidebar: j == 0,
                            borderRadius: 14,
                            focusScale: 1.04,
                            onTap: () => openTvLiveChannel(
                              context,
                              ref,
                              item,
                              items,
                              title: copy.catalogCategoryLabel(cat.name),
                            ),
                            child: TvGlass(
                              radius: 12,
                              child: SizedBox(
                                width: 128,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: ColoredBox(
                                          color: AppColors.surfaceElevated,
                                          child: RemoteImage(
                                            url: item.posterUrl ??
                                                item.backdropUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
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
                                      ),
                                    ),
                                    // Task #143 #9: quality / variant badges.
                                    if (item.badges.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 4,
                                        children: [
                                          for (final b in item.badges.take(2))
                                            TechBadge(b, compact: true),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
