import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_log.dart';
import '../../core/demo_mode.dart';
import '../../core/panels.dart';
import '../../core/remote_config.dart';
import '../../core/session_controller.dart';
import '../auth/login_screen.dart' show LoginGlow, LoginRoundIconBtn;
import 'panel_copy.dart';

/// First step after the splash: pick the kind of IPTV panel to connect.
/// Same look as the sign-in screen (glow, logo, glass card).
class ChoosePanelScreen extends ConsumerWidget {
  const ChoosePanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(panelUiLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final options = panelOptions(ref.watch(remoteConfigProvider), copy);
    final hasPanel = ref.watch(panelsProvider).any((c) => c.enabled);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LoginGlow(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      if (hasPanel || context.canPop())
                        LoginRoundIconBtn(
                          icon: const AppBackIcon(size: 18, style: AppBackIconStyle.chevron),
                          onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                        ),
                      const Spacer(),
                      AppLanguageToggle(
                        language: language,
                        onChanged: (v) => ref.read(sessionProvider.notifier).setLanguage(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Center(child: AppLogo(height: 44, alignToStart: false))
                    .animate()
                    .fadeIn(duration: 400.ms),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    children: [
                      Text(
                        copy.choosePanelTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        copy.choosePanelBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      for (var i = 0; i < options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PanelTypeCard(
                            option: options[i],
                            onTap: () {
                              AppLog.tap('connect.choose', data: {'kind': options[i].kind.name});
                              context.push('/connect/${options[i].kind.name}');
                            },
                          ).animate().fadeIn(delay: (80 * i).ms).slideY(begin: 0.08, end: 0),
                        ),
                      if (!hasPanel) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              AppLog.tap('connect.try_demo');
                              ref.read(demoModeProvider.notifier).state = true;
                              context.go('/home');
                            },
                            icon: Icon(Icons.play_circle_outline_rounded, color: AppColors.textSecondary),
                            label: Text(copy.tryDemo, style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        ),
                      ],
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

class _PanelTypeCard extends StatelessWidget {
  const _PanelTypeCard({required this.option, required this.onTap});

  final PanelOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: AppColors.surface.withValues(alpha: 0.8),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(option.icon, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          option.subtitle,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
