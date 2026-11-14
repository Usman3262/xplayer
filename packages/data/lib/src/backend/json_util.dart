// Small helpers shared by the backend contract models. Everything is tolerant:
// a missing or wrongly typed field becomes null/empty, never an exception
// (rule: invalid remote data must never crash the app).

import '../remote/json_read.dart';

Map<String, dynamic> jsonMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const <String, dynamic>{};

List<Map<String, dynamic>> jsonMapList(Object? v) =>
    v is List ? v.whereType<Map>().map(jsonMap).toList() : const [];

List<String> jsonStrList(Object? v) =>
    v is List ? v.map(jsonStr).whereType<String>().toList() : const [];

DateTime? jsonDate(Object? v) {
  final s = jsonStr(v);
  return s == null ? null : DateTime.tryParse(s);
}

/// Enum by wire name; unknown values → [fallback] (newer server, older app).
T jsonEnum<T extends Enum>(Object? v, List<T> values, T fallback) {
  final s = jsonStr(v);
  if (s == null) return fallback;
  for (final e in values) {
    if (e.name == s) return e;
  }
  return fallback;
}

/// Semantic version compare ("6.0.36+145" → 6.0.36). Same rules as SQL `version_cmp`.
int compareAppVersion(String a, String b) {
  List<int> parts(String v) {
    final core = v.split('+').first.replaceAll(RegExp(r'[^0-9.]'), '');
    final p = core.split('.');
    return List.generate(3, (i) => i < p.length ? int.tryParse(p[i]) ?? 0 : 0);
  }

  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}
