import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Big "87 Mbps" readout for the connection test (client 20 Oct #10).
class SpeedReadout extends StatelessWidget {
  const SpeedReadout({
    super.key,
    required this.title,
    required this.mbps,
    required this.running,
    this.verdict,
    this.verdictColor,
    this.scale = 1,
  });

  final String title;
  final double? mbps;
  final bool running;
  final String? verdict;
  final Color? verdictColor;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final v = mbps;
    final number = v == null ? '—' : (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
    return Container(
      padding: EdgeInsets.all(18 * scale),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF131C2C), Color(0xFF0C1220)]),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 13 * scale, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          SizedBox(height: 6 * scale),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(number, style: TextStyle(fontSize: 56 * scale, fontWeight: FontWeight.w900, color: AppColors.cyan, height: 1)),
                SizedBox(width: 8 * scale),
                Text('Mbps', style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          SizedBox(height: 10 * scale),
          if (running)
            SizedBox(width: 160 * scale, child: LinearProgressIndicator(minHeight: 3, color: AppColors.cyan))
          else if (verdict != null)
            Text(verdict!, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w800, color: verdictColor ?? AppColors.textSecondary)),
        ],
      ),
    );
  }
}
