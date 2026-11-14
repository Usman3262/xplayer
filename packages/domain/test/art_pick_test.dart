import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = 'http://cf.00112.xyz/images/8k_backdrop.jpg';
  const tmdb = 'https://image.tmdb.org/t/p/w1280/abc.jpg';

  test('TMDB image wins over provider art with a burned-in logo', () {
    expect(pickCleanArt([provider, tmdb]), tmdb);
  });

  test('falls back to the first non-empty image', () {
    expect(pickCleanArt([null, '', ' ', provider]), provider);
    expect(pickCleanArt(const [null, 'null']), isNull);
  });

  test('wide art uses the poster only when no backdrop exists', () {
    expect(pickWideArt([null], poster: 'p.jpg'), 'p.jpg');
    // Client 4 Nov: the poster before a provider backdrop ("8K" logo).
    expect(pickWideArt([provider], poster: tmdb), tmdb);
    expect(pickWideArt([provider], poster: 'p.jpg'), 'p.jpg');
    expect(pickWideArt([provider, tmdb], poster: 'p.jpg'), tmdb);
    expect(pickWideArt([provider]), provider);
  });
}
