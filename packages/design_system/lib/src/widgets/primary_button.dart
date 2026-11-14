import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import 'app_loaders.dart';

class PrimaryButton extends StatelessWidget {
  PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon = Icons.play_arrow_rounded,
    this.filled = true,
    this.expand = true,
    Color? color,
    this.loading = false,
    this.autofocus = false,
  }) : color = color ?? AppColors.cyan;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool expand;
  final Color color;
  final bool loading;

  /// Takes the focus when shown (TV remote). Off by default.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    // Loading: primary fill stays fully on; only large white waveDots (no text/icon).
    final Widget child = loading
        ? Center(child: AppLoader.button())
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: filled ? Colors.black : color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: filled ? Colors.black : AppColors.textPrimary,
                    fontWeight: AppFonts.control(FontWeight.w800),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );

    return SizedBox(
      height: 52,
      width: expand ? double.infinity : null,
      child: filled
          ? FilledButton(
              autofocus: autofocus,
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                // Stay primary while loading (don't fade to grey).
                disabledBackgroundColor: loading
                    ? color
                    : color.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: child,
            )
          : OutlinedButton(
              autofocus: autofocus,
              onPressed: enabled ? onPressed : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color.withValues(alpha: 0.7)),
                foregroundColor: AppColors.textPrimary,
                backgroundColor: loading ? color : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: child,
            ),
    );
  }
}
