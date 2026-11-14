import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  final newest = [
    for (var i = 0; i < 60; i++)
      MediaItem(id: 'm$i', title: 'M$i', kind: MediaKind.movie, rating: (i * 7 % 50) / 5),
  ];

  test('10 titles, ranked by rating (client 6 Nov: Top 10 with numbers)', () {
    final top = WeeklyTop10.pick(newest, now: DateTime.utc(2026, 11, 3));
    expect(top.length, 10);
    for (var i = 1; i < top.length; i++) {
      expect((top[i - 1].rating ?? 0) >= (top[i].rating ?? 0), isTrue);
    }
  });

  test('same list all week, new list the next week (refresh every 7 days)', () {
    ids(DateTime t) => WeeklyTop10.pick(newest, now: t).map((m) => m.id).toList();
    final monday = ids(DateTime.utc(2026, 11, 2, 1));
    final sunday = ids(DateTime.utc(2026, 11, 8, 23));
    final next = ids(DateTime.utc(2026, 11, 9, 1));
    expect(sunday, monday);
    expect(next, isNot(monday));
  });

  test('empty list gives no row', () {
    expect(WeeklyTop10.pick(const []), isEmpty);
  });
}
