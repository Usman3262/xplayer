import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'tv_poster.dart';

/// Home / browse / search loading: real card and hero shapes with a neutral
/// surface and [AppLoader], not theme-colored [AppLoader.cardPlaceholder]
/// rails or [AppShimmer.homeSkeleton] bones.
class TvFeedLoading extends StatelessWidget {
  const TvFeedLoading({
    super.key,
    this.showHero = true,
    this.heroHeight = 420,
    this.railCount = 3,
    this.cardsPerRail = 5,
    this.padding = const EdgeInsets.fromLTRB(36, 0, 36, 48),
  });

  final bool showHero;
  final double heroHeight;
  final int railCount;
  final int cardsPerRail;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < railCount; r++) ...[
          if (r > 0) const SizedBox(height: 20),
          _RailShell(cardCount: cardsPerRail),
        ],
      ],
    );

    if (!showHero) {
      return Padding(padding: padding, child: rails);
    }

    // shrinkWrap: also used inside other vertical lists (Kids home), where an
    // unbounded viewport fails layout and the parent crashes in paint.
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: heroHeight,
          child: ColoredBox(
            color: AppColors.surface,
            child: Center(child: AppLoader.player(size: 52)),
          ),
        ),
        Padding(padding: padding, child: rails),
      ],
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({required this.cardCount});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 160,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: TvPoster.railHeightFor(),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            itemCount: cardCount,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) => const _PosterCardShell(),
          ),
        ),
      ],
    );
  }
}

class _PosterCardShell extends StatelessWidget {
  const _PosterCardShell();

  @override
  Widget build(BuildContext context) {
    final w = TvPoster.standardWidth;
    return SizedBox(
      width: w,
      height: TvPoster.cardHeightFor(w),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: AppColors.surfaceElevated,
          child: Center(child: AppLoader.inline(size: 28)),
        ),
      ),
    );
  }
}
