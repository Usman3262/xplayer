import 'package:data/data.dart';

/// The on-device catalog of the user's panels (Phase 6). Opened lazily; the
/// sync engine (6.2) fills it, screens (Phase 7) read from it.
class CatalogService {
  CatalogService._();

  static CatalogStore? _store;

  static CatalogStore get store => _store ??= CatalogStore.open();

  /// Test hook (in-memory database).
  static void useStore(CatalogStore s) => _store = s;

  /// A removed panel's catalog goes with it.
  static Future<void> clearPanel(String panelId) => store.clearPanel(panelId);
}
