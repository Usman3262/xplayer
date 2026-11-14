import 'package:domain/domain.dart';

/// The provider lists 4K and HD copies of a movie as separate titles
/// ("4K-AR: صقر وكناريا" and "AR: صقر وكناريا"). On a device whose video
/// chip cannot decode 4K (Infinix: max 2560×1440, client 20 Oct), the
/// player offers the HD copy instead of a dead end.
bool isUhdItem(MediaItem m) =>
    m.badges.any((b) => b.toUpperCase().contains('4K') || b.toUpperCase().contains('UHD')) ||
    RegExp(r'\b(4K|UHD|2160p)\b', caseSensitive: false).hasMatch(m.title);

/// Title without quality / country prefixes, for matching copies.
String comparableTitle(String t) => t
    .replaceAll(RegExp(r'^\s*(4K|UHD|8K)[-\s|:]*', caseSensitive: false), '')
    .replaceAll(RegExp(r'^\s*[A-Z]{2,4}\s*[:|-]\s*'), '')
    .replaceAll(RegExp(r'\b(4K|UHD|2160p|1080p|HD|FHD)\b', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Picks the non-4K copy of [item] from [candidates] (a catalog search by
/// title). Null when there is none.
MediaItem? pickHdAlternative(MediaItem item, List<MediaItem> candidates) {
  final want = comparableTitle(item.title);
  if (want.isEmpty) return null;
  for (final c in candidates) {
    if (c.id == item.id || c.kind != item.kind || isUhdItem(c)) continue;
    if (comparableTitle(c.title) == want) return c;
  }
  return null;
}

Future<MediaItem?> findHdAlternative(CatalogRepository catalog, MediaItem item) async {
  final q = comparableTitle(item.title);
  if (q.isEmpty) return null;
  try {
    final found = await catalog.search(q, kind: item.kind).timeout(const Duration(seconds: 8));
    return pickHdAlternative(item, found);
  } catch (_) {
    return null;
  }
}
