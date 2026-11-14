import 'package:shared_preferences/shared_preferences.dart';

/// Category of each favourited channel, kept on the device (client 21 Oct:
/// Live TV and Sports favourites were mixed). Server favourites carry no
/// category, so a channel without "sport" in its name (ALWAN F1, SSC, beIN
/// 1) was put under Live TV. Recorded when the favourite is added, where the
/// channel row still knows its category.
abstract final class FavoriteCategories {
  static const _key = 'app_fav_categories_v1';
  static final Map<String, String> _map = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    for (final e in prefs.getStringList(_key) ?? const <String>[]) {
      final i = e.indexOf('|');
      if (i > 0) _map[e.substring(0, i)] = e.substring(i + 1);
    }
    _loaded = true;
  }

  static String? categoryOf(String id) => _map[id];

  static Future<void> remember(String id, String? categoryId) async {
    if (categoryId == null || categoryId.isEmpty) return;
    if (_map[id] == categoryId) return;
    _map[id] = categoryId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final e in _map.entries) '${e.key}|${e.value}']);
  }
}
