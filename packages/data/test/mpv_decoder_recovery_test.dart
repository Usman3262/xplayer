import 'package:test/test.dart';

import '../lib/src/playback/mpv_decoder_recovery.dart';

void main() {
  group('classifyAppMpvDecoderEvidence', () {
    test('null surface', () {
      expect(
        classifyAppMpvDecoderEvidence(
          'ffmpeg/video: h264_mediacodec: Both surface and native_window are NULL',
        ),
        AppMpvDecoderEvidence.nullSurface,
      );
    });

    test('released / flush', () {
      expect(
        classifyAppMpvDecoderEvidence(
          'flush() is valid only at Executing states; currently at Released state',
        ),
        AppMpvDecoderEvidence.codecReleased,
      );
      expect(
        classifyAppMpvDecoderEvidence(
          'Failed to dequeue output buffer (status=-542398533)',
        ),
        AppMpvDecoderEvidence.codecReleased,
      );
    });

    test('hw decode frame', () {
      expect(
        classifyAppMpvDecoderEvidence(
          'Error while decoding frame (hardware decoding)!',
        ),
        AppMpvDecoderEvidence.hwDecodeFrame,
      );
    });

    test('unrelated noise', () {
      expect(
        classifyAppMpvDecoderEvidence('property not found osc'),
        AppMpvDecoderEvidence.none,
      );
      expect(
        classifyAppMpvDecoderEvidence('Failed to create file cache.'),
        AppMpvDecoderEvidence.none,
      );
      expect(classifyAppMpvDecoderEvidence(null), AppMpvDecoderEvidence.none);
    });
  });
}
