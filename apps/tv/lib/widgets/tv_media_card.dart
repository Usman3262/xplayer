import 'package:design_system/design_system.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import 'focus_tile.dart';
import 'tv_poster.dart';
import 'tv_ui.dart';

/// Screenshot-standard landscape title card (Continue Watching / rails).
///
/// 16:9 art, RESUME / tech pills, cyan focus play glyph, bottom title meta,
/// progress strip. Used as the default TV rail card across the app.
///
/// Prefers [MediaItem.backdropUrl] (landscape ~16:9); [MediaItem.posterUrl]
/// is portrait ~2:3 when no backdrop is available.
class TvLandscapeCard extends StatelessWidget {
  const TvLandscapeCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.episodeLabel,
    this.timeLeftLabel,
    this.badges = const [],
    this.progress,
    this.resume = false,
    this.vip = false,
    this.width = standardWidth,
    this.autofocus = false,
    this.escapeToSidebar = false,
    this.onTap,
  });

  static const standardWidth = 292.0;
  static const focusBorderWidth = 2.5;
  static const radius = 14.0;

  static double imageHeightFor([double width = standardWidth]) =>
      width * 9 / 16;

  static double cardHeightFor([double width = standardWidth]) =>
      imageHeightFor(width) + focusBorderWidth * 2;

  static double railHeightFor([double width = standardWidth]) =>
      cardHeightFor(width) + 12;

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final String? episodeLabel;
  final String? timeLeftLabel;
  final List<String> badges;
  final double? progress;
  final bool resume;
  final bool vip;
  final double width;
  final bool autofocus;
  final bool escapeToSidebar;
  final VoidCallback? onTap;

  factory TvLandscapeCard.fromMedia(
    MediaItem item, {
    Key? key,
    bool preferPlay = false,
    bool autofocus = false,
    bool escapeToSidebar = false,
    VoidCallback? onTap,
    double width = standardWidth,
  }) {
    final progress = item.progress;
    final resuming = preferPlay && progress != null && progress > 0.02;
    final tech = <String>[
      for (final b in item.badges)
        if (!_isVipBadge(b) && !_isResumeBadge(b)) b,
    ].take(2).toList();
    return TvLandscapeCard(
      key: key,
      title: item.displayTitle,
      imageUrl: item.backdropUrl ?? item.posterUrl,
      subtitle: item.subtitle ??
          (item.genres.isNotEmpty ? item.genres.first : null),
      episodeLabel: item.kind == MediaKind.series
          ? (item.progressLabel ?? item.durationLabel)
          : item.durationLabel,
      timeLeftLabel: resuming
          ? (item.progressLabel ?? _timeLeftGuess(progress, item.durationLabel))
          : null,
      badges: tech,
      progress: resuming ? progress : progress,
      resume: resuming,
      vip: item.badges.any(_isVipBadge) || item.isOriginal,
      width: width,
      autofocus: autofocus,
      escapeToSidebar: escapeToSidebar,
      onTap: onTap,
    );
  }

  static bool _isVipBadge(String b) {
    final u = b.toUpperCase();
    return u.contains('VIP') || u.contains('ORIGINAL');
  }

  static bool _isResumeBadge(String b) => b.toUpperCase().contains('RESUME');

  static String? _timeLeftGuess(double? progress, String? durationLabel) {
    if (progress == null || progress <= 0 || progress >= 1) return null;
    final pct = ((1 - progress) * 100).round();
    if ((durationLabel ?? '').isNotEmpty) {
      return '${((1 - progress) * 100).clamp(1, 99).round()}% left · $durationLabel';
    }
    return '$pct% left';
  }

  @override
  Widget build(BuildContext context) {
    final h = cardHeightFor(width);
    final imgH = imageHeightFor(width);
    return SizedBox(
      width: width,
      height: h,
      child: FocusTile(
        autofocus: autofocus,
        escapeToSidebar: escapeToSidebar,
        borderRadius: radius,
        borderWidth: focusBorderWidth,
        focusScale: 1.04,
        onTap: onTap,
        focusedOverlay: IgnorePointer(
          child: Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withValues(alpha: 0.95),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 34,
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: SizedBox(
            width: width,
            height: imgH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Provider covers are mostly portrait. Fill the tile with the
                // art (dimmed) and show the whole cover on top: a landscape
                // image fills the tile as before, a portrait one is no longer
                // stretched or cropped to a strip. Same URL and decode size,
                // so the image is decoded once.
                RemoteImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  // Width-only decode — both dims stretch via ResizeImage.exact.
                  memCacheWidth: (width * 2).round(),
                ),
                const ColoredBox(color: Color(0x99000000)),
                RemoteImage(
                  url: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: (width * 2).round(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33000000),
                        Color(0x00000000),
                        Color(0xCC000000),
                      ],
                      stops: [0, 0.42, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      if (resume) ...[
                        const TvPill(
                          'RESUME',
                          tone: TvPillTone.cyan,
                          compact: true,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (vip) ...[
                        const TvPill(
                          'VIP',
                          tone: TvPillTone.magenta,
                          compact: true,
                        ),
                        const SizedBox(width: 6),
                      ],
                      for (final b in badges.take(2)) ...[
                        TvPill(badgeText(b), tone: TvPillTone.muted, compact: true),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: progress != null ? 10 : 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if ((episodeLabel ?? '').trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              episodeLabel!.trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty ||
                          (timeLeftLabel ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if ((subtitle ?? '').trim().isNotEmpty)
                              Expanded(
                                child: Text(
                                  subtitle!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                            if ((timeLeftLabel ?? '').trim().isNotEmpty)
                              Text(
                                timeLeftLabel!.trim(),
                                style: TextStyle(
                                  color: AppColors.cyan.withValues(
                                    alpha: 0.95,
                                  ),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      minHeight: 3.5,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      color: AppColors.cyan,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screenshot-standard sports fixture card (Today's Matches).
class TvMatchCard extends StatelessWidget {
  const TvMatchCard({
    super.key,
    required this.match,
    this.autofocus = false,
    this.escapeToSidebar = false,
    this.onTap,
    this.width = 330,
  });

  final SportsMatch match;
  final bool autofocus;
  final bool escapeToSidebar;
  final VoidCallback? onTap;
  final double width;

  static const height = 156.0;
  static const radius = 14.0;

  String _abbr(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '???';
    if (parts.length == 1) {
      return parts.first.length <= 3
          ? parts.first.toUpperCase()
          : parts.first.substring(0, 3).toUpperCase();
    }
    return parts.take(3).map((p) => p[0].toUpperCase()).join();
  }

  Widget _crest(String name) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        _abbr(name),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = match;
    final league = m.broadcaster.isNotEmpty
        ? m.broadcaster
        : '${AppBrand.name} Sports';
    return SizedBox(
      width: width,
      height: height,
      child: FocusTile(
        autofocus: autofocus,
        escapeToSidebar: escapeToSidebar,
        borderRadius: radius,
        borderWidth: 2.5,
        focusScale: 1.03,
        onTap: onTap,
        child: TvGlass(
          radius: radius,
          tint: AppColors.cyan,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      league,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (m.isLive)
                    TvPill(
                      m.minute.isNotEmpty ? '● LIVE ${m.minute}' : '● LIVE',
                      tone: TvPillTone.live,
                      compact: true,
                    )
                  else
                    TvPill(
                      m.minute.isNotEmpty ? 'UPCOMING ${m.minute}' : 'UPCOMING',
                      tone: TvPillTone.cyan,
                      compact: true,
                    ),
                ],
              ),
              const Spacer(),
              // A channel (no opponent): its name only, no score.
              if (m.awayTeam.isEmpty)
                Text(
                  m.homeTeam,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                )
              else
              Row(
                children: [
                  _crest(m.homeTeam),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.homeTeam,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      m.isLive || m.homeScore + m.awayScore > 0
                          ? (Directionality.of(context) == TextDirection.rtl
                              ? '${m.awayScore}  -  ${m.homeScore}'
                              : '${m.homeScore}  -  ${m.awayScore}')
                          : 'VS',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      m.awayTeam,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _crest(m.awayTeam),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (m.stadium.isNotEmpty) m.stadium,
                        '4K HDR',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvUi.meta.copyWith(fontSize: 10),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sports_soccer_rounded,
                          size: 12,
                          color: AppColors.cyan,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Match Center',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
