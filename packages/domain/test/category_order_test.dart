import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const a = CatalogCategory(id: '1', name: 'Arabic');
  const b = CatalogCategory(id: '2', name: 'Foreign');
  const c = CatalogCategory(id: '3', name: '4K');
  const d = CatalogCategory(id: '4', name: 'New package');

  test('saved order first, new packages after, removed ids ignored', () {
    final out = applyCategoryOrder([a, b, c, d], ['2', '99', '1', '3']);
    expect(out.map((e) => e.id), ['2', '1', '3', '4']);
  });

  test('no saved order keeps provider order', () {
    expect(applyCategoryOrder([a, b, c], const []).map((e) => e.id), ['1', '2', '3']);
  });
}
