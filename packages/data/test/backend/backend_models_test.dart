import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteConfig', () {
    // Real reply from get_app_config(platform: tv) on the project (config v6).
    final live = jsonDecode(File('test/fixtures/app_config_tv.json').readAsStringSync());

    test('parses the live reply', () {
      final c = RemoteConfig.tryParse(live)!;
      expect(c.version, 6);
      expect(c.authMode, AuthMode.optional);
      expect(c.isEnabled('push_notifications'), isFalse);
      expect(c.isEnabled('live_tv'), isTrue);
      expect(c.intSetting('providers.connect_timeout_ms', 0), 8000);
      expect(c.stringSetting('player.live_format', ''), 'ts');
      expect(c.panelTypes.map((p) => p.key), ['xtream', 'm3u', 'stalker']);
      expect(c.panelTypes.first.fields.map((f) => f.key), ['host', 'username', 'password']);
      expect(c.panelTypes[2].fields.last.type, 'mac');
      expect(c.theme['primary'], '#22D3EE');
      expect(c.versionPolicy!.check('1.0.0'), UpdateRequirement.none);
    });

    test('home: sections in order, panel sources, Top 10 link', () {
      final h = RemoteConfig.tryParse(live)!.home;
      expect(h.sections.length, 10);
      expect(h.sections.first.type, HomeSectionType.heroBanners);
      final top = h.sections.firstWhere((s) => s.type == HomeSectionType.top10);
      expect(top.source, SectionSource.providerRating);
      expect(top.intParam('days'), 90);
      expect(top.layout, SectionLayout.ranked);
      expect(h.top10ById(top.top10ListId)!.source, Top10Source.providerRating);
      expect(
        h.sections.where((s) => s.type == HomeSectionType.newReleases).map((s) => s.source),
        everyElement(SectionSource.providerAdded),
      );
    });

    test('unchanged reply and junk return null, never throw', () {
      expect(RemoteConfig.tryParse({'version': 6, 'unchanged': true}), isNull);
      expect(RemoteConfig.isUnchanged({'version': 6, 'unchanged': true}), isTrue);
      expect(RemoteConfig.tryParse('nope'), isNull);
      expect(RemoteConfig.tryParse(null), isNull);
    });

    test('bad fields are dropped; unknown section types skipped', () {
      final c = RemoteConfig.tryParse({
        'version': '7',
        'flags': {'a': true, 'b': 'nope', 'c': 1},
        'settings': {'auth.mode': 'weird'},
        'theme': {'primary': '#FFFFFF', 'bad': 3},
        'onboarding': [
          {'key': 'xtream', 'label': 'X', 'fields': [{'key': 'host', 'label': 'H', 'type': 'hologram'}]},
          {'label': 'missing key'},
        ],
        'home': {
          'sections': [
            {'id': '1', 'title': 'Ok', 'type': 'top10', 'source': 'future_source', 'limit': 500},
            {'id': '2', 'title': 'From the future', 'type': 'vr_room'},
            {'title': 'no id', 'type': 'top10'},
          ],
          'banners': [{'id': 'b', 'title': 'T'}],
        },
        'version_policy': 'garbage',
      })!;
      expect(c.version, 7);
      expect(c.flags, {'a': true, 'c': true});
      expect(c.authMode, AuthMode.optional);
      expect(c.theme, {'primary': '#FFFFFF', 'bad': '3'});
      expect(c.panelTypes.single.fields.single.type, 'text');
      expect(c.home.sections.single.source, SectionSource.unknown);
      expect(c.home.sections.single.limit, 100);
      expect(c.home.banners, isEmpty); // no image
      expect(c.versionPolicy, isNull);
      expect(c.isEnabled('not_in_config'), isTrue);
      expect(c.isEnabled('not_in_config', fallback: false), isFalse);
    });

    test('version policy', () {
      const p = VersionPolicy(min: '1.2.0', recommended: '1.4.0');
      expect(p.check('1.1.9'), UpdateRequirement.required);
      expect(p.check('1.3.0+77'), UpdateRequirement.recommended);
      expect(p.check('1.4.0'), UpdateRequirement.none);
      expect(compareAppVersion('6.0.36+145', '6.0.36'), 0);
      expect(compareAppVersion('1.10', '1.9'), 1);
    });
  });

  group('home refs', () {
    test('admin picks keep panel id, tmdb and title fallback', () {
      final s = HomeSection.tryParse({
        'id': 's', 'title': 'Picks', 'type': 'custom', 'source': 'manual',
        'items': [
          {'kind': 'movie', 'panel': 'neo', 'panel_id': '501', 'tmdb': 157336},
          {'kind': 'movie'}, // unusable → dropped
          {'kind': 'link', 'link': 'xplayer://sports'},
        ],
      })!;
      expect(s.items.length, 2);
      expect(s.items.first.panelItemId, '501');
      expect(s.items.first.tmdbId, 157336);
      expect(s.items.last.kind, ContentKind.link);
    });
  });

  group('sports', () {
    test('list + detail', () {
      final list = FixtureSummary.listFrom([
        {
          'id': 'm', 'status': 'live', 'minute': 34, 'kickoff_at': '2026-11-15T18:00:00Z',
          'home_score': 1, 'away_score': 0, 'has_channels': true,
          'home': {'id': 'h', 'name': 'Home'}, 'away': {'id': 'a', 'name': 'Away'},
          'competition': {'id': 'c', 'name': 'League'},
        },
        {'id': 'broken'},
      ]);
      expect(list.single.isLive, isTrue);
      expect(list.single.competition!.name, 'League');

      final d = FixtureDetail.tryParse({
        'match': {'id': 'm', 'status': 'halftime', 'kickoff_at': '2026-11-15T18:00:00Z', 'venue': 'Arena'},
        'home': {'id': 'h', 'name': 'Home'},
        'away': {'id': 'a', 'name': 'Away'},
        'lineups': [
          {'team': 'h', 'formation': '4-3-3', 'players': [
            {'name': 'A', 'number': 9}, {'name': 'B', 'starter': false}, {'number': 1}]},
        ],
        'events': [{'minute': 45, 'extra': 2, 'type': 'goal', 'player': 'A'}, {'type': 'x'}],
        'channels': [{'match': 'Sports 1'}],
      })!;
      expect(d.summary.status, FixtureStatus.halftime);
      expect(d.lineups.single.starters.length, 1);
      expect(d.lineups.single.bench.length, 1);
      expect(d.events.single.clock, "45+2'");
      expect(d.channels.single.matchName, 'Sports 1');
      expect(FixtureDetail.tryParse(null), isNull);
    });
  });

  group('catalog / metadata', () {
    test('artwork urls', () {
      const a = ArtworkUrls();
      expect(a.poster('/abc.jpg'), 'https://image.tmdb.org/t/p/w342/abc.jpg');
      expect(a.backdrop('abc.jpg'), 'https://image.tmdb.org/t/p/w1280/abc.jpg');
      expect(a.poster('https://cdn.x/y.png'), 'https://cdn.x/y.png');
      expect(a.poster(null), isNull);
    });

    test('resolve reply keeps positions', () {
      final r = TitleMetadata.resolveReply({
        'results': [
          {'kind': 'movie', 'id': 'u1', 'tmdb_id': 157336, 'title': 'Interstellar', 'year': 2014, 'rating': 8.4},
          null,
        ],
      });
      expect(r.length, 2);
      expect(r.first!.tmdbId, 157336);
      expect(r.last, isNull);
      expect(TitleMetadata.resolveReply('junk'), isEmpty);
    });

    test('query json prefers tmdb id', () {
      expect(const MetadataQuery(kind: CatalogKind.series, tmdbId: 1396, title: 'x').toJson(),
          {'kind': 'series', 'tmdb_id': 1396});
      expect(const MetadataQuery(kind: CatalogKind.movie, title: 'EN - Up (2009)').toJson(),
          {'kind': 'movie', 'title': 'EN - Up (2009)'});
    });

    test('season reply sorted', () {
      final eps = EpisodeMetadata.seasonReply({
        'episodes': [
          {'id': 'b', 'episode_number': 2},
          {'id': 'a', 'episode_number': 1, 'name': 'Pilot'},
          {'id': 'c'},
        ],
      });
      expect(eps.map((e) => e.number), [1, 2]);
    });

    test('search hits', () {
      final h = CatalogSearchHit.listFrom([
        {'kind': 'series', 'id': '1', 'title': 'Breaking Bad', 'score': 0.9},
        {'kind': 'movie'},
      ]);
      expect(h.single.kind, CatalogKind.series);
    });
  });
}
