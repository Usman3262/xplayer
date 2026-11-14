import '../entities/media_item.dart';
import 'rotating_picks.dart';

/// Top 10 rows with numbers on every platform (client 6 Nov: "restore Top 10
/// and the ranking numbers, refreshed every 7–10 days on all platforms").
/// No ranking data comes from the backend, so the list is the best-rated of
/// the newest titles, chosen once per week (Monday 00:00 UTC) and the same on
/// every device in that week, ranked by rating.
abstract final class WeeklyTop10 {
  static const period = Duration(days: 7);

  /// [newest] is the provider list, newest first.
  static List<MediaItem> pick(
    List<MediaItem> newest, {
    DateTime? now,
    String salt = 'top10',
  }) {
    final recent = newest.take(60).toList();
    if (recent.isEmpty) return const [];
    final order = {for (var i = 0; i < recent.length; i++) recent[i].id: i};
    int byRating(MediaItem a, MediaItem b) {
      final r = (b.rating ?? 0).compareTo(a.rating ?? 0);
      return r != 0 ? r : order[a.id]!.compareTo(order[b.id]!);
    }

    final pool = [...recent]..sort(byRating);
    final chosen = RotatingPicks.select(
      pool.take(20).toList(),
      idOf: (m) => m.id,
      now: now ?? DateTime.now(),
      period: period,
      count: 10,
      salt: salt,
    );
    return [...chosen]..sort(byRating);
  }

  /// Index of the week [now] falls in (used to keep a saved list for 7 days).
  static int week(DateTime now) => RotatingPicks.slot(now, period);
}
