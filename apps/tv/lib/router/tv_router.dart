import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/tv_session.dart';
import '../features/sports/tv_match_centre_screen.dart';
import '../features/account/tv_my_account_screen.dart';
import '../features/auth/tv_legal_screen.dart';
import '../features/auth/tv_login_screen.dart';
import '../features/browse/tv_new_popular_screen.dart';
import '../features/clips/tv_clips_soon_screen.dart';
import '../features/browse/tv_view_all_screen.dart';
import '../features/details/tv_details_screen.dart';
import '../widgets/tv_exit_guard.dart';
import '../features/downloads/tv_downloads_screen.dart';
import '../features/downloads/tv_offline_player_screen.dart';
import '../features/home/tv_home_screen.dart';
import '../features/notifications/tv_inbox_screen.dart';
import '../features/kids/tv_kids_screen.dart';
import '../features/library/tv_library_hub_screen.dart';
import '../features/live/tv_live_screen.dart';
import '../features/movies/tv_movies_screen.dart';
import '../features/player/tv_player_screen.dart';
import '../features/profiles/tv_edit_profile_screen.dart';
import '../features/profiles/tv_manage_profiles_screen.dart';
import '../features/profiles/tv_profiles_screen.dart';
import '../features/search/tv_search_screen.dart';
import '../features/series/tv_series_screen.dart';
import '../features/settings/tv_customize_home_screen.dart';
import '../features/settings/tv_devices_screen.dart';
import '../features/settings/tv_mfa_setup_screen.dart';
import '../features/settings/tv_security_screen.dart';
import '../features/settings/tv_sessions_screen.dart';
import '../features/settings/tv_settings_screen.dart';
import '../features/settings/tv_splash_preview_screen.dart';
import '../features/settings/tv_subscription_screen.dart';
import '../features/splash/tv_splash_screen.dart';
import '../features/sports/tv_sports_screen.dart';
import '../features/update/tv_update_app_screen.dart';
import '../core/tv_demo_mode.dart';
import '../shell/tv_shell.dart';

final tvRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _TvRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(tvSessionProvider);
      final loc = state.matchedLocation;

      if (!session.bootstrapped) {
        return loc == '/splash' ? null : '/splash';
      }

      // Splash owns its exit (anim + bootstrap). Keep it until the screen
      // navigates; do not bounce other routes back here after bootstrap.
      if (loc == '/splash') return null;

      // Force-update gate (minVersion.tv) — reachable before login.
      if (loc == '/update') return null;

      // Task #143 #4: legal pages reachable while logged out (login footer).
      final isPublicLegal =
          loc == '/legal/terms' || loc == '/legal/privacy';
      if (!session.loggedIn) {
        // Demo (client 5 Nov #30): the app pages open, account pages ask to sign in.
        if (ref.read(tvDemoModeProvider)) return tvDemoRedirect(loc);
        if (loc == '/login' || isPublicLegal) return null;
        return '/login';
      }

      if (!session.profileSelected) {
        return loc.startsWith('/profiles') ? null : '/profiles';
      }

      // Login is done — bounce away. /profiles stays reachable as a switcher
      // after selection (Back returns to the previous route).
      if (loc == '/login') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const TvSplashScreen(),
      ),
      GoRoute(
        path: '/update',
        builder: (_, _) => const TvUpdateAppScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const TvExitGuard(child: TvLoginScreen()),
      ),
      GoRoute(
        path: '/legal/terms',
        builder: (_, _) => const TvLegalScreen(kind: 'terms'),
      ),
      GoRoute(
        path: '/legal/privacy',
        builder: (_, _) => const TvLegalScreen(kind: 'privacy'),
      ),
      GoRoute(
        path: '/profiles',
        builder: (_, _) => const TvExitGuard(child: TvProfilesScreen()),
      ),
      GoRoute(
        path: '/profiles/manage',
        builder: (_, _) => const TvManageProfilesScreen(),
      ),
      GoRoute(
        path: '/profiles/edit/:id',
        builder: (_, state) =>
            TvEditProfileScreen(id: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return TvShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const TvHomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/movies',
                builder: (_, _) => const TvMoviesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/series',
                builder: (_, _) => const TvSeriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/live', builder: (_, _) => const TvLiveScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sports',
                builder: (_, _) => const TvSportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/kids',
                builder: (_, _) => const TvKidsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-account',
                builder: (_, _) => const TvMyAccountScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/new',
                builder: (_, _) => const TvNewPopularScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-list',
                builder: (_, state) {
                  final tab = state.uri.queryParameters['tab'];
                  return TvLibraryHubScreen(
                    key: ValueKey('library-${tab ?? 'cw'}'),
                    initialTab: libraryTabFromQuery(tab),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, state) => TvSearchScreen(
                  scope: TvSearchScreen.scopeFromQuery(
                    state.uri.queryParameters['scope'],
                  ),
                  kids: state.uri.queryParameters['scope'] == 'kids',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const TvSettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/library',
        redirect: (context, state) {
          final tab = state.uri.queryParameters['tab'];
          if (tab == null || tab.isEmpty) return '/my-list';
          return '/my-list?tab=$tab';
        },
      ),
      GoRoute(
        path: '/browse/:kind/:categoryId',
        builder: (_, state) => TvViewAllScreen(
          // Live/Sports rows also link here; they used to fall through to
          // movie and list the wrong (empty) catalog.
          kind: switch (state.pathParameters['kind']) {
            'series' => MediaKind.series,
            'live' => MediaKind.live,
            'sports' => MediaKind.live,
            _ => MediaKind.movie,
          },
          categoryId: state.pathParameters['categoryId']!,
          title: state.uri.queryParameters['title'] ?? '',
        ),
      ),
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const TvInboxScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (_, _) => const TvDownloadsScreen(),
      ),
      GoRoute(
        path: '/offline/:id',
        builder: (_, state) =>
            TvOfflinePlayerScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/clips',
        builder: (_, _) => const TvClipsSoonScreen(),
      ),
      // Match centre: fixtures, lineups, events, statistics.
      GoRoute(
        path: '/match-centre',
        builder: (_, _) => const TvMatchCentreScreen(),
      ),
      GoRoute(
        path: '/match-centre/:id',
        builder: (_, state) => TvMatchScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/details/:id',
        builder: (_, state) =>
            TvDetailsScreen(
              id: state.pathParameters['id']!,
              initial: state.extra is MediaItem ? state.extra as MediaItem : null,
            ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (_, state) {
          final start =
              int.tryParse(state.uri.queryParameters['startSec'] ?? '');
          final seriesId = state.uri.queryParameters['seriesId'];
          final kindRaw = state.uri.queryParameters['kind'];
          MediaKind? kindHint;
          switch (kindRaw) {
            case 'live':
              kindHint = MediaKind.live;
            case 'series':
              kindHint = MediaKind.series;
            case 'vod':
            case 'movie':
              kindHint = MediaKind.movie;
            case 'sports':
              kindHint = MediaKind.sports;
          }
          final title = state.uri.queryParameters['title'];
          final extra = state.extra;
          return TvPlayerScreen(
            id: state.pathParameters['id']!,
            startSec: start,
            seriesId: seriesId,
            kindHint: kindHint,
            initialTitle: (title != null && title.trim().isNotEmpty)
                ? title.trim()
                : null,
            initialItem: extra is MediaItem ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/settings/security',
        builder: (_, _) => const TvSecurityScreen(),
      ),
      GoRoute(
        path: '/settings/security/mfa',
        builder: (_, _) => const TvMfaSetupScreen(),
      ),
      GoRoute(
        path: '/settings/security/sessions',
        builder: (_, _) => const TvSessionsScreen(),
      ),
      GoRoute(
        path: '/settings/devices',
        builder: (_, _) => const TvDevicesScreen(),
      ),
      GoRoute(
        path: '/settings/subscription',
        builder: (_, _) => const TvSubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings/customize-home',
        builder: (_, _) => const TvCustomizeHomeScreen(),
      ),
      GoRoute(
        path: '/settings/lab/splash-preview',
        builder: (_, _) => const TvSplashPreviewScreen(),
      ),
    ],
  );
});

class _TvRouterRefresh extends ChangeNotifier {
  _TvRouterRefresh(this.ref) {
    _sub = ref.listen<TvSessionState>(tvSessionProvider, (_, next) {
      // Signing in ends the demo.
      if (next.loggedIn && ref.read(tvDemoModeProvider)) {
        ref.read(tvDemoModeProvider.notifier).state = false;
      }
      notifyListeners();
    });
    _demoSub = ref.listen<bool>(tvDemoModeProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
  late final ProviderSubscription<TvSessionState> _sub;
  late final ProviderSubscription<bool> _demoSub;

  @override
  void dispose() {
    _sub.close();
    _demoSub.close();
    super.dispose();
  }
}
