import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

final _searchQueryProvider = StateProvider<String>((ref) => '');

/// Search. [scope] null = Home / global (every content type); otherwise
/// only that section (client 17 Oct): Movies -> movies, Series -> series,
/// Live TV -> live channels without sports, Sports -> sports channels, and
/// only what the user's package allows.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key, this.scope});

  final MediaKind? scope;

  static MediaKind? scopeFromQuery(String? value) => switch (value) {
        'movie' => MediaKind.movie,
        'series' => MediaKind.series,
        'live' => MediaKind.live,
        'sports' => MediaKind.sports,
        _ => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_searchQueryProvider);
    final trending = ref.watch(trendingProvider);
    final genres = ref.watch(genresProvider);
    final sportsOn = ref.watch(sportsEnabledProvider).valueOrNull ?? false;
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(color: AppColors.textPrimary),
              onChanged: (v) =>
                  ref.read(_searchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: switch (scope) {
                  MediaKind.movie => copy.searchMovies,
                  MediaKind.series => copy.searchSeries,
                  MediaKind.live => copy.searchLive,
                  MediaKind.sports => copy.searchSports,
                  null => copy.searchGlobal(sportsOn: sportsOn),
                },
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
          if (query.trim().isEmpty && scope == null)
            genres.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (gs) {
                final unique =
                    copy.withoutDuplicateCategoryLabels(gs, (name) => name);
                return SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: unique.length.clamp(0, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => CategoryChip(
                      label: copy.catalogCategoryLabel(unique[i]),
                      onTap: () => ref
                          .read(_searchQueryProvider.notifier)
                          .state = unique[i],
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: query.trim().isEmpty && scope != null
                ? const SizedBox.shrink()
                : query.trim().isEmpty
                ? trending.when(
                    loading: () => AppShimmer.posterRail(),
                    error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(trendingProvider),
        ),
                    data: (items) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Trending Now',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...items.map((item) => _ResultTile(item: item)),
                      ],
                    ),
                  )
                : _PagedSearchResults(
                    query: query.trim(),
                    scope: scope,
                    onClear: () =>
                        ref.read(_searchQueryProvider.notifier).state = '',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Cursor-paged search results (backend `meta.nextCursor`).
class _PagedSearchResults extends ConsumerStatefulWidget {
  const _PagedSearchResults({
    required this.query,
    required this.onClear,
    this.scope,
  });

  final String query;
  final MediaKind? scope;
  final VoidCallback onClear;

  @override
  ConsumerState<_PagedSearchResults> createState() =>
      _PagedSearchResultsState();
}

class _PagedSearchResultsState extends ConsumerState<_PagedSearchResults> {
  static const _pageSize = 40;

  final List<MediaItem> _items = [];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;

  /// Newest query wins: an older, slower response is dropped (it used to
  /// land after the newer one, or block the newer load entirely).
  int _gen = 0;
  Set<String>? _sportsIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resetAndLoad());
    });
  }

  @override
  void didUpdateWidget(covariant _PagedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 280), () {
        unawaited(_resetAndLoad());
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    if (!mounted) return;
    _gen++;
    setState(() {
      _loading = false;
      _items.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (!mounted || _loading || !_hasMore) return;
    final gen = _gen;
    final query = widget.query;
    setState(() => _loading = true);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final scope = widget.scope;
      final page = await repo.searchPage(
            query,
            kind: scope,
            cursor: _cursor,
            limit: _pageSize,
          );
      if (!mounted || gen != _gen) return;
      var items = page.items;
      final sportsOn =
          ref.read(sportsEnabledProvider).valueOrNull ?? false;
      if (scope == MediaKind.live || scope == MediaKind.sports || !sportsOn) {
        if (_sportsIds == null) {
          final cats = await repo.getCategories(MediaKind.live);
          if (!mounted || gen != _gen) return;
          _sportsIds = {
            for (final c in cats)
              if (RemoteCatalogRepository.isSportsCategory(c)) c.id,
          };
        }
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
      if (!mounted || gen != _gen) return;
      setState(() {
        final seen = {for (final m in _items) m.id};
        _items.addAll(items.where((m) => seen.add(m.id)));
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  bool _moreQueued = false;

  // Called from the list's item builder: loading starts after this frame,
  // so setState never runs while the list is being built.
  void _loadMoreSoon() {
    if (_moreQueued || _loading || !_hasMore) return;
    _moreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moreQueued = false;
      if (mounted) unawaited(_loadMore());
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    if (_error != null && _items.isEmpty) {
      return AppEmpty(
        title: copy.searchLoadError,
        icon: Icons.wifi_off_rounded,
        actionLabel: copy.retry,
        onAction: () => unawaited(_resetAndLoad()),
      );
    }
    if ((_loading || _gen == 0) && _items.isEmpty) {
      return AppShimmer.posterRail();
    }
    if (_items.isEmpty) {
      return AppEmpty(
        title: copy.searchNoResults(widget.query),
        subtitle: copy.searchNoResultsHint,
        icon: Icons.search_off_rounded,
        actionLabel: 'Clear search',
        onAction: widget.onClear,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          if (_hasMore && !_loading) _loadMoreSoon();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: AppLoader.inline(size: 28)),
          );
        }
        if (i >= _items.length - 4) _loadMoreSoon();
        return _ResultTile(item: _items[i]);
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      tileColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: SizedBox(
        width: 48,
        height: 64,
        child: RemoteImage(
          url: item.posterUrl,
          borderRadius: BorderRadius.circular(8),
          memCacheWidth: 96,
        ),
      ),
      title: Text(item.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [
          item.kind.name.toUpperCase(),
          if (item.genres.isNotEmpty) item.genres.first,
        ].join(' • '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openMediaBrowse(context, item),
    );
  }
}
