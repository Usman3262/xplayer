import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usman 12 Nov (backend #135): Top 10 comes from GET /catalog/top10, the same
/// on every device; the app's own rule only when the call fails.
class _FakeMedia extends Fake implements AppMediaRepository {
  int calls = 0;
  Object? fail;
  Map<String, dynamic> answer = const {};

  @override
  Future<WeeklyTop10Dto> weeklyTop10() async {
    calls++;
    if (fail != null) throw fail!;
    return WeeklyTop10Dto.fromJson(answer);
  }

  // Fallback (app rule): newest titles, one movie with a poster.
  @override
  Future<PageResult<CatalogStreamDto>> vodStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) async =>
      const PageResult(items: [
        CatalogStreamDto(
          streamId: 'local',
          name: 'Local Film',
          contentType: 'vod',
          posterUrl: 'https://image.tmdb.org/p.jpg',
          rating: '7',
          added: 1000,
        ),
      ]);

  @override
  Future<PageResult<CatalogStreamDto>> seriesList({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) async => const PageResult(items: []);

  @override
  Future<List<CatalogCategoryDto>> vodCategories() async => const [];
  @override
  Future<List<CatalogCategoryDto>> seriesCategories() async => const [];
}

Map<String, dynamic> row(String id, String type) => {
      'streamId': id,
      'name': 'Title $id',
      'contentType': type,
      'posterUrl': 'https://image.tmdb.org/$id.jpg',
      'rating': '8',
      'added': 1794173640,
    };

void main() {
  final next = DateTime.now().toUtc().add(const Duration(days: 3));
  Map<String, dynamic> week({int movies = 12, int series = 2}) => {
        'week': '2026-11-13',
        'nextUpdateAt': next.toIso8601String(),
        'movies': [for (var i = 0; i < movies; i++) row('m$i', 'vod')],
        'series': [for (var i = 0; i < series; i++) row('s$i', 'series')],
      };

  test('server order is the rank, 10 at most, one call for both lists', () async {
    final media = _FakeMedia()..answer = week();
    final repo = RemoteCatalogRepository(media);
    final movies = await repo.top10(MediaKind.movie);
    final series = await repo.top10(MediaKind.series);
    expect(movies.map((e) => e.id), [for (var i = 0; i < 10; i++) 'm$i']);
    expect(series.map((e) => e.id), ['s0', 's1']);
    expect(media.calls, 1);
    expect(repo.top10NextUpdate.isAtSameMomentAs(next), isTrue);
  });

  test('call fails: the app rule is used', () async {
    final media = _FakeMedia()..fail = ApiException('Network error.', code: 'NETWORK');
    final repo = RemoteCatalogRepository(media);
    final movies = await repo.top10(MediaKind.movie);
    expect(movies.map((e) => e.id), ['local']);
  });

  test('answer without lists or with both lists empty: the app rule is used', () async {
    final media = _FakeMedia()..answer = {'week': '2026-11-13'};
    expect((await RemoteCatalogRepository(media).top10(MediaKind.movie)).map((e) => e.id), ['local']);
    media.answer = week(movies: 0, series: 0);
    expect((await RemoteCatalogRepository(media).top10(MediaKind.movie)).map((e) => e.id), ['local']);
  });

  test('one empty list stays empty (that package has none)', () async {
    final media = _FakeMedia()..answer = week(movies: 3, series: 0);
    final repo = RemoteCatalogRepository(media);
    expect(await repo.top10(MediaKind.series), isEmpty);
  });

  test('the live answer shape parses (12 Nov sample)', () {
    final w = WeeklyTop10Dto.fromJson({
      'week': '2026-11-06',
      'updatedAt': '2026-11-12T13:03:15.813Z',
      'nextUpdateAt': '2026-11-12T21:00:00.000Z',
      'movies': [row('780853', 'vod')],
      'series': [row('18148', 'series')],
    });
    expect(w.week, '2026-11-06');
    expect(w.nextUpdateAt, DateTime.utc(2026, 11, 12, 21));
    expect(w.movies.single.added, 1794173640);
  });
}
