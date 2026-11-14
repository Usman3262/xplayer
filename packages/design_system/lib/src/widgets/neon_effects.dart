import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pulsing neon glow on a **circle outline** only (no filled background glow).
class NeonGlowCircle extends StatefulWidget {
  const NeonGlowCircle({
    super.key,
    required this.child,
    this.size = 110,
    this.color = AppColors.cyan,
    this.strokeWidth = 2.2,
    this.enabled = true,
  });

  final Widget child;
  final double size;
  final Color color;
  final double strokeWidth;
  final bool enabled;

  @override
  State<NeonGlowCircle> createState() => _NeonGlowCircleState();
}

class _NeonGlowCircleState extends State<NeonGlowCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final pulse = widget.enabled ? _c.value : 0.5;
          return CustomPaint(
            painter: _NeonCirclePainter(
              color: widget.color,
              strokeWidth: widget.strokeWidth,
              glowStrength: 0.35 + pulse * 0.65,
            ),
            child: Center(child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _NeonCirclePainter extends CustomPainter {
  _NeonCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.glowStrength,
  });

  final Color color;
  final double strokeWidth;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeWidth - 4;

    // Soft outer glow layers along the stroke path only
    for (final (blur, alpha) in [
      (18.0, 0.18 * glowStrength),
      (10.0, 0.35 * glowStrength),
      (4.0, 0.55 * glowStrength),
    ]) {
      final glow = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 1.5
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawCircle(center, radius, glow);
    }

    // Crisp outline
    final edge = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(covariant _NeonCirclePainter oldDelegate) {
    return oldDelegate.glowStrength != glowStrength ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Neon glow applied to **glyph outlines / text** only.
class NeonGlowText extends StatefulWidget {
  const NeonGlowText(
    this.text, {
    super.key,
    this.style,
    this.color = AppColors.cyan,
    this.textAlign,
    this.enabled = true,
  });

  final String text;
  final TextStyle? style;
  final Color color;
  final TextAlign? textAlign;
  final bool enabled;

  @override
  State<NeonGlowText> createState() => _NeonGlowTextState();
}

class _NeonGlowTextState extends State<NeonGlowText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? const TextStyle();
    // Tight cyan shadows look like a blue "dot" on Arabic lettering
    // (client 19 Oct: blue mark on "بدون تنازل"). Soft glow only, or none.
    final arabic = _hasArabic(widget.text);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.enabled ? (0.4 + _c.value * 0.6) : 0.7;
        final shadows = !widget.enabled
            ? null
            : arabic
                ? <Shadow>[
                    Shadow(
                      color: widget.color.withValues(alpha: 0.22 * t),
                      blurRadius: 18,
                    ),
                  ]
                : <Shadow>[
                    Shadow(
                      color: widget.color.withValues(alpha: 0.35 * t),
                      blurRadius: 16,
                    ),
                    Shadow(
                      color: widget.color.withValues(alpha: 0.55 * t),
                      blurRadius: 8,
                    ),
                    Shadow(
                      color: widget.color.withValues(alpha: 0.9 * t),
                      blurRadius: 2,
                    ),
                  ];
        return Text(
          widget.text,
          textAlign: widget.textAlign,
          style: base.copyWith(
            color: base.color ?? AppColors.textPrimary,
            shadows: shadows,
          ),
        );
      },
    );
  }

  static bool _hasArabic(String text) {
    for (final u in text.runes) {
      if (u >= 0x0600 && u <= 0x06FF) return true;
    }
    return false;
  }
}

/// Neon glow on an **icon** (vector) - not a background box.
class NeonGlowIcon extends StatefulWidget {
  const NeonGlowIcon(
    this.icon, {
    super.key,
    this.size = 48,
    this.color = AppColors.cyan,
    this.enabled = true,
  });

  final IconData icon;
  final double size;
  final Color color;
  final bool enabled;

  @override
  State<NeonGlowIcon> createState() => _NeonGlowIconState();
}

class _NeonGlowIconState extends State<NeonGlowIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.enabled ? (0.4 + _c.value * 0.6) : 0.7;
        return Icon(
          widget.icon,
          size: widget.size,
          color: widget.color,
          shadows: [
            Shadow(
              color: widget.color.withValues(alpha: 0.35 * t),
              blurRadius: 18,
            ),
            Shadow(
              color: widget.color.withValues(alpha: 0.7 * t),
              blurRadius: 6,
            ),
          ],
        );
      },
    );
  }
}

/// Neon glow on a **rounded rectangle outline** only (for buttons/cards border).
class NeonGlowBorder extends StatefulWidget {
  const NeonGlowBorder({
    super.key,
    required this.child,
    this.color = AppColors.cyan,
    this.radius = 12,
    this.strokeWidth = 1.6,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;
  final bool enabled;
  final EdgeInsets padding;

  @override
  State<NeonGlowBorder> createState() => _NeonGlowBorderState();
}

class _NeonGlowBorderState extends State<NeonGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = 0.35 + _c.value * 0.65;
        return CustomPaint(
          painter: _NeonRRectPainter(
            color: widget.color,
            radius: widget.radius,
            strokeWidth: widget.strokeWidth,
            glowStrength: t,
          ),
          child: Padding(padding: widget.padding, child: child),
        );
      },
      child: widget.child,
    );
  }
}

class _NeonRRectPainter extends CustomPainter {
  _NeonRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.glowStrength,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth,
        strokeWidth,
        size.width - strokeWidth * 2,
        size.height - strokeWidth * 2,
      ),
      Radius.circular(radius),
    );

    for (final (blur, alpha) in [
      (14.0, 0.2 * glowStrength),
      (7.0, 0.4 * glowStrength),
      (2.5, 0.65 * glowStrength),
    ]) {
      final glow = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 1
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawRRect(rrect, glow);
    }

    final edge = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRRect(rrect, edge);
  }

  @override
  bool shouldRepaint(covariant _NeonRRectPainter oldDelegate) {
    return oldDelegate.glowStrength != glowStrength ||
        oldDelegate.color != color;
  }
}

/// Back-compat: outline glow around child (not a filled neon box).
class NeonPulse extends StatelessWidget {
  NeonPulse({
    super.key,
    required this.child,
    this.color = AppColors.cyan,
    this.enabled = true,
    this.radius = 12,
  });

  final Widget child;
  final Color color;
  final bool enabled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return NeonGlowBorder(
      color: color,
      enabled: enabled,
      radius: radius,
      child: child,
    );
  }
}

/// Tap scale only - no background glow box.
class NeonTap extends StatefulWidget {
  NeonTap({
    super.key,
    required this.child,
    required this.onTap,
    Color? color,
  }) : color = color ?? AppColors.cyan;

  final Widget child;
  final VoidCallback onTap;
  final Color color;

  @override
  State<NeonTap> createState() => _NeonTapState();
}

class _NeonTapState extends State<NeonTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
