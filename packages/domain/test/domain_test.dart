import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('media item holds id', () {
    const item = MediaItem(
      id: 'x',
      title: 'Test',
      kind: MediaKind.movie,
    );
    expect(item.id, 'x');
  });
}
