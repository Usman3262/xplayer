import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    final async = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      body: async.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: AppShimmer.block(height: 200),
        ),
        error: (e, _) => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: copy.couldNotLoad,
          actionLabel: copy.retry,
          onAction: () => ref.invalidate(subscriptionsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text(
                copy.noActiveSubscription,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          final sub = list.first;
          final renew = _prettyDate(sub.renewsAt);
          final daysLeft = _daysRemaining(sub.renewsAt);
          final active = sub.status.toLowerCase() == 'active' ||
              sub.status.toLowerCase() == 'verified';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                copy.subscriptionPackage,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 14),
              NeonPulse(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14202B), Color(0xFF1A1208)],
                    ),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TechBadge(
                            copy.subscriptionStatusLabel(sub.status),
                            tone: BadgeTone.cyan,
                          ),
                          if (active) ...[
                            const SizedBox(width: 8),
                            TechBadge(
                              copy.badgeVerified,
                              tone: BadgeTone.gold,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.verified_rounded,
                              color: AppColors.gold,
                              size: 22,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        sub.packageName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      // Client 23 Oct round 3 #16: the name stays from the server; the
                      // label under it reads "SPORT" (was the package code "SAUDI").
                      ...[
                        const SizedBox(height: 4),
                        Text(
                          'SPORT',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (daysLeft != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          daysLeft <= 0
                              ? copy.expiresToday
                              : copy.daysRemaining(daysLeft),
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (renew != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          copy.expiresOn(renew),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (sub.sportsEnabled ||
                  sub.features
                      .map((e) => e.toLowerCase())
                      .contains('sports'))
                _perk(copy.liveSportsPackageIncluded),
              if (sub.maxDevices != null)
                _perk(copy.upToRegisteredDevices(sub.maxDevices!)),
              if (sub.maxConcurrentStreams != null)
                _perk(copy.activeStreamsAtTime(sub.maxConcurrentStreams!)),
              for (final f in sub.features)
                if (f.toLowerCase() != 'sports')
                  _perk(copy.subscriptionFeatureLabel(f)),
              const SizedBox(height: 16),
              Text(
                copy.subscriptionBillingFooter,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static int? _daysRemaining(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(dt.year, dt.month, dt.day);
    return end.difference(start).inDays;
  }

  static String? _prettyDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _perk(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.cyan, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
