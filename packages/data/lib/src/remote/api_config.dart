import 'package:flutter/foundation.dart';

/// Backend API base including `/v1` (no trailing slash).
///
/// Override at build/run time:
/// `flutter run --dart-define=APP_API_BASE=https://host/v1`
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  final String baseUrl;

  /// Primary API behind Cloudflare (firewall / DDoS protection, 23 Oct).
  static const defaultBaseUrl = 'https://api.sksj.online/v1';

  /// Built-in backups tried after [defaultBaseUrl] on network failure, before
  /// any backup learned from the signed config. Only used with the default
  /// base, so a local `APP_API_BASE` override never falls back to
  /// production. Empty since 5 Nov: the old Railway address no longer
  /// exists; the server's signed config is the only source of backups.
  static const builtInBackupBaseUrls = <String>[];

  factory ApiConfig.fromEnvironment() {
    const fromEnv = String.fromEnvironment(
      'APP_API_BASE',
      defaultValue: defaultBaseUrl,
    );
    final base = fromEnv.replaceAll(RegExp(r'/$'), '');
    // Account and control traffic is HTTPS only in release builds (client
    // 19 Oct: cleartext is allowed only for provider media). A plain-HTTP
    // override is accepted for local debug/profile runs only.
    if (kReleaseMode && !base.startsWith('https://')) {
      return const ApiConfig(baseUrl: defaultBaseUrl);
    }
    return ApiConfig(baseUrl: base);
  }
}
