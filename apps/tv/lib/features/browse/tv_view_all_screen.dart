import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../core/tv_media_nav.dart';
import '../../widgets/focus_tile.dart';
import '../../widgets/tv_poster.dart';

/// Category id in `/browse/:kind/all`: every title of that kind.
const tvAllCategory = 'all';

/// Category id in `/browse/:kind/newest`: the newest titles, as in the Home
/// "Recently Added" rows (client 10 Nov: their View All opened New & Popular,
/// another list).
const tvNewestCategory = 'newest';

/// Route to the full, paged list of one category (or [tvAllCategory]).
String tvViewAllRoute(MediaKind kind, String categoryId, String title) =>
    '/browse/${kind.name}/${Uri.encodeComponent(categoryId)}'
    '?title=${Uri.encodeQueryComponent(title)}';

/// View All: every title in one provider category, as a paged grid.
class TvViewAllScreen extends ConsumerStatefulWidget {
  const TvViewAllScreen({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.title,
  });

  final MediaKind kind;
  final String categoryId;
  final String title;

  @override
  ConsumerState<TvViewAllScreen> createState() => _TvViewAllScreenState();
}

class _TvViewAllScreenState extends ConsumerState<TvViewAllScreen> {
  static const _pageSize = 48;

  final List<MediaItem> _items = [];
  String? _cursor;
  int? _total;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  // Client 18 Oct TV #9: search inside this package only.
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<MediaItem>? _results;
  bool _searching = false;
  int _searchGen = 0;

  bool get _canSearch =>
      widget.categoryId != tvAllCategory &&
      widget.categoryId != tvNewestCategory &&
      (widget.kind == MediaKind.movie || widget.kind == MediaKind.series);

  void _onQuery(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      _searchGen++;
      setState(() {
        _query = '';
        _results = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final gen = ++_searchGen;
      setState(() {
        _query = q;
        _searching = true;
      });
      try {
        final page = await ref.read(catalogRepositoryProvider).searchPage(
              q,
              kind: widget.kind,
              categoryId: widget.categoryId,
              limit: 100,
            );
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _results = page.items;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _results = const [];
          _searching = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  bool _moreScheduled = false;

  void _scheduleLoadMore() {
    if (_moreScheduled || _loading || !_hasMore) return;
    _moreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moreScheduled = false;
      if (mounted) unawaited(_loadMore());
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    if (widget.categoryId == tvNewestCategory) {
      await _loadNewest();
      return;
    }
    try {
      final page = await ref.read(catalogRepositoryProvider).browse(
            kind: widget.kind,
            // 'all' = the whole catalog of this kind (home rows, All chip).
            categoryId: widget.categoryId == tvAllCategory
                ? null
                : widget.categoryId,
            cursor: _cursor,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        final seen = {for (final m in _items) m.id};
        _items.addAll(page.items.where((m) => seen.add(m.id)));
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _total = page.total ?? _total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The same newest-first list the Recently Added row shows, in one page.
  Future<void> _loadNewest() async {
    final catalog = ref.read(catalogRepositoryProvider);
    try {
      final items = widget.kind == MediaKind.series
          ? await catalog.getNewSeries()
          : await catalog.getNewReleases();
      if (!mounted) return;
      setState(() {
        final seen = <String>{};
        _items
          ..clear()
          ..addAll(items.where((m) => seen.add(m.id)));
        _hasMore = false;
        _total = _items.length;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final width = MediaQuery.sizeOf(context).width;
    const gap = 14.0;
    const side = 36.0;
    final perRow =
        ((width - side * 2 + gap) / (TvPoster.standardWidth + gap))
            .floor()
            .clamp(2, 8);
    final searching = _query.isNotEmpty;
    final shown = searching ? (_results ?? const <MediaItem>[]) : _items;
    final count = shown.length;
    final busy = searching ? _searching : _loading;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 20, side, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    FocusTile(
                      borderRadius: 24,
                      onTap: () => context.pop(),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: AppBackIcon(
                          style: AppBackIconStyle.material,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    if ((searching ? count : (_total ?? count)) > 0)
                      Text(
                        copy.titlesCount(searching ? count : (_total ?? count)),
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_canSearch)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(side, 0, side, 8),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                    child: TextField(
                      controller: _search,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: copy.searchInPackage(widget.title),
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.cyan,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: _onQuery,
                    ),
                  ),
                ),
              ),
            if (count == 0 && busy)
              SliverFillRemaining(
                child: Center(child: AppLoader.inline(size: 36)),
              )
            else if (count == 0)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    searching
                        ? copy.noResultsFor(_query)
                        : _error != null
                        ? '$_error'
                        : copy.noTitlesInCategory,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(side, 8, side, 40),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: perRow,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: TvPoster.standardWidth /
                        TvPoster.cardHeightFor(),
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    // Near the end: fetch the next page — after this frame,
                    // never from inside build (it called setState during
                    // build, so the next pages could fail to load).
                    if (!searching && i >= count - perRow * 2) {
                      _scheduleLoadMore();
                    }
                    final m = shown[i];
                    return Align(
                      alignment: Alignment.topCenter,
                      child: TvPoster.fromMedia(
                        m,
                        autofocus: i == 0,
                        onTap: () => openTvMedia(context, m),
                      ),
                    );
                  },
                ),
              ),
            if (count > 0 && busy)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Center(child: AppLoader.inline(size: 28)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
