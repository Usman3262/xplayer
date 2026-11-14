import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "Soon / قريبًا" in place of Watch Now for titles not released yet
/// (client 4 Nov, as on LG): not a button, nothing to play.
class SoonPill extends StatelessWidget {
  const SoonPill({super.key, required this.label, this.height = 48, this.fontSize = 16});
  final String label;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.magenta,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, color: Colors.white, size: fontSize + 4),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fontSize)),
          ],
        ),
      );
}
