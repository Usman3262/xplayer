import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:domain/domain.dart' show AppBrand;

import '../assets/app_assets.dart';
import '../theme/app_colors.dart';

/// Brand lockup (combined mark + wordmark PNG).
///
/// Placement follows ambient directionality when [alignToStart] is true:
/// LTR → left edge, RTL → right edge.
///
/// Horizontal lockup swaps assets by locale direction:
/// LTR → [logoLockup] (mark then wordmark);
/// RTL → [logoLockupRtl] (wordmark then mark).
/// Glyphs stay `the app` (never `4K APP`).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 28,
    this.showWordmark = true,
    this.alignToStart = true,
    this.lockupAsset = AppAssets.logoLockup,
    this.lockupAssetRtl = AppAssets.logoLockupRtl,
    this.markAsset = AppAssets.logoMark,
    this.assetPackage = AppAssets.package,
  });

  final double height;
  final bool showWordmark;

  /// When true and width is bounded, pins the lockup to the start edge
  /// (left in LTR, right in RTL). Use in app bars / chrome rows.
  final bool alignToStart;

  /// LTR combined lockup (mark → wordmark).
  final String lockupAsset;

  /// RTL combined lockup (wordmark → mark).
  final String lockupAssetRtl;

  final String markAsset;
  final String? assetPackage;

  /// Locked mark plate (2048×1406).
  static const markAspect = 2048 / 1406;

  /// Set once by the Android TV app. Off everywhere else, so phone, iPhone
  /// and Windows logos are unchanged.
  static bool decodeNearDisplaySize = false;

  /// Logo uploaded in the admin panel (Branding & theme). When set, it is shown
  /// in the same place and size as the built-in logo (no layout change); the
  /// built-in artwork is the fallback while loading or on error.
  static String? remoteUrl;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Artwork is direction-specific PNGs — never mirror glyphs.
    final brand = Directionality(
      textDirection: TextDirection.ltr,
      child: _buildBrand(rtl: rtl),
    );

    if (!alignToStart) {
      return brand;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return brand;
        // Ambient Directionality controls start edge (RTL → right).
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: brand,
          ),
        );
      },
    );
  }

  Widget _buildBrand({required bool rtl}) {
    final url = remoteUrl;
    if (url == null || url.isEmpty) return _buildAsset(rtl: rtl);
    return CachedNetworkImage(
      imageUrl: url,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => _buildAsset(rtl: rtl),
      errorWidget: (_, _, _) => _buildAsset(rtl: rtl),
    );
  }

  Widget _buildAsset({required bool rtl}) {
    if (!showWordmark) {
      // Decode the 2048 px mark near its on-screen size: drawing the full
      // image at 15-40 dp looked jagged / low quality (client 21 Oct,
      // watermark). Two-step downscale at decode keeps it crisp.
      return Builder(builder: (context) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final h = height;
        return Image.asset(
          markAsset,
          package: assetPackage,
          height: h,
          cacheHeight: (h * dpr * 2).round(),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
          errorBuilder: (_, _, _) => _FallbackMark(height: height),
        );
      });
    }

    // Android TV: the 2400 px lockup, drawn at 20-80 dp, is decoded near its
    // on-screen size, as the mark already is (client 9 Nov: blurry logos).
    if (decodeNearDisplaySize) {
      return Builder(builder: (context) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        return Image.asset(
          lockupAsset,
          package: assetPackage,
          height: height,
          cacheHeight: (height * dpr * 2).round(),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
          errorBuilder: (_, _, _) => _FallbackLockup(height: height),
        );
      });
    }

    // A brand lockup is never mirrored: same mark + wordmark order in Arabic
    // and Urdu (the RTL asset looked like a flipped logo to the client).
    return Image.asset(
      lockupAsset,
      package: assetPackage,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      errorBuilder: (_, _, _) => _FallbackLockup(height: height),
    );
  }
}

class _FallbackLockup extends StatelessWidget {
  const _FallbackLockup({required this.height, this.rtl = false});
  final double height;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final mark = _FallbackMark(height: height);
    final word = Text(
      AppBrand.name,
      style: TextStyle(
        fontSize: height * 0.55,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
      ),
    );
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: rtl
            ? [word, const SizedBox(width: 6), mark]
            : [mark, const SizedBox(width: 6), word],
      ),
    );
  }
}

class _FallbackMark extends StatelessWidget {
  const _FallbackMark({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * AppLogo.markAspect,
      child: CustomPaint(painter: _AppMarkPainter()),
    );
  }
}

class _AppMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cyan = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;
    final magenta = Paint()
      ..color = AppColors.magenta
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    final cRect = Rect.fromLTRB(
      size.width * 0.05,
      size.height * 0.12,
      size.width * 0.48,
      size.height * 0.88,
    );
    canvas.drawArc(cRect, -0.95, -4.55, false, cyan);

    final path = Path()
      ..moveTo(size.width * 0.52, size.height * 0.40)
      ..lineTo(size.width * 0.58, size.height * 0.22)
      ..lineTo(size.width * 0.66, size.height * 0.14)
      ..lineTo(size.width * 0.70, size.height * 0.46)
      ..lineTo(size.width * 0.50, size.height * 0.46)
      ..moveTo(size.width * 0.70, size.height * 0.46)
      ..lineTo(size.width * 0.70, size.height * 0.86)
      ..moveTo(size.width * 0.70, size.height * 0.46)
      ..lineTo(size.width * 0.94, size.height * 0.12)
      ..moveTo(size.width * 0.70, size.height * 0.46)
      ..lineTo(size.width * 0.96, size.height * 0.88);
    canvas.drawPath(path, magenta);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
