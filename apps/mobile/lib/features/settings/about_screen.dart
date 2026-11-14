import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppLogo(height: 88, alignToStart: true),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              copy.aboutAppName,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ),
          const SizedBox(height: 6),
          // The installed version and build, never a fixed label.
          if (ref.watch(appVersionBuildProvider).valueOrNull case final v?)
            Center(child: TechBadge(copy.aboutVersionBadge(v))),
          const SizedBox(height: 12),
          Text(
            copy.mediaPlayerOnlyNotice,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _navCard(
            context,
            title: copy.termsOfUse,
            subtitle: copy.termsSubtitle,
            route: '/settings/terms',
          ),
          _navCard(
            context,
            title: copy.privacyPolicy,
            subtitle: copy.privacySubtitle,
            route: '/settings/privacy',
          ),
          const SizedBox(height: 20),
          Text(
            copy.copyrightLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: copy.replayOnboarding,
            filled: false,
            icon: Icons.slideshow_rounded,
            onPressed: () async {
              await ref.read(sessionProvider.notifier).resetOnboarding();
              if (context.mounted) context.go('/onboarding');
            },
          ),
        ],
      ),
    );
  }

  Widget _navCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        ),
      ),
    );
  }
}
