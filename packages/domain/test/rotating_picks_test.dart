import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Client 21 Oct A13: "New & Popular" and the main banner must change.
void main() {
  final ids = [for (var i = 0; i < 40; i++) 'id$i'];
  String id(String s) => s;

  test('same picks within one period, different in the next', () {
    final a = RotatingPicks.select(ids, idOf: id, now: DateTime.utc(2026, 10, 21, 1), period: const Duration(hours: 6), count: 4);
    final same = RotatingPicks.select(ids, idOf: id, now: DateTime.utc(2026, 10, 21, 5, 59), period: const Duration(hours: 6), count: 4);
    final next = RotatingPicks.select(ids, idOf: id, now: DateTime.utc(2026, 10, 21, 6, 1), period: const Duration(hours: 6), count: 4);
    expect(same, a);
    expect(next, isNot(a));
  });

  test('order of the pool does not matter (same on every device)', () {
    final now = DateTime.utc(2026, 10, 21, 12);
    final a = RotatingPicks.select(ids, idOf: id, now: now, period: const Duration(days: 1));
    final b = RotatingPicks.select(ids.reversed.toList(), idOf: id, now: now, period: const Duration(days: 1));
    expect(a, b);
  });

  test('New & Popular keeps the 3 newest first and rotates the rest daily', () {
    final today = RotatingPicks.newestWithRotation(ids, idOf: id, now: DateTime.utc(2026, 10, 21, 10));
    final tomorrow = RotatingPicks.newestWithRotation(ids, idOf: id, now: DateTime.utc(2026, 10, 22, 10));
    expect(today.take(3), ['id0', 'id1', 'id2']);
    expect(tomorrow.take(3), ['id0', 'id1', 'id2']);
    expect(today.length, 10);
    expect(today.toSet().length, 10);
    expect(today.skip(3), isNot(tomorrow.skip(3)));
  });

  test('banner stays the same all week and changes on Friday 00:00 Saudi time (client 5 / 12 Nov)', () {
    MediaItem m(String i, MediaKind k) => MediaItem(id: i, title: i, kind: k, badges: const ['4K'], posterUrl: 'https://x/$i.jpg');
    final movies = [for (var i = 0; i < 20; i++) m('m$i', MediaKind.movie)];
    final series = [for (var i = 0; i < 20; i++) m('s$i', MediaKind.series)];
    // Weeks start Friday 00:00 Saudi time = Thursday 21:00 UTC (client 12 Nov).
    final friday = pickHeroCarousel(movies: movies, series: series, at: DateTime.utc(2026, 10, 15, 21, 1));
    final thursday = pickHeroCarousel(movies: movies, series: series, at: DateTime.utc(2026, 10, 22, 20, 59));
    final nextWeek = pickHeroCarousel(movies: movies, series: series, at: DateTime.utc(2026, 10, 22, 21, 1));
    expect(friday.length, 4);
    expect(friday.map((e) => e.id), thursday.map((e) => e.id));
    expect(friday.map((e) => e.id), isNot(nextWeek.map((e) => e.id)));
  });
}
