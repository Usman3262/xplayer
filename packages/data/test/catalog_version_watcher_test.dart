import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  test('first version is remembered, later changes are reported', () async {
    final versions = ['v1', 'v1', 'v2', null, 'v2', 'v3'];
    var i = 0;
    final w = CatalogVersionWatcher(() async => versions[i++]);
    final seen = <String>[];
    final sub = w.changes.listen(seen.add);
    expect(await w.check(), isFalse); // v1 remembered
    expect(await w.check(), isFalse); // same
    expect(await w.check(), isTrue); // v2
    expect(await w.check(), isFalse); // null ignored
    expect(await w.check(), isFalse); // same
    expect(await w.check(), isTrue); // v3
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['v2', 'v3']);
    await sub.cancel();
    w.dispose();
  });

  test('reset forgets the version; errors are ignored', () async {
    var calls = 0;
    final w = CatalogVersionWatcher(() async {
      calls++;
      if (calls == 2) throw Exception('offline');
      return calls == 1 ? 'a' : 'b';
    });
    expect(await w.check(), isFalse);
    expect(await w.check(), isFalse); // error
    w.reset();
    expect(await w.check(), isFalse); // 'b' remembered after reset
    w.dispose();
  });
}
