import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';
import 'app_loaders.dart';

/// Brand-colored shimmer — **each bone shimmers on its own** (not one screen sweep).
class AppShimmer extends StatelessWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Duration period;

  static final _base = AppColors.surfaceElevated;
  static const _highlight = Color(0xFF3A4254);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _base,
      highlightColor: _highlight,
      period: period,
      child: child,
    );
  }

  /// Single skeleton bone with its own shimmer pass.
  static Widget bone({
    required double width,
    required double height,
    BorderRadius? radius,
    int index = 0,
  }) {
    final period = Duration(milliseconds: 1100 + (index % 6) * 140);
    return AppShimmer(
      period: period,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: radius ?? BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Horizontal poster rail — card placeholders use progressiveDots (not shimmer).
  static Widget posterRail({
    double height = 160,
    double width = 110,
    int count = 6,
  }) {
    return SizedBox(
      height: height + 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => AppLoader.cardPlaceholder(
          width: width,
          height: height,
          seed: i,
        ),
      ),
    );
  }

  /// Full page of stacked rails.
  static Widget pageRails({int rails = 3}) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: rails,
      itemBuilder: (_, rail) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: bone(
                width: 140,
                height: 14,
                index: rail,
                radius: BorderRadius.circular(4),
              ),
            ),
            posterRail(count: 5),
          ],
        ),
      ),
    );
  }

  /// Hero + rails for home-like screens.
  static Widget homeSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: bone(
            width: double.infinity,
            height: 210,
            index: 0,
            radius: BorderRadius.circular(16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: bone(
            width: 120,
            height: 14,
            index: 1,
            radius: BorderRadius.circular(4),
          ),
        ),
        posterRail(count: 5),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: bone(
            width: 160,
            height: 14,
            index: 4,
            radius: BorderRadius.circular(4),
          ),
        ),
        posterRail(count: 5),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: bone(
            width: 130,
            height: 14,
            index: 5,
            radius: BorderRadius.circular(4),
          ),
        ),
        posterRail(count: 5),
      ],
    );
  }

  /// Vertical episode / channel rows. Same theme accents and progressiveDots
  /// as home card placeholders, in the list-tile shape those screens use.
  /// [AppLoader.paging] sits centered under the list when [showPaging] is true.
  static Widget listRows({int count = 6, bool showPaging = true}) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          AppLoader.listRowPlaceholder(seed: i),
        if (showPaging)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            child: Center(child: AppLoader.paging(size: 36)),
          ),
      ],
    );
  }

  /// Two-column poster grid. Cards match the home rail placeholders.
  /// [AppLoader.paging] sits centered under the grid (progressiveDots).
  static Widget twoColumnCards({int count = 6, bool showPaging = true}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 16.0;
        const gap = 12.0;
        final colW = (constraints.maxWidth - pad * 2 - gap) / 2;
        final imageH = colW * 1.42;
        final cellH = imageH + 40;
        return Column(
          children: [
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(pad, 4, pad, 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: gap,
                  childAspectRatio: colW / cellH,
                ),
                itemCount: count,
                itemBuilder: (_, i) => AppLoader.cardPlaceholder(
                  width: colW,
                  height: imageH,
                  seed: i,
                ),
              ),
            ),
            if (showPaging)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                child: Center(child: AppLoader.paging(size: 36)),
              ),
          ],
        );
      },
    );
  }

  /// TV-sized rail — progressiveDots card placeholders.
  static Widget tvRail({double height = 180, int count = 8}) {
    return SizedBox(
      height: height + 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 36),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => AppLoader.cardPlaceholder(
          width: 120,
          height: height,
          seed: i,
        ),
      ),
    );
  }

  /// Single block (details header, settings card, etc.).
  static Widget block({
    double height = 120,
    double? width,
    BorderRadius? radius,
    int index = 0,
  }) {
    return bone(
      width: width ?? double.infinity,
      height: height,
      radius: radius ?? BorderRadius.circular(14),
      index: index,
    );
  }
}
