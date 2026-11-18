import 'package:shared_preferences/shared_preferences.dart';

import '../diag/diag.dart';
import 'library_store.dart';

/// Calls one Supabase RPC (`library_pull` / `library_push`).
typedef LibraryRpc = Future<Object?> Function(String fn, Map<String, dynamic> params);

/// Signed-in user's library ↔ the account (8.1 / 8.2). Pull first (newest
/// wins on the phone), then push what changed here since the last push —
/// the first sync after signing up uploads the guest's whole library.
/// Batches of ≤300 titles; only the user's own rows (RLS on the server).
class LibrarySync {
  LibrarySync({required this.store, required this.prefs, required this.rpc});

  final LibraryStore store;
  final SharedPreferences prefs;
  final LibraryRpc rpc;

  static const batch = 300;
  bool _running = false;

  String _pushedKey(String panel, String user) => 'xp.lib_pushed.$user.$panel';
  String _pulledKey(String panel, String user) => 'xp.lib_pulled.$user.$panel';

  /// One round for [panelKey] (panel type + host) and the signed-in [userId].
  Future<({int pulled, int pushed})> sync(String panelKey, String userId) async {
    if (_running) return (pulled: 0, pushed: 0);
    _running = true;
    final sw = Stopwatch()..start();
    try {
      // 1. Pull what changed on other devices.
      final pulledAt = prefs.getString(_pulledKey(panelKey, userId));
      final raw = await rpc('library_pull', {'p_panel': panelKey, 'p_since': pulledAt});
      final rows = [
        if (raw is List)
          for (final r in raw)
            if (r is Map) Map<String, dynamic>.from(r),
      ];
      final pulled = await store.applyRemote(rows);
      final newest = rows.map((r) => '${r['at'] ?? ''}').where((s) => s.isNotEmpty).fold<String?>(
          pulledAt, (a, b) => a == null || DateTime.parse(b).isAfter(DateTime.parse(a)) ? b : a);
      if (newest != null) await prefs.setString(_pulledKey(panelKey, userId), newest);

      // 2. Push what changed here (everything the first time).
      final pushedAt = DateTime.tryParse(prefs.getString(_pushedKey(panelKey, userId)) ?? '');
      final changes = store.changesSince(pushedAt);
      var pushed = 0;
      for (var i = 0; i < changes.length; i += batch) {
        final part = changes.sublist(i, i + batch > changes.length ? changes.length : i + batch);
        final n = await rpc('library_push', {'p_panel': panelKey, 'p_items': part});
        pushed += n is int ? n : 0;
      }
      if (changes.isNotEmpty) {
        await prefs.setString(_pushedKey(panelKey, userId), '${changes.first['at']}');
      }
      if (pulled > 0 || pushed > 0 || pushedAt == null) {
        Diag.event('LIBRARY', 'account sync in ${sw.elapsedMilliseconds}ms: $pulled titles from the account, '
            '$pushed sent${pushedAt == null ? ' (first sync: whole device library)' : ''}');
      }
      return (pulled: pulled, pushed: pushed);
    } finally {
      _running = false;
    }
  }
}
