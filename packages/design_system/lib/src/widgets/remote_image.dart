import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../theme/app_colors.dart';
import 'app_loaders.dart';

/// The posters / backdrops cache. Its index is a JSON file, not the default
/// SQLite database: under many posters at once (Home, rows loading) SQLite
/// logged "database has been locked for 0:00:10" dozens of times and images
/// waited 10 s each (iPhone simulator log, 12 Nov). The JSON index batches its
/// writes. New name, so the old SQLite index is no longer used.
class AppImageCache {
  AppImageCache._();

  static const _key = 'appImagesV2';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 1500,
      repo: JsonCacheInfoRepository(databaseName: _key),
    ),
  );
}

/// Cached network image with loading / error fallback (CDN posters, etc.).
///
/// Important: never decode with both [memCacheWidth] and [memCacheHeight].
/// Flutter's default [ResizeImagePolicy.exact] stretches the bitmap to that
/// size (like [BoxFit.fill]). We pass a single dimension and let [fit]
/// ([BoxFit.cover] by default) crop correctly at paint time.
///
/// Default [BoxFit.cover] suits full-bleed backdrops (~16:9). Portrait poster
/// tiles should pass [BoxFit.contain] so ~2:3 art is not cropped.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.borderRadius,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fallbackColors = const [Color(0xFF151A24), Color(0xFF0A0C10)],
    this.fallbackUrl,
  });

  final String? url;
  final BoxFit fit;

  /// Which part stays visible when [fit] crops (e.g. a poster's upper part).
  final Alignment alignment;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// Decode / cache at reduced size for list tiles (saves RAM).
  /// Prefer width-only; if both are set, width wins to avoid stretch.
  final int? memCacheWidth;
  final int? memCacheHeight;
  final List<Color> fallbackColors;

  /// Shown when [url] is empty or fails, e.g. the series poster behind an
  /// episode still (client 20 Oct I6). Tried once, no further fallback.
  final String? fallbackUrl;

  bool get _hasFallbackUrl =>
      fallbackUrl != null && fallbackUrl!.isNotEmpty && fallbackUrl != url;

  Widget _fallbackImage() => RemoteImage(
        url: fallbackUrl,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fallbackColors: fallbackColors,
      );

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius;
    Widget child;
    if (url == null || url!.isEmpty) {
      child = _hasFallbackUrl ? _fallbackImage() : _fallback();
    } else {
      // Size decode to the laid-out tile, not full CDN resolution (low-RAM devices).
      child = LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final layoutW = width ??
              (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
          final layoutH = height ??
              (constraints.maxHeight.isFinite ? constraints.maxHeight : null);

          // One dimension only — both would stretch under ResizeImagePolicy.exact.
          final int? cacheW;
          final int? cacheH;
          if (memCacheWidth != null) {
            cacheW = memCacheWidth;
            cacheH = null;
          } else if (memCacheHeight != null) {
            cacheW = null;
            cacheH = memCacheHeight;
          } else if (layoutW != null && layoutW.isFinite) {
            cacheW = (layoutW * dpr).round().clamp(64, 1920);
            cacheH = null;
          } else if (layoutH != null && layoutH.isFinite) {
            cacheW = null;
            cacheH = (layoutH * dpr).round().clamp(64, 1920);
          } else {
            cacheW = 720;
            cacheH = null;
          }

          return CachedNetworkImage(
            imageUrl: url!,
            cacheManager: AppImageCache.instance,
            fit: fit,
            alignment: alignment,
            width: width,
            height: height,
            memCacheWidth: cacheW,
            memCacheHeight: cacheH,
            fadeInDuration: const Duration(milliseconds: 180),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (_, _) => _fallback(showSpinner: true),
            errorWidget: (_, _, _) =>
                _hasFallbackUrl ? _fallbackImage() : _fallback(),
          );
        },
      );
    }

    if (radius != null) {
      return ClipRRect(borderRadius: radius, child: child);
    }
    return child;
  }

  Widget _fallback({bool showSpinner = false}) {
    final shortSide = <double>[
      if (width != null && width!.isFinite) width!,
      if (height != null && height!.isFinite) height!,
    ];
    final minSide =
        shortSide.isEmpty ? 120.0 : shortSide.reduce((a, b) => a < b ? a : b);
    // Large tiles → staggeredDotsWave; compact posters → progressiveDots.
    final useWave = minSide >= 160;
    final loaderSize = (minSide * 0.28).clamp(22.0, 48.0);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fallbackColors,
        ),
      ),
      child: Center(
        child: showSpinner
            ? (useWave
                ? AppLoader.player(size: loaderSize)
                : AppLoader.paging(size: loaderSize))
            : Icon(
                Icons.movie_outlined,
                color: AppColors.textSecondary,
              ),
      ),
    );
  }
}
