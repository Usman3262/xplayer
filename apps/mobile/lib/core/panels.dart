import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog.dart';
import 'remote_config.dart';
import 'session_controller.dart';

/// The user's IPTV panels on this device (Xtream / M3U / Stalker), on top of
/// `ConnectionManager` from packages/data. Adapters use the limits and live
/// format from the admin config; a new config re-registers them.
class PanelsService {
  PanelsService._();

  static ConnectionManager? _manager;

  static ConnectionManager get manager => _manager ??= ConnectionManager(
        config: () => RemoteConfigService.current,
        onRemoved: CatalogService.clearPanel,
      );

  /// Test hook: use a manager with fake adapters / storage.
  @visibleForTesting
  static void useManager(ConnectionManager m) => _manager = m;

  /// Call once in main() after RemoteConfigService.init: loads the saved
  /// panels (no network), then re-checks them after the first frame.
  static Future<void> init() async {
    registerProviderAdapters(RemoteConfigService.current);
    RemoteConfigService.listenable.addListener(
      () => registerProviderAdapters(RemoteConfigService.current),
    );
    await manager.load();
    // Spec §3.5: never assume a panel is still active. Not blocking start.
    Future<void>.delayed(const Duration(seconds: 2), manager.recheckAll);
  }

  /// At least one panel is switched on → the app can open Home.
  static bool get hasPanel => manager.connections.value.any((c) => c.enabled);
}

/// Saved panels for widgets; rebuilds when one is added/changed/removed.
final panelsProvider = Provider<List<PanelConnection>>((ref) {
  final l = PanelsService.manager.connections;
  void listener() => ref.invalidateSelf();
  l.addListener(listener);
  ref.onDispose(() => l.removeListener(listener));
  return l.value;
});

/// UI language for the panel screens (session language). Separate so the
/// screens can be tested without starting the session.
final panelUiLanguageProvider = Provider<String>(
  (ref) => ref.watch(sessionProvider.select((s) => s.language)),
);
