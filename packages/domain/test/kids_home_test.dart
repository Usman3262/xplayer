import 'package:domain/domain.dart';
import 'package:test/test.dart';

MediaItem m(String id, MediaKind k, {double? rating, String? cat, String? series, bool art = true}) =>
    MediaItem(
      id: id,
      title: id,
      kind: k,
      rating: rating,
      categoryId: cat,
      seriesId: series,
      posterUrl: art ? 'https://x/$id.jpg' : null,
    );

void main() {
  final series = [for (var i = 0; i < 30; i++) m('s$i', MediaKind.series, rating: (i % 10).toDouble())];
  final movies = [for (var i = 0; i < 30; i++) m('m$i', MediaKind.movie)];
  final rails = [
    (kind: MediaKind.series, categoryId: 'cs', items: series),
    (kind: MediaKind.movie, categoryId: 'cm', items: movies),
    (kind: MediaKind.live, categoryId: 'cl', items: [m('l1', MediaKind.live)]),
  ];

  test('Top 10 series and movies: 10 each, right kind', () {
    final h = KidsHome.from(rails, now: DateTime.utc(2026, 10, 21, 12));
    expect(h.topSeries, hasLength(10));
    expect(h.topMovies, hasLength(10));
    expect(h.topSeries.every((x) => x.kind == MediaKind.series), isTrue);
    expect(h.topMovies.every((x) => x.kind == MediaKind.movie), isTrue);
  });

  test('same 10 all week (Riyadh Mon–Sun), new set next Monday', () {
    ids(DateTime t) => KidsHome.from(rails, now: t).topSeries.map((x) => x.id).toList();
    // Week of Mon 19 Oct 2026 (Riyadh): Mon 00:00 +03 = Sun 18 Oct 21:00 UTC.
    final mon = ids(DateTime.utc(2026, 10, 18, 21, 0, 1));
    final sun = ids(DateTime.utc(2026, 10, 25, 20, 59, 59));
    final next = ids(DateTime.utc(2026, 10, 25, 21, 0, 1));
    expect(sun, mon);
    expect(next, isNot(mon));
  });

  test('order of arrival does not change the picks', () {
    final a = KidsHome.from(rails, now: DateTime.utc(2026, 10, 21)).topMovies.map((x) => x.id).toSet();
    final shuffled = [
      (kind: MediaKind.movie, categoryId: 'cm', items: movies.reversed.toList()),
      (kind: MediaKind.series, categoryId: 'cs', items: series),
    ];
    final b = KidsHome.from(shuffled, now: DateTime.utc(2026, 10, 21)).topMovies.map((x) => x.id).toSet();
    expect(b, a);
  });

  test('banner: newest of each category, best rated first, no live', () {
    final h = KidsHome.from(rails, now: DateTime.utc(2026, 10, 21));
    // newest 4 series s0..s3 (ratings 0..3) + newest 4 movies (unrated).
    expect(h.banner.first.id, 's3');
    expect(h.banner.any((x) => x.kind == MediaKind.live), isFalse);
    expect(h.banner, hasLength(6));
  });

  test('continue watching keeps only kids titles', () {
    final h = KidsHome.from(rails, now: DateTime.utc(2026, 10, 21));
    final cw = h.continueWatching([
      m('s5', MediaKind.series),
      m('ep1', MediaKind.series, series: 's9'),
      m('x', MediaKind.movie, cat: 'cm'),
      m('adult', MediaKind.movie, cat: 'other'),
    ]);
    expect(cw.map((x) => x.id), ['s5', 'ep1', 'x']);
  });

  test('small pool shows what there is; no art is skipped', () {
    final h = KidsHome.from([
      (kind: MediaKind.series, categoryId: null, items: [m('a', MediaKind.series), m('b', MediaKind.series, art: false)]),
    ], now: DateTime.utc(2026, 10, 21));
    expect(h.topSeries.map((x) => x.id), ['a']);
    expect(h.topMovies, isEmpty);
  });

  test('no title twice in a Top 10 (dubbed / subtitled copies)', () {
    final dupes = [
      for (var i = 0; i < 12; i++) m('a$i', MediaKind.series),
      MediaItem(id: 'p1', title: 'Puppy Dog Pals (2017)', kind: MediaKind.series, posterUrl: 'u'),
      MediaItem(id: 'p2', title: 'Puppy Dog Pals (2017) DUB', kind: MediaKind.series, posterUrl: 'u'),
      MediaItem(id: 'p3', title: 'puppy dog pals (2017) dub', kind: MediaKind.series, posterUrl: 'u'),
      MediaItem(id: 'p4', title: 'Puppy Dog Pals (2017) (US) اصدقاء الجراء', kind: MediaKind.series, posterUrl: 'u'),
    ];
    for (var d = 0; d < 14; d++) {
      final h = KidsHome.from([(kind: MediaKind.series, categoryId: null, items: dupes)],
          now: DateTime.utc(2026, 10, 1).add(Duration(days: 7 * d)));
      final pals = h.topSeries.where((x) => x.title.toLowerCase().contains('puppy')).length;
      expect(pals <= 1, isTrue);
      expect(h.topSeries, hasLength(10));
    }
  });

  test('same film with an Arabic name is one entry; sequels stay apart', () {
    final pool = [
      MediaItem(id: 'h1', title: 'Hercules (1997)', kind: MediaKind.movie, posterUrl: 'u'),
      MediaItem(id: 'h2', title: 'Hercules (1997) هرقل', kind: MediaKind.movie, posterUrl: 'u'),
      MediaItem(id: 'c1', title: 'Cloudy with a Chance of Meatballs (2009)', kind: MediaKind.movie, posterUrl: 'u'),
      MediaItem(id: 'c2', title: 'Cloudy with a Chance of Meatballs 2 (2013)', kind: MediaKind.movie, posterUrl: 'u'),
    ];
    final h = KidsHome.from([(kind: MediaKind.movie, categoryId: null, items: pool)], now: DateTime.utc(2026, 10, 21));
    final ids = h.topMovies.map((x) => x.id).toSet();
    expect(ids.contains('h1') != ids.contains('h2'), isTrue);
    expect(ids.containsAll({'c1', 'c2'}), isTrue);
    expect(h.topMovies, hasLength(3));
  });
}
