import '../entities/media_item.dart';
import 'weekly_picks.dart';

/// Kids home (client 21 Oct): rotating banner of the best recently added
/// titles, Continue Watching, Top 10 Kids Series, Top 10 Kids Movies.
///
/// The Top 10 rows are [WeeklyPicks]: a random 10 that stays the same from
/// Monday to Sunday (Riyadh) on every device and changes the next Monday.
class KidsHome {
  const KidsHome({
    required this.banner,
    required this.topSeries,
    required this.topMovies,
    required this.titleIds,
    required this.categoryIds,
  });

  final List<MediaItem> banner;
  final List<MediaItem> topSeries;
  final List<MediaItem> topMovies;

  /// Every kids title id seen, and the kids category ids (for Continue
  /// Watching).
  final Set<String> titleIds;
  final Set<String> categoryIds;

  static const empty = KidsHome(
    banner: [],
    topSeries: [],
    topMovies: [],
    titleIds: {},
    categoryIds: {},
  );

  /// [rails]: each kids category's titles, newest first, with its kind and
  /// category id.
  factory KidsHome.from(
    List<({MediaKind kind, String? categoryId, List<MediaItem> items})> rails, {
    required DateTime now,
    int bannerCount = 6,
  }) {
    bool art(MediaItem m) => (m.posterUrl ?? '').isNotEmpty;
    List<MediaItem> pool(MediaKind k) => [
          for (final r in rails)
            if (r.kind == k)
              for (final m in r.items)
                if (art(m)) m,
        ];
    return KidsHome(
      banner: pickRecentBest(
        [
          for (final r in rails)
            if (r.kind != MediaKind.live) r.items,
        ],
        count: bannerCount,
      ),
      topSeries: _weeklyTop(pool(MediaKind.series), now, 'kids-series'),
      topMovies: _weeklyTop(pool(MediaKind.movie), now, 'kids-movies'),
      titleIds: {
        for (final r in rails)
          for (final m in r.items) m.id,
      },
      categoryIds: {
        for (final r in rails)
          if ((r.categoryId ?? '').isNotEmpty) r.categoryId!,
      },
    );
  }

  /// Continue Watching items that belong to Kids.
  List<MediaItem> continueWatching(List<MediaItem> all) => [
        for (final m in all)
          if (titleIds.contains(m.id) ||
              (m.seriesId != null && titleIds.contains(m.seriesId)) ||
              (m.categoryId != null && categoryIds.contains(m.categoryId)))
            m,
      ];
}

/// The week's random order of [pool], then the first [count] different
/// titles: the provider lists dubbed and subtitled copies under separate ids
/// ("Puppy Dog Pals" twice in one Top 10, TCL 21 Oct).
List<MediaItem> _weeklyTop(
  List<MediaItem> pool,
  DateTime now,
  String salt, {
  int count = 10,
}) {
  final ordered = WeeklyPicks.select(
    pool,
    idOf: (m) => m.id,
    now: now,
    count: pool.length,
    salt: salt,
  );
  final titles = <String>{};
  return [
    for (final m in ordered)
      if (titles.add(_titleKey(m))) m,
  ].take(count).toList();
}

/// Same show, different copy (TCL 21 Oct): "Puppy Dog Pals (2017)" and
/// "Puppy Dog Pals (2017) (US) اصدقاء الجراء", "Hercules (1997)" and
/// "Hercules (1997) هرقل". The name up to its year is the key; sequels
/// ("Cloudy … 2 (2013)") stay apart.
String _titleKey(MediaItem m) {
  final t = m.title.toLowerCase();
  final year = RegExp(r'^(.*?\(\s*\d{4}\s*\))').firstMatch(t);
  final base = year != null ? year.group(1)! : t;
  return base
      .replaceAll(RegExp(r'\b(dub|dubbed|sub|subbed|arabic|english|hd|4k)\b'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

/// The best of the newest titles: each list arrives newest first, so its
/// first [perList] titles with art are the recent ones; those are ranked by
/// rating (unrated last, ties keep arrival order) and [count] are kept.
List<MediaItem> pickRecentBest(
  List<List<MediaItem>> lists, {
  int perList = 4,
  int count = 6,
}) {
  final seen = <String>{};
  final pool = <MediaItem>[];
  for (final list in lists) {
    var taken = 0;
    for (final m in list) {
      if (taken >= perList) break;
      if ((m.backdropUrl ?? m.posterUrl)?.isNotEmpty != true) continue;
      if (!seen.add(m.id)) continue;
      pool.add(m);
      taken++;
    }
  }
  final order = {for (var i = 0; i < pool.length; i++) pool[i].id: i};
  pool.sort((a, b) {
    final c = (b.rating ?? -1).compareTo(a.rating ?? -1);
    return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
  });
  return pool.take(count).toList();
}
