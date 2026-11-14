import 'package:domain/domain.dart';
import 'package:test/test.dart';

List<String> _pool(int n) => [for (var i = 0; i < n; i++) 'id$i'];
List<String> _pick(List<String> pool, DateTime now, {String salt = 'movies'}) =>
    WeeklyPicks.select(pool, idOf: (s) => s, now: now, salt: salt);

void main() {
  // Monday 12 Oct 2026 00:00 Riyadh = Sunday 11 Oct 21:00 UTC.
  final weekStart = DateTime.utc(2026, 10, 11, 21);

  test('week starts Monday 00:00 Riyadh (UTC+3)', () {
    expect(WeeklyPicks.weekStartUtc(DateTime.utc(2026, 10, 15, 9)), weekStart);
    expect(WeeklyPicks.weekKey(DateTime.utc(2026, 10, 15, 9)), '2026-10-12');
  });

  test('same picks for the whole week', () {
    final pool = _pool(60);
    final first = _pick(pool, weekStart);
    expect(first, hasLength(10));
    for (final t in [
      weekStart.add(const Duration(hours: 1)),
      DateTime.utc(2026, 10, 15, 12),
      // Sunday 18 Oct 23:59:59 Riyadh — last second of the week.
      DateTime.utc(2026, 10, 18, 20, 59, 59),
    ]) {
      expect(_pick(pool, t), first, reason: '$t');
    }
  });

  test('new picks at the weekly boundary', () {
    final pool = _pool(60);
    final lastSecond = DateTime.utc(2026, 10, 18, 20, 59, 59);
    final nextWeek = DateTime.utc(2026, 10, 18, 21); // Mon 19 Oct 00:00 Riyadh
    expect(WeeklyPicks.weekKey(lastSecond), '2026-10-12');
    expect(WeeklyPicks.weekKey(nextWeek), '2026-10-19');
    expect(_pick(pool, nextWeek), isNot(_pick(pool, lastSecond)));
  });

  test('order of the incoming rows does not change the picks', () {
    final pool = _pool(40);
    final reversed = pool.reversed.toList();
    expect(_pick(reversed, weekStart), _pick(pool, weekStart));
  });

  test('duplicates are removed; small and empty pools', () {
    expect(_pick(['a', 'a', 'b'], weekStart).toSet(), {'a', 'b'});
    expect(_pick(['a', 'a', 'b'], weekStart), hasLength(2));
    expect(_pick(const [], weekStart), isEmpty);
  });

  test('movie and series picks are independent (salt)', () {
    final pool = _pool(60);
    expect(
      _pick(pool, weekStart, salt: 'movies'),
      isNot(_pick(pool, weekStart, salt: 'series')),
    );
  });
}
