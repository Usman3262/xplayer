import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_log.dart';
import '../core/demo_mode.dart';
import '../core/session_controller.dart';
import '../features/sports/match_centre_screen.dart';
import '../features/account/my_account_screen.dart';
import '../features/auth/login_approval_wait_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/mfa_verify_screen.dart';
import '../features/auth/recovery_login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/demo/demo_screens.dart';
import '../features/browse/catalog_view_all_screen.dart';
import '../features/browse/live_category_screen.dart';
import '../features/browse/kids_screen.dart';
import '../features/browse/cinema_vault_screen.dart';
import '../features/browse/new_popular_screen.dart';
import '../features/clips/clips_soon_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/downloads/offline_player_screen.dart';
import '../features/details/movie_details_screen.dart';
import '../features/details/series_details_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_hub_screen.dart';
import '../features/live/live_tv_screen.dart';
import '../features/movies/movies_screen.dart';
import '../features/my_list/my_list_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/player/player_screen.dart';
import '../features/profiles/edit_profile_screen.dart';
import '../features/profiles/manage_profiles_screen.dart';
import '../features/profiles/profile_select_screen.dart';
import '../features/search/search_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/privacy_policy_screen.dart';
import '../features/settings/terms_of_use_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/connection_diagnostic_screen.dart';
import '../features/settings/audio_subtitles_screen.dart';
import '../features/settings/customize_home_screen.dart';
import '../features/settings/devices_screen.dart';
import '../features/settings/sign_in_requests_screen.dart';
import '../features/settings/language_screen.dart';
import '../features/settings/mfa_setup_screen.dart';
import '../features/notifications/inbox_screen.dart';
import '../features/settings/notifications_screen.dart';
import '../features/settings/parental_controls_screen.dart';
import '../features/settings/playback_prefs_screen.dart';
import '../features/settings/security_screen.dart';
import '../features/settings/sessions_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/splash_preview_screen.dart';
import '../features/settings/subscription_screen.dart';
import '../features/settings/tv_pair_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/sports/sports_or_kids_branch.dart';
import '../features/update/update_app_screen.dart';
import '../shell/main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  // Signing in ends the demo.
  ref.listen<bool>(sessionProvider.select((s) => s.isLoggedIn), (_, logged) {
    if (logged) ref.read(demoModeProvider.notifier).state = false;
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    observers: [_AppNavObserver()],
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      if (!session.bootstrapped) {
        return loc == '/splash' ? null : '/splash';
      }

      final isSplash = loc == '/splash';
      final isUpdate = loc == '/update';
      final isOnboarding = loc == '/onboarding';
      final isAuth = loc.startsWith('/auth');
      final isProfiles = loc.startsWith('/profiles');

      if (isSplash || isUpdate) return null;

      if (!session.onboardingDone) {
        return isOnboarding ? null : '/onboarding';
      }

      // Task #143 #4: legal pages must open from login (logged-out).
      final isPublicLegal =
          loc == '/settings/terms' ||
          loc == '/settings/privacy' ||
          loc == '/settings/copyright';

      // Store-review demo: the real app over openly licensed content, no
      // sign-in. Account-only pages show the sign-in gate; /auth stays open
      // so the user can leave the demo and sign in.
      if (!session.isLoggedIn && ref.read(demoModeProvider)) {
        return demoRedirectFor(loc);
      }

      if (!session.isLoggedIn) {
        if (isAuth || isPublicLegal) return null;
        return '/auth/welcome';
      }

      if (!session.profileSelected) {
        return isProfiles ? null : '/profiles';
      }

      if (isAuth || isOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/update', builder: (_, _) => const UpdateAppScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: demoSignInRoute,
        builder: (_, _) => const DemoSignInScreen(),
      ),
      GoRoute(
        path: demoCreditsRoute,
        builder: (_, _) => const DemoCreditsScreen(),
      ),
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/login-approval',
        builder: (_, state) => LoginApprovalWaitScreen(
          challengeId: state.uri.queryParameters['challenge'] ?? '',
          expiresAt: state.uri.queryParameters['expires'],
        ),
      ),
      GoRoute(
        path: '/auth/mfa',
        builder: (_, state) => MfaVerifyScreen(
          challengeId: state.uri.queryParameters['challenge'] ?? '',
        ),
      ),
      // MFA recovery codes only — no email forgot-password flow (client request).
      GoRoute(
        path: '/auth/recovery',
        builder: (_, _) => const RecoveryLoginScreen(),
      ),
      GoRoute(
        path: '/profiles',
        builder: (_, _) => const ProfileSelectScreen(),
      ),
      GoRoute(
        path: '/profiles/manage',
        builder: (_, _) => const ManageProfilesScreen(),
      ),
      GoRoute(
        path: '/profiles/edit/:id',
        builder: (_, state) =>
            EditProfileScreen(id: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/movies', builder: (_, _) => const MoviesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/series', builder: (_, _) => const SeriesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/live', builder: (_, _) => const LiveTvScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sports',
                builder: (_, _) => const SportsOrKidsBranch(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (_, state) => SearchScreen(
          scope: SearchScreen.scopeFromQuery(
            state.uri.queryParameters['scope'],
          ),
        ),
      ),
      GoRoute(path: '/my-list', builder: (_, _) => const MyListScreen()),
      GoRoute(
        path: '/library',
        builder: (_, state) => LibraryHubScreen(
          initialTab: libraryTabFromQuery(state.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(path: '/my-account', builder: (_, _) => const MyAccountScreen()),
      GoRoute(path: '/new', builder: (_, _) => const NewPopularScreen()),
      GoRoute(path: '/vault', builder: (_, _) => const CinemaVaultScreen()),
      GoRoute(path: '/kids', builder: (_, _) => const KidsScreen()),
      GoRoute(
        path: '/browse/:kind/:categoryId',
        builder: (_, state) => switch (state.pathParameters['kind']) {
          // Live packages: numbered channel list (client 21 Oct reference).
          'live' || 'sports' => LiveCategoryScreen(
            categoryId: state.pathParameters['categoryId']!,
            title: state.uri.queryParameters['title'] ?? '',
            items: state.extra is List<MediaItem>
                ? state.extra! as List<MediaItem>
                : null,
          ),
          _ => CatalogViewAllScreen(
            // Live TV / Sports packages open their channels (client 18 Oct
            // #8: they opened as a movie category and showed nothing).
            kind: switch (state.pathParameters['kind']) {
              'series' => MediaKind.series,
              'live' || 'sports' => MediaKind.live,
              _ => MediaKind.movie,
            },
            categoryId: state.pathParameters['categoryId']!,
            title: state.uri.queryParameters['title'] ?? '',
          ),
        },
      ),
      GoRoute(path: '/clips', builder: (_, _) => const ClipsSoonScreen()),
      // Match centre: fixtures, lineups, events, statistics.
      GoRoute(
        path: '/match-centre',
        builder: (_, _) => const MatchCentreScreen(),
      ),
      GoRoute(
        path: '/match-centre/:id',
        builder: (_, state) => MatchScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/diagnostic',
        builder: (_, _) => const ConnectionDiagnosticScreen(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearanceScreen(),
      ),
      GoRoute(
        path: '/settings/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings/devices',
        builder: (_, _) => const DevicesScreen(),
      ),
      GoRoute(
        path: '/settings/sign-in-requests',
        builder: (_, _) => const SignInRequestsScreen(),
      ),
      GoRoute(
        path: '/settings/devices/pair-tv',
        builder: (_, _) => const TvPairScreen(),
      ),
      GoRoute(
        path: '/settings/security',
        builder: (_, _) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/settings/security/mfa',
        builder: (_, _) => const MfaSetupScreen(),
      ),
      GoRoute(
        path: '/settings/security/sessions',
        builder: (_, _) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/settings/playback',
        builder: (_, _) => const PlaybackPrefsScreen(),
      ),
      GoRoute(
        path: '/settings/audio',
        builder: (_, _) => const AudioSubtitlesScreen(),
      ),
      GoRoute(
        path: '/settings/language',
        builder: (_, _) => const LanguageScreen(),
      ),
      GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen()),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings/parental',
        builder: (_, _) => const ParentalControlsScreen(),
      ),
      GoRoute(
        path: '/settings/customize-home',
        builder: (_, _) => const CustomizeHomeScreen(),
      ),
      GoRoute(
        path: '/settings/lab/splash-preview',
        builder: (_, _) => const SplashPreviewScreen(),
      ),
      GoRoute(path: '/settings/about', builder: (_, _) => const AboutScreen()),
      GoRoute(
        path: '/settings/privacy',
        builder: (_, _) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/settings/terms',
        builder: (_, _) => const TermsOfUseScreen(),
      ),
      GoRoute(
        path: '/movie/:id',
        builder: (_, state) => MovieDetailsScreen(
          id: state.pathParameters['id']!,
          initial: state.extra is MediaItem ? state.extra as MediaItem : null,
        ),
      ),
      GoRoute(
        path: '/offline/:id',
        builder: (_, state) =>
            OfflinePlayerScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/series/:id',
        builder: (_, state) => SeriesDetailsScreen(
          id: state.pathParameters['id']!,
          initial: state.extra is MediaItem ? state.extra as MediaItem : null,
        ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (_, state) {
          final start = int.tryParse(
            state.uri.queryParameters['startSec'] ?? '',
          );
          final kindRaw = state.uri.queryParameters['kind']?.toLowerCase();
          final seriesId = state.uri.queryParameters['seriesId'];
          MediaKind? kind;
          switch (kindRaw) {
            case 'movie':
            case 'vod':
              kind = MediaKind.movie;
            case 'series':
              kind = MediaKind.series;
            case 'live':
              kind = MediaKind.live;
            case 'sports':
              kind = MediaKind.sports;
          }
          return PlayerScreen(
            id: state.pathParameters['id']!,
            startSec: start,
            kindHint: kind,
            seriesId: seriesId,
          );
        },
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this.ref) {
    _sub = ref.listen<SessionState>(sessionProvider, (_, _) {
      notifyListeners();
    });
    _demoSub = ref.listen<bool>(demoModeProvider, (_, _) {
      notifyListeners();
    });
  }

  final Ref ref;
  late final ProviderSubscription<SessionState> _sub;
  late final ProviderSubscription<bool> _demoSub;

  @override
  void dispose() {
    _sub.close();
    _demoSub.close();
    super.dispose();
  }
}

class _AppNavObserver extends NavigatorObserver {
  String? _name(Route<dynamic>? route) =>
      route?.settings.name ?? route?.settings.arguments?.toString();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.nav('push', from: _name(previousRoute), to: _name(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.nav('pop', from: _name(route), to: _name(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLog.nav('replace', from: _name(oldRoute), to: _name(newRoute));
  }
}
