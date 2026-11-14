import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_controller.dart';
import '../../core/media_nav.dart';
import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../home/home_screen.dart' show confirmRemoveContinue;

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

/// Continue Watching / Watch later / Remind Me / History — one hub.
class LibraryHubScreen extends ConsumerStatefulWidget {
  const LibraryHubScreen({super.key, this.initialTab = LibraryTab.continueWatching});

  final LibraryTab initialTab;

  @override
  ConsumerState<LibraryHubScreen> createState() => _LibraryHubScreenState();
}

class _LibraryHubScreenState extends ConsumerState<LibraryHubScreen> {
  late LibraryTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  void _open(MediaItem item) {
    // Continue Watching / in-progress → resume in player (P1.9).
    // Otherwise details-first (Task #143 #12).
    final progress = item.progress;
    if (_tab == LibraryTab.continueWatching ||
        (progress != null && progress > 0.02)) {
      openMediaPlayback(context, item);
    } else {
      openMediaBrowse(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final cw = ref.watch(continueWatchingProvider);
    final myList = ref.watch(myListItemsProvider);
    final reminders = ref.watch(libraryProvider).reminders;
    final historyAsync = ref.watch(historyProvider);

    final items = switch (_tab) {
      LibraryTab.continueWatching => cw,
      LibraryTab.watchLater => myList,
      LibraryTab.reminders => reminders,
      LibraryTab.history => historyAsync.valueOrNull ?? const <MediaItem>[],
    };

    final empty = switch (_tab) {
      LibraryTab.continueWatching => copy.continueEmpty,
      LibraryTab.watchLater => copy.listEmptyTitle,
      LibraryTab.reminders => copy.remindersEmpty,
      LibraryTab.history => copy.historyEmpty,
    };

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: RefreshIndicator(
        color: AppColors.cyan,
        onRefresh: () async {
          await ref.read(libraryProvider.notifier).syncFromRemote();
          ref.invalidate(historyProvider);
          await ref.read(historyProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.libraryHub,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.libraryHubHint,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          CategoryChip(
                            label: copy.continueWatching,
                            selected: _tab == LibraryTab.continueWatching,
                            onTap: () => setState(
                              () => _tab = LibraryTab.continueWatching,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CategoryChip(
                            label: copy.watchLater,
                            selected: _tab == LibraryTab.watchLater,
                            onTap: () =>
                                setState(() => _tab = LibraryTab.watchLater),
                          ),
                          const SizedBox(width: 8),
                          CategoryChip(
                            label: copy.remindMe,
                            selected: _tab == LibraryTab.reminders,
                            onTap: () =>
                                setState(() => _tab = LibraryTab.reminders),
                          ),
                          const SizedBox(width: 8),
                          CategoryChip(
                            label: copy.history,
                            selected: _tab == LibraryTab.history,
                            onTap: () =>
                                setState(() => _tab = LibraryTab.history),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_tab == LibraryTab.history && historyAsync.isLoading)
              SliverToBoxAdapter(child: AppShimmer.twoColumnCards())
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      empty,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final item = items[i];
                      final showProgress = _tab == LibraryTab.continueWatching &&
                          item.progress != null;
                      final row = Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NeonTap(
                          // Task #143 #12: title tap → details first (Play from there).
                          onTap: () => _open(item),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                if (_tab == LibraryTab.continueWatching)
                                  // Client 25 Oct: landscape, as on Home.
                                  _ContinueThumb(item: item)
                                else
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 72,
                                      height: 100,
                                      child: RemoteImage(
                                        url: item.posterUrl,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.displayTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if ((copy.continueLabel(positionSec: item.resumePositionSec, title: item.title, series: item.kind == MediaKind.series, progress: item.progress) ?? item.progressLabel) != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          (copy.continueLabel(positionSec: item.resumePositionSec, title: item.title, series: item.kind == MediaKind.series, progress: item.progress) ?? item.progressLabel)!,
                                          textDirection: TextDirection.ltr,
                                          style: TextStyle(
                                            color: AppColors.cyan,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (showProgress) ...[
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          child: LinearProgressIndicator(
                                            value: item.progress,
                                            minHeight: 4,
                                            backgroundColor: Colors.white24,
                                            color: AppColors.cyan,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  _tab == LibraryTab.continueWatching
                                      ? Icons.play_circle_fill_rounded
                                      : Icons.chevron_right_rounded,
                                  color: AppColors.cyan,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (_tab != LibraryTab.continueWatching) return row;
                      // Remove from Continue Watching (client 12 Nov): swipe
                      // the row sideways or long-press it; both ask first.
                      return Dismissible(
                        key: ValueKey('cw-${item.id}-${item.seriesId ?? ''}'),
                        direction: DismissDirection.horizontal,
                        background: const _RemoveSwipeBackground(),
                        secondaryBackground:
                            const _RemoveSwipeBackground(end: true),
                        // The library drops the row itself once removed.
                        confirmDismiss: (_) async {
                          await confirmRemoveContinue(context, ref, item);
                          return false;
                        },
                        child: GestureDetector(
                          onLongPress: () =>
                              confirmRemoveContinue(context, ref, item),
                          child: row,
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 Continue Watching picture: episode still / movie backdrop, or the
/// poster whole over a blurred fill ([ContinueCard]).
class _ContinueThumb extends ConsumerWidget {
  const _ContinueThumb({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = item.kind == MediaKind.series || item.seriesId != null;
    // Episode still / movie scene from Continue Watching (looked up by the
    // library), else the movie's backdrop; TMDB first (no provider logo).
    final backdrop = pickCleanArt([
      item.backdropUrl,
      if (!series) ref.watch(vodInfoProvider(item.id)).valueOrNull?.backdropUrl,
    ]);
    return ContinueCard(
      width: 128,
      showTitle: false,
      title: item.displayTitle,
      imageUrl: item.posterUrl,
      wideImageUrl: backdrop,
    );
  }
}

/// Red strip with a bin behind a Continue Watching row being swiped.
class _RemoveSwipeBackground extends StatelessWidget {
  const _RemoveSwipeBackground({this.end = false});
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: end
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    );
  }
}
