import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/demo_mode.dart';
import '../../core/session_controller.dart';
import '../../core/ui_sound.dart';
import '../../widgets/main_app_bar.dart';

// Demo mode runs the real app (same screens, layouts and player) over
// [DemoContent]. Only these two small pages are demo-specific: the sign-in
// gate for account-only pages and the licence credits. Both use the
// settings page styles.

/// Shown instead of an account-only page (profiles, downloads, devices,
/// subscription, security, ...) while in demo.
class DemoSignInScreen extends ConsumerWidget {
  const DemoSignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppAtmosphere(
        intensity: 0.7,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NeonGlowIcon(
                  Icons.lock_person_rounded,
                  size: 48,
                  color: AppColors.cyan,
                ),
                const SizedBox(height: 16),
                Text(
                  copy.demoSignInTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  copy.demoSignInBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: copy.exitDemoSignIn,
                  icon: Icons.login_rounded,
                  onPressed: () {
                    playUiTap(ref);
                    exitDemo(ref);
                    context.go('/connect');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Licence credits for every demo title (reachable from Settings and the
/// details pages while in demo).
class DemoCreditsScreen extends ConsumerWidget {
  const DemoCreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: AppAtmosphere(
        intensity: 0.7,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              copy.demoCredits,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              copy.demoCreditsIntro,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            for (final c in DemoContent.credits.values)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.creditLine,
                      style: TextStyle(color: AppColors.cyan),
                    ),
                    const SizedBox(height: 4),
                    _Link(label: c.licenceUrl),
                    Text(
                      c.source,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(label);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

/// Credit line on the real details page while in demo ("© Blender
/// Foundation · CC BY 3.0"); taps open the credits. Nothing outside demo.
class DemoCreditLine extends ConsumerWidget {
  const DemoCreditLine({super.key, required this.id});

  /// Demo title id; a title without its own credit (the demo series) links
  /// to the full credits list.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoModeProvider)) return const SizedBox.shrink();
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    final credit = DemoContent.credits[id];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => context.push(demoCreditsRoute),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                credit?.creditLine ?? copy.demoCredits,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
