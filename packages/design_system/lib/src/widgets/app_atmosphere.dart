import 'package:flutter/material.dart';

/// Soft premium atmosphere behind scaffolds (not flat black).
/// Accents come from Appearance settings when provided.
class AppAtmosphere extends StatelessWidget {
  const AppAtmosphere({
    super.key,
    this.child,
    this.intensity = 1,
    this.cyanAccent,
    this.magentaAccent,
    this.background,
  });

  final Widget? child;
  final double intensity;
  final Color? cyanAccent;
  final Color? magentaAccent;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final a = intensity.clamp(0.35, 1.0);
    final cyan = cyanAccent ?? AppColors.cyan;
    final magenta = magentaAccent ?? AppColors.magenta;
    final bg = background ?? const Color(0xFF000000);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: bg),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.85, -0.95),
              radius: 1.15,
              colors: [
                cyan.withValues(alpha: 0.14 * a),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.9, 1.05),
              radius: 1.2,
              colors: [
                magenta.withValues(alpha: 0.12 * a),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF070B12).withValues(alpha: 0.55 * a),
                Colors.transparent,
                const Color(0xFF050308).withValues(alpha: 0.7 * a),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}
