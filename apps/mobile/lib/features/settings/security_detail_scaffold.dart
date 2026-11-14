import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';

/// Security detail chrome — same atmosphere + glass panel as auth screens.
class SecurityDetailScaffold extends ConsumerWidget {
  const SecurityDetailScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.helpTitle,
    required this.helpBody,
    required this.child,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String helpTitle;
  final String helpBody;
  final Widget child;
  final String? badge;

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    helpTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              helpBody,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final howToTooltip = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    ).howTo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SecurityAtmosphere(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              AppColors.surface.withValues(alpha: 0.7),
                          side: BorderSide(color: AppColors.border),
                        ),
                        icon: const AppBackIcon(size: 16),
                      ),
                      const Expanded(
                        child: AppLogo(height: 52, alignToStart: true),
                      ),
                      IconButton(
                        tooltip: howToTooltip,
                        onPressed: () => _showHelp(context),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              AppColors.surface.withValues(alpha: 0.7),
                          side: BorderSide(color: AppColors.border),
                        ),
                        icon: Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.cyan,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      if (badge != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TechBadge(badge!, tone: BadgeTone.magenta),
                        ),
                        const SizedBox(height: 12),
                      ],
                      NeonGlowText(
                        title,
                        color: AppColors.cyan,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          height: 1.1,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 320.ms)
                          .slideY(begin: 0.06, end: 0),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ).animate().fadeIn(delay: 60.ms),
                      const SizedBox(height: 22),
                      _GlassPanel(child: child)
                          .animate()
                          .fadeIn(delay: 100.ms)
                          .slideY(begin: 0.05, end: 0),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityAtmosphere extends StatelessWidget {
  const _SecurityAtmosphere();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050B12),
                Color(0xFF000000),
                Color(0xFF140816),
              ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: _Orb(color: AppColors.cyan, size: 220),
        ),
        Positioned(
          bottom: 120,
          left: -90,
          child: _Orb(color: AppColors.magenta, size: 260),
        ),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: NeonGlowBorder(
          color: AppColors.cyan,
          radius: 22,
          strokeWidth: 1.2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Shared list row used on Security hub / Devices / Sessions.
class SecurityNavTile extends StatelessWidget {
  const SecurityNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xCC111622),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(icon, color: AppColors.cyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
