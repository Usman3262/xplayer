import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MediaItem mv(String id, String title) =>
      MediaItem(id: id, title: title, kind: MediaKind.movie, posterUrl: 'http://img/$id.jpg');

  test('My List and Continue Watching survive a restart (guest, no server)', () async {
    final a = LibraryStore(await SharedPreferences.getInstance());
    await a.remember(mv('1', 'Dune'));
    await a.toggleMyList('1');
    await a.remember(MediaItem(id: 'e7', title: 'S1 E7', kind: MediaKind.series, seriesId: 's9'),
        positionSec: 600, durationSec: 2400);
    await a.setProgress('e7', 0.25);

    // "Restart": a new store over the same saved data.
    final b = LibraryStore(await SharedPreferences.getInstance());
    final list = b.myListItems();
    expect(list.single.title, 'Dune');
    expect(list.single.posterUrl, 'http://img/1.jpg');
    final cw = b.continueWatchingItems().single;
    expect((cw.id, cw.seriesId, cw.resumePositionSec, cw.progress), ('e7', 's9', 600, 0.25));
  });

  test('Continue Watching: newest first; finished titles leave the row', () async {
    final s = LibraryStore(await SharedPreferences.getInstance());
    for (final id in ['a', 'b', 'c']) {
      await s.remember(mv(id, id.toUpperCase()));
      await s.setProgress(id, 0.5);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await s.setProgress('b', 0.99);
    expect(s.continueWatchingItems().map((m) => m.id), ['c', 'a']);
  });

  test('an empty title never replaces a saved name; a broken copy never breaks the lists', () async {
    final s = LibraryStore(await SharedPreferences.getInstance());
    await s.remember(mv('1', 'Dune'));
    await s.remember(mv('1', ''));
    await s.toggleMyList('1');
    expect(s.myListItems().single.title, 'Dune');

    SharedPreferences.setMockInitialValues({'app_library_items_v1': '{not json', 'app_my_list': ['1']});
    final broken = LibraryStore(await SharedPreferences.getInstance());
    expect(broken.myListItems(), isEmpty);
  });
}
