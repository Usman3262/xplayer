import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_log.dart';
import '../../core/panels.dart';
import '../../core/session_controller.dart';
import '../../widgets/main_app_bar.dart';
import '../connect/panel_copy.dart';

/// Settings → My panels: status, expiry, main panel, check, on/off, rename,
/// remove, add. Same page style as the other settings pages.
class PanelsScreen extends ConsumerStatefulWidget {
  const PanelsScreen({super.key});

  @override
  ConsumerState<PanelsScreen> createState() => _PanelsScreenState();
}

class _PanelsScreenState extends ConsumerState<PanelsScreen> {
  final _checking = <String>{};

  ConnectionManager get _m => PanelsService.manager;

  Future<void> _recheck(String id) async {
    setState(() => _checking.add(id));
    await _m.recheck(id);
    if (mounted) setState(() => _checking.remove(id));
  }

  Future<void> _rename(PanelConnection c, AppCopy copy) async {
    final ctl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(copy.rename),
        content: TextField(controller: ctl, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(copy.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(copy.save)),
        ],
      ),
    );
    ctl.dispose();
    if (name != null) await _m.rename(c.id, name);
  }

  Future<void> _remove(PanelConnection c, AppCopy copy) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.name),
        content: Text(copy.removePanelConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(copy.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(copy.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AppLog.tap('panels.remove', data: {'kind': c.kind.name});
    await _m.remove(c.id);
    // Last panel gone → back to "Choose your panel".
    if (mounted && !PanelsService.hasPanel) context.go('/connect');
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(panelUiLanguageProvider);
    final copy = AppCopy.ofLanguage(language);
    final panels = ref.watch(panelsProvider);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: const MainAppBar(showBack: true),
      floatingActionButton: panels.length >= _m.maxPanels
          ? null
          : FloatingActionButton.extended(
              key: const Key('panels-add'),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
              onPressed: () => context.push('/connect'),
              icon: const Icon(Icons.add_rounded),
              label: Text(copy.addPanel),
            ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _m.recheckAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(copy.myPanels, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 16),
            if (panels.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(copy.panelsEmpty, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              ),
            for (final c in panels)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PanelCard(
                  panel: c,
                  copy: copy,
                  checking: _checking.contains(c.id),
                  expiry: c.expiresAt == null
                      ? copy.panelNoExpiry
                      : copy.panelExpiresOn(dates.formatMediumDate(c.expiresAt!.toLocal())),
                  onAction: (a) async {
                    AppLog.tap('panels.${a.name}', data: {'kind': c.kind.name});
                    switch (a) {
                      case _PanelAction.primary:
                        await _m.setPrimary(c.id);
                      case _PanelAction.check:
                        await _recheck(c.id);
                      case _PanelAction.toggle:
                        await _m.setEnabled(c.id, !c.enabled);
                        if (!context.mounted) return;
                        if (!PanelsService.hasPanel) context.go('/connect');
                      case _PanelAction.rename:
                        await _rename(c, copy);
                      case _PanelAction.remove:
                        await _remove(c, copy);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PanelAction { primary, check, toggle, rename, remove }

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.panel,
    required this.copy,
    required this.checking,
    required this.expiry,
    required this.onAction,
  });

  final PanelConnection panel;
  final AppCopy copy;
  final bool checking;
  final String expiry;
  final ValueChanged<_PanelAction> onAction;

  Color get _statusColor => switch (panel.status) {
        ConnectionStatus.active || ConnectionStatus.connected || ConnectionStatus.synchronizing => AppColors.match,
        ConnectionStatus.disabled || ConnectionStatus.removed || ConnectionStatus.pending || ConnectionStatus.connecting =>
          AppColors.textSecondary,
        ConnectionStatus.temporarilyUnavailable => AppColors.gold,
        _ => AppColors.danger,
      };

  IconData get _icon => switch (panel.kind) {
        ProviderKind.xtream => Icons.dns_rounded,
        ProviderKind.m3u => Icons.playlist_play_rounded,
        ProviderKind.stalker => Icons.router_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final status = checking ? copy.panelStatusChecking : panelStatusText(panel, copy);
    return Opacity(
      opacity: panel.enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: panel.isPrimary ? AppColors.primary.withValues(alpha: 0.6) : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          panel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      if (panel.isPrimary) ...[
                        const SizedBox(width: 8),
                        TechBadge(copy.mainPanel),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(status, style: TextStyle(color: _statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('  ·  ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Flexible(
                        child: Text(
                          expiry,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<_PanelAction>(
              icon: Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              onSelected: onAction,
              itemBuilder: (_) => [
                if (panel.enabled && !panel.isPrimary)
                  PopupMenuItem(value: _PanelAction.primary, child: Text(copy.makeMainPanel)),
                if (panel.enabled) PopupMenuItem(value: _PanelAction.check, child: Text(copy.checkPanelNow)),
                PopupMenuItem(
                  value: _PanelAction.toggle,
                  child: Text(panel.enabled ? copy.panelTurnOff : copy.panelTurnOn),
                ),
                PopupMenuItem(value: _PanelAction.rename, child: Text(copy.rename)),
                PopupMenuItem(
                  value: _PanelAction.remove,
                  child: Text(copy.remove, style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
