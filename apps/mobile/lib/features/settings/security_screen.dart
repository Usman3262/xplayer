import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session_controller.dart';
import 'security_detail_scaffold.dart';

/// Hub: pick one security task, then open its dedicated screen.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final copy = AppCopy.ofLanguage(session.language);
    return Scaffold(
      backgroundColor: Colors.black,
      body: AppAtmosphere(
        intensity: 0.85,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
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
                  const SizedBox(width: 8),
                  const Expanded(
                    child: AppLogo(height: 44, alignToStart: true),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 18),
              TechBadge(copy.accountSecurityBadge, tone: BadgeTone.magenta),
              const SizedBox(height: 12),
              NeonGlowText(
                copy.security,
                color: AppColors.cyan,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                  letterSpacing: -0.4,
                ),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 8),
              Text(
                user == null
                    ? copy.signInToManageSecurity
                    : copy.securityStatusLine(
                        mfa: user.mfaEnabled,
                        emailVerified: true,
                      ),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SecurityNavTile(
                icon: Icons.phonelink_lock_rounded,
                title: copy.mfaTitle,
                subtitle: user?.mfaEnabled == true
                    ? copy.mfaEnabledLabel
                    : copy.mfaSubtitleSetup,
                onTap: () => context.push('/settings/security/mfa'),
              ),
              SecurityNavTile(
                icon: Icons.devices_other_rounded,
                title: copy.sessionsTitle,
                subtitle: copy.sessionsNavSubtitle,
                onTap: () => context.push('/settings/security/sessions'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
