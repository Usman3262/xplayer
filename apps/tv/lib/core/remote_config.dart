import 'package:data/data.dart';
import 'package:design_system/design_system.dart' show AppLogo, AppThemeConfig;
import 'package:domain/domain.dart' show AppBrand;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';

/// Remote configuration from the admin panel (theme, flags, branding, home,
/// login policy …). The app's screens stay as designed — config only changes
/// colours, texts, what's on/off and what the rails show (D17).
class RemoteConfigService {
  RemoteConfigService._();

  static RemoteConfigRepository? _repo;

  /// The published config in use (built-in defaults until one arrives).
  static ValueListenable<RemoteConfig> get listenable =>
      _repo?.current ?? ValueNotifier(RemoteConfig.empty);

  static RemoteConfig get current => _repo?.current.value ?? RemoteConfig.empty;

  /// Call once in main() before runApp: applies the cached config instantly,
  /// then refreshes in the background.
  static Future<void> init({required String appVersion}) async {
    final client = Backend.client;
    if (client == null) return; // no backend configured → built-in defaults
    final repo = RemoteConfigRepository(
      platform: _platform,
      appVersion: appVersion,
      country: PlatformDispatcher.instance.locale.countryCode,
      fetch: (params) => client.rpc('get_app_config', params: params),
    );
    _repo = repo;
    repo.current.addListener(() => _apply(repo.current.value));
    final cached = await repo.loadCached();
    _apply(cached);
    // Network after the first frame; never blocks startup.
    Future<void>.delayed(Duration.zero, () async {
      await repo.refresh();
      repo.startAutoRefresh();
    });
  }

  /// Re-check now (app resumed, user signed in/out). Never throws.
  static Future<bool> refresh() async => (await _repo?.refresh()) ?? false;

  /// The TV app always reports the "tv" platform.
  static String get _platform => 'tv';

  static void _apply(RemoteConfig c) {
    if (c.version == 0) return; // nothing published / cached yet
    if (c.theme.isNotEmpty) AppThemeConfig.applyJson(c.theme);
    AppBrand.setDisplayOverride(c.stringSetting('branding.display_name', ''));
    final logo = c.stringSetting('branding.logo_url', '').trim();
    AppLogo.remoteUrl = logo.startsWith('https://') ? logo : null;
  }
}

/// Config for widgets. Rebuilds when a new config is applied.
final remoteConfigProvider = Provider<RemoteConfig>((ref) {
  final l = RemoteConfigService.listenable;
  void listener() => ref.invalidateSelf();
  l.addListener(listener);
  ref.onDispose(() => l.removeListener(listener));
  return l.value;
});

/// `ref.watch(featureEnabledProvider('sports'))` — unknown flags default to on,
/// so an older config never hides a feature the app can't name.
final featureEnabledProvider = Provider.family<bool, String>(
  (ref, flag) => ref.watch(remoteConfigProvider).isEnabled(flag),
);

/// Pages that belong to a feature flag. A switched-off feature's page is never
/// shown, whatever button, deep link or notification tried to open it.
const _routeFlags = <String, String>{
  '/movies': 'movies',
  '/series': 'series',
  '/live': 'live_tv',
  '/sports': 'sports',
  '/match-centre': 'sports',
  '/kids': 'kids',
  '/clips': 'clips',
  '/downloads': 'downloads',
  '/offline': 'downloads',
  '/search': 'search',
  '/inbox': 'notification_inbox',
  '/my-list': 'favorites',
  '/settings/diagnostic': 'diagnostics',
  '/settings/appearance': 'theme_presets',
  '/settings/parental': 'parental_controls',
};

/// Router guard: '/home' when [location] belongs to a switched-off feature.
String? featureOffRedirect(String location, [RemoteConfig? override]) {
  final config = override ?? RemoteConfigService.current;
  for (final e in _routeFlags.entries) {
    final matches = location == e.key || location.startsWith('${e.key}/');
    if (matches && !config.isEnabled(e.value)) return '/home';
  }
  return null;
}
