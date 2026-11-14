import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only `seriesDetail` is used by the season/episode paths under test.
class _FakeMedia implements AppMediaRepository {
  _FakeMedia(this.detail);
  final SeriesDetailDto detail;
  int calls = 0;

  @override
  Future<SeriesDetailDto> seriesDetail(String seriesId) async {
    calls++;
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SeriesSeasonDto _season(String key, List<String> ids, {int? durationSec}) =>
    SeriesSeasonDto(
      season: key,
      episodes: [
        for (var i = 0; i < ids.length; i++)
          SeriesEpisodeDto(
            id: ids[i],
            title: 'Ep ${ids[i]}',
            episodeNum: i + 1,
            durationSec: durationSec,
          ),
      ],
    );

RemoteCatalogRepository _repo(List<SeriesSeasonDto> seasons) =>
    RemoteCatalogRepository(
      _FakeMedia(
        SeriesDetailDto(
          seriesId: 's1',
          name: 'Show',
          posterUrl: 'https://img/poster.jpg',
          seasons: seasons,
        ),
      ),
    );

void main() {
  test('season numbers are the provider keys, not 1..count', () async {
    final repo = _repo([
      _season('1', ['a1', 'a2']),
      _season('3', ['c1']),
    ]);
    expect(await repo.getSeasonNumbers('s1'), [1, 3]);
    expect(await repo.getSeasonCount('s1'), 2);
  });

  test('a season the series does not have is empty (no season-1 repeat)',
      () async {
    final repo = _repo([
      _season('1', ['a1', 'a2']),
      _season('3', ['c1']),
    ]);
    expect(await repo.getEpisodes('s1', season: 2), isEmpty);
    final s3 = await repo.getEpisodes('s1', season: 3);
    expect(s3.map((e) => e.id), ['c1']);
    expect(s3.single.season, 3);
    expect(s3.single.seriesId, 's1');
  });

  test('default season 1 maps to the first real season (series from S2)',
      () async {
    final repo = _repo([
      _season('2', ['b1']),
      _season('4', ['d1']),
    ]);
    expect(await repo.getSeasonNumbers('s1'), [2, 4]);
    final first = await repo.getEpisodes('s1');
    expect(first.map((e) => e.id), ['b1']);
    expect(first.single.season, 2);
  });

  test('empty seasons and non-numeric keys are skipped; order ascending',
      () async {
    final repo = _repo([
      _season('5', ['e1']),
      const SeriesSeasonDto(season: '2'),
      _season('x', ['z1']),
      _season('0', ['s0']),
    ]);
    expect(await repo.getSeasonNumbers('s1'), [0, 5]);
  });

  test('missing duration is not invented', () async {
    final repo = _repo([
      _season('1', ['a1']),
      _season('2', ['b1'], durationSec: 2700),
    ]);
    final s1 = await repo.getEpisodes('s1', season: 1);
    expect(s1.single.durationLabel, '');
    final s2 = await repo.getEpisodes('s1', season: 2);
    expect(s2.single.durationLabel, '45m');
  });

  test('episode duration minutes field is not divided again', () async {
    final repo = _repo([
      _season('1', ['a1'], durationSec: 45),
    ]);
    final eps = await repo.getEpisodes('s1', season: 1);
    expect(eps.single.durationLabel, '45m');
  });

  // Client 10 Nov: next / previous went the wrong way on a series whose
  // provider lists episodes newest first.
  RemoteCatalogRepository repoWith(List<SeriesEpisodeDto> eps) =>
      _repo([SeriesSeasonDto(season: '1', episodes: eps)]);
  SeriesEpisodeDto ep(String id, int? n) =>
      SeriesEpisodeDto(id: id, title: 'Ep $id', episodeNum: n);

  test('episodes come in episode-number order', () async {
    final repo = repoWith([ep('e3', 3), ep('e1', 1), ep('e2', 2)]);
    final eps = await repo.getEpisodes('s1', season: 1);
    expect(eps.map((e) => e.id), ['e1', 'e2', 'e3']);
    expect(eps.map((e) => e.number), [1, 2, 3]);
  });

  test('provider order stays when an episode has no number', () async {
    final repo = repoWith([ep('e3', 3), ep('x', null), ep('e1', 1)]);
    final eps = await repo.getEpisodes('s1', season: 1);
    expect(eps.map((e) => e.id), ['e3', 'x', 'e1']);
  });

  test('equal episode numbers keep provider order', () async {
    final repo = repoWith([ep('b', 2), ep('a', 1), ep('b2', 2)]);
    final eps = await repo.getEpisodes('s1', season: 1);
    expect(eps.map((e) => e.id), ['a', 'b', 'b2']);
  });
}
