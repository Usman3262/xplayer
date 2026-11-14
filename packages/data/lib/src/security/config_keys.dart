/// Ed25519 public keys (raw 32 bytes, base64) trusted for the signed app
/// config, by key id. Public keys are safe to commit.
///
/// Backend `npm run config:export` / production `k1` (20 Oct 2026).
/// `k2` (5 Nov 2026): next key, trusted now so the server can switch to it once
/// most customers run a build that contains it (key rotation, client item B03).
/// Rotation: add the next kid here and release; then switch the server; then
/// remove the old kid in a later release.
const Map<String, String> kConfigPublicKeys = {
  'k1': 'f9mW6WD8Ypg1WdgYSBuZELEGBJLzYYqkKbpsEMnlct4=',
  'k2': 'eDTvMYF2vCtkNYe1G5hVf1Fgz9JuONqd9+unv2hEXcg=',
};

/// Static copies of the signed config on hosts that do not share the API's
/// fate (7-day validity). Verified with [kConfigPublicKeys]. https only.
const List<String> kConfigMirrorUrls = [
  'https://download.sksj.online/config.json',
];

/// Permanent install / update APK links (always newest published build).
/// Used by TV Downloader and the in-app update screen. Never change these
/// strings without ops + client notice.
abstract final class AppReleaseUrls {
  static const installPage = 'https://download.sksj.online';
  static const tvApk = 'https://download.sksj.online/tv.apk';
  static const mobileApk = 'https://download.sksj.online/mobile.apk';
  static const releasesJson = 'https://download.sksj.online/releases.json';
}
