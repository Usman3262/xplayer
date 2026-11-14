/// Artwork choice (client 2 Nov): provider-hosted images often carry a large
/// burned-in "8K" logo, TMDB images are clean, so TMDB comes first.
bool isTmdbImage(String? url) =>
    url != null && url.contains('image.tmdb.org');

String? _clean(String? u) {
  final t = u?.trim();
  return (t == null || t.isEmpty || t == 'null') ? null : t;
}

/// First TMDB image among [candidates], else the first non-empty one.
String? pickCleanArt(Iterable<String?> candidates) {
  final list = [for (final c in candidates) ?_clean(c)];
  for (final u in list) {
    if (isTmdbImage(u)) return u;
  }
  return list.isEmpty ? null : list.first;
}

/// Wide art for a 16:9 slot (client 4 Nov, as LG 6.1.18): a TMDB backdrop,
/// else the poster (cropped to fill), and a provider backdrop only when there
/// is no poster at all: provider backdrops carry the large "8K" logo.
String? pickWideArt(Iterable<String?> backdrops, {String? poster}) {
  final list = [for (final c in backdrops) ?_clean(c)];
  for (final u in list) {
    if (isTmdbImage(u)) return u;
  }
  return _clean(poster) ?? (list.isEmpty ? null : list.first);
}
