import 'dart:async';

import 'package:data/data.dart' show isProviderAdOrHeaderChannel;
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_controller.dart';
import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../core/ui_sound.dart';

/// One live package (client 21 Oct reference, A17): back + package name +
/// "N channels", "Search in <package>", then a numbered channel list —
/// number, logo, name with the package under it, heart, play.
class LiveCategoryScreen extends ConsumerStatefulWidget {
  const LiveCategoryScreen({
    super.key,
    required this.categoryId,
    required this.title,
    this.items,
  });

  final String categoryId;
  final String title;

  /// Channels to show instead of loading [categoryId] (My Favorites,
  /// client 23 Oct round 3 #10: tapping it opened nothing).
  final List<MediaItem>? items;

  @override
  ConsumerState<LiveCategoryScreen> createState() => _LiveCategoryScreenState();
}

class _LiveCategoryScreenState extends ConsumerState<LiveCategoryScreen> {
  static const _pageSize = 100;

  final List<MediaItem> _items = [];
  final _search = TextEditingController();
  String _query = '';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Whole package (packages hold up to a few hundred channels), so search
  /// and the count cover every channel.
  Future<void> _loadAll() async {
    final given = widget.items;
    if (given != null) {
      setState(() {
        _items.addAll(given);
        _loading = false;
      });
      return;
    }
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? cursor;
      final seen = <String>{};
      for (var guard = 0; guard < 10; guard++) {
        final page = await repo.browse(
          kind: MediaKind.live,
          categoryId: widget.categoryId,
          cursor: cursor,
          limit: _pageSize,
        );
        if (!mounted) return;
        setState(() {
          _items.addAll([
            for (final m in page.items)
              if (!isProviderAdOrHeaderChannel(m.title) && seen.add(m.id)) m,
          ]);
          _loading = page.hasMore;
        });
        if (!page.hasMore || page.nextCursor == null) break;
        cursor = page.nextCursor;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<MediaItem> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return [
      for (final m in _items)
        if (m.displayTitle.toLowerCase().contains(q)) m,
    ];
  }

  void _play(MediaItem item) {
    playUiTap(ref);
    openMediaBrowse(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final shown = _shown;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Material(
                    color: AppColors.surfaceElevated,
                    shape: CircleBorder(
                      side: BorderSide(color: AppColors.border),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppColors.cyan,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _items.isEmpty && _loading
                              ? '${copy.loading}…'
                              : copy.channelsCount(_items.length),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '${copy.searchInPackage(widget.title)}…',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            Expanded(child: _list(copy, shown)),
          ],
        ),
      ),
    );
  }

  Widget _list(AppCopy copy, List<MediaItem> shown) {
    if (_items.isEmpty && _loading) {
      return Center(child: AppLoader.inline(size: 36));
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _error != null ? copy.couldNotLoad : copy.noLiveChannels,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Text(
          copy.noTitlesInCategory,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: shown.length + (_loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= shown.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: AppLoader.inline(size: 24)),
          );
        }
        final item = shown[i];
        return _ChannelRow(
          number: _items.indexOf(item) + 1,
          item: item,
          packageName: widget.title,
          onPlay: () => _play(item),
        );
      },
    );
  }
}

class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({
    required this.number,
    required this.item,
    required this.packageName,
    required this.onPlay,
  });

  final int number;
  final MediaItem item;
  final String packageName;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final saved = lib.isFavoriteChannel(item.id);
    return InkWell(
      onTap: onPlay,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$number',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: (item.posterUrl ?? item.backdropUrl) == null
                  ? Icon(Icons.live_tv_rounded,
                      color: AppColors.textSecondary)
                  : Padding(
                      padding: const EdgeInsets.all(4),
                      child: RemoteImage(
                        url: item.posterUrl ?? item.backdropUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: saved
                  ? AppCopy.ofLanguage(ref.read(sessionProvider).language).favorited
                  : AppCopy.ofLanguage(ref.read(sessionProvider).language).favorite,
              onPressed: () => _toggleFavourite(ref, lib, saved),
              icon: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved ? AppColors.magenta : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: AppColors.cyan,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPlay,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.black, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same rule as the package rows: server Favourites, shared with the TV.
  void _toggleFavourite(WidgetRef ref, LibraryState lib, bool saved) {
    playUiTap(ref);
    final n = ref.read(libraryProvider.notifier);
    if (saved) {
      if (lib.myList.any((e) => e.id == item.id)) {
        n.toggleMyList(item.id, item: item);
      }
      if (lib.ratingFor(item.id) == 1 || lib.liked.any((e) => e.id == item.id)) {
        n.setRating(item.id, 0, item: item);
      }
    } else {
      n.setRating(item.id, 1, item: item);
    }
  }
}
