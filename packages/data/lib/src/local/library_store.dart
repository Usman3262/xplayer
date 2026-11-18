import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local Netflix-style library: My List, CW, downloads, reminders, ratings.
///
/// Lists hold ids; a small copy of each saved title (name, poster, kind,
/// series, position) is kept next to them, so My List / Continue Watching
/// show after an app restart without any server — guests keep everything
/// on the phone (Phase 8: the same copies sync to the account).
class LibraryStore {
  LibraryStore(this._prefs);

  final SharedPreferences _prefs;

  static const _myListKey = 'app_my_list';
  static const _progressKey = 'app_progress';
  static const _downloadsKey = 'app_downloads';
  static const _remindersKey = 'app_reminders';
  static const _ratingsKey = 'app_ratings';
  static const _seededKey = 'app_library_seeded';
  static const _itemsKey = 'app_library_items_v1';

  /// Most saved titles kept (oldest unused copies dropped).
  static const maxItems = 600;

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
    await _touch(id);
  }

  Future<void> addToMyList(String id) async {
    final list = myListIds;
    if (list.contains(id)) return;
    list.insert(0, id);
    await _prefs.setStringList(_myListKey, list);
    await _touch(id);
  }

  Future<void> removeFromMyList(String id) async {
    final list = myListIds..remove(id);
    await _prefs.setStringList(_myListKey, list);
    await _touch(id);
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
    await _touch(id);
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
    await _touch(id);
  }

  // ── Saved copies of titles ─────────────────────────────────────────────

  Map<String, Map<String, dynamic>> get _items {
    final raw = _prefs.getString(_itemsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {}; // a broken copy never breaks the library
    }
  }

  /// When the title was last saved / watched (newest first in lists).
  DateTime? savedAt(String id) {
    final at = _items[id]?['at'];
    return at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null;
  }

  /// Keeps (or refreshes) the copy of [item]; position / duration in s.
  Future<void> remember(MediaItem item, {int? positionSec, int? durationSec}) async {
    final title = item.title.trim();
    if (item.id.isEmpty) return;
    final all = _items;
    final old = all[item.id] ?? const <String, dynamic>{};
    all[item.id] = {
      'title': title.isNotEmpty ? title : (old['title'] ?? ''),
      'kind': item.kind.name,
      if (item.subtitle != null) 'sub': item.subtitle else if (old['sub'] != null) 'sub': old['sub'],
      if ((item.posterUrl ?? old['poster']) != null) 'poster': item.posterUrl ?? old['poster'],
      if ((item.backdropUrl ?? old['backdrop']) != null) 'backdrop': item.backdropUrl ?? old['backdrop'],
      if ((item.seriesId ?? old['series']) != null) 'series': item.seriesId ?? old['series'],
      if ((item.categoryId ?? old['cat']) != null) 'cat': item.categoryId ?? old['cat'],
      if ((item.containerExtension ?? old['ext']) != null) 'ext': item.containerExtension ?? old['ext'],
      if (item.year != null) 'year': item.year,
      if (item.isLive) 'live': true,
      'pos': positionSec ?? old['pos'],
      'dur': durationSec ?? old['dur'],
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _trim(all);
    await _prefs.setString(_itemsKey, jsonEncode(all));
    onChanged?.call();
  }

  /// Marks the title as changed now (removals included), for the account sync.
  Future<void> _touch(String id) async {
    final all = _items;
    final j = all[id];
    if (j == null) return;
    j['at'] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_itemsKey, jsonEncode(all));
    onChanged?.call();
  }

  /// Called after any change (the account sync schedules a push).
  static void Function()? onChanged;

  // ── Account sync (8.1) ─────────────────────────────────────────────────

  /// Titles changed after [since] (all when null), as rows for the server:
  /// list flags, rating, progress and the title copy. Newest first.
  List<Map<String, dynamic>> changesSince(DateTime? since) {
    final all = _items;
    final list = myListIds.toSet();
    final ratings = ratingsMap;
    final progress = progressMap;
    final out = <(int, Map<String, dynamic>)>[];
    for (final e in all.entries) {
      final at = (e.value['at'] as int?) ?? 0;
      if (since != null && at <= since.millisecondsSinceEpoch) continue;
      final j = e.value;
      out.add((at, {
        'id': e.key,
        'kind': j['kind'] ?? 'movie',
        'title': j['title'] ?? '',
        if (j['poster'] != null) 'poster': j['poster'],
        if (j['series'] != null) 'series': j['series'],
        'extra': {
          for (final k in const ['sub', 'backdrop', 'cat', 'ext', 'year', 'live'])
            if (j[k] != null) k: j[k],
        },
        'my_list': list.contains(e.key),
        'rating': ratings[e.key] ?? 0,
        'progress': progress[e.key] ?? 0,
        if (j['pos'] != null) 'pos': j['pos'],
        if (j['dur'] != null) 'dur': j['dur'],
        'at': DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).toIso8601String(),
      }));
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final x in out) x.$2];
  }

  /// Rows from the server, newest wins against what is on the phone.
  /// Returns how many titles changed here.
  Future<int> applyRemote(List<Map<String, dynamic>> rows) async {
    final all = _items;
    final list = myListIds;
    final ratings = ratingsMap;
    final progress = progressMap;
    var changed = 0;
    for (final r in rows) {
      final id = '${r['id'] ?? ''}';
      final at = DateTime.tryParse('${r['at'] ?? ''}')?.millisecondsSinceEpoch;
      if (id.isEmpty || at == null) continue;
      final local = all[id];
      if (local != null && ((local['at'] as int?) ?? 0) >= at) continue;
      final extra = r['extra'] is Map ? Map<String, dynamic>.from(r['extra'] as Map) : const <String, dynamic>{};
      all[id] = {
        'title': '${r['title'] ?? ''}'.isNotEmpty ? r['title'] : (local?['title'] ?? ''),
        'kind': r['kind'] ?? local?['kind'] ?? 'movie',
        if ((r['poster'] ?? local?['poster']) != null) 'poster': r['poster'] ?? local?['poster'],
        if ((r['series'] ?? local?['series']) != null) 'series': r['series'] ?? local?['series'],
        for (final k in const ['sub', 'backdrop', 'cat', 'ext', 'year', 'live'])
          if ((extra[k] ?? local?[k]) != null) k: extra[k] ?? local?[k],
        'pos': r['pos'] ?? local?['pos'],
        'dur': r['dur'] ?? local?['dur'],
        'at': at,
      };
      list.remove(id);
      if (r['my_list'] == true) list.insert(0, id);
      final rating = r['rating'] is int ? r['rating'] as int : 0;
      if (rating == 0) {
        ratings.remove(id);
      } else {
        ratings[id] = rating;
      }
      final p = r['progress'] is num ? (r['progress'] as num).toDouble() : 0.0;
      if (p < 0.02) {
        progress.remove(id);
      } else {
        progress[id] = p.clamp(0.0, 1.0);
      }
      changed++;
    }
    if (changed == 0) return 0;
    _trim(all);
    await _prefs.setString(_itemsKey, jsonEncode(all));
    await _prefs.setStringList(_myListKey, list);
    await _prefs.setStringList(_ratingsKey, [for (final e in ratings.entries) '${e.key}|${e.value}']);
    await _prefs.setStringList(_progressKey, [for (final e in progress.entries) '${e.key}|${e.value}']);
    return changed;
  }

  /// Copies no list uses any more go first, then the oldest.
  void _trim(Map<String, Map<String, dynamic>> all) {
    if (all.length <= maxItems) return;
    final used = {...myListIds, ...progressMap.keys, ...downloadIds, ...reminderIds, ...ratingsMap.keys};
    final order = all.keys.toList()
      ..sort((a, b) {
        final ua = used.contains(a) ? 1 : 0, ub = used.contains(b) ? 1 : 0;
        if (ua != ub) return ua - ub;
        return ((all[a]!['at'] as int?) ?? 0) - ((all[b]!['at'] as int?) ?? 0);
      });
    for (final id in order.take(all.length - maxItems)) {
      all.remove(id);
    }
  }

  MediaItem? _itemFor(String id, Map<String, Map<String, dynamic>> all) {
    final j = all[id];
    if (j == null) return null;
    final kind = MediaKind.values.where((k) => k.name == j['kind']).firstOrNull ?? MediaKind.movie;
    final pos = j['pos'] is int ? j['pos'] as int : null;
    return MediaItem(
      id: id,
      title: '${j['title'] ?? ''}',
      subtitle: j['sub'] as String?,
      kind: kind,
      isLive: j['live'] == true || kind == MediaKind.live,
      posterUrl: j['poster'] as String?,
      backdropUrl: j['backdrop'] as String?,
      seriesId: j['series'] as String?,
      categoryId: j['cat'] as String?,
      containerExtension: j['ext'] as String?,
      year: j['year'] is int ? j['year'] as int : null,
      progress: progressMap[id],
      resumePositionSec: pos,
    );
  }

  /// Saved titles for [ids], in the given order (ids without a copy are
  /// skipped — nothing to show for them).
  List<MediaItem> resolveItems(Iterable<String> ids) {
    final all = _items;
    return [for (final id in ids) ?_itemFor(id, all)];
  }

  List<MediaItem> myListItems() => resolveItems(myListIds);

  /// Started, not finished; the most recently watched first.
  List<MediaItem> continueWatchingItems() {
    final all = _items;
    int at(String id) => (all[id]?['at'] as int?) ?? 0;
    final ids = [
      for (final e in progressMap.entries)
        if (e.value < 0.95) e.key,
    ]..sort((a, b) => at(b).compareTo(at(a)));
    return resolveItems(ids);
  }

  List<MediaItem> downloadItems() => resolveItems(downloadIds);

  List<MediaItem> reminderItems() => resolveItems(reminderIds);

  List<MediaItem> likedItems() {
    final ids =
        ratingsMap.entries.where((e) => e.value == 1).map((e) => e.key);
    return resolveItems(ids);
  }
}
