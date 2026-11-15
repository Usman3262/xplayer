import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'panels.dart';
import 'remote_config.dart';

/// The on-device catalog of the user's panels (Phase 6): the store screens
/// read from, and the background sync that fills it.
///
/// Sync runs: after the start-up panel check, right after a panel is
/// connected, and when the app comes back to the foreground (fresh
/// categories are skipped, so this is cheap). It pauses when the app goes to
/// the background and continues where it stopped.
class CatalogService {
  CatalogService._();

  static CatalogStore? _store;
  static CatalogSyncer? _syncer;
  static Set<String> _knownPanels = {};
  static bool _paused = false;

  static CatalogStore get store => _store ??= CatalogStore.open();

  static CatalogSyncer get syncer {
    final s = _syncer ??= CatalogSyncer(store: store, policy: SyncPolicy.fromConfig(RemoteConfigService.current));
    s.policy = SyncPolicy.fromConfig(RemoteConfigService.current); // admin changes apply
    return s;
  }

  /// Test hooks (in-memory database).
  @visibleForTesting
  static void useStore(CatalogStore s) {
    _store = s;
    _syncer = null;
  }

  /// A removed panel's catalog goes with it (any running sync stops first).
  static Future<void> clearPanel(String panelId) async {
    _syncer?.cancel(panelId, reason: 'panel removed');
    await store.clearPanel(panelId);
  }

  /// Watches the panel list: a newly connected panel is synced at once.
  static void init() {
    final conns = PanelsService.manager.connections;
    _knownPanels = {for (final c in conns.value) c.id};
    conns.addListener(() {
      final now = {for (final c in conns.value) c.id};
      final added = now.difference(_knownPanels);
      _knownPanels = now;
      for (final id in added) {
        syncPanel(id);
      }
    });
  }

  /// Syncs every switched-on, working panel, main panel first, one after
  /// another (panels each get their own polite request budget).
  static Future<void> syncAll({bool force = false}) async {
    if (_paused) return;
    final panels = PanelsService.manager.connections.value
        .where((c) => c.enabled && c.status.isUsable)
        .toList()
      ..sort((a, b) => a.isPrimary == b.isPrimary ? 0 : (a.isPrimary ? -1 : 1));
    for (final c in panels) {
      if (_paused) return;
      await syncPanel(c.id, force: force);
    }
  }

  static Future<void> syncPanel(String panelId, {bool force = false}) async {
    if (_paused) return;
    final m = PanelsService.manager;
    final adapter = await m.adapterFor(panelId);
    if (adapter == null) return;
    final r = await syncer.sync(panelId, adapter, force: force);
    if (r.phase == SyncPhase.done) await m.markSynced(panelId);
    if (r.phase == SyncPhase.failed && r.failure != null) {
      // Login / expiry problems show on the panel (My panels) right away.
      await m.recheck(panelId);
    }
  }

  /// App to background: stop downloading; resumes later where it stopped.
  static void pause() {
    _paused = true;
    _syncer?.cancelAll(reason: 'app in background');
  }

  static void resume() {
    _paused = false;
    syncAll();
  }
}

/// Sync progress per panel, for screens (e.g. a small "updating…" hint).
final catalogSyncProvider = Provider<Map<String, SyncProgress>>((ref) {
  final l = CatalogService.syncer.progress;
  void listener() => ref.invalidateSelf();
  l.addListener(listener);
  ref.onDispose(() => l.removeListener(listener));
  return l.value;
});
