import 'package:data/src/remote/trailer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const want = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  test('bare id', () => expect('${youtubeTrailerUri('dQw4w9WgXcQ')}', want));
  test('watch url', () => expect('${youtubeTrailerUri('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3')}', want));
  test('short url', () => expect('${youtubeTrailerUri('youtu.be/dQw4w9WgXcQ')}', want));
  test('embed url', () => expect('${youtubeTrailerUri('https://youtube.com/embed/dQw4w9WgXcQ')}', want));
  test('empty / junk / other site → null', () {
    for (final v in [null, '', '  ', '0', 'n/a', 'https://example.com/v=dQw4w9WgXcQ', 'abc']) {
      expect(youtubeTrailerUri(v), isNull, reason: '$v');
    }
  });
}
