import 'package:flutter/material.dart';

/// Back chevron that flips with locale without Material double-mirroring.
///
/// LTR → points left (back). RTL → points right (forward).
/// Icons are locked to LTR [textDirection] so `matchTextDirection` does not
/// flip them a second time under Arabic/Urdu.
class AppBackIcon extends StatelessWidget {
  const AppBackIcon({
    super.key,
    this.size = 18,
    this.color,
    this.style = AppBackIconStyle.ios,
  });

  final double size;
  final Color? color;
  final AppBackIconStyle style;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final icon = switch (style) {
      AppBackIconStyle.ios =>
        rtl ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_new_rounded,
      AppBackIconStyle.material =>
        rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
      AppBackIconStyle.chevron =>
        rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
    };
    return Icon(
      icon,
      size: size,
      color: color,
      // Prevent Material from mirroring again under RTL Directionality.
      textDirection: TextDirection.ltr,
    );
  }
}

enum AppBackIconStyle { ios, material, chevron }
