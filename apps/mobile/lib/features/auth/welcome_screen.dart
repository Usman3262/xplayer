import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_log.dart';
import '../../core/demo_mode.dart';
import '../../core/session_controller.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    // The welcome screen is never part of the demo (e.g. back from login).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(demoModeProvider)) exitDemo(ref);
    });
  }

  /// Store-review demo: the real app over openly licensed sample content.
  void _tryDemo() {
    AppLog.tap('welcome.try_demo');
    ref.read(demoModeProvider.notifier).state = true;
    context.go('/home');
  }

  Future<void> _goLogin() async {
    if (_signingIn) return;
    AppLog.tap('welcome.sign_in');
    setState(() => _signingIn = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await context.push('/auth/login');
    if (mounted) setState(() => _signingIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF071520),
                  Color(0xFF000000),
                  Color(0xFF18071A),
                ],
              ),
            ),
          ),
          Positioned(
            top: -40,
            left: -40,
            child: _blob(AppColors.cyan, 280),
          ),
          Positioned(
            bottom: 80,
            right: -70,
            child: _blob(AppColors.magenta, 300),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AppLanguageToggle(
                        language: language,
                        onChanged: (v) {
                          AppLog.tap('welcome.language', data: {'to': v});
                          ref.read(sessionProvider.notifier).setLanguage(v);
                        },
                      ),
                      const Spacer(),
                      const TechBadge(
                        'ULTRA HD • VIP READY',
                        tone: BadgeTone.gold,
                      ),
                    ],
                  ).animate().fadeIn(),
                  const Spacer(flex: 2),
                  const Center(
                    child: AppLogo(height: 56, alignToStart: false),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scale(begin: const Offset(0.9, 0.9)),
                  const SizedBox(height: 18),
                  NeonGlowText(
                    copy.welcomeHeadline,
                    textAlign: TextAlign.center,
                    color: AppColors.cyan,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      height: 1.15,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 12),
                  Text(
                    copy.welcomeBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                      fontSize: 14,
                    ),
                  ).animate().fadeIn(delay: 160.ms),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      TechBadge('4K UHD'),
                      TechBadge('DOLBY ATMOS', tone: BadgeTone.magenta),
                      TechBadge('LIVE SPORTS', tone: BadgeTone.live),
                      TechBadge('HDR10+', tone: BadgeTone.gold),
                    ],
                  ).animate().fadeIn(delay: 220.ms),
                  const Spacer(flex: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: NeonGlowBorder(
                        color: AppColors.cyan,
                        radius: 22,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NeonGlowBorder(
                                color: AppColors.cyan,
                                radius: 12,
                                child: PrimaryButton(
                                  label: copy.signIn,
                                  icon: Icons.login_rounded,
                                  loading: _signingIn,
                                  onPressed: _signingIn ? null : _goLogin,
                                ),
                              ),
                              const SizedBox(height: 10),
                              PrimaryButton(
                                label: copy.tryDemo,
                                icon: Icons.play_circle_outline_rounded,
                                filled: false,
                                onPressed: _tryDemo,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                copy.accountFromPanel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                copy.mediaPlayerOnlyNotice,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.12, end: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _blob(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
