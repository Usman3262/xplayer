import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../theme/app_colors.dart';

/// progressiveDots that never overflows: the package lays its dots out in a
/// box of exactly `size`, so a parent narrower than `size` overflowed the Row
/// ("RenderFlex overflowed by 9.9 pixels"). Shrinks to the space available.
class AppDots extends StatelessWidget {
  const AppDots({super.key, required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var s = size;
        if (box.maxWidth.isFinite && box.maxWidth < s) s = box.maxWidth;
        if (box.maxHeight.isFinite && box.maxHeight < s) s = box.maxHeight;
        if (s <= 0) return const SizedBox.shrink();
        return Center(
          widthFactor: 1,
          heightFactor: 1,
          child: LoadingAnimationWidget.progressiveDots(color: color, size: s),
        );
      },
    );
  }
}

/// Locked the app loader map (app standard — do not change casually):
/// - Buttons → [AppLoader.button] (`progressiveDots`)
/// - Player / video buffering → [AppLoader.player] (`staggeredDotsWave`)
/// - Poster cards (home rails, two-column grids) → [AppLoader.cardPlaceholder]
/// - Vertical list rows (series episodes, sports channels) → [AppLoader.listRowPlaceholder]
/// - End of a card grid or list while another page loads → [AppLoader.paging] (`progressiveDots`), bottom center
/// - Page / nav wait → [AppLoader.page] (`progressiveDots`)
/// - Inline chips → [AppLoader.inline] (`threeRotatingDots`)
/// - Auth forms → [AppLoader.auth] (`progressiveDots`)
///
/// Placeholders use [AppColors] surfaces and [AppColors.themeAccent],
/// with progressiveDots inside the art area. Do not swap in shimmer bones
/// or a different animation for these layouts.
class AppLoader extends StatelessWidget {
  AppLoader._({
    required this.builder,
    this.size = 42,
    Color? color,
    this.label,
  }) : color = color ?? AppColors.cyan;

  factory AppLoader.button({
    Key? key,
    double size = 40,
    Color color = Colors.white,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          AppDots(color: c, size: s),
      size: size,
      color: color,
    );
  }

  factory AppLoader.page({
    Key? key,
    double size = 48,
    Color? color,
    String? label,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          AppDots(color: c, size: s),
      size: size,
      color: color ?? AppColors.cyan,
      label: label,
    );
  }

  factory AppLoader.inline({
    Key? key,
    double size = 28,
    Color? color,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          LoadingAnimationWidget.threeRotatingDots(color: c, size: s),
      size: size,
      color: color ?? AppColors.cyan,
    );
  }

  factory AppLoader.player({
    Key? key,
    double size = 56,
    Color? color,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          LoadingAnimationWidget.staggeredDotsWave(color: c, size: s),
      size: size,
      color: color ?? AppColors.cyan,
    );
  }

  factory AppLoader.auth({
    Key? key,
    double size = 48,
    Color? color,
    String? label,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          AppDots(color: c, size: s),
      size: size,
      color: color ?? AppColors.cyan,
      label: label,
    );
  }

  factory AppLoader.paging({
    Key? key,
    double size = 36,
    Color? color,
  }) {
    return AppLoader._(
      builder: (c, s) =>
          AppDots(color: c, size: s),
      size: size,
      color: color ?? AppColors.cyan,
    );
  }

  /// Episode / channel row: thumbnail with progressiveDots plus title bars.
  /// Same colors and animation as [cardPlaceholder], in list-tile shape.
  factory AppLoader.listRowPlaceholder({
    Key? key,
    int seed = 0,
  }) {
    return AppLoader._(
      builder: (c, s) => _ListRowPlaceholder(seed: seed),
      size: 28,
      color: AppColors.themeAccent(seed),
    );
  }

  /// Poster-sized placeholder with theme-colored progressiveDots.
  factory AppLoader.cardPlaceholder({
    Key? key,
    double width = 118,
    double height = 170,
    int seed = 0,
  }) {
    return AppLoader._(
      builder: (c, s) => _CardPlaceholder(
        width: width,
        height: height,
        seed: seed,
      ),
      size: 28,
      color: AppColors.themeAccent(seed),
    );
  }

  final Widget Function(Color color, double size) builder;
  final double size;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final anim = builder(color, size);
    if (label == null) return anim;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        anim,
        const SizedBox(height: 14),
        Text(
          label!,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ListRowPlaceholder extends StatelessWidget {
  const _ListRowPlaceholder({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.themeAccent(seed);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 110,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: AppDots(
              color: accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 120,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder({
    required this.width,
    required this.height,
    required this.seed,
  });

  final double width;
  final double height;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.themeAccent(seed);
    return SizedBox(
      width: width,
      height: height + 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              alignment: Alignment.center,
              child: AppDots(
                color: accent,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: width * 0.7,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
