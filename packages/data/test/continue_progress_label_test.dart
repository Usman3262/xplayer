import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mediaFromContinue progressLabel', () {
    test('formats elapsed / total as mm:ss / mm:ss', () {
      final item = AppMediaRepository.mediaFromContinue(
        const ContinueWatchingDto(
          streamId: 's1',
          title: 'Demo',
          contentType: 'vod',
          positionSec: 125,
          durationSec: 3600,
        ),
      );
      expect(item.progressLabel, '02:05 / 1:00:00');
    });

    test('omits total when duration missing', () {
      final item = AppMediaRepository.mediaFromContinue(
        const ContinueWatchingDto(
          streamId: 's2',
          title: 'Demo',
          contentType: 'vod',
          positionSec: 65,
          durationSec: 0,
        ),
      );
      expect(item.progressLabel, '01:05');
    });
  });
}
