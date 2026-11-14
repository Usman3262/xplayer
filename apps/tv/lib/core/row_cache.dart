import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Last rows of the Movies / Series pages saved on the TV (client 6 Nov:
/// "sections take a very long time to load"; LG shows its saved rows at once
/// and refreshes them behind). Only what a row shows is kept: no stream URLs,
/// no account data. Per profile and section; a fresh copy replaces each row
/// as soon as it arrives.
class RowCache {
  RowCache._();

  static const _maxAge = Duration(hours: 12);

  static String _key(String profileId, String section) => 'app_rows_${section}_$profileId';

  static Map<String, Object?> _item(MediaItem m) => {
        'id': m.id,
        't': m.title,
        if (m.titleArabic != null) 'ta': m.titleArabic,
        'k': m.kind.name,
        if (m.year != null) 'y': m.year,
        if (m.rating != null) 'r': m.rating,
        if (m.durationLabel != null) 'd': m.durationLabel,
        if (m.genres.isNotEmpty) 'g': m.genres,
        if (m.badges.isNotEmpty) 'b': m.badges,
        if (m.isLive) 'l': true,
        if (m.posterUrl != null) 'p': m.posterUrl,
        if (m.backdropUrl != null) 'bd': m.backdropUrl,
        if (m.containerExtension != null) 'c': m.containerExtension,
        if (m.categoryId != null) 'cat': m.categoryId,
        if (m.seriesId != null) 's': m.seriesId,
      };

  static MediaItem? _parse(Object? o) {
    if (o is! Map) return null;
    final id = o['id'], t = o['t'], k = o['k'];
    if (id is! String || t is! String || k is! String) return null;
    final kind = MediaKind.values.where((e) => e.name == k).firstOrNull;
    if (kind == null) return null;
    List<String> strs(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];
    final y = o['y'], r = o['r'];
    return MediaItem(
      id: id,
      title: t,
      titleArabic: o['ta'] as String?,
      kind: kind,
      year: y is int ? y : null,
      rating: r is num ? r.toDouble() : null,
      durationLabel: o['d'] as String?,
      genres: strs(o['g']),
      badges: strs(o['b']),
      isLive: o['l'] == true,
      posterUrl: o['p'] as String?,
      backdropUrl: o['bd'] as String?,
      containerExtension: o['c'] as String?,
      categoryId: o['cat'] as String?,
      seriesId: o['s'] as String?,
    );
  }

  /// Saved rows by category id (with totals), or empty when none / too old.
  static Future<({Map<String, List<MediaItem>> rows, Map<String, int> totals})> load(
    String profileId,
    String section,
  ) async {
    const empty = (rows: <String, List<MediaItem>>{}, totals: <String, int>{});
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(profileId, section));
      if (raw == null) return empty;
      final j = jsonDecode(raw);
      if (j is! Map) return empty;
      final at = DateTime.tryParse('${j['at']}');
      if (at == null || DateTime.now().difference(at) > _maxAge) return empty;
      final rows = <String, List<MediaItem>>{};
      final totals = <String, int>{};
      final r = j['rows'];
      if (r is Map) {
        r.forEach((cat, list) {
          if (cat is! String || list is! List) return;
          final items = [for (final o in list) ?_parse(o)];
          if (items.isNotEmpty) rows[cat] = items;
        });
      }
      final tt = j['totals'];
      if (tt is Map) {
        tt.forEach((cat, n) {
          if (cat is String && n is int) totals[cat] = n;
        });
      }
      return (rows: rows, totals: totals);
    } catch (_) {
      return empty;
    }
  }

  /// Saves the rows now on screen (first [perRow] items of each).
  static Future<void> save(
    String profileId,
    String section,
    Map<String, List<MediaItem>> rows,
    Map<String, int> totals, {
    int perRow = 10,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(profileId, section),
        jsonEncode({
          'at': DateTime.now().toIso8601String(),
          'rows': {
            for (final e in rows.entries)
              e.key: [for (final m in e.value.take(perRow)) _item(m)],
          },
          'totals': totals,
        }),
      );
    } catch (_) {
      // A missing cache only means the rows load from the server.
    }
  }
}
