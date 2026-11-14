/// Decoder selection within MPV/FFmpeg; this does not change playback engines.
enum AppDecoderMode {
  auto('auto', 'auto-safe'),
  androidHardware('hardware', 'mediacodec-copy'),
  androidSurface('surface', 'mediacodec'),
  software('software', 'no');

  const AppDecoderMode(this.key, this.mpvValue);
  final String key;
  final String mpvValue;

  String mpvValueFor({required bool android}) =>
      androidOnly && !android ? auto.mpvValue : mpvValue;

  bool get androidOnly => this == androidHardware || this == androidSurface;

  // Surface decoding must be paired with its matching native output driver.
  // Never set mediacodec alone with the default GPU/copy output path.
  String? videoOutputFor({required bool android}) =>
      android && this == androidSurface ? 'mediacodec_embed' : null;

  /// mpv `hwdec` on Windows (Settings → Video decoder). Auto = mpv's safe
  /// GPU pick (zero-copy d3d11va where the GPU has the codec); a list such
  /// as 'd3d11va,nvdec,dxva2' fell back to CPU decoding with the bundled
  /// mpv 0.36. The explicit GPU choices help where Auto picks the CPU.
  String get windowsMpvValue => switch (this) {
        auto => 'auto-safe',
        androidHardware => 'd3d11va',
        androidSurface => 'dxva2',
        software => 'no',
      };

  /// Settings label on Windows.
  String pcLabel({bool arabic = false}) => switch (this) {
        auto => arabic ? 'تلقائي (GPU)' : 'Auto (GPU)',
        androidHardware => arabic ? 'GPU · D3D11' : 'GPU · D3D11',
        androidSurface =>
          arabic ? 'GPU · DXVA2 (بطاقات أقدم)' : 'GPU · DXVA2 (older GPUs)',
        software => arabic ? 'برمجي (CPU)' : 'Software (CPU)',
      };

  static AppDecoderMode fromKey(String? key) =>
      values.firstWhere((mode) => mode.key == key, orElse: () => auto);

  String label({bool arabic = false}) => switch (this) {
    auto => arabic ? 'تلقائي' : 'Auto',
    androidHardware => arabic ? 'عتاد أندرويد' : 'Android hardware',
    androidSurface => arabic ? 'عتاد أندرويد (Surface)' : 'Android Surface hardware',
    software => arabic ? 'برمجي' : 'Software',
  };
}
