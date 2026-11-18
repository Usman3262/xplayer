import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same rules as the `library_push` / `library_pull` RPCs: newest wins.
class FakeAccount {
  final rows = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  int pushedRows = 0;

  Future<Object?> rpc(String fn, Map<String, dynamic> p) async {
    calls.add(fn);
    if (fn == 'library_push') {
      var n = 0;
      for (final i in (p['p_items'] as List).cast<Map<String, dynamic>>()) {
        pushedRows++;
        final old = rows[i['id']];
        if (old == null || DateTime.parse(i['at']).isAfter(DateTime.parse(old['at']))) {
          rows[i['id']] = Map.of(i);
          n++;
        }
      }
      return n;
    }
    final since = p['p_since'] == null ? null : DateTime.parse(p['p_since'] as String);
    return [
      for (final r in rows.values)
        if (since == null || DateTime.parse(r['at']).isAfter(since)) r,
    ];
  }
}

void main() {
  late SharedPreferences prefs;
  late LibraryStore store;
  late FakeAccount account;
  late LibrarySync sync;
  const panel = 'xtream:panel.example', user = 'u1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = LibraryStore(prefs);
    account = FakeAccount();
    sync = LibrarySync(store: store, prefs: prefs, rpc: account.rpc);
  });

  test('guest → account: the first sync uploads the whole device library', () async {
    await store.remember(const MediaItem(id: '1', title: 'Dune', kind: MediaKind.movie));
    await store.toggleMyList('1');
    await store.remember(const MediaItem(id: '2', title: 'Heat', kind: MediaKind.movie), positionSec: 300, durationSec: 6000);
    await store.setProgress('2', 0.05);
    final r = await sync.sync(panel, user);
    expect(r.pushed, 2);
    expect(account.rows['1']!['my_list'], isTrue);
    expect(account.rows['2']!['pos'], 300);
  });

  test('another device\'s changes arrive; only changes are sent afterwards', () async {
    await store.remember(const MediaItem(id: '1', title: 'Dune', kind: MediaKind.movie));
    await sync.sync(panel, user);
    account.rows['9'] = {
      'id': '9', 'kind': 'series', 'title': 'Dark', 'series': '9', 'my_list': true, 'rating': 1,
      'progress': 0.3, 'pos': 900, 'dur': 3000, 'at': DateTime.now().toUtc().add(const Duration(seconds: 1)).toIso8601String(),
    };
    account.pushedRows = 0;
    final r = await sync.sync(panel, user);
    expect(r.pulled, 1);
    expect(store.myListItems().map((m) => m.title), ['Dark']);
    expect(store.ratingFor('9'), 1);
    expect(store.continueWatchingItems().single.resumePositionSec, 900);
    // Nothing new on the phone: '1' is not sent again (only the pulled
    // row may echo back once; the server ignores equal times).
    expect(account.pushedRows, lessThanOrEqualTo(1));
  });

  test('newest wins both ways: an older account copy never undoes a newer phone change', () async {
    await store.remember(const MediaItem(id: '1', title: 'Dune', kind: MediaKind.movie));
    await store.toggleMyList('1'); // now, on the phone
    account.rows['1'] = {
      'id': '1', 'kind': 'movie', 'title': 'Dune', 'my_list': false, 'rating': 0, 'progress': 0,
      'at': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
    };
    await sync.sync(panel, user);
    expect(store.myListIds, ['1']);
    expect(account.rows['1']!['my_list'], isTrue);
  });

  test('removing from My List is a change too (it reaches the account)', () async {
    await store.remember(const MediaItem(id: '1', title: 'Dune', kind: MediaKind.movie));
    await store.toggleMyList('1');
    await sync.sync(panel, user);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.toggleMyList('1');
    await sync.sync(panel, user);
    expect(account.rows['1']!['my_list'], isFalse);
  });
}
