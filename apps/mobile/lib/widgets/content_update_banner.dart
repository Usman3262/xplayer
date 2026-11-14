import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/catalog_sync.dart';
import '../core/session_controller.dart';

/// "New content available" card over every screen while a newer package
/// catalog is waiting. Refresh reloads the lists; Later hides it until the
/// next change.
class ContentUpdateBanner extends ConsumerWidget {
  const ContentUpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(contentUpdatePendingProvider);
    final copy = AppCopy.ofLanguage(
      ref.watch(sessionProvider.select((s) => s.language)),
    );
    return Stack(
      children: [
        child,
        if (pending)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom + 64,
            child: Material(
              color: AppColors.surfaceElevated,
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(Icons.fiber_new_rounded, color: AppColors.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            copy.contentUpdateTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            copy.contentUpdateBody,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(contentUpdatePendingProvider.notifier)
                          .state = false,
                      child: Text(copy.contentUpdateLater),
                    ),
                    FilledButton(
                      onPressed: () => refreshCatalogNow(ref),
                      child: Text(copy.contentUpdateRefresh),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
