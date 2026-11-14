import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/library_controller.dart' show libraryProvider;
import '../core/providers.dart';
import '../core/tv_live_zap.dart';
import '../core/tv_locale.dart';
import '../core/tv_media_nav.dart';
import 'focus_tile.dart';
import 'tv_poster.dart';
import 'tv_ui.dart';

/// Horizontal content rail using portrait ~2:3 poster cards.
class ContentRail extends StatelessWidget {
  const ContentRail({
    super.key,
    required this.title,
    required this.items,
    this.trailing,
    this.arabicTitle,
    this.accent,
    this.autofocusFirst = false,

    /// When true (Continue Watching), taps open the player with resume.
    this.preferPlay = false,
    this.onViewAll,
    this.viewAllLabel,
    this.ranked = false,
    this.maxItems,
  });

  final String title;

  /// Optional count / hint on the end (Figma: "48 Titles").
  final String? trailing;
  final String? arabicTitle;
  final Color? accent;
  final List<MediaItem> items;
  final bool autofocusFirst;
  final bool preferPlay;
  final VoidCallback? onViewAll;
  final String? viewAllLabel;

  /// Numbers the cards 1–10 (Weekly Picks).
  final bool ranked;

  /// Cards shown; null = one catalog page. My List passes the full count so
  /// "40 Titles" really lists 40.
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    // Cap every rail to one catalog page (10).
    final page = items.take(maxItems ?? CatalogPaging.pageSize).toList();
    final endLabel = viewAllLabel ?? trailing;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 8, 10),
            child: TvSectionTitle(
              title,
              trailing: endLabel,
              arabicTitle: arabicTitle,
              accent: accent,
              onTap: onViewAll,
            ),
          ),
          SizedBox(
            height: TvPoster.railHeightFor(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              itemCount: page.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final item = page[i];
                final showProgress =
                    preferPlay ||
                    (item.progress != null && item.progress! > 0.02);
                final poster = TvPoster.fromMedia(
                  item,
                  showProgress: showProgress,
                  autofocus: autofocusFirst && i == 0,
                  escapeToSidebar: i == 0,
                  onTap: () {
                    if (item.kind == MediaKind.live || item.isLive) {
                      ProviderScope.containerOf(
                        context,
                        listen: false,
                      ).read(liveZapProvider.notifier).state = LiveZapList([
                        for (final c in page)
                          if (c.kind == MediaKind.live || c.isLive) c,
                      ], title: title);
                    }
                    openTvMedia(context, item, preferPlay: preferPlay);
                  },
                );
                // LG numbering on every ranked row (client 4 Nov).
                return ranked
                    ? RankedRailItem(rank: i + 1, child: poster)
                    : poster;
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue Watching on TV (client 24 Oct): landscape cards like the phone,
/// the episode still / backdrop filling the card; OK resumes playback.
/// Client 25 Oct: every Continue Watching row uses it (Home, Movies, Series,
/// Kids, My APP, Library), never portrait posters.
class ContinueRail extends ConsumerWidget {
  const ContinueRail({
    super.key,
    required this.title,
    required this.items,
    this.accent,
    this.onViewAll,
    this.viewAllLabel,
    this.autofocusFirst = false,
    this.showHeader = true,
    this.maxItems,
  });

  final String title;
  final List<MediaItem> items;
  final Color? accent;
  final VoidCallback? onViewAll;
  final String? viewAllLabel;
  final bool autofocusFirst;

  /// False where the screen draws its own section header (My APP).
  final bool showHeader;

  /// Cards shown; null = one catalog page.
  final int? maxItems;

  // Client 2 Nov: smaller Continue Watching cards (was 300).
  // LG size (client 5 Nov: Continue Watching cards as on LG): 336 px on the
  // 1920 px LG screen = 168 on the 960-point Android TV screen.
  static const _w = 168.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final page = items.take(maxItems ?? CatalogPaging.pageSize).toList();
    // The TV language (the theme flag used before is never set on TV, so
    // Arabic showed English captions and dialog).
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    // One key per card, unique even if two rows share an id.
    final seen = <String, int>{};
    final keys = [
      for (final m in page)
        'cw-${m.id}#${seen.update(m.id, (n) => n + 1, ifAbsent: () => 0)}',
    ];
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 8, 10),
              child: TvSectionTitle(
                title,
                trailing: viewAllLabel,
                accent: accent,
                onTap: onViewAll,
              ),
            ),
          SizedBox(
            height: ContinueCard.heightFor(_w, centeredTitle: true) + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              itemCount: page.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final item = page[i];
                final series =
                    item.kind == MediaKind.series || item.seriesId != null;
                // Episode still / movie scene from Continue Watching (looked up by the
                // library), else the movie's backdrop; TMDB first (no provider logo).
                final backdrop = pickCleanArt([
                  item.backdropUrl,
                  if (!series)
                    ref
                        .watch(vodInfoProvider(item.id))
                        .valueOrNull
                        ?.backdropUrl,
                ]);
                return FocusTile(
                  // Keyed by title: after a removal the focus stays on the
                  // card it moved to, not on the slot (client 10 Nov).
                  key: ValueKey(keys[i]),
                  borderRadius: 14,
                  escapeToSidebar: i == 0,
                  autofocus: autofocusFirst && i == 0,
                  // Red key (as on LG) or Menu key: remove from Continue
                  // Watching (client 10 Nov). Holding OK does the same
                  // (client 12 Nov: most remotes have neither key); a
                  // short OK still opens the title.
                  onLongSelect: () =>
                      _confirmRemoveContinue(context, ref, item, copy),
                  onKeyFirst: (e) {
                    if (e is! KeyDownEvent ||
                        (e.logicalKey != LogicalKeyboardKey.colorF0Red &&
                            e.logicalKey != LogicalKeyboardKey.contextMenu)) {
                      return KeyEventResult.ignored;
                    }
                    _confirmRemoveContinue(context, ref, item, copy);
                    return KeyEventResult.handled;
                  },
                  focusedOverlay: _RemoveHint(label: copy.holdOkToRemove),
                  onTap: () => openTvMedia(context, item, preferPlay: true),
                  child: SizedBox(
                    width: _w,
                    height: ContinueCard.heightFor(_w, centeredTitle: true),
                    child: ContinueCard(
                      width: _w,
                      centeredTitle: true,
                      title: item.displayTitle,
                      imageUrl: item.posterUrl,
                      wideImageUrl: backdrop,
                      caption:
                          copy.continueLabel(
                            positionSec: item.resumePositionSec,
                            title: item.title,
                            series: series,
                            progress: item.progress,
                          ) ??
                          item.progressLabel,
                      progress: item.progress,
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
}

/// "Hold OK to remove" on the focused card, top corner, as on LG.
class _RemoveHint extends StatelessWidget {
  const _RemoveHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 6,
      start: 6,
      end: 6,
      child: IgnorePointer(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _removeDialogOpen = false;

/// "Remove from Continue Watching?" for [item]; on Remove, focus moves to the
/// next card first (as on LG), then the card goes.
Future<void> _confirmRemoveContinue(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  AppCopy copy,
) async {
  if (_removeDialogOpen) return;
  _removeDialogOpen = true;
  bool? remove;
  try {
    remove = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1F2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.removeFromContinue,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TvButton(
                        autofocus: true,
                        label: copy.cancel,
                        onTap: () => Navigator.of(ctx).pop(false),
                      ),
                      const SizedBox(width: TvUi.buttonGap),
                      TvButton(
                        primary: true,
                        icon: Icons.delete_outline_rounded,
                        label: copy.remove,
                        onTap: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } finally {
    _removeDialogOpen = false;
  }
  if (remove != true || !context.mounted) return;
  // The dialog gives focus back to the card; move it on before the card goes.
  await WidgetsBinding.instance.endOfFrame;
  final node = FocusManager.instance.primaryFocus;
  final rtl =
      context.mounted && Directionality.maybeOf(context) == TextDirection.rtl;
  final forward = rtl ? TraversalDirection.left : TraversalDirection.right;
  final back = rtl ? TraversalDirection.right : TraversalDirection.left;
  if (!tvMoveFocus(node, forward) && !tvMoveFocus(node, back)) {
    if (!tvMoveFocus(node, TraversalDirection.down)) {
      tvMoveFocus(node, TraversalDirection.up);
    }
  }
  final ok = await ref.read(libraryProvider.notifier).removeFromContinue(item);
  if (!ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(copy.removeFromContinueFailed)));
  }
}
