import 'package:data/data.dart';
import 'package:test/test.dart';

// Usman 13 Nov: GET /v1/downloads?profileId= (every device of the profile).
void main() {
  test('a download removed in the panel reads as removed', () {
    final d = ProfileDownloadDto.fromJson({
      'grantId': 'g1',
      'deviceId': 'dev-2',
      'deviceName': 'Living room TV',
      'contentType': 'series',
      'streamId': '900',
      'seriesId': '77',
      'episodeId': '901',
      'title': 'Episode 1',
      'state': 'removed',
      'containerExtension': 'mkv',
      'status': 'CANCELLED',
      'sizeBytes': 123456,
    });
    expect(d.isRemoved, isTrue);
    expect(d.playableId, '901');
    expect(d.deviceName, 'Living room TV');
    expect(d.sizeBytes, 123456);
    expect(d.containerExtension, 'mkv');
  });

  test('state falls back to status on older answers', () {
    expect(ProfileDownloadDto.fromJson({'status': 'CANCELLED'}).isRemoved, isTrue);
    expect(ProfileDownloadDto.fromJson({'status': 'COMPLETED'}).isCompleted, isTrue);
    expect(ProfileDownloadDto.fromJson({'status': 'ACTIVE'}).state, 'active');
    expect(ProfileDownloadDto.fromJson({'contentType': 'vod', 'streamId': '5'}).playableId, '5');
  });
}
