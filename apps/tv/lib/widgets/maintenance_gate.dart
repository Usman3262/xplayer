import 'package:design_system/design_system.dart' show AppColors;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/remote_config.dart';

/// Shows the admin's maintenance message (App customization → Versions &
/// maintenance) instead of the app while a window is active for this platform.
/// Uses the app's own colours; no new design. Lifts itself when the window ends.
class MaintenanceGate extends ConsumerWidget {
  const MaintenanceGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(remoteConfigProvider).maintenance;
    final ended = m?.until != null && !m!.until!.isAfter(DateTime.now());
    if (m == null || ended) {
      return child;
    }
    final until = m.until == null
        ? null
        : TimeOfDay.fromDateTime(m.until!.toLocal()).format(context);

    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.construction_rounded,
                    size: 56,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    m.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    m.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (until != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '≈ $until',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    autofocus: true, // TV remote lands here
                    onPressed: () => RemoteConfigService.refresh(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
