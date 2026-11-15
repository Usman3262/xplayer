import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

/// Cinematic auth shell - ambient neon atmosphere + glass panel (not flat forms).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.badge,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AuthAtmosphere(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 16, 0),
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: IconButton(
                            // Opened with go() (e.g. from the account offer)
                            // there is nothing to pop: fall back to Home.
                            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  AppColors.surface.withValues(alpha: 0.7),
                              side: BorderSide(color: AppColors.border),
                            ),
                            icon: const AppBackIcon(size: 16),
                          ),
                        ),
                        const AppLogo(height: 52, alignToStart: false),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      if (badge != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TechBadge(badge!, tone: BadgeTone.magenta),
                        ),
                        const SizedBox(height: 14),
                      ],
                      NeonGlowText(
                        title,
                        color: AppColors.cyan,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                          height: 1.1,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08, end: 0),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ).animate().fadeIn(delay: 80.ms),
                      const SizedBox(height: 28),
                      _GlassPanel(
                        child: child,
                      ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.06, end: 0),
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

class _AuthAtmosphere extends StatelessWidget {
  const _AuthAtmosphere();

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
        Positioned(
          top: 220,
          left: 40,
          child: _Orb(color: AppColors.gold, size: 100),
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

/// Auth alias for [AppTextField] — same chrome as login / security forms.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      obscure: obscure,
      keyboardType: keyboardType,
      prefix: prefix,
      suffix: suffix,
    );
  }
}
