import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/display_name.dart';
import 'remote_image.dart';
import 'tech_badge.dart';

/// Standard portrait poster card — fixed **2:3** art, [BoxFit.contain].
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.rating,
    this.matchPercent,
    this.rank,
    this.width = standardWidth,
    this.seed = 0,
    this.imageUrl,
    this.progress,
    /// Task #143 #10: e.g. "42 min" beside the progress bar.
    this.progressCaption,
    /// Emphasize Continue Watching vs normal posters.
    this.emphasized = false,
    this.onTap,
  });

  /// Mobile rail / grid standard width.
  static const standardWidth = 118.0;

  /// Portrait poster ratio (width : height = 2 : 3).
  static const portraitRatio = 2 / 3;

  static const footerHeight = 40.0;

  static double imageHeightFor(double width) => width / portraitRatio;

  static double railHeightFor([double width = standardWidth]) =>
      imageHeightFor(width) + footerHeight;

  final String title;
  final String? subtitle;
  final List<String> badges;
  final double? rating;
  final int? matchPercent;
  final int? rank;
  final double width;
  final int seed;
  final String? imageUrl;
  final double? progress;
  final String? progressCaption;
  final bool emphasized;
  final VoidCallback? onTap;

  double get _imageH => imageHeightFor(width);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: _imageH + footerHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: _imageH,
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
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan
                                .withValues(alpha: emphasized ? 0.32 : 0.18),
                            blurRadius: emphasized ? 22 : 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: RemoteImage(
                        url: imageUrl,
                        fit: BoxFit.contain,
                        // Portrait ~2:3 server posterUrl — contain, no crop.
                      ),
                    ),
                  ),
                  // Weekly Picks number (client 17 Oct #3): bottom-right of
                  // the poster in both languages, one size, in a small
                  // badge so it reads on any artwork.
                  if (rank != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 26),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.cyan.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          '$rank',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  if (badges.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: TechBadge(badges.first, compact: true),
                    ),
                  // Client 23 Oct round 3 #11: the rating on the poster, in
                  // the TV design and corner (top-left; the badge keeps the
                  // other corner).
                  if (PosterRatingBadge.label(rating) != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: PosterRatingBadge(rating: rating!),
                    ),
                  // Client 20 Oct I5: minutes on their own line over a dark
                  // scrim, then a full-width bar, so both read at a glance.
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
                          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (progressCaption != null) ...[
                                Text(
                                  progressCaption!,
                                  // "35:59 / 1:33:30" read backwards in Arabic.
                                  textDirection: TextDirection.ltr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: emphasized ? 11.5 : 10,
                                    fontWeight: FontWeight.w800,
                                    shadows: const [
                                      Shadow(blurRadius: 4, color: Colors.black),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 5),
                              ],
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress!.clamp(0, 1),
                                  minHeight: emphasized ? 5 : 4,
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
              height: footerHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cleanDisplayName(title),
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
                    if (subtitle != null || matchPercent != null)
                      Text(
                        [
                          if (subtitle case final s?) cleanDisplayName(s),
                          if (matchPercent case final m?) '$m% Match',
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

/// Rating chip on a poster: dark pill, gold star, one decimal (same as the
/// TV poster badge).
class PosterRatingBadge extends StatelessWidget {
  const PosterRatingBadge({super.key, required this.rating});

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
