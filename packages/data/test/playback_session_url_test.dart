import 'package:data/src/remote/media_models.dart';
import 'package:test/test.dart';

// The lease no longer picks a "preferred" URL: the player opens [playUrl]
// first and tries [alternatePlayUrls] in backend order only if it fails.
void main() {
  test('http primary stays the first URL; https alternate is a fallback', () {
    final lease = PlaybackSessionDto.fromJson({
      'playbackId': 'p1',
      'contentType': 'vod',
      'streamId': '1',
      'playUrl': 'http://cf.00112.xyz/movie/a/b/1.mkv',
      'alternatePlayUrls': [
        'https://cf.00112.xyz/movie/a/b/1.mkv',
      ],
    });
    expect(lease.playUrl, 'http://cf.00112.xyz/movie/a/b/1.mkv');
    expect(lease.alternatePlayUrls, ['https://cf.00112.xyz/movie/a/b/1.mkv']);
  });

  test('https primary is kept; alternates keep backend order', () {
    final lease = PlaybackSessionDto.fromJson({
      'playbackId': 'p1',
      'contentType': 'vod',
      'streamId': '1',
      'playUrl': 'https://cdn.example/x.mkv',
      'alternatePlayUrls': [
        'http://cdn.example/x.mkv',
        'https://backup.example/x.mkv',
      ],
    });
    expect(lease.playUrl, 'https://cdn.example/x.mkv');
    expect(lease.alternatePlayUrls, [
      'http://cdn.example/x.mkv',
      'https://backup.example/x.mkv',
    ]);
  });
}
