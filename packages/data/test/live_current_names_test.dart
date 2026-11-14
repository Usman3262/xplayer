import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only `liveStreams` is used by `currentLiveRows`. Two pages per package.
class _FakeMedia implements AppMediaRepository {
  final pages = <String, List<List<CatalogStreamDto>>>{
    'mbc': [
      [_live('1', 'MBC ELIFE ᴿᴬᵂ', 'mbc'), _live('2', 'MBC 1 ᴿᴬᵂ', 'mbc')],
      [_live('3', 'MBC 1 ᴴᴰ', 'mbc'), _live('4', 'MBC 1', 'mbc')],
    ],
  };
  int calls = 0;

  @override
  Future<PageResult<CatalogStreamDto>> liveStreams({
    String? categoryId,
    int limit = 10,
    String? cursor,
  }) async {
    calls++;
    final list = pages[categoryId] ?? const [];
    final i = int.tryParse(cursor ?? '0') ?? 0;
    return PageResult(
      items: i < list.length ? list[i] : const [],
      nextCursor: i + 1 < list.length ? '${i + 1}' : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogStreamDto _live(String id, String name, String cat) => CatalogStreamDto(
      streamId: id,
      name: name,
      categoryId: cat,
      contentType: 'live',
    );

// Favourites saved by apps before 1 Nov: names without the quality label.
MediaItem _saved(String id, String title, {String? cat = 'mbc'}) =>
    MediaItem(id: id, title: title, kind: MediaKind.live, categoryId: cat);

void main() {
  test('saved live channels get their current name with the label', () async {
    final media = _FakeMedia();
    final repo = RemoteCatalogRepository(media);
    final now = await repo.currentLiveRows([
      _saved('2', 'MBC 1'),
      _saved('4', 'MBC 1'),
      _saved('1', 'MBC ELIFE'),
    ]);
    expect(now['2']!.title, 'MBC 1 RAW');
    expect(now['4']!.title, 'MBC 1');
    expect(now['1']!.title, 'MBC ELIFE RAW');
    expect(media.calls, 2);
  });

  test('stops reading a package once its channels are found', () async {
    final media = _FakeMedia();
    final repo = RemoteCatalogRepository(media);
    final now = await repo.currentLiveRows([_saved('2', 'MBC 1')]);
    expect(now['2']!.title, 'MBC 1 RAW');
    expect(media.calls, 1);
  });

  test('movies and rows without a package are left alone', () async {
    final media = _FakeMedia();
    final repo = RemoteCatalogRepository(media);
    final now = await repo.currentLiveRows([
      const MediaItem(id: '9', title: 'Film', kind: MediaKind.movie, categoryId: 'mbc'),
      _saved('7', 'MBC 1', cat: null),
    ]);
    expect(now, isEmpty);
    expect(media.calls, 0);
  });

  test('withTitle keeps everything else', () {
    final row = _saved('2', 'MBC 1').withTitle('MBC 1 RAW');
    expect(row.title, 'MBC 1 RAW');
    expect(row.id, '2');
    expect(row.kind, MediaKind.live);
    expect(row.categoryId, 'mbc');
  });
}
