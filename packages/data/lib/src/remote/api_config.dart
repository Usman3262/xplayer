import 'package:flutter/foundation.dart';

/// Backend API base (no trailing slash).
///
/// No backend is configured: the old one was removed. The app's data layer
/// (repositories, DTOs, API clients) is kept so a new source (Neo / Supabase)
/// can plug in with the same shapes. Until then every remote call fails fast
/// and the in-app demo catalog still works.
///
/// Set one at build/run time:
/// `flutter run --dart-define=APP_API_BASE=https://host/v1`
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  final String baseUrl;

  /// Built-in API base. Empty = no backend.
  static const defaultBaseUrl = '';

  /// Built-in backup bases tried after [defaultBaseUrl] on network failure.
  static const builtInBackupBaseUrls = <String>[];

  /// True when a backend base URL is set.
  bool get isConfigured => baseUrl.isNotEmpty;

  factory ApiConfig.fromEnvironment() {
    const fromEnv = String.fromEnvironment(
      'APP_API_BASE',
      defaultValue: defaultBaseUrl,
    );
    final base = fromEnv.trim().replaceAll(RegExp(r'/$'), '');
    // Release builds talk to the backend over HTTPS only.
    if (kReleaseMode && base.isNotEmpty && !base.startsWith('https://')) {
      return const ApiConfig(baseUrl: defaultBaseUrl);
    }
    return ApiConfig(baseUrl: base);
  }
}
