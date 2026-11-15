import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/nav_loader.dart';

/// Category id in `/browse/:kind/newest`: the newest titles, as in the Home
/// "Recently Added" rows (client 10 Nov, as on TV: See All opened New &
/// Popular, another list).
const catalogNewestCategory = 'newest';

/// Route to the newest list of [kind] with its page [title].
String catalogNewestRoute(MediaKind kind, String title) =>
    '/browse/${kind.name}/$catalogNewestCategory'
    '?title=${Uri.encodeQueryComponent(title)}';

/// Full category grid (mirrors TV [TvViewAllScreen] at `/browse/:kind/:categoryId`).
class CatalogViewAllScreen extends ConsumerStatefulWidget {
  const CatalogViewAllScreen({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.title,
  });

  final MediaKind kind;
  final String categoryId;
  final String title;

  @override
  ConsumerState<CatalogViewAllScreen> createState() =>
      _CatalogViewAllScreenState();
}

class _CatalogViewAllScreenState extends ConsumerState<CatalogViewAllScreen> {
  static const _pageSize = 48;

  final List<MediaItem> _items = [];
  String? _cursor;
  int? _total;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    if (widget.categoryId == catalogNewestCategory) {
      await _loadNewest();
      return;
    }
    try {
      final page = await ref.read(catalogRepositoryProvider).browse(
            kind: widget.kind,
            categoryId: widget.categoryId,
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
    final count = _items.length;

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  if ((_total ?? count) > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      copy.titlesCount(_total ?? count),
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (count == 0 && _loading)
            SliverFillRemaining(
              child: Center(child: AppLoader.inline(size: 36)),
            )
          else if (count == 0)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _error != null ? copy.couldNotLoad : copy.noTitlesInCategory,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: PosterCard.standardWidth /
                      PosterCard.railHeightFor(PosterCard.standardWidth),
                ),
                itemCount: count,
                itemBuilder: (context, i) {
                  // Next page after this frame: the grid is being built now
                  // (setState here crashed: device log 15 Nov).
                  if (i >= count - 4) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_loadMore());
                    });
                  }
                  final item = _items[i];
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
              ),
            ),
          if (count > 0 && _loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(child: AppLoader.inline(size: 28)),
              ),
            ),
        ],
      ),
    );
  }
}
