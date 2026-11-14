/// "Weekly Movie Picks" / "Weekly Series Picks" when the catalog has no
/// ranking data (the backend sends no views, popularity or rank field, so a
/// "Top 10" would be invented).
///
/// - **Stable for a week:** the same pool gives the same picks from Monday
///   00:00 to Sunday 23:59:59 Riyadh time (UTC+3, no DST), whatever order the
///   rows arrive in.
/// - **Refresh:** at the next Monday 00:00 Riyadh time.
/// - **No cache needed:** the selection is a pure function of (week, ids), so
///   every device shows the same picks for the same catalog page.
/// - **Fallback:** a pool smaller than [count] returns all of it; an empty pool
///   returns nothing (the row is hidden).
abstract final class WeeklyPicks {
  /// Week boundary timezone: Saudi Arabia (the client's market).
  static const utcOffset = Duration(hours: 3);

  /// Start of the pick week containing [now], as a UTC instant.
  static DateTime weekStartUtc(DateTime now) {
    final local = now.toUtc().add(utcOffset);
    final day = DateTime.utc(local.year, local.month, local.day);
    final monday = day.subtract(Duration(days: local.weekday - DateTime.monday));
    return monday.subtract(utcOffset);
  }

  /// `yyyy-mm-dd` of that week's Monday (Riyadh), e.g. `2026-10-12`.
  static String weekKey(DateTime now) {
    final m = weekStartUtc(now).add(utcOffset);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${m.year}-${two(m.month)}-${two(m.day)}';
  }

  /// Up to [count] items of [pool] for the week of [now]. [salt] keeps the
  /// movie and series selections independent.
  static List<T> select<T>(
    List<T> pool, {
    required String Function(T) idOf,
    required DateTime now,
    int count = 10,
    String salt = '',
  }) {
    if (count <= 0 || pool.isEmpty) return const [];
    final unique = <String, T>{};
    for (final item in pool) {
      unique.putIfAbsent(idOf(item), () => item);
    }
    final key = '${weekKey(now)}|$salt';
    final scored = [
      for (final e in unique.entries) (e.key, e.value, _fnv1a('$key|${e.key}')),
    ]..sort((a, b) {
        final c = a.$3.compareTo(b.$3);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in scored.take(count)) e.$2];
  }

  /// 32-bit FNV-1a: deterministic across runs and platforms (unlike
  /// `String.hashCode`).
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}
