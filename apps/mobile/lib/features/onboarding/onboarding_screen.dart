import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/panels.dart';
import '../../core/session_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _pageCount = 4;

  static final _meta = [
    (icon: Icons.hd_rounded, accent: AppColors.cyan),
    (icon: Icons.sports_soccer_rounded, accent: AppColors.magenta),
    (icon: Icons.devices_rounded, accent: AppColors.gold),
    (icon: Icons.shield_moon_rounded, accent: AppColors.cyan),
  ];

  List<({String title, String body, IconData icon, Color accent})> _pages(
    AppCopy copy,
  ) =>
      [
        (
          title: copy.onboardTitle1,
          body: copy.onboardBody1,
          icon: _meta[0].icon,
          accent: _meta[0].accent,
        ),
        (
          title: copy.onboardTitle2,
          body: copy.onboardBody2,
          icon: _meta[1].icon,
          accent: _meta[1].accent,
        ),
        (
          title: copy.onboardTitle3,
          body: copy.onboardBody3,
          icon: _meta[2].icon,
          accent: _meta[2].accent,
        ),
        (
          title: copy.onboardTitle4,
          body: copy.onboardBody4,
          icon: _meta[3].icon,
          accent: _meta[3].accent,
        ),
      ];

  Future<void> _finish() async {
    debugPrint('[ACTION] onboarding.complete');
    await ref.read(sessionProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go(PanelsService.hasPanel ? '/home' : '/connect');
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(sessionProvider.select((s) => s.language));
    final copy = AppCopy.ofLanguage(language);
    final pages = _pages(copy);
    final page = pages[_index];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071018), Color(0xFF000000), Color(0xFF160814)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      AppLanguageToggle(
                        language: language,
                        onChanged: (v) {
                          ref.read(sessionProvider.notifier).setLanguage(v);
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _finish,
                        child: Text(
                          copy.skip,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),
              const Center(
                child: AppLogo(height: 48, alignToStart: false),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _pageCount,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final p = pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          NeonGlowCircle(
                            size: 120,
                            color: p.accent,
                            child: NeonGlowIcon(
                              p.icon,
                              size: 46,
                              color: p.accent,
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .scale(begin: const Offset(0.88, 0.88)),
                          const SizedBox(height: 28),
                          NeonGlowText(
                            p.title,
                            color: p.accent,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 26,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            p.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.45,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: active ? page.accent : AppColors.border,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: page.accent.withValues(alpha: 0.7),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: NeonGlowBorder(
                    key: ValueKey(_index),
                    color: page.accent,
                    radius: 12,
                    child: PrimaryButton(
                      label: _index == _pageCount - 1
                          ? copy.getStarted
                          : copy.next,
                      color: page.accent,
                      icon: _index == _pageCount - 1
                          ? Icons.rocket_launch_rounded
                          : Icons.arrow_forward_rounded,
                      onPressed: () {
                        if (_index == _pageCount - 1) {
                          _finish();
                        } else {
                          _page.nextPage(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
