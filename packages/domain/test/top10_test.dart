import 'package:domain/domain.dart';
import 'package:test/test.dart';

MediaItem m(
  String id,
  String title, {
  double? rating,
  String? poster = 'https://image.tmdb.org/p.jpg',
  String? category,
  bool soon = false,
  int? added,
}) =>
    MediaItem(
      id: id,
      title: title,
      kind: MediaKind.movie,
      rating: rating,
      posterUrl: poster,
      categoryId: category,
      badges: soon ? const [soonBadge] : const [],
      addedSec: added,
    );

void main() {
  test('the same film listed twice appears once (client 10 Nov)', () {
    final top = Top10.pick([
      m('1', 'Ölümlü Dünya', rating: 6),
      m('2', 'TR-D: Ölümlü Dünya', rating: 6),
      m('3', 'Second Chance Holiday (2024)', rating: 5),
      m('4', 'Second Chance Holiday', rating: 5),
    ]);
    expect(top.map((e) => e.id), ['1', '3']);
  });

  test('highest rating first, the newer title first on a tie', () {
    final top = Top10.pick([
      m('new', 'A', rating: 7),
      m('mid', 'B', rating: 9),
      m('old', 'C', rating: 7),
    ]);
    expect(top.map((e) => e.id), ['mid', 'new', 'old']);
  });

  test('no poster, Coming Soon and excluded (Kids) categories are left out', () {
    final top = Top10.pick(
      [
        m('a', 'No art', rating: 9, poster: null),
        m('b', 'Soon', rating: 9, soon: true),
        m('c', 'Cartoon', rating: 9, category: 'kids'),
        m('d', 'Film', rating: 1),
      ],
      excludeCategoryIds: {'kids'},
    );
    expect(top.map((e) => e.id), ['d']);
  });

  test('ten titles at most, same input gives the same list every time', () {
    final list = [for (var i = 0; i < 30; i++) m('$i', 'Title $i', rating: (i * 7 % 10).toDouble())];
    final a = Top10.pick(list).map((e) => e.id).toList();
    final b = Top10.pick(List.of(list)).map((e) => e.id).toList();
    expect(a, hasLength(10));
    expect(a, b);
  });

  test('titleKey drops provider tags, years, brackets and quality words', () {
    expect(Top10.titleKey('TR-D: Ölümlü Dünya'), 'ölümlü dünya');
    expect(Top10.titleKey('AR | The Movie (2025) [4K]'), 'the movie');
    expect(Top10.titleKey('The Movie 4K HDR'), 'the movie hdr');
    expect(Top10.titleKey('فانزو (2024)'), 'فانزو');
  });

  test('the week starts Friday 00:00 Saudi time (Thursday 21:00 UTC)', () {
    // Thursday 12 Nov 2026, 11:30 UTC -> Friday 6 Nov 2026 00:00 Saudi.
    expect(Top10.weekStart(DateTime.utc(2026, 11, 12, 11, 30)),
        DateTime.utc(2026, 11, 5, 21));
    // Thursday 20:59 UTC is still the old week; 21:00 UTC starts the new one.
    expect(Top10.weekStart(DateTime.utc(2026, 11, 12, 20, 59)),
        DateTime.utc(2026, 11, 5, 21));
    expect(Top10.weekStart(DateTime.utc(2026, 11, 12, 21)),
        DateTime.utc(2026, 11, 12, 21));
    // Friday afternoon Saudi time.
    expect(Top10.weekStart(DateTime.utc(2026, 11, 13, 12)),
        DateTime.utc(2026, 11, 12, 21));
  });

  test('a title added during the week waits until Friday', () {
    final week = DateTime.utc(2026, 11, 5, 21);
    final sec = week.millisecondsSinceEpoch ~/ 1000;
    final list = [
      m('new', 'Added Wednesday', rating: 9, added: sec + 5 * 86400),
      m('old', 'Added last week', rating: 7, added: sec - 86400),
      m('nodate', 'No date', rating: 6),
    ];
    expect(Top10.pick(list, weekStart: week).map((e) => e.id), ['old', 'nodate']);
    // Next Friday it counts.
    final next = week.add(const Duration(days: 7));
    expect(Top10.pick(list, weekStart: next).map((e) => e.id),
        ['new', 'old', 'nodate']);
  });

  test('only the 60 newest titles before the week start are ranked', () {
    final week = DateTime.utc(2026, 11, 5, 21);
    final sec = week.millisecondsSinceEpoch ~/ 1000;
    final list = [
      for (var i = 0; i < 70; i++)
        m('$i', 'Title $i', rating: i == 65 ? 10 : 5, added: sec - 60 - i),
    ];
    final top = Top10.pick(list, weekStart: week).map((e) => e.id);
    expect(top, isNot(contains('65')));
    expect(top.first, '0');
  });
}
