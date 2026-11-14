import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_controller.dart';
import '../../core/providers.dart';
import '../../core/tv_locale.dart';
import '../../widgets/content_rail.dart';
import '../../widgets/tv_genre_chip_bar.dart';
import '../../widgets/tv_page_header.dart';
import '../../widgets/tv_ui.dart';

enum LibraryTab { continueWatching, watchLater, reminders, history }

LibraryTab libraryTabFromQuery(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'list':
    case 'mylist':
    case 'watchlater':
    case 'watch-later':
      return LibraryTab.watchLater;
    case 'remind':
    case 'reminders':
      return LibraryTab.reminders;
    case 'history':
      return LibraryTab.history;
    case 'continue':
    case 'cw':
    default:
      return LibraryTab.continueWatching;
  }
}

/// My List V2 — Continue Watching / Watch later / Remind Me / History with
/// sectioned horizontal rails (Figma v2TV3).
class TvLibraryHubScreen extends ConsumerStatefulWidget {
  const TvLibraryHubScreen({
    super.key,
    this.initialTab = LibraryTab.continueWatching,
  });

  final LibraryTab initialTab;

  @override
  ConsumerState<TvLibraryHubScreen> createState() => _TvLibraryHubScreenState();
}

class _TvLibraryHubScreenState extends ConsumerState<TvLibraryHubScreen> {
  late LibraryTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant TvLibraryHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
    }
  }

  Future<void> _refresh() async {
    await ref.read(libraryProvider.notifier).syncFromRemote();
    ref.invalidate(historyProvider);
    await ref.read(historyProvider.future);
  }

  List<_KindRail> _railsFor(List<MediaItem> items, AppCopy copy) {
    final movies = <MediaItem>[];
    final series = <MediaItem>[];
    final live = <MediaItem>[];
    final sports = <MediaItem>[];
    for (final m in items) {
      switch (m.kind) {
        case MediaKind.movie:
          movies.add(m);
        case MediaKind.series:
          series.add(m);
        case MediaKind.live:
          live.add(m);
        case MediaKind.sports:
          sports.add(m);
      }
    }
    final ar = AppCopy.ofLanguage('ar');
    return [
      if (movies.isNotEmpty)
        _KindRail(
          title: copy.movies,
          arabicTitle: ar.movies,
          accent: AppColors.cyan,
          items: movies,
        ),
      if (series.isNotEmpty)
        _KindRail(
          title: copy.series,
          arabicTitle: ar.series,
          accent: AppColors.magenta,
          items: series,
        ),
      if (live.isNotEmpty)
        _KindRail(
          title: copy.liveTv,
          arabicTitle: ar.liveTv,
          accent: const Color(0xFFFF4D4D),
          items: live,
        ),
      if (sports.isNotEmpty)
        _KindRail(
          title: copy.sports,
          arabicTitle: ar.sports,
          accent: const Color(0xFFFF8A3D),
          items: sports,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final ar = AppCopy.ofLanguage('ar');
    final cw = ref.watch(continueWatchingProvider);
    final myList = ref.watch(myListItemsProvider);
    final reminders = ref.watch(libraryProvider).reminders;
    final historyAsync = ref.watch(historyProvider);
    final history = historyAsync.valueOrNull ?? const <MediaItem>[];

    final items = switch (_tab) {
      LibraryTab.continueWatching => cw,
      LibraryTab.watchLater => myList,
      LibraryTab.reminders => reminders,
      LibraryTab.history => history,
    };

    final empty = switch (_tab) {
      LibraryTab.continueWatching => copy.continueEmpty,
      LibraryTab.watchLater => copy.listEmptyTitle,
      LibraryTab.reminders => copy.remindersEmpty,
      LibraryTab.history => copy.historyEmpty,
    };

    final totalSaved = cw.length + myList.length + reminders.length;
    final tabLabels = [
      '${copy.continueWatching} (${cw.length})',
      '${copy.watchLater} (${myList.length})',
      '${copy.remindMe} (${reminders.length})',
      '${copy.history} (${history.length})',
    ];
    final tabIndex = LibraryTab.values.indexOf(_tab);
    final preferPlay = _tab == LibraryTab.continueWatching;
    final kindRails = _railsFor(items, copy);
    final useKindRails = kindRails.length > 1;
    final showEmpty = switch (_tab) {
      LibraryTab.continueWatching => cw.isEmpty && myList.isEmpty,
      _ => items.isEmpty,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvPageHeader(
            title: copy.myList,
            arabicTitle: ar.myList,
            titleChip: copy.titlesCount(totalSaved),
            subtitle: copy.libraryHubHint,
            trailing: TvButton(
              icon: Icons.refresh_rounded,
              label: copy.refresh,
              onTap: _refresh,
              escapeUpToSidebar: true,
            ),
          ),
          TvGenreChipBar(
            labels: tabLabels,
            selectedIndex: tabIndex.clamp(0, tabLabels.length - 1),
            onSelected: (i) {
              setState(() => _tab = LibraryTab.values[i]);
              if (LibraryTab.values[i] == LibraryTab.history) {
                ref.invalidate(historyProvider);
              }
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: showEmpty
                ? AppEmpty(
                    title: empty,
                    icon: Icons.bookmark_add_outlined,
                    actionLabel: 'Refresh',
                    onAction: _refresh,
                  )
                : ClipRect(
                    // Rows scrolled up must not draw over the header and tabs;
                    // focus glow may still spill left / right / down.
                    clipper: const _ClipTopOnly(),
                    child: ListView(
                      clipBehavior: Clip.none,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                      children: [
                        if (_tab == LibraryTab.continueWatching) ...[
                          if (cw.isNotEmpty)
                            ContinueRail(
                              title: copy.continueWatching,
                              viewAllLabel: copy.titlesCount(cw.length),
                              items: cw,
                              maxItems: cw.length,
                              autofocusFirst: true,
                              accent: AppColors.cyan,
                            ),
                          if (myList.isNotEmpty)
                            ContentRail(
                              title: copy.myList,
                              arabicTitle: ar.myList,
                              trailing: copy.titlesCount(myList.length),
                              items: myList,
                              maxItems: myList.length,
                              accent: AppColors.magenta,
                              autofocusFirst: cw.isEmpty,
                            ),
                        ] else if (useKindRails)
                          for (var i = 0; i < kindRails.length; i++)
                            ContentRail(
                              title: kindRails[i].title,
                              arabicTitle: kindRails[i].arabicTitle,
                              trailing: copy.titlesCount(
                                kindRails[i].items.length,
                              ),
                              items: kindRails[i].items,
                              maxItems: kindRails[i].items.length,
                              accent: kindRails[i].accent,
                              preferPlay: preferPlay,
                              autofocusFirst: i == 0,
                            )
                        else
                          ContentRail(
                            title: switch (_tab) {
                              LibraryTab.watchLater => copy.myList,
                              LibraryTab.reminders => copy.reminders,
                              LibraryTab.history => copy.history,
                              LibraryTab.continueWatching =>
                                copy.continueWatching,
                            },
                            trailing: copy.titlesCount(items.length),
                            items: items,
                            maxItems: items.length,
                            preferPlay: preferPlay,
                            autofocusFirst: true,
                            accent: switch (_tab) {
                              LibraryTab.continueWatching => AppColors.cyan,
                              LibraryTab.watchLater => AppColors.magenta,
                              LibraryTab.reminders => const Color(0xFFFFB020),
                              LibraryTab.history => AppColors.cyan,
                            },
                          ),
                        const SizedBox(height: TvUi.sectionGap),
                        TvStatusFooter(
                          left: TvPlatformProfile.pc ? '${AppBrand.name.toUpperCase()} FOR WINDOWS' : '${AppBrand.name.toUpperCase()} LIVING ROOM EXPERIENCE',
                          right: 'My List Synced',
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KindRail {
  const _KindRail({
    required this.title,
    required this.arabicTitle,
    required this.accent,
    required this.items,
  });
  final String title;
  final String arabicTitle;
  final Color accent;
  final List<MediaItem> items;
}

class _ClipTopOnly extends CustomClipper<Rect> {
  const _ClipTopOnly();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-400, 0, size.width + 400, size.height + 400);

  @override
  bool shouldReclip(covariant _ClipTopOnly oldClipper) => false;
}
