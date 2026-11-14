import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Continue Watching row reads still / backdrop / season / episode', () {
    final c = ContinueWatchingDto.fromJson({
      'contentType': 'series',
      'streamId': '901',
      'seriesId': '77',
      'episodeId': '901',
      'title': 'الندم',
      'posterUrl': 'poster.jpg',
      'stillUrl': 'https://image.tmdb.org/t/p/w300/still.jpg',
      'seasonNumber': 1,
      'episodeNumber': 4,
    });
    expect(c.stillUrl, contains('still.jpg'));
    expect(c.seasonNumber, 1);
    expect(c.episodeNumber, 4);
    final m = AppMediaRepository.mediaFromContinue(c);
    expect(m.posterUrl, 'poster.jpg');
    expect(m.backdropUrl, c.stillUrl);
  });

  test('row without a still keeps the poster out of the wide slot', () {
    final m = AppMediaRepository.mediaFromContinue(
      ContinueWatchingDto.fromJson({
        'contentType': 'series',
        'streamId': '5',
        'title': 'فوضى',
        'posterUrl': 'poster.jpg',
      }),
    );
    expect(m.backdropUrl, isNull);
    expect(m.kind, MediaKind.series);
  });

  test('episode still found by id, then by season + episode', () {
    final d = SeriesDetailDto.fromJson({
      'seriesId': '77',
      'name': 'S',
      'backdropUrl': 'bd.jpg',
      'seasons': [
        {
          'season': '2',
          'episodes': [
            {'id': '11', 'title': 'E1', 'episodeNum': 1, 'stillUrl': 's1.jpg'},
            {'id': '12', 'title': 'E2', 'episodeNum': 2, 'stillUrl': 's2.jpg'},
          ],
        },
      ],
    });
    expect(d.backdropUrl, 'bd.jpg');
    expect(d.stillFor(episodeId: '12'), 's2.jpg');
    expect(d.stillFor(episodeId: 'x', season: 2, episode: 1), 's1.jpg');
    expect(d.stillFor(season: 3, episode: 1), isNull);
  });
}
