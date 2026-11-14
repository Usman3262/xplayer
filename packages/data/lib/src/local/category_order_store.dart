import 'package:shared_preferences/shared_preferences.dart';

import '../remote/extras_api.dart';

/// Package order per profile and section (live | vod | series), client
/// 17 Oct. Saved on the device at once (instant, works offline) and on the
/// server, so it follows the profile to the user's other devices and to
/// the next sign-in.
class CategoryOrderStore {
  CategoryOrderStore(this._api);

  final ExtrasApi _api;

  static String _key(String profileId, String section) =>
      'app.catorder.$profileId.$section';

  /// Set while this device's order has not reached the server yet. Without
  /// it, a failed save was overwritten by the server's older order on the
  /// next load and the new order "did not save" (client 18 Oct TV #1).
  static String _dirtyKey(String profileId, String section) =>
      'app.catorder.dirty.$profileId.$section';

  /// Device copy first; the server copy replaces it when it exists.
  Future<List<String>> load(String profileId, String section) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList(_key(profileId, section)) ?? const [];
    if (prefs.getBool(_dirtyKey(profileId, section)) ?? false) {
      try {
        if (await _api.saveCategoryOrder(profileId, section, local)) {
          await prefs.remove(_dirtyKey(profileId, section));
        }
      } catch (_) {}
      return local;
    }
    try {
      final remote = await _api.categoryOrder(profileId, section);
      if (remote == null) return local; // server without the route
      if (remote.isEmpty && local.isNotEmpty) {
        // First use with the new server: upload this device's order.
        await _api.saveCategoryOrder(profileId, section, local);
        return local;
      }
      await prefs.setStringList(_key(profileId, section), remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<void> save(
    String profileId,
    String section,
    List<String> categoryIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(profileId, section), categoryIds);
    await prefs.setBool(_dirtyKey(profileId, section), true);
    try {
      if (await _api.saveCategoryOrder(profileId, section, categoryIds)) {
        await prefs.remove(_dirtyKey(profileId, section));
      }
    } catch (_) {
      // Kept on the device; uploaded by the next load.
    }
  }
}
