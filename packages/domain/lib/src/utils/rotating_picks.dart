/// A selection that changes every [period] but is the same on every device
/// within one period (client 21 Oct A13: "New & Popular" and the main banner
/// must change instead of staying fixed). Pure function of (period, ids): no
/// cache, no server call.
abstract final class RotatingPicks {
  /// Index of the [period]-long slot containing [now] (UTC, from 2024-01-01).
  static int slot(DateTime now, Duration period) =>
      now.toUtc().difference(DateTime.utc(2024, 1, 1)).inMinutes ~/ period.inMinutes;

  /// Up to [count] items of [pool], mixed differently for each slot. [salt]
  /// keeps separate rows (movies / series / banner) independent.
  static List<T> select<T>(
    List<T> pool, {
    required String Function(T) idOf,
    required DateTime now,
    required Duration period,
    int count = 10,
    String salt = '',
  }) {
    if (count <= 0 || pool.isEmpty) return const [];
    final unique = <String, T>{};
    for (final item in pool) {
      unique.putIfAbsent(idOf(item), () => item);
    }
    final key = '${slot(now, period)}|$salt';
    final scored = [
      for (final e in unique.entries) (e.key, e.value, _fnv1a('$key|${e.key}')),
    ]..sort((a, b) {
        final c = a.$3.compareTo(b.$3);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in scored.take(count)) e.$2];
  }

  /// "New & Popular": the [keepNewest] newest stay first, the rest of the row
  /// rotates daily among the next newest titles of [pool] (newest first).
  static List<T> newestWithRotation<T>(
    List<T> pool, {
    required String Function(T) idOf,
    required DateTime now,
    int count = 10,
    int keepNewest = 3,
    String salt = '',
  }) {
    if (pool.length <= count) return List.of(pool);
    final head = pool.take(keepNewest).toList();
    final rest = select(
      pool.skip(keepNewest).toList(),
      idOf: idOf,
      now: now,
      period: const Duration(days: 1),
      count: count - head.length,
      salt: 'new|$salt',
    );
    return [...head, ...rest];
  }

  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
