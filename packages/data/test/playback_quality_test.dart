import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  group('playbackMaxHeightFor', () {
    test('Data saver caps at 720', () {
      expect(
        playbackMaxHeightFor(
          qualityPref: 'Data saver',
          tier: DeviceTier.high,
        ),
        720,
      );
    });

    test('Original is 2160', () {
      expect(
        playbackMaxHeightFor(
          qualityPref: 'Original',
          tier: DeviceTier.low,
        ),
        2160,
      );
    });

    test('Auto follows tier', () {
      expect(
        playbackMaxHeightFor(qualityPref: 'Auto', tier: DeviceTier.low),
        720,
      );
      expect(
        playbackMaxHeightFor(qualityPref: 'Auto', tier: DeviceTier.mid),
        1080,
      );
      expect(
        playbackMaxHeightFor(qualityPref: 'Auto', tier: DeviceTier.high),
        2160,
      );
    });
  });

  group('DeviceCapabilities.computeTier', () {
    test('low RAM → low', () {
      expect(
        DeviceCapabilities.computeTier(
          totalRamMb: 2048,
          isLowRamDevice: false,
          hevc: null,
        ),
        DeviceTier.low,
      );
    });

    test('high RAM + hevc4k → high', () {
      expect(
        DeviceCapabilities.computeTier(
          totalRamMb: 8192,
          isLowRamDevice: false,
          hevc: const CodecMaxRes(
            mime: 'video/hevc',
            width: 3840,
            height: 2160,
            fps: 60,
          ),
        ),
        DeviceTier.high,
      );
    });
  });

  group('TierMpvConfig.forCapabilities', () {
    test('low tier preserves automatic hardware negotiation', () {
      const caps = DeviceCapabilities(
        model: 'X657B',
        brand: 'Infinix',
        hardware: 'mt6761',
        socModel: 'mt6761',
        sdkInt: 30,
        release: '11',
        abis: ['armeabi-v7a'],
        totalRamMb: 2848,
        isLowRamDevice: true,
        screenWidthPx: 720,
        screenHeightPx: 1432,
        density: 2,
        refreshRate: 60,
        hdr: false,
        codecs: {},
        tier: DeviceTier.low,
      );
      final cfg = TierMpvConfig.forCapabilities(caps);
      expect(cfg.hwdec, 'auto-safe');
      expect(cfg.hwdecCodecs, isNull);
    });
  });

  test('missing 4K support does not blacklist all HEVC hardware decoding', () {
    const caps = DeviceCapabilities(
      model: 'X672', brand: 'Infinix', hardware: 'mt6781', socModel: 'mt6781',
      sdkInt: 31, release: '12', abis: ['arm64-v8a'], totalRamMb: 7745,
      isLowRamDevice: false, screenWidthPx: 1080, screenHeightPx: 2291,
      density: 3, refreshRate: 60, hdr: false, tier: DeviceTier.mid,
      codecs: {'video/hevc': CodecMaxRes(
        mime: 'video/hevc', width: 1920, height: 1080, fps: 30,
      )},
    );
    expect(caps.hevc4k, isFalse);
    final cfg = TierMpvConfig.forCapabilities(caps);
    expect(cfg.hwdec, 'auto-safe');
    expect(cfg.hwdecCodecs, isNull);
    expect(cfg.maxHeight, 1080);
  });

  group('PlaybackUiState', () {
    test('loading phases', () {
      expect(
        const PlaybackUiState(phase: PlaybackPhase.openingMedia).isLoading,
        isTrue,
      );
      expect(
        const PlaybackUiState(phase: PlaybackPhase.playing).isLoading,
        isFalse,
      );
    });
  });
}
