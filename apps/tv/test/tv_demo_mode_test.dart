import 'package:player_tv/core/providers.dart';
import 'package:player_tv/core/tv_demo_mode.dart';
import 'package:data/data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client 5 Nov #30: Android TV demo mode, as on the phone.
void main() {
  test('demo serves the real screens from the demo catalog', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(tvDemoModeProvider.notifier).state = true;
    final repo = c.read(catalogRepositoryProvider);
    expect(repo, isA<DemoCatalogRepository>());
    final movies = await repo.getMovies();
    expect(movies, isNotEmpty);
    expect(movies.every((m) => (m.streamUrl ?? '').startsWith('https://')), isTrue);
  });

  test('demo router: app pages open, account pages ask to sign in', () {
    for (final open in ['/home', '/movies', '/series', '/live', '/search', '/settings', '/legal/terms', '/login']) {
      expect(tvDemoRedirect(open), isNull, reason: open);
    }
    for (final account in ['/profiles', '/downloads', '/settings/subscription', '/settings/devices', '/settings/security']) {
      expect(tvDemoRedirect(account), '/login', reason: account);
    }
  });
}
