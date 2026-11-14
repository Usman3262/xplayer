import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Glass style for navigation, menus, chips and buttons (Figma v2; client
/// 17 Oct: "modern glass-style treatment" on every platform). The TV used
/// this from 15 Oct; the phone apps use the same surfaces.
abstract final class AppGlass {
  static BoxDecoration surface({
    required BorderRadius radius,
    bool selected = false,
    bool circle = false,
    bool pressed = false,
  }) {
    final top = Color.fromRGBO(255, 255, 255, pressed ? 0.26 : 0.17);
    final bottom = Color.fromRGBO(255, 255, 255, pressed ? 0.10 : 0.05);
    return BoxDecoration(
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : radius,
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5BEBFF), AppColors.cyan],
            )
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
      border: Border.all(
        color: selected
            ? AppColors.cyan
            : const Color.fromRGBO(255, 255, 255, 0.22),
        width: 1,
      ),
      boxShadow: [
        if (selected)
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.35),
            blurRadius: 12,
          )
        else
          const BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.35),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
      ],
    );
  }

  /// Frosted bar (bottom navigation): translucent with a light top edge.
  static const BoxDecoration bar = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.fromRGBO(255, 255, 255, 0.10), Color.fromRGBO(10, 14, 22, 0.86)],
    ),
    border: Border(
      top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.18)),
    ),
  );
}
