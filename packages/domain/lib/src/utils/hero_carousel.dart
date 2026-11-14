import '../entities/media_item.dart';
import 'rotating_picks.dart';
import 'top10.dart';

/// Home main-banner slides: **2 movies + 2 series**, preferring recently
/// added **4K** titles, with a rotating pick so the same four do not stick
/// forever (client 20 Oct).
///
/// Rules: titles need artwork; 4K first (badge or title), else any title;
/// only the [recentWindow] newest of that pool (provider order); a new
/// set every week from Friday 00:00 Saudi time (no change on rebuild); no
/// duplicates; fewer than 2+2 eligible → whatever exists, then any art.
List<MediaItem> pickHeroCarousel({
  required List<MediaItem> movies,
  required List<MediaItem> series,
  DateTime? at,
  int movieCount = 2,
  int seriesCount = 2,
}) {
  // Client 21 Oct A13: the banner "stays fixed". A new mix every week from
  // the [recentWindow] newest (4K first) titles; the same on every device
  // within one week. The week starts Friday 00:00 Saudi time, as Top 10
  // (client 12 Nov), and titles added during the week wait until Friday.
  final now = Top10.weekStart(at ?? DateTime.now());
  final moviePicks =
      _pickPool(_addedBefore(movies, now, movieCount), movieCount, now, 'hero-movies');
  final seriesPicks =
      _pickPool(_addedBefore(series, now, seriesCount), seriesCount, now, 'hero-series');
  final out = <MediaItem>[...moviePicks, ...seriesPicks];
  if (out.isNotEmpty) return out;

  // Fallback: any art from either pool.
  return RotatingPicks.select(
    [..._withArt(movies), ..._withArt(series)],
    idOf: (m) => m.id,
    now: now,
    period: heroPeriod,
    count: 4,
    salt: 'hero-any',
  );
}

/// How many of the newest eligible titles the banner rotates through.
const int recentWindow = 24;

/// How often the banner changes: once a week (client 5 Nov: "the Home banner
/// should be refreshed every week"; it changed every 6 h).
const Duration heroPeriod = Duration(days: 7);

List<MediaItem> _pickPool(List<MediaItem> pool, int n, DateTime now, String salt) {
  final art = _withArt(pool);
  if (art.isEmpty || n <= 0) return const [];
  final fourK = art.where(_looks4k).toList();
  // The provider lists newest first: rotate among the [recentWindow] most
  // recent titles so the banner shows new 4K arrivals, not old catalogue.
  final src = (fourK.length >= n ? fourK : art).take(recentWindow).toList();
  return RotatingPicks.select(src, idOf: (m) => m.id, now: now, period: heroPeriod, count: n, salt: salt);
}

/// Titles added before [weekStart]; all of [pool] when that leaves fewer
/// than [n] with art (a catalogue without dates, or a very new one).
List<MediaItem> _addedBefore(List<MediaItem> pool, DateTime weekStart, int n) {
  final before = [
    for (final m in pool)
      if (Top10.addedBefore(m.addedSec, weekStart)) m,
  ];
  return _withArt(before).length >= n ? before : pool;
}

List<MediaItem> _withArt(List<MediaItem> pool) => [
      for (final m in pool)
        if ((m.backdropUrl ?? m.posterUrl)?.isNotEmpty == true) m,
    ];

bool _looks4k(MediaItem m) {
  for (final b in m.badges) {
    final u = b.toUpperCase();
    if (u.contains('4K') || u.contains('UHD') || u.contains('ULTRA')) {
      return true;
    }
  }
  final t = m.title.toUpperCase();
  return t.contains('4K') || t.contains('UHD');
}
