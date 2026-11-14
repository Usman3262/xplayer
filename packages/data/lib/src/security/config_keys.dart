/// Ed25519 public keys (raw 32 bytes, base64) trusted for a signed remote
/// app config, by key id. Empty = signed remote config is off.
const Map<String, String> kConfigPublicKeys = {};

/// Static copies of the signed config (https only). Empty = none.
const List<String> kConfigMirrorUrls = [];

/// Install / update links for self-hosted APKs. Empty = in-app update off.
abstract final class AppReleaseUrls {
  static const installPage = '';
  static const tvApk = '';
  static const mobileApk = '';
  static const releasesJson = '';
}
