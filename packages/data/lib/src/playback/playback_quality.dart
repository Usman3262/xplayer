import '../device/device_capabilities.dart';

/// Maps Settings quality pref + device tier → maxHeight for start/selector.
int playbackMaxHeightFor({
  required String qualityPref,
  required DeviceTier tier,
}) {
  final q = qualityPref.trim().toLowerCase();
  if (q == 'data saver' || q == '720p') return 720;
  if (q == 'original' || q == 'ultra 4k' || q == '4k') return 2160;
  if (q == '1080p') return 1080;
  // Auto
  return TierMpvConfig.forTier(tier).maxHeight;
}

List<String> playbackCodecPreference({
  required String qualityPref,
  required DeviceCapabilities caps,
}) {
  final q = qualityPref.trim().toLowerCase();
  if (q == 'data saver') return const ['avc', 'hevc'];
  if (caps.tier == DeviceTier.low) return const ['avc', 'hevc'];
  return const ['hevc', 'avc'];
}
