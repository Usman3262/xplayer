import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../core/tv_locale.dart' show tvUiLanguage;
import 'focus_tile.dart';

/// TV portrait card matching mobile [PosterCard] art + footer style,
/// with TV focus ring and play glyph.
///
/// [imageUrl] is usually [MediaItem.posterUrl] (portrait ~2:3). Landscape
/// [MediaItem.backdropUrl] (~16:9) is for heroes and full-bleed backgrounds.
class TvPoster extends StatelessWidget {
  const TvPoster({
    super.key,
    required this.title,
    this.imageUrl,
    this.width = standardWidth,
    this.badge,
    this.subtitle,
    this.altTitle,
    this.matchPercent,
    this.progress,
    this.progressCaption,
    this.rating,
    this.emphasized = false,
    this.autofocus = false,
    this.escapeToSidebar = false,
    this.onTap,
    this.rank,
  });

  /// Standard rail / Continue Watching card from catalog metadata.
  factory TvPoster.fromMedia(
    MediaItem item, {
    Key? key,
    bool autofocus = false,
    bool escapeToSidebar = false,
    VoidCallback? onTap,
    double width = standardWidth,
    bool showProgress = false,
    bool emphasized = false,
    int? rank,
  }) {
    final progress = item.progress;
    final resuming = showProgress && progress != null && progress > 0.02;
    final badge = item.badges.isNotEmpty
        ? item.badges.first
        : (item.isOriginal ? 'VIP' : null);
    return TvPoster(
      key: key,
      title: item.displayTitle,
      imageUrl: item.posterUrl ?? item.backdropUrl,
      subtitle: item.subtitle ??
          (item.genres.isNotEmpty ? item.genres.first : null),
      badge: badge,
      progress: resuming ? progress : null,
      progressCaption: resuming
          // Factory without a context: the TV language is kept in
          // [tvUiLanguage] (the theme flag is never set on TV, so Arabic
          // showed English captions).
          ? (AppCopy.ofLanguage(tvUiLanguage).continueLabel(
                positionSec: item.resumePositionSec,
                title: item.title,
                series: item.kind == MediaKind.series,
                progress: progress,
              ) ??
              item.progressLabel)
          : null,
      // Movies and series only (channels have no rating).
      rating: (item.kind == MediaKind.movie || item.kind == MediaKind.series)
          ? item.rating
          : null,
      emphasized: emphasized || resuming,
      width: width,
      autofocus: autofocus,
      escapeToSidebar: escapeToSidebar,
      onTap: onTap,
      rank: rank,
    );
  }

  /// Aligned with mobile [PosterCard.standardWidth] (+ slight TV bump).
  static const standardWidth = 118.0;

  static const _footerH = PosterCard.footerHeight;

  static const focusBorderWidth = 2.5;

  static double imageHeightFor(double width) =>
      PosterCard.imageHeightFor(width);

  static double cardHeightFor([double width = standardWidth]) =>
      imageHeightFor(width) + _footerH + focusBorderWidth * 2;

  static double railHeightFor([double width = standardWidth]) =>
      cardHeightFor(width) + 12;

  final String title;
  final String? imageUrl;
  final double width;
  final String? badge;
  final String? subtitle;
  final String? altTitle;
  final int? matchPercent;
  final double? progress;
  final String? progressCaption;

  /// Provider rating as sent (scale not stated by the API), shown top-start.
  final double? rating;
  final bool emphasized;
  final bool autofocus;
  final bool escapeToSidebar;
  final VoidCallback? onTap;

  /// Weekly Picks position 1–10 (client 18 Oct TV #8), bottom-right like the
  /// phone's [PosterCard].
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final imgH = imageHeightFor(width);
    return SizedBox(
      width: width,
      height: cardHeightFor(width),
      child: FocusTile(
        autofocus: autofocus,
        escapeToSidebar: escapeToSidebar,
        borderRadius: 12,
        borderWidth: focusBorderWidth,
        focusScale: 1.05,
        onTap: onTap,
        focusedOverlay: IgnorePointer(
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: 0.92),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 30,
              ),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: imgH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(emphasized ? 14 : 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: emphasized
                              ? AppColors.cyan.withValues(alpha: 0.85)
                              : AppColors.border,
                          width: emphasized ? 1.6 : 1,
                        ),
                        borderRadius:
                            BorderRadius.circular(emphasized ? 14 : 12),
                        // No box shadow: the ClipRRect around it cut it off,
                        // so every poster paid a 16-22 px blur on each scroll
                        // frame for nothing (TCL scroll lag, 16 Oct).
                      ),
                      // Whole poster, never cropped (client 16 Oct #2):
                      // provider art is not always 2:3. The same image fills
                      // the frame darkened behind it (one decode, cached).
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RemoteImage(
                            url: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: (width * 2).round(),
                          ),
                          const ColoredBox(color: Color(0xA6000000)),
                          RemoteImage(
                            url: imageUrl,
                            fit: BoxFit.contain,
                            memCacheWidth: (width * 2).round(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (rank != null)
                    // LG numbering (client 4 Nov): bottom-left, white
                    // outline, see-through, sized to the poster as on LG.
                    Positioned(
                      left: width * 0.042,
                      bottom: -width * 0.025,
                      child: RankNumberLg(
                        rank: rank!,
                        fontSize: width * 0.466,
                        strokeWidth: width >= 160 ? 2.2 : 1.6,
                      ),
                    ),
                  // One fixed corner for the rating on every poster; the
                  // catalog badge keeps the opposite corner.
                  if (TvRatingBadge.label(rating) != null)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: TvRatingBadge(rating: rating!),
                    ),
                  if (badge != null)
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: TechBadge(badge!, compact: true),
                    ),
                  // Client 20 Oct I5: minutes on their own line over a dark
                  // scrim, then a full-width bar (same as the phone card).
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xD9000000)],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (progressCaption != null) ...[
                                Text(
                                  progressCaption!,
                                  textDirection: TextDirection.ltr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(blurRadius: 4, color: Colors.black),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress!.clamp(0, 1),
                                  minHeight: emphasized ? 6 : 5,
                                  backgroundColor: Colors.white30,
                                  color: AppColors.cyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: _footerH,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty ||
                        matchPercent != null ||
                        (altTitle ?? '').trim().isNotEmpty)
                      Text(
                        [
                          if ((subtitle ?? '').trim().isNotEmpty)
                            subtitle!.trim(),
                          if (matchPercent case final m?) '$m% Match',
                          if ((altTitle ?? '').trim().isNotEmpty)
                            altTitle!.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Star + number for a poster corner. Shared so every poster formats the
/// rating the same way (one decimal, no "/10": the backend does not say
/// whether a value is 10- or 5-based). Missing, 0 or out-of-range → nothing.
class TvRatingBadge extends StatelessWidget {
  const TvRatingBadge({super.key, required this.rating});

  final double rating;

  /// Display text, or null when there is no usable rating.
  static String? label(double? rating) {
    final r = rating;
    if (r == null || !r.isFinite || r <= 0 || r > 10) return null;
    return r.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final text = label(rating);
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 12, color: AppColors.gold),
            const SizedBox(width: 3),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner art. The catalog has no wide backdrops (backdropUrl is the
/// portrait poster), so `BoxFit.cover` in a wide banner cropped and enlarged
/// it (client 16 Oct #2). Shows the darkened art as the background and the
/// whole poster at its own proportions on the end side.
class TvHeroArt extends StatelessWidget {
  const TvHeroArt({super.key, required this.url, this.posterPadding});

  final String? url;
  /// Unused since the LG banner (kept for callers).
  final EdgeInsetsGeometry? posterPadding;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    // As on LG 6.1.30 (client 7 Nov: "the Android TV banner must look like LG"):
    // the art fills a 16:9 box on the far side of the banner (a TMDB backdrop
    // at its own shape; a poster shows its upper part, like LG's "center 22%"),
    // solid black behind the title, fading into the art. No framed poster card.
    return LayoutBuilder(
      builder: (context, c) {
        final artW = (c.maxHeight * 16 / 9).clamp(0.0, c.maxWidth);
        final solid = c.maxWidth <= 0 ? 0.0 : (1 - artW / c.maxWidth).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: 0,
              width: artW,
              child: RemoteImage(
                url: u,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.56),
                memCacheWidth: 1280,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: const [
                    Colors.black,
                    Colors.black,
                    Color(0x8C000000),
                    Color(0x1A000000),
                    Color(0x00000000),
                  ],
                  stops: [0, solid, (solid + 0.14).clamp(0.0, 1.0), 0.75, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Color(0x00000000)],
                  stops: [0, 0.3],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Frosted dark card used for channel tiles and panels (not poster rails).
class TvGlass extends StatelessWidget {
  const TvGlass({
    super.key,
    required this.child,
    this.radius = 14,
    this.padding = EdgeInsets.zero,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withValues(alpha: 0.10),
            (tint ?? Colors.white).withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
