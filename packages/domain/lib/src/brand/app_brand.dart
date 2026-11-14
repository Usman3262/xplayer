/// The app's display name, for in-app text.
///
/// Do not hard-code the name anywhere. The single source of truth is
/// `app.config` at the repo root (APP_NAME). Android and iOS build it into the
/// launcher name, and each app's `main()` copies that native name in here via
/// `AppBrand.init(...)` before `runApp`.
class AppBrand {
  AppBrand._();

  static String _name = '';

  /// Display name from `app.config` (e.g. "XPlayer").
  static String get name => _name;

  /// Called once from `main()` with `PackageInfo.appName`.
  static void init(String nativeAppName) {
    final n = nativeAppName.trim();
    if (n.isNotEmpty) _name = n;
  }
}
