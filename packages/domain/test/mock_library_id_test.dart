import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('sample ids from early builds are recognised', () {
    expect(isMockLibraryId('movie-crimson'), isTrue);
    expect(isMockLibraryId('series-neon'), isTrue);
    expect(isMockLibraryId('episode_one'), isTrue);
  });

  test('real provider ids are never treated as samples', () {
    expect(isMockLibraryId('768292'), isFalse);
    expect(isMockLibraryId('17371'), isFalse);
    expect(isMockLibraryId(''), isFalse);
    expect(isMockLibraryId('movie-2024'), isFalse);
  });
}
