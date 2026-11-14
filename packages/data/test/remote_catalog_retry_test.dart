import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogStreamDto _stream(String id, String type) =>
    CatalogStreamDto(streamId: id, name: 'Title $id', contentType: type);

/// Fails while [online] is false, like a phone without internet.
class _FakeMedia extends Fake implements AppMediaRepository {
  bool online = false;

  Future<PageResult<CatalogStreamDto>> _page(String type) async {
    if (!online) throw ApiException('Network error.', code: 'NETWORK');
    return PageResult(items: [_stream('1', type)]);
  }

  @override
  Future<PageResult<CatalogStreamDto>> vodStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) => _page('vod');

  @override
  Future<PageResult<CatalogStreamDto>> seriesList({
    String? categoryId,
    int limit = 10,
    String? cursor,
    String? sort,
  }) => _page('series');

  @override
  Future<PageResult<CatalogStreamDto>> liveStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
  }) => _page('live');

  @override
  Future<List<CatalogCategoryDto>> liveCategories() async => const [];
}

/// Client 9 Nov: after the internet came back, Retry did nothing until the
/// app was closed and reopened.
void main() {
  test('Home loads on Retry after a failed load, same repository', () async {
    final media = _FakeMedia();
    final repo = RemoteCatalogRepository(media);

    await expectLater(repo.getHomeFeed(), throwsA(isA<ApiException>()));

    media.online = true;
    final feed = await repo.getHomeFeed();
    expect(feed.hero.id, isNot('empty'));
    expect(feed.liveChannels, isNotEmpty);
  });

  test('a failed series load is not remembered as "no series"', () async {
    final media = _FakeMedia();
    final repo = RemoteCatalogRepository(media);

    expect(await repo.getSeries(), isEmpty);

    media.online = true;
    expect(await repo.getSeries(), isNotEmpty);
  });
}
