import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local Netflix-style library: My List, CW, downloads, reminders, ratings.
///
/// Prefs store ids and progress only. Catalog metadata comes from the API
/// (see app [LibraryController.syncFromRemote]); local resolve does not use
/// mock catalog rows.
class LibraryStore {
  LibraryStore(this._prefs);

  final SharedPreferences _prefs;

  static const _myListKey = 'app_my_list';
  static const _progressKey = 'app_progress';
  static const _downloadsKey = 'app_downloads';
  static const _remindersKey = 'app_reminders';
  static const _ratingsKey = 'app_ratings';
  static const _seededKey = 'app_library_seeded';

  /// Marks the store initialized. Does not seed sample catalog ids.
  Future<void> ensureSeeded() async {
    if (_prefs.getBool(_seededKey) == true) return;
    await _prefs.setBool(_seededKey, true);
  }

  List<String> get myListIds =>
      List<String>.from(_prefs.getStringList(_myListKey) ?? const []);

  bool isInMyList(String id) => myListIds.contains(id);

  Future<void> toggleMyList(String id) async {
    final list = myListIds;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.insert(0, id);
    }
    await _prefs.setStringList(_myListKey, list);
  }

  Future<void> addToMyList(String id) async {
    final list = myListIds;
    if (list.contains(id)) return;
    list.insert(0, id);
    await _prefs.setStringList(_myListKey, list);
  }

  Future<void> removeFromMyList(String id) async {
    final list = myListIds..remove(id);
    await _prefs.setStringList(_myListKey, list);
  }

  Map<String, double> get progressMap {
    final raw = _prefs.getStringList(_progressKey) ?? const [];
    final map = <String, double>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length != 2) continue;
      final v = double.tryParse(parts[1]);
      if (v == null) continue;
      map[parts[0]] = v.clamp(0.0, 1.0);
    }
    return map;
  }

  double progressFor(String id) => progressMap[id] ?? 0;

  Future<void> setProgress(String id, double progress) async {
    final map = progressMap;
    final p = progress.clamp(0.0, 0.98);
    if (p < 0.02) {
      map.remove(id);
    } else {
      map[id] = p;
    }
    await _writeProgress(map);
  }

  Future<void> _writeProgress(Map<String, double> map) async {
    final list = map.entries.map((e) => '${e.key}|${e.value}').toList();
    await _prefs.setStringList(_progressKey, list);
  }

  List<String> get downloadIds =>
      List<String>.from(_prefs.getStringList(_downloadsKey) ?? const []);

  bool isDownloaded(String id) => downloadIds.contains(id);

  Future<void> toggleDownload(String id) async {
    final list = downloadIds;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.insert(0, id);
    }
    await _prefs.setStringList(_downloadsKey, list);
  }

  // --- Reminders (Coming Soon / New) ---

  List<String> get reminderIds =>
      List<String>.from(_prefs.getStringList(_remindersKey) ?? const []);

  bool hasReminder(String id) => reminderIds.contains(id);

  Future<void> toggleReminder(String id) async {
    final list = reminderIds;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.insert(0, id);
    }
    await _prefs.setStringList(_remindersKey, list);
  }

  // --- Thumbs rating: 1 = up, -1 = down, 0 = none ---

  Map<String, int> get ratingsMap {
    final raw = _prefs.getStringList(_ratingsKey) ?? const [];
    final map = <String, int>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length != 2) continue;
      final v = int.tryParse(parts[1]);
      if (v == null) continue;
      map[parts[0]] = v;
    }
    return map;
  }

  int ratingFor(String id) => ratingsMap[id] ?? 0;

  Future<void> setRating(String id, int rating) async {
    final map = ratingsMap;
    if (rating == 0 || rating == map[id]) {
      map.remove(id);
    } else {
      map[id] = rating.clamp(-1, 1);
    }
    final list = map.entries.map((e) => '${e.key}|${e.value}').toList();
    await _prefs.setStringList(_ratingsKey, list);
  }

  /// Ids alone cannot hydrate posters/titles; API sync owns list UI.
  List<MediaItem> resolveItems(Iterable<String> ids) => const [];

  List<MediaItem> myListItems() => resolveItems(myListIds);

  List<MediaItem> continueWatchingItems() {
    final entries = progressMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return resolveItems(entries.map((e) => e.key));
  }

  List<MediaItem> downloadItems() => resolveItems(downloadIds);

  List<MediaItem> reminderItems() => resolveItems(reminderIds);

  List<MediaItem> likedItems() {
    final ids =
        ratingsMap.entries.where((e) => e.value == 1).map((e) => e.key);
    return resolveItems(ids);
  }
}
