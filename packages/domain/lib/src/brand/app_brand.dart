/// The app's display name, for in-app text.
///
/// Do not hard-code the name anywhere. The single source of truth is
/// `app.config` at the repo root (APP_NAME). Android and iOS build it into the
/// launcher name, and each app's `main()` copies that native name in here via
/// `AppBrand.init(...)` before `runApp`.
///
/// Admins can override the name shown *inside* the apps remotely
/// (`branding.display_name` in the published config) — see [setDisplayOverride].
/// The launcher/home-screen name itself can't change remotely.
class AppBrand {
  AppBrand._();

  static String _native = '';
  static String? _override;

  /// Display name: remote override if set, else the build name (e.g. "XPlayer").
  static String get name => _override ?? _native;

  /// The name built into the app (`app.config`), ignoring any remote override.
  static String get nativeName => _native;

  /// Called once from `main()` with `PackageInfo.appName`.
  static void init(String nativeAppName) {
    final n = nativeAppName.trim();
    if (n.isNotEmpty) _native = n;
  }

  /// Remote override from the admin panel; empty/null = use the build name.
  static void setDisplayOverride(String? value) {
    final v = value?.trim();
    _override = (v == null || v.isEmpty) ? null : v;
  }
}
