import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_splash_brand.dart';

/// Same splash mark + bolt as cold start, scaled down for playback open.
/// Indeterminate by default (no fake % — brief §2.2 / Phase 2).
/// Brand animation only — no CircularProgressIndicator (avoids double loaders).
class AppPlaybackLoading extends StatelessWidget {
  const AppPlaybackLoading({
    super.key,
    this.progress,
    this.label = 'Loading',
    this.logoHeight = 40,
    this.indeterminate = true,
  });

  /// Optional real 0.0–1.0 progress. Ignored when [indeterminate] is true.
  final double? progress;
  final String label;
  final double logoHeight;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final showPct = !indeterminate && progress != null;
    final pct = ((progress ?? 0) * 100).round().clamp(0, 100);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSplashBrand(
          markHeight: logoHeight,
          showWordmark: false,
          continuous: true,
        ),
        const SizedBox(height: 16),
        Text(
          showPct ? '$label… $pct%' : '$label…',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
