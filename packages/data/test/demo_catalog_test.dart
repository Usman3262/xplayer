import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = DemoCatalogRepository();

  test('every demo title has a credit and an https stream', () {
    for (final m in DemoContent.movies) {
      expect(DemoContent.credits[m.id], isNotNull, reason: m.id);
      expect(m.streamUrl, startsWith('https://'));
    }
    for (final c in DemoContent.live) {
      expect(DemoContent.credits[c.id], isNotNull, reason: c.id);
      expect(c.streamUrl, startsWith('https://'));
    }
  });

  test('demo never points at a provider host', () {
    const allowed = {
      'upload.wikimedia.org',
      'download.blender.org',
      'demo.unified-streaming.com',
      'test-streams.mux.dev',
      'devstreaming-cdn.apple.com',
    };
    expect(allowed.containsAll(DemoContent.hosts), isTrue,
        reason: DemoContent.hosts.toString());
  });

  test('home feed, movies, series and live load', () async {
    final feed = await repo.getHomeFeed();
    expect(feed.top10, isNotEmpty);
    expect(await repo.getMovies(), hasLength(4));
    expect(await repo.getSeries(), hasLength(1));
    expect(await repo.getLiveChannels(), hasLength(2));
  });

  test('series has one season with an episode per film', () async {
    expect(await repo.getSeasonNumbers('demo-series-open-movies'), [1]);
    final eps = await repo.getEpisodes('demo-series-open-movies');
    expect(eps, hasLength(DemoContent.movies.length));
    expect(eps.every((e) => e.stillUrl != null && e.streamUrl != null), isTrue);
  });

  test('search is scoped by kind', () async {
    expect((await repo.search('sintel')).map((m) => m.id), ['demo-sintel']);
    expect(await repo.search('sintel', kind: MediaKind.series), isEmpty);
    expect(await repo.search('  '), isEmpty);
  });

  test('my list toggles locally', () async {
    final m = DemoContent.movies.first;
    repo.toggleMyList(m);
    expect(repo.inMyList(m.id), isTrue);
    expect(await repo.getMyList(), [m]);
    repo.toggleMyList(m);
    expect(await repo.getMyList(), isEmpty);
  });

  test('live channels browse, resolve by id and search like the real catalog',
      () async {
    final page = await repo.browse(kind: MediaKind.live, categoryId: 'demo-live');
    expect(page.items.map((m) => m.id), ['demo-live-1', 'demo-live-2']);
    expect(page.items.every((m) => m.isLive && m.kind == MediaKind.live), isTrue);
    final ch = await repo.getById('demo-live-2', kind: MediaKind.live);
    expect(ch?.streamUrl, startsWith('https://'));
    expect((await repo.search('channel', kind: MediaKind.live)), hasLength(2));
  });

  test('only https demo hosts are allowed to open', () {
    expect(DemoContent.isAllowedUrl(DemoContent.movies.first.streamUrl), isTrue);
    expect(DemoContent.isAllowedUrl('http://test-streams.mux.dev/x.m3u8'), isFalse);
    expect(DemoContent.isAllowedUrl('https://example.com/x.m3u8'), isFalse);
    expect(DemoContent.isAllowedUrl(null), isFalse);
  });
}
