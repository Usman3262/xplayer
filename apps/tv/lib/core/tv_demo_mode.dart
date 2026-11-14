import 'package:data/data.dart' show DemoCatalogRepository;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demo on Android TV (client 5 Nov #30, as on the phone): the real TV
/// screens over the openly licensed demo catalog, no account. In memory
/// only: an app restart shows the sign-in screen again.
final tvDemoModeProvider = StateProvider<bool>((ref) => false);

/// One demo catalog for the whole demo session.
final tvDemoCatalogProvider = Provider<DemoCatalogRepository>(
  (ref) => DemoCatalogRepository(),
);

/// Pages that need an account: in demo they send the user to sign in.
const _accountOnlyPrefixes = <String>[
  '/profiles',
  '/downloads',
  '/inbox',
  '/settings/subscription',
  '/settings/devices',
  '/settings/security',
  '/settings/sessions',
  '/settings/mfa',
  '/settings/parental',
];

/// Where the router sends [location] in demo (signed out); null opens it.
String? tvDemoRedirect(String location) {
  if (location == '/login' || location.startsWith('/legal')) return null;
  for (final p in _accountOnlyPrefixes) {
    if (location == p || location.startsWith('$p/')) return '/login';
  }
  return null;
}
