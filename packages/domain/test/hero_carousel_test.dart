import 'package:domain/domain.dart';
import 'package:test/test.dart';

MediaItem _m(String id, MediaKind kind, {List<String> badges = const []}) =>
    MediaItem(
      id: id,
      title: id,
      kind: kind,
      badges: badges,
      posterUrl: 'https://example.com/$id.jpg',
    );

void main() {
  test('picks 2 movies and 2 series preferring 4K', () {
    final movies = [
      _m('m1', MediaKind.movie),
      _m('m2', MediaKind.movie, badges: const ['4K']),
      _m('m3', MediaKind.movie, badges: const ['4K ULTRA']),
      _m('m4', MediaKind.movie, badges: const ['HD']),
    ];
    final series = [
      _m('s1', MediaKind.series, badges: const ['4K']),
      _m('s2', MediaKind.series),
      _m('s3', MediaKind.series, badges: const ['4K']),
    ];
    final at = DateTime.utc(2026, 10, 20);
    final picks = pickHeroCarousel(movies: movies, series: series, at: at);
    expect(picks.length, 4);
    expect(picks.where((e) => e.kind == MediaKind.movie).length, 2);
    expect(picks.where((e) => e.kind == MediaKind.series).length, 2);
    expect(picks.take(2).every(_looks4k), isTrue);
  });

  test('rotates across weeks (client 5 Nov: weekly banner)', () {
    final movies = [
      for (var i = 0; i < 6; i++)
        _m('m$i', MediaKind.movie, badges: const ['4K']),
    ];
    final series = [
      for (var i = 0; i < 6; i++)
        _m('s$i', MediaKind.series, badges: const ['4K']),
    ];
    final a = pickHeroCarousel(
      movies: movies,
      series: series,
      at: DateTime.utc(2026, 10, 20),
    );
    final b = pickHeroCarousel(
      movies: movies,
      series: series,
      at: DateTime.utc(2026, 10, 27),
    );
    expect(a.map((e) => e.id).toList(), isNot(b.map((e) => e.id).toList()));
  });
}

bool _looks4k(MediaItem m) =>
    m.badges.any((b) => b.toUpperCase().contains('4K'));
