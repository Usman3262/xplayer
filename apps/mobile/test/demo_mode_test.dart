import 'package:player_mobile/core/demo_mode.dart';
import 'package:player_mobile/core/providers.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo mode serves the real screens from the demo catalog', () async {
    final c = ProviderContainer(overrides: []);
    addTearDown(c.dispose);
    c.read(demoModeProvider.notifier).state = true;

    final repo = c.read(catalogRepositoryProvider);
    expect(repo, isA<DemoCatalogRepository>());
    // Same instance across catalog epoch bumps (My List lives in it).
    c.read(catalogEpochProvider.notifier).state++;
    expect(identical(c.read(catalogRepositoryProvider), repo), isTrue);

    final movies = await c.read(moviesProvider.future);
    expect(movies.map((m) => m.id), contains('demo-bbb'));
    // Backend-only extras are empty in demo (no request).
    expect(await c.read(vodInfoProvider('demo-bbb').future), isNull);
    expect(await c.read(liveEpgProvider('demo-live-1').future), isEmpty);
    expect(await c.read(catalogCountsProvider.future), isNull);
    final live = await c.read(catalogRepositoryProvider).browse(
          kind: MediaKind.live,
          categoryId: 'demo-live',
        );
    expect(live.items, hasLength(2));
  });

  test('demo router: app routes open, account pages show the gate', () {
    for (final open in [
      '/home',
      '/movies',
      '/series',
      '/live',
      '/sports',
      '/search',
      '/movie/demo-bbb',
      '/series/demo-series-open-movies',
      '/player/demo-bbb',
      '/my-list',
      '/library',
      '/settings',
      '/settings/about',
      '/settings/appearance',
      '/auth/welcome',
      '/auth/login',
      demoCreditsRoute,
    ]) {
      expect(demoRedirectFor(open), isNull, reason: open);
    }
    for (final gated in [
      '/profiles',
      '/profiles/manage',
      '/downloads',
      '/offline/demo-bbb',
      '/inbox',
      '/match-centre/1',
      '/settings/subscription',
      '/settings/devices',
      '/settings/devices/pair-tv',
      '/settings/security/sessions',
      '/settings/parental',
    ]) {
      expect(demoRedirectFor(gated), demoSignInRoute, reason: gated);
    }
    expect(demoRedirectFor('/onboarding'), '/home');
  });
}
