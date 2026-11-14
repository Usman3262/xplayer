import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tv_locale.dart';
import '../../widgets/focus_tile.dart';
import 'tv_security_scaffold.dart';

class TvSecurityScreen extends ConsumerWidget {
  const TvSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    return TvSecurityScaffold(
      title: copy.security,
      subtitle: 'MFA, sessions, and devices — same account as mobile.',
      child: ListView(
        children: [
          _row(
            context,
            icon: Icons.phonelink_lock_rounded,
            title: copy.mfaTitle,
            subtitle: copy.mfaSubtitleSetup,
            route: '/settings/security/mfa',
            autofocus: true,
          ),
          _row(
            context,
            icon: Icons.devices_other_rounded,
            title: copy.sessionsTitle,
            subtitle: copy.sessionsNavSubtitle,
            route: '/settings/security/sessions',
          ),
          _row(
            context,
            icon: Icons.smartphone_rounded,
            title: copy.devices,
            subtitle: copy.devicesRegisteredShort,
            route: '/settings/devices',
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusTile(
        autofocus: autofocus,
        borderRadius: 14,
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0C101A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.cyan),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
