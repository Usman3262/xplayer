import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/account.dart';
import '../../core/app_log.dart';
import '../../core/panels.dart';
import '../auth/login_screen.dart' show LoginGlow;

/// Shown once after the first panel connects (D17): an app account is
/// optional and only saves favorites / history / settings across devices.
class AccountOfferScreen extends ConsumerStatefulWidget {
  const AccountOfferScreen({super.key});

  @override
  ConsumerState<AccountOfferScreen> createState() => _AccountOfferScreenState();
}

class _AccountOfferScreenState extends ConsumerState<AccountOfferScreen> {
  @override
  void initState() {
    super.initState();
    AccountService.markOffered();
  }

  void _go(String route, String action) {
    AppLog.tap('account_offer.$action');
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.ofLanguage(ref.watch(panelUiLanguageProvider));
    final policy = ref.watch(accountPolicyProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LoginGlow(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Center(child: AppLogo(height: 48, alignToStart: false))
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(begin: const Offset(0.92, 0.92)),
                  const SizedBox(height: 28),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(Icons.cloud_sync_rounded, size: 40, color: AppColors.primary),
                            const SizedBox(height: 14),
                            Text(
                              copy.accountOfferTitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              copy.accountOfferBody,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                            ),
                            const SizedBox(height: 22),
                            if (policy.allowRegistration) ...[
                              PrimaryButton(
                                key: const Key('offer-create'),
                                label: copy.accountCreate,
                                icon: Icons.person_add_alt_1_rounded,
                                onPressed: () => _go('/auth/register', 'create'),
                              ),
                              const SizedBox(height: 10),
                            ],
                            PrimaryButton(
                              key: const Key('offer-signin'),
                              label: copy.signIn,
                              icon: Icons.login_rounded,
                              filled: false,
                              onPressed: () => _go('/auth/login', 'sign_in'),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              key: const Key('offer-skip'),
                              onPressed: () => _go('/home', 'not_now'),
                              child: Text(copy.accountNotNow, style: TextStyle(color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.08, end: 0),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
