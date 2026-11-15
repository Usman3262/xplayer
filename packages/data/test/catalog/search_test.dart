import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CatalogStore store;
  ProviderMovie mv(String id, String name) =>
      ProviderMovie(id: id, name: name, stream: StreamRef(kind: MediaKind.movie, id: id), categoryId: 'c');

  setUp(() async {
    store = CatalogStore(CatalogDb(NativeDatabase.memory()));
    await store.saveMovies('p', 'c', [
      mv('1', 'The Dark Night (2008)'),
      mv('2', 'Night of the Living Dead'),
      mv('3', '100% Love'),
      mv('4', 'Mission_Impossible'),
    ]);
  });
  tearDown(() => store.close());

  Future<List<String>> ids(String q) async => [for (final m in await store.searchMovies('p', q)) m.id]..sort();

  test('every word must match, in any order, any case', () async {
    expect(await ids('night dark'), ['1']);
    expect(await ids('NIGHT'), ['1', '2']);
    expect(await ids('  dead   living '), ['2']);
  });

  test('% and _ in a query are plain characters', () async {
    expect(await ids('100%'), ['3']);
    expect(await ids('%'), ['3']);
    expect(await ids('t_e'), isEmpty); // '_' is not "any character"
    expect(await ids('mission_'), ['4']);
  });

  test('empty query → nothing', () async {
    expect(await ids('   '), isEmpty);
  });
}
