import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

class TechBadge extends StatelessWidget {
  const TechBadge(
    this.label, {
    super.key,
    this.tone = BadgeTone.cyan,
    this.compact = false,
  });

  final String label;
  final BadgeTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Coming Soon tag (domain `soonBadge`): "قريبًا" in Arabic, magenta.
    final soon = this.label == 'SOON';
    final label = badgeText(this.label);
    final tone = soon ? BadgeTone.magenta : this.tone;
    final colors = switch (tone) {
      BadgeTone.cyan => (AppColors.cyan, AppColors.cyan.withValues(alpha: 0.15)),
      BadgeTone.magenta => (AppColors.magenta, AppColors.magenta.withValues(alpha: 0.18)),
      BadgeTone.gold => (AppColors.gold, AppColors.gold.withValues(alpha: 0.16)),
      BadgeTone.neutral => (AppColors.textPrimary, AppColors.surfaceElevated),
      BadgeTone.live => (AppColors.live, AppColors.live.withValues(alpha: 0.2)),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.$1.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        // Latin tech tags ("HDR10+") read left to right even in Arabic;
        // in RTL the "+" jumped to the front ("+HDR10", 19 Oct).
        textDirection: _rtlScript.hasMatch(label) ? null : TextDirection.ltr,
        style: TextStyle(
          color: colors.$1,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Text for a title badge in the app's language: domain `soonBadge` →
/// "قريبًا", domain `dubbedBadge` → «مدبلج» / "Dubbed" (client 12 Nov);
/// other tags ("4K", "EG", "SUB") as they are.
String badgeText(String badge) => switch (badge) {
      'SOON' => AppFonts.arabicUi ? 'قريبًا' : 'SOON',
      'DUBBED' => AppFonts.arabicUi ? 'مدبلج' : 'Dubbed',
      _ => badge,
    };

final _rtlScript = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

enum BadgeTone { cyan, magenta, gold, neutral, live }
