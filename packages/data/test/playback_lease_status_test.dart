import 'package:data/src/remote/media_models.dart';
import 'package:test/test.dart';

void main() {
  test('PlaybackLeaseStatusDto inactive', () {
    final dto = PlaybackLeaseStatusDto.fromJson({
      'status': 'Inactive',
      'label': '0/1',
      'active': 0,
      'max': 1,
      'playback': null,
    });
    expect(dto.isActive, isFalse);
    expect(dto.label, '0/1');
    expect(dto.playback, isNull);
  });

  test('PlaybackLeaseStatusDto active with device', () {
    final dto = PlaybackLeaseStatusDto.fromJson({
      'status': 'Active',
      'label': '1/1',
      'active': 1,
      'max': 1,
      'playback': {
        'playbackId': 'p1',
        'deviceId': 'd1',
        'contentType': 'live',
        'streamId': '99',
        'startedAt': '2026-10-12T08:00:00.000Z',
        'expiresAt': '2026-10-12T08:03:00.000Z',
      },
    });
    expect(dto.isActive, isTrue);
    expect(dto.label, '1/1');
    expect(dto.playback?.deviceId, 'd1');
    expect(dto.playback?.streamId, '99');
  });
}
