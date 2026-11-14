/// Device performance tier for playback + UI (brief §5.3).
enum DeviceTier { low, mid, high }

class CodecMaxRes {
  const CodecMaxRes({
    required this.mime,
    required this.width,
    required this.height,
    required this.fps,
    this.uhdFps,
    this.fhdFps,
  });

  final String mime;
  final int width;
  final int height;

  /// Frame rate at [width]x[height]. Width and height are independent upper
  /// bounds, so that corner size may be unsupported or only supported at a
  /// low rate even when 3840x2160@30 is fine.
  final double fps;

  /// Max frame rate measured at exactly 3840x2160 (0 = size unsupported).
  /// Null for capabilities cached by builds before 5.1.14.
  final double? uhdFps;

  /// Max frame rate measured at exactly 1920x1080 (0 = size unsupported).
  final double? fhdFps;

  bool supports({required int w, required int h, double fps = 30}) {
    // Prefer measurements taken at the requested standard size.
    final measured = w <= 1920 && h <= 1080
        ? fhdFps
        : (w <= 3840 && h <= 2160 ? uhdFps : null);
    if (measured != null) return measured + 0.5 >= fps;
    return width >= w && height >= h && this.fps + 0.5 >= fps;
  }

  Map<String, dynamic> toJson() => {
    'mime': mime,
    'width': width,
    'height': height,
    'fps': fps,
    if (uhdFps != null) 'uhdFps': uhdFps,
    if (fhdFps != null) 'fhdFps': fhdFps,
  };

  factory CodecMaxRes.fromJson(Map<String, dynamic> j) => CodecMaxRes(
    mime: '${j['mime'] ?? ''}',
    width: (j['width'] as num?)?.toInt() ?? 0,
    height: (j['height'] as num?)?.toInt() ?? 0,
    fps: (j['fps'] as num?)?.toDouble() ?? 0,
    uhdFps: (j['uhdFps'] as num?)?.toDouble(),
    fhdFps: (j['fhdFps'] as num?)?.toDouble(),
  );
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.model,
    required this.brand,
    required this.hardware,
    required this.socModel,
    required this.sdkInt,
    required this.release,
    required this.abis,
    required this.totalRamMb,
    required this.isLowRamDevice,
    required this.screenWidthPx,
    required this.screenHeightPx,
    required this.density,
    required this.refreshRate,
    required this.hdr,
    required this.codecs,
    required this.tier,
  });

  final String model;
  final String brand;
  final String hardware;
  final String socModel;
  final int sdkInt;
  final String release;
  final List<String> abis;
  final int totalRamMb;
  final bool isLowRamDevice;
  final int screenWidthPx;
  final int screenHeightPx;
  final double density;
  final double refreshRate;
  final bool hdr;
  final Map<String, CodecMaxRes> codecs;
  final DeviceTier tier;

  CodecMaxRes? get hevc => codecs['video/hevc'];
  CodecMaxRes? get avc => codecs['video/avc'];
  CodecMaxRes? get vp9 => codecs['video/x-vnd.on2.vp9'];
  CodecMaxRes? get av1 => codecs['video/av01'];

  bool get hevc4k {
    final c = hevc;
    return c != null && c.supports(w: 3840, h: 2160);
  }

  bool get avc1080 {
    final c = avc;
    return c != null && c.supports(w: 1920, h: 1080);
  }

  static DeviceTier computeTier({
    required int totalRamMb,
    required bool isLowRamDevice,
    required CodecMaxRes? hevc,
  }) {
    if (isLowRamDevice || totalRamMb <= 3072) return DeviceTier.low;
    final can4k = hevc != null && hevc.supports(w: 3840, h: 2160);
    if (totalRamMb >= 6144 && can4k) return DeviceTier.high;
    if (totalRamMb < 6144) return DeviceTier.mid;
    return can4k ? DeviceTier.high : DeviceTier.mid;
  }

  String get diagLine {
    final h4 = hevc4k ? 'yes' : 'no';
    final a1 = avc1080 ? 'yes' : 'no';
    return 'tier=${tier.name} model=$model brand=$brand hardware=$hardware '
        'soc=$socModel android=$release sdk=$sdkInt ramMb=$totalRamMb '
        'lowRam=$isLowRamDevice hevc4k=$h4 avc1080=$a1 '
        'screen=${screenWidthPx}x$screenHeightPx dens=$density '
        'refresh=$refreshRate hdr=$hdr abis=${abis.join(",")}';
  }
}

/// mpv / PlayerConfiguration values per tier (brief §7).
class TierMpvConfig {
  const TierMpvConfig({
    required this.tier,
    required this.hwdec,
    required this.demuxerMaxBytes,
    required this.demuxerMaxBackBytes,
    required this.demuxerReadaheadSecs,
    required this.cacheSecs,
    required this.bufferSizeBytes,
    required this.maxHeight,
    required this.imageCacheMb,
    this.vdLavcThreads,
    this.hwdecCodecs,
  });

  final DeviceTier tier;
  final String hwdec;
  final int demuxerMaxBytes;
  final int demuxerMaxBackBytes;
  final int demuxerReadaheadSecs;
  final int cacheSecs;
  final int bufferSizeBytes;
  final int maxHeight;
  final int imageCacheMb;
  final int? vdLavcThreads;

  /// Optional explicit codec allowlist; null uses mpv automatic negotiation.
  final String? hwdecCodecs;

  factory TierMpvConfig.forTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.low:
        return const TierMpvConfig(
          tier: DeviceTier.low,
          hwdec: 'auto-safe',
          demuxerMaxBytes: 32 * 1024 * 1024,
          demuxerMaxBackBytes: 8 * 1024 * 1024,
          demuxerReadaheadSecs: 30,
          cacheSecs: 30,
          bufferSizeBytes: 32 * 1024 * 1024,
          maxHeight: 720,
          imageCacheMb: 40,
          vdLavcThreads: 2,
          hwdecCodecs: null,
        );
      case DeviceTier.mid:
        return const TierMpvConfig(
          tier: DeviceTier.mid,
          hwdec: 'auto-safe',
          demuxerMaxBytes: 80 * 1024 * 1024,
          demuxerMaxBackBytes: 16 * 1024 * 1024,
          demuxerReadaheadSecs: 60,
          cacheSecs: 60,
          bufferSizeBytes: 64 * 1024 * 1024,
          maxHeight: 1080,
          imageCacheMb: 80,
        );
      case DeviceTier.high:
        return const TierMpvConfig(
          tier: DeviceTier.high,
          hwdec: 'auto-safe',
          demuxerMaxBytes: 140 * 1024 * 1024,
          demuxerMaxBackBytes: 32 * 1024 * 1024,
          demuxerReadaheadSecs: 90,
          cacheSecs: 90,
          bufferSizeBytes: 128 * 1024 * 1024,
          maxHeight: 2160,
          imageCacheMb: 160,
        );
    }
  }

  /// Resolution probes guide source selection, not codec-wide exclusions.
  /// Let mpv negotiate each stream with Android and fall back on real failure.
  factory TierMpvConfig.forCapabilities(DeviceCapabilities caps) =>
      TierMpvConfig.forTier(caps.tier);

  String get pbLine =>
      'mpv-config tier=${tier.name} hwdec=$hwdec '
      'demuxerMax=${demuxerMaxBytes ~/ (1024 * 1024)}MiB '
      'readahead=$demuxerReadaheadSecs cacheSecs=$cacheSecs '
      'bufferSize=${bufferSizeBytes ~/ (1024 * 1024)}MiB maxHeight=$maxHeight';
}
