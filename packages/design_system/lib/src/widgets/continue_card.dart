import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'remote_image.dart';

/// Continue Watching card, landscape 16:9 for movies and series alike
/// (client 24 Oct). The episode still / movie scene fills the card. Until one
/// exists the poster is cropped to fill too, keeping its upper part, never
/// boxed inside the wide card (client 2 Nov), and a failed scene image falls
/// back to the poster instead of the empty brand card.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.wideImageUrl,
    this.imageIsWide = false,
    this.caption,
    this.progress,
    this.width = 240,
    this.focused = false,
    this.onTap,
    this.scale = 1,
    this.centeredTitle = false,
    this.showTitle = true,
  });

  final String title;

  /// Image from Continue Watching (episode still for series, poster for movies).
  final String? imageUrl;

  /// Landscape artwork (backdrop), preferred when known.
  final String? wideImageUrl;

  /// [imageUrl] is already landscape (an episode still): crop centred.
  final bool imageIsWide;

  /// "S1 E2 · 9 / 31 min", "20 / 109 min".
  final String? caption;
  final double? progress;
  final double width;
  final bool focused;
  final VoidCallback? onTap;
  final double scale;

  /// TV (client 24 Oct): larger title, up to two
  /// lines, with room above and below the line so Arabic marks are not cut.
  final bool centeredTitle;

  /// False for a picture-only thumbnail (Library list: the title is beside it).
  final bool showTitle;

  static double heightFor(double width, {bool centeredTitle = false}) =>
      width * 9 / 16 + (centeredTitle ? 50 : 30);

  @override
  Widget build(BuildContext context) {
    final h = width * 9 / 16;
    final wide = (wideImageUrl ?? '').isNotEmpty;
    final image = RemoteImage(
      url: wide ? wideImageUrl : imageUrl,
      fallbackUrl: wide ? imageUrl : null,
      fit: BoxFit.cover,
      alignment: (wide || imageIsWide) ? Alignment.center : const Alignment(0, -0.4),
      width: width,
      height: h,
    );
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: width,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF111826),
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(
                  color: focused ? Colors.white : AppColors.cyan.withValues(alpha: 0.35),
                  width: focused ? 2.5 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image,
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
                        padding: EdgeInsets.fromLTRB(10 * scale, 18 * scale, 10 * scale, 8 * scale),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if ((caption ?? '').isNotEmpty) ...[
                              Text(
                                caption!,
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5 * scale,
                                  fontWeight: FontWeight.w800,
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                                ),
                              ),
                              SizedBox(height: 5 * scale),
                            ],
                            if (progress != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress!.clamp(0, 1),
                                  minHeight: 4 * scale,
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
            if (showTitle) SizedBox(height: 6 * scale),
            if (!showTitle)
              const SizedBox.shrink()
            else if (centeredTitle)
              SizedBox(
                width: width,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14 * scale,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              )
            else
              SizedBox(
                width: width,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5 * scale, color: AppColors.textPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
