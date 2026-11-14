import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Store-review demo ("Try demo" on the welcome screen): the real app with
/// openly licensed sample content ([DemoContent]) and no account. Only in
/// memory: an app restart shows the normal welcome screen again.
final demoModeProvider = StateProvider<bool>((ref) => false);

/// One demo catalog for the whole demo session (My List lives in it), so a
/// catalog epoch bump does not drop it.
final demoCatalogRepositoryProvider = Provider<DemoCatalogRepository>(
  (ref) => DemoCatalogRepository(),
);

/// Gate shown for account-only pages while in demo.
const demoSignInRoute = '/demo/sign-in';
const demoCreditsRoute = '/demo/credits';

/// Pages that need a APP 4K account; in demo they open [demoSignInRoute].
const _accountOnlyPrefixes = <String>[
  '/profiles',
  '/downloads',
  '/offline',
  '/inbox',
  '/clips',
  '/match-centre',
  '/settings/subscription',
  '/settings/devices',
  '/settings/security',
  '/settings/parental',
  '/settings/notifications',
  '/settings/diagnostic',
];

bool isDemoAccountOnlyRoute(String location) {
  for (final p in _accountOnlyPrefixes) {
    if (location == p || location.startsWith('$p/')) return true;
  }
  return false;
}

/// Where the router sends [location] while in demo (signed out); null opens
/// it. The real app routes are open, account-only pages show the sign-in
/// gate, and /auth stays open so the user can leave the demo and sign in.
String? demoRedirectFor(String location) {
  if (location.startsWith('/auth')) return null;
  if (location == '/onboarding') return '/home';
  if (isDemoAccountOnlyRoute(location)) return demoSignInRoute;
  return null;
}

/// Leaves demo: the router then sends the user to the welcome screen.
void exitDemo(WidgetRef ref) {
  ref.read(demoModeProvider.notifier).state = false;
}
