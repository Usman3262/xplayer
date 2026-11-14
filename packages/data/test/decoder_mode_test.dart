import 'package:data/src/playback/decoder_mode.dart';
import 'package:test/test.dart';

void main() {
  test('new or invalid saved preferences select Auto', () {
    expect(AppDecoderMode.fromKey(null), AppDecoderMode.auto);
    expect(AppDecoderMode.fromKey('unknown'), AppDecoderMode.auto);
  });
  test('all modes preserve their stable saved keys', () {
    for (final mode in AppDecoderMode.values) {
      expect(AppDecoderMode.fromKey(mode.key), mode);
    }
  });
  test('hardware requests Android MediaCodec copy; software disables hwdec', () {
    expect(AppDecoderMode.androidHardware.mpvValueFor(android: true), 'mediacodec-copy');
    expect(AppDecoderMode.software.mpvValueFor(android: true), 'no');
    expect(AppDecoderMode.auto.mpvValueFor(android: true), 'auto-safe');
  });
  test('Surface mode pairs Android decoder and output without affecting other platforms', () {
    final mode = AppDecoderMode.androidSurface;
    expect(mode.mpvValueFor(android: true), 'mediacodec');
    expect(mode.videoOutputFor(android: true), 'mediacodec_embed');
    expect(mode.mpvValueFor(android: false), 'auto-safe');
    expect(mode.videoOutputFor(android: false), isNull);
    expect(mode.androidOnly, isTrue);
    for (final other in AppDecoderMode.values.where((value) => value != mode)) {
      expect(other.videoOutputFor(android: true), isNull);
    }
  });
  test('Android decoder cannot be requested on other platforms', () {
    expect(AppDecoderMode.androidHardware.mpvValueFor(android: false), 'auto-safe');
    expect(AppDecoderMode.software.mpvValueFor(android: false), 'no');
  });
}
