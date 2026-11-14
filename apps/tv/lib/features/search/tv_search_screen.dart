import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_media_nav.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_genre_chip_bar.dart';
import '../../widgets/tv_feed_loading.dart';
import '../../widgets/tv_poster.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_ui.dart';

enum _SearchKindFilter { all, movies, series, live, sports }

/// Global Search V2 — field, trending/recent when empty, top-result hero +
/// kind filters + poster rails when querying (Figma v2TV5s).
/// [scope] null = global search (all kinds, filter chips). Opened from
/// Movies, Series, Live TV or Sports it searches only that section on the
/// server and shows no other kinds (client 17 Oct).
class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key, this.scope, this.kids = false});

  final MediaKind? scope;

  /// Opened from Kids: searches only kids content (client 1 Nov #8).
  final bool kids;

  static MediaKind? scopeFromQuery(String? value) => switch (value) {
        'movie' => MediaKind.movie,
        'series' => MediaKind.series,
        'live' => MediaKind.live,
        'sports' => MediaKind.sports,
        _ => null,
      };

  /// Scope for the search button on the page at [location].
  static String searchPathFor(String location) {
    String? scope;
    if (location.startsWith('/movies')) scope = 'movie';
    if (location.startsWith('/series')) scope = 'series';
    if (location.startsWith('/live')) scope = 'live';
    if (location.startsWith('/sports')) scope = 'sports';
    if (location.startsWith('/kids')) scope = 'kids';
    return scope == null ? '/search' : '/search?scope=$scope';
  }

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  static const _pageSize = 40;

  final _controller = TextEditingController();
  String _query = '';
  List<MediaItem> _results = const [];
  List<MediaItem> _discover = const [];
  _SearchKindFilter _kind = _SearchKindFilter.all;
  Set<String>? _sportsIds;

  static _SearchKindFilter _filterFor(MediaKind? scope) => switch (scope) {
        MediaKind.movie => _SearchKindFilter.movies,
        MediaKind.series => _SearchKindFilter.series,
        MediaKind.live => _SearchKindFilter.live,
        MediaKind.sports => _SearchKindFilter.sports,
        null => _SearchKindFilter.all,
      };

  @override
  void didUpdateWidget(covariant TvSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.kids != widget.kids) {
      _kind = _filterFor(widget.scope);
      if (_query.isNotEmpty) unawaited(_resetSearch(_query));
    }
  }
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _cursor;
  Timer? _debounce;

  Future<void> _run(String q) async {
    final trimmed = q.trim();
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _loading = true;
        _kind = _filterFor(widget.scope);
        _cursor = null;
        _hasMore = false;
      });
      final items = widget.kids
          ? const <MediaItem>[]
          : await ref.read(searchProvider('').future);
      if (!mounted) return;
      setState(() {
        _results = items;
        _discover = items;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_resetSearch(trimmed));
    });
  }

  /// Bumped for every new query: a response for an older query is dropped
  /// (client 16 Oct #19). Before, a new query was skipped while the previous
  /// request was in flight, and the old results then showed for the new text.
  int _searchGen = 0;
  bool _searchFailed = false;

  Future<void> _resetSearch(String trimmed) async {
    _searchGen++;
    setState(() {
      _query = trimmed;
      _loading = true;
      _loadingMore = false;
      _searchFailed = false;
      _results = const [];
      _cursor = null;
      _hasMore = true;
    });
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if ((!reset && _loadingMore) || (!_hasMore && !reset) || _query.isEmpty) {
      return;
    }
    final gen = _searchGen;
    final query = _query;
    setState(() => _loadingMore = true);
    if (widget.kids) {
      try {
        final items = await ref.read(kidsSearchProvider(query).future);
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _results = items;
          _hasMore = false;
          _loading = false;
          _loadingMore = false;
        });
      } catch (_) {
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _loading = false;
          _loadingMore = false;
          _hasMore = false;
          _searchFailed = true;
        });
      }
      return;
    }
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final scope = widget.scope;
      final page = await repo.searchPage(
            query,
            kind: scope,
            cursor: reset ? null : _cursor,
            limit: _pageSize,
          );
      if (gen != _searchGen) return;
      var items = page.items;
      final sportsOn =
          ref.read(sportsEnabledProvider).valueOrNull ?? false;
      if (scope == MediaKind.live || scope == MediaKind.sports || !sportsOn) {
        _sportsIds ??= {
          for (final c in await repo.getCategories(MediaKind.live))
            if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
        };
        final ids = _sportsIds!;
        bool sports(MediaItem m) =>
            RemoteCatalogRepository.isSportsHit(m, ids);
        items = [
          for (final m in items)
            if (switch (scope) {
              MediaKind.sports => sportsOn && sports(m),
              MediaKind.live => !sports(m),
              _ => sportsOn || !sports(m),
            })
              m,
        ];
      }
      if (!mounted) return;
      setState(() {
        if (reset) {
          _results = items;
        } else {
          final seen = {for (final m in _results) m.id};
          _results = [
            ..._results,
            ...items.where((m) => seen.add(m.id)),
          ];
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _hasMore = false;
          _searchFailed = true;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _kind = _filterFor(widget.scope);
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<MediaItem> get _filtered {
    // Scoped search: the server and the sports filter already kept only
    // this section.
    if (widget.scope != null || widget.kids) return _results;
    switch (_kind) {
      case _SearchKindFilter.all:
        return _results;
      case _SearchKindFilter.movies:
        return [for (final m in _results) if (m.kind == MediaKind.movie) m];
      case _SearchKindFilter.series:
        return [for (final m in _results) if (m.kind == MediaKind.series) m];
      case _SearchKindFilter.live:
        return [
          for (final m in _results)
            if (m.kind == MediaKind.live || m.isLive) m,
        ];
      case _SearchKindFilter.sports:
        return [for (final m in _results) if (m.kind == MediaKind.sports) m];
    }
  }

  int _count(_SearchKindFilter f) {
    switch (f) {
      case _SearchKindFilter.all:
        return _results.length;
      case _SearchKindFilter.movies:
        return _results.where((m) => m.kind == MediaKind.movie).length;
      case _SearchKindFilter.series:
        return _results.where((m) => m.kind == MediaKind.series).length;
      case _SearchKindFilter.live:
        return _results
            .where((m) => m.kind == MediaKind.live || m.isLive)
            .length;
      case _SearchKindFilter.sports:
        return _results.where((m) => m.kind == MediaKind.sports).length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final ar = AppCopy.ofLanguage('ar');
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    final emptyQuery = _query.isEmpty;
    final filtered = _filtered;
    // Client 18 Oct TV #5: every result is a portrait poster, as on Home.
    // The first result used to be a wide banner that stretched its poster.
    final rest = filtered;
    final moviesSeries = [
      for (final m in rest)
        if (m.kind == MediaKind.movie || m.kind == MediaKind.series) m,
    ];
    final liveSports = [
      for (final m in rest)
        if (m.kind == MediaKind.live ||
            m.kind == MediaKind.sports ||
            m.isLive)
          m,
    ];

    final kindLabels = [
      '${copy.all} (${_count(_SearchKindFilter.all)})',
      '${copy.movies} (${_count(_SearchKindFilter.movies)})',
      '${copy.series} (${_count(_SearchKindFilter.series)})',
      '${copy.liveTv} (${_count(_SearchKindFilter.live)})',
      if (sportsOn) '${copy.sports} (${_count(_SearchKindFilter.sports)})',
    ];
    final kindValues = [
      _SearchKindFilter.all,
      _SearchKindFilter.movies,
      _SearchKindFilter.series,
      _SearchKindFilter.live,
      if (sportsOn) _SearchKindFilter.sports,
    ];
    final kindIndex = kindValues.indexOf(_kind).clamp(0, kindValues.length - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvPageHeader(
            title: copy.search.toUpperCase(),
            arabicTitle: ar.search,
            subtitle: emptyQuery
                ? copy.searchInSection
                : 'for "$_query" · ${copy.titlesCount(filtered.length)}',
            showSearch: false,
          ),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.55),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.22),
                  blurRadius: 16,
                ),
              ],
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: widget.kids
                    ? copy.searchKids
                    : copy.searchGlobal(sportsOn: sportsOn),
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                filled: false,
                border: InputBorder.none,
                prefixIcon:
                    Icon(Icons.search, color: AppColors.cyan),
                suffixIcon: _query.isEmpty
                    ? Icon(
                        Icons.mic_none_rounded,
                        color: AppColors.textSecondary,
                      )
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textSecondary,
                        onPressed: () {
                          _controller.clear();
                          _run('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _run,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const TvFeedLoading(
                    showHero: false,
                    railCount: 2,
                    padding: EdgeInsets.zero,
                  )
                : emptyQuery
                    ? _EmptyDiscover(
                        copy: copy,
                        discover: _discover,
                        onChip: (title) {
                          _controller.text = title;
                          _controller.selection = TextSelection.collapsed(
                            offset: title.length,
                          );
                          _run(title);
                        },
                      )
                    : ListView(
                        clipBehavior: Clip.none,
                        scrollCacheExtent:
                            const ScrollCacheExtent.pixels(1400),
                        children: [
                          if (widget.scope == null && !widget.kids)
                          TvGenreChipBar(
                            labels: kindLabels,
                            selectedIndex: kindIndex,
                            onSelected: (i) => setState(
                              () => _kind = kindValues[i],
                            ),
                          ),
                          if (filtered.isEmpty && _searchFailed)
                            Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: Column(
                                children: [
                                  Text(copy.searchLoadError, style: TvUi.body),
                                  const SizedBox(height: 12),
                                  TvButton(
                                    icon: Icons.refresh_rounded,
                                    label: copy.retry,
                                    onTap: () =>
                                        unawaited(_resetSearch(_query)),
                                  ),
                                ],
                              ),
                            )
                          else if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: AppEmpty(
                                title: copy.noTitlesInCategory,
                                icon: Icons.search_off_rounded,
                              ),
                            )
                          else ...[
                            if (_kind == _SearchKindFilter.all &&
                                (moviesSeries.isNotEmpty ||
                                    liveSports.isNotEmpty)) ...[
                              if (moviesSeries.isNotEmpty)
                                ContentRail(
                                  title: '${copy.movies} & ${copy.series}',
                                  trailing:
                                      copy.titlesCount(moviesSeries.length),
                                  items: moviesSeries,
                                  accent: AppColors.cyan,
                                ),
                              if (liveSports.isNotEmpty)
                                ContentRail(
                                  title: '${copy.liveTv} & ${copy.sports}',
                                  trailing:
                                      copy.titlesCount(liveSports.length),
                                  items: liveSports,
                                  accent: AppColors.magenta,
                                ),
                            ] else ...[
                              const SizedBox(height: 12),
                              TvSectionTitle(
                                copy.search,
                                trailing: copy.titlesCount(filtered.length),
                              ),
                              const SizedBox(height: 10),
                              _PosterWrap(
                                items: filtered,
                                includeTop: true,
                              ),
                            ],
                          ],
                          if (_hasMore) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: FocusTile(
                                borderRadius: 12,
                                onTap: () => unawaited(_loadMore()),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  child: _loadingMore
                                      ? AppLoader.inline(size: 28)
                                      : Text(
                                          copy.viewAll,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.cyan,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: TvUi.sectionGap),
                          TvStatusFooter(
                            left:
                                '${AppBrand.name.toUpperCase()} SMART SEARCH ENGINE · CROSS-INDEXED 4K METADATA',
                            right: TvPlatformProfile.pc ? 'Windows PC' : '1080p Living Room V2',
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDiscover extends StatelessWidget {
  const _EmptyDiscover({
    required this.copy,
    required this.discover,
    required this.onChip,
  });

  final AppCopy copy;
  final List<MediaItem> discover;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) {
    final recent = discover.take(6).toList();
    final trending = discover.skip(2).take(8).toList();
    if (recent.isEmpty && trending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Text(copy.searchInSection, style: TvUi.meta),
      );
    }
    return ListView(
      clipBehavior: Clip.none,
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'RECENT SEARCHES',
                  style: TvUi.eyebrow.copyWith(
                    color: Colors.white,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                'Clear',
                style: TextStyle(
                  color: AppColors.cyan.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in recent)
                FocusTile(
                  borderRadius: 20,
                  borderWidth: 2,
                  focusScale: 1.0,
                  onTap: () => onChip(item.displayTitle),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (trending.isNotEmpty) ...[
          Text(
            'TRENDING ON ${AppBrand.name}',
            style: TvUi.eyebrow.copyWith(
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in trending)
                FocusTile(
                  borderRadius: 20,
                  borderWidth: 2,
                  focusScale: 1.0,
                  autofocus: recent.isEmpty,
                  onTap: () => onChip(item.displayTitle),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color: AppColors.magenta,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ContentRail(
            title: copy.neu,
            trailing: copy.titlesCount(trending.length),
            items: trending,
            autofocusFirst: false,
            accent: AppColors.magenta,
          ),
        ],
        const SizedBox(height: TvUi.sectionGap),
        TvStatusFooter(
          left:
              TvPlatformProfile.pc ? '${AppBrand.name.toUpperCase()} SMART SEARCH ENGINE · CROSS-INDEXED 4K METADATA' : '${AppBrand.name.toUpperCase()} SMART SEARCH ENGINE · CROSS-INDEXED 4K METADATA · VOICE REMOTE READY',
          right: TvPlatformProfile.pc ? 'Windows PC' : '1080p Living Room V2',
        ),
      ],
    );
  }
}

class _PosterWrap extends StatelessWidget {
  const _PosterWrap({
    required this.items,
    this.includeTop = true,
  });

  final List<MediaItem> items;
  final bool includeTop;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: TvPoster.railHeightFor() + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          return TvPoster.fromMedia(
            item,
            showProgress: item.progress != null && item.progress! > 0.02,
            autofocus: includeTop && i == 0,
            escapeToSidebar: i == 0,
            onTap: () => openTvMedia(context, item),
          );
        },
      ),
    );
  }
}
