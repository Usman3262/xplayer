import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/catalog.dart';
import '../core/panels.dart';

/// How many titles the main panel has on this device (refreshes with the
/// catalog revision: 3× per sync).
final _catalogCountsProvider = FutureProvider.autoDispose<CatalogCounts?>((ref) async {
  ref.watch(catalogRevisionProvider);
  final panel = ref.watch(panelsProvider).where((c) => c.isPrimary && c.enabled).firstOrNull;
  if (panel == null) return null;
  return CatalogService.store.counts(panel.id);
});

/// Thin bar above the navigation: how much of the panel's catalog is on the
/// device, sync progress while it runs, and a refresh button (forced sync).
class CatalogSyncBar extends ConsumerWidget {
  const CatalogSyncBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelsProvider).where((c) => c.isPrimary && c.enabled).firstOrNull;
    if (panel == null) return const SizedBox.shrink();
    final copy = AppCopy.ofLanguage(ref.watch(panelUiLanguageProvider));
    final p = ref.watch(catalogSyncProvider)[panel.id];
    final counts = ref.watch(_catalogCountsProvider).valueOrNull;
    final titles = counts == null ? 0 : counts.movies + counts.series + counts.live;
    final running = p?.running ?? false;
    final pct = running && p!.phase == SyncPhase.items && p.total > 0 ? (p.done / p.total).clamp(0.0, 1.0) : null;

    final String label;
    if (running) {
      label = pct == null ? copy.syncPreparing : copy.syncLoading((pct * 100).round(), titles);
    } else if (p?.phase == SyncPhase.failed || (p?.phase == SyncPhase.stopped && (p?.failedCategories ?? 0) > 0)) {
      label = copy.syncPanelNotAnswering;
    } else {
      label = copy.syncUpToDate(titles);
    }

    return Container(
      key: const Key('catalog-sync-bar'),
      color: AppColors.surface.withValues(alpha: 0.92),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(running ? Icons.cloud_download_outlined : Icons.check_circle_outline_rounded,
                  size: 15, color: running ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                key: const Key('catalog-refresh'),
                tooltip: copy.syncRefresh,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: running
                    ? null
                    : () {
                        if (CatalogService.refreshCooldownLeft(panel.id) != null) {
                          Diag.event('SYNC', 'refresh tapped: refreshed moments ago, nothing downloaded');
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(content: Text(copy.syncJustRefreshed)));
                          return;
                        }
                        Diag.event('SYNC', 'refresh tapped by the user');
                        CatalogService.syncPanel(panel.id, force: true);
                      },
                icon: Icon(Icons.refresh_rounded, color: running ? AppColors.textSecondary : AppColors.primary),
              ),
            ],
          ),
          if (running)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct, // null while categories load → moving bar
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.border,
              ),
            ),
        ],
      ),
    );
  }
}
