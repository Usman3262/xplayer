import 'package:flutter/material.dart';
import 'package:domain/domain.dart' show AppBrand;

import 'app_logo.dart';

import '../assets/app_assets.dart';
import '../theme/app_colors.dart';

/// Brand wordmark asset. Always LTR (`the app`) — never mirrors in RTL locales.
class AppWordmark extends StatelessWidget {
  const AppWordmark({
    super.key,
    this.height = 28,
    this.showFourK = true,
  });

  final double height;
  final bool showFourK;

  @override
  Widget build(BuildContext context) {
    // Brand lockup must not reverse under Arabic/Urdu Directionality.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Image.asset(
        AppAssets.wordmark,
        package: AppAssets.package,
        height: height,
        // Android TV only: decoded near its on-screen size (client 9 Nov).
        cacheHeight: AppLogo.decodeNearDisplaySize
            ? (height * MediaQuery.devicePixelRatioOf(context) * 2).round()
            : null,
        fit: BoxFit.contain,
        filterQuality: AppLogo.decodeNearDisplaySize
            ? FilterQuality.medium
            : FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (_, _, _) => _FallbackWordmark(
          height: height,
          showFourK: showFourK,
        ),
      ),
    );
  }
}

class _FallbackWordmark extends StatelessWidget {
  const _FallbackWordmark({
    required this.height,
    required this.showFourK,
  });

  final double height;
  final bool showFourK;

  @override
  Widget build(BuildContext context) {
    final appSize = height * 0.72;
    final fourKSize = height * 0.78;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFCBD5E1),
                  Color(0xFF94A3B8),
                ],
                stops: [0.0, 0.45, 1.0],
              ).createShader(bounds),
              child: Text(
                AppBrand.name,
                style: TextStyle(
                  fontSize: appSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: height * 0.02,
                  height: 1,
                  color: Colors.white,
                ),
              ),
            ),
            if (showFourK) ...[
              SizedBox(width: height * 0.14),
              Text(
                '4K',
                style: TextStyle(
                  fontSize: fourKSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: height * 0.01,
                  height: 1,
                  color: AppColors.cyan,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
