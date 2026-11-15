import 'dart:convert';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'live_panel.dart';

/// Hand-made playlist with the shapes seen in the wild.
const sample = '﻿#EXTM3U url-tvg="http://epg.example/a.xml, http://epg.example/b.xml" x-tvg-url=""\r\n'
    '#EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One, HD" tvg-logo="http://img/bbc.png" group-title="UK" tvg-chno="101" catchup-days="7",BBC One HD\r\n'
    '#EXTVLCOPT:http-user-agent=Mozilla/5.0 Test\r\n'
    '#EXTVLCOPT:http-referrer=http://ref.example/\r\n'
    'http://host/live/u/p/1001.ts\r\n'
    '#EXTINF:-1 tvg-id="bbc1.uk" group-title="UK",BBC One HD\r\n'
    'http://backup.host/bbc1.m3u8\r\n'
    '#EXTINF:-1 tvg-id="bbc1.uk" group-title="UK",BBC One HD\r\n'
    'http://host/live/u/p/1001.ts\r\n'
    '#EXTINF:-1 group-title="UK",##### UK SPORTS #####\r\n'
    'http://host/live/u/p/9999.ts\r\n'
    '#EXTINF:-1,No Group Channel\r\n'
    '#EXTGRP:News\r\n'
    'https://cdn.example/news/index.m3u8\r\n'
    '#EXTINF:-1 tvg-logo="http://img/dune.jpg" group-title="Movies | Sci-Fi",Dune (2021)\r\n'
    'http://host/movie/u/p/780853.mkv\r\n'
    '#EXTINF:5400 group-title="Movies",Home Video\r\n'
    'https://files.example/videos/home.mp4\r\n'
    '#EXTINF:-1 tvg-logo="http://img/show.jpg" group-title="Series",My Show S01 E02\r\n'
    'http://host/series/u/p/5002.mkv\r\n'
    '#EXTINF:-1 group-title="Series",My Show S01 E01\r\n'
    'http://host/series/u/p/5001.mkv\r\n'
    '#EXTINF:2700 group-title="Series",My Show S02E01 - New Season\r\n'
    'https://files.example/show/s2e1.mp4\r\n'
    '#EXTINF:-1 group-title="Series",Other Show - S1E5\r\n'
    'http://host/series/u/p/6005.mp4\r\n'
    '# a comment\r\n'
    '#EXTINF:-1,Broken entry with no url\r\n'
    'not-a-url\r\n';

void main() {
  group('parser', () {
    final p = parseM3u(sample);

    test('header, EPG URLs, BOM, CRLF', () {
      expect(p.hadHeader, isTrue);
      expect(p.epgUrls, ['http://epg.example/a.xml', 'http://epg.example/b.xml']);
    });

    test('attributes (commas inside values), title after the attributes, headers', () {
      final bbc = p.entries.first;
      expect(bbc.title, 'BBC One HD');
      expect(bbc.attr('tvg-name'), 'BBC One, HD');
      expect(bbc.attr('tvg-chno'), '101');
      expect(bbc.group, 'UK');
      expect(bbc.headers, {'User-Agent': 'Mozilla/5.0 Test', 'Referer': 'http://ref.example/'});
      // Headers belong to their entry only.
      expect(p.entries[1].headers, isEmpty);
    });

    test('duplicate URLs dropped, #EXTGRP fallback, junk lines skipped', () {
      expect(p.entries.where((e) => e.url == 'http://host/live/u/p/1001.ts'), hasLength(1));
      expect(p.entries.firstWhere((e) => e.title == 'No Group Channel').group, 'News');
      expect(p.entries.any((e) => e.url == 'not-a-url'), isFalse);
    });

    test('kind detection', () {
      MediaKind k(String title, String url) => m3uKindOf(M3uEntry(title: title, url: url));
      expect(k('X', 'http://h/live/u/p/1.ts'), MediaKind.live);
      expect(k('X', 'http://h/stream.m3u8'), MediaKind.live);
      expect(k('X', 'http://h/movie/u/p/1.mkv'), MediaKind.movie);
      expect(k('X', 'http://h/series/u/p/1.mkv'), MediaKind.series);
      expect(k('Film', 'https://f/a.mp4'), MediaKind.movie);
      expect(k('Show S03E04', 'https://f/a.mp4'), MediaKind.series);
    });

    test('episode info', () {
      expect(m3uEpisodeInfo('My Show S01 E02'), (show: 'My Show', season: 1, episode: 2));
      expect(m3uEpisodeInfo('Other Show - S1E5'), (show: 'Other Show', season: 1, episode: 5));
      expect(m3uEpisodeInfo('My Show S02E01 - New Season')!.season, 2);
      expect(m3uEpisodeInfo('Just A Movie'), isNull);
    });

    test('ids: panel number when present, else a stable hash', () {
      expect(m3uEntryId(const M3uEntry(title: '', url: 'http://h/live/u/p/1001.ts')), '1001');
      final a = m3uEntryId(const M3uEntry(title: '', url: 'https://cdn/x/index.m3u8'));
      expect(a, hasLength(16));
      expect(m3uEntryId(const M3uEntry(title: '', url: 'https://cdn/x/index.m3u8')), a);
    });

    test('no header / empty / garbage never crash', () {
      expect(parseM3u('').entries, isEmpty);
      expect(parseM3u('<html>login</html>').entries, isEmpty);
      final bare = parseM3u('http://h/a.ts\nhttp://h/b.ts');
      expect(bare.hadHeader, isFalse);
      expect(bare.entries, hasLength(2));
    });
  });

  group('catalog', () {
    final c = buildM3uCatalog(sample);

    test('live: headers skipped, same channel on another URL deduped by tvg-id+name', () {
      expect(c.channels.map((x) => x.name), ['BBC One HD', 'No Group Channel']);
      final bbc = c.channels.first;
      expect(bbc.id, '1001');
      expect(bbc.number, 101);
      expect(bbc.epgId, 'bbc1.uk');
      expect(bbc.catchupDays, 7);
      expect(bbc.categoryId, 'UK');
      expect(c.liveCategories.map((x) => x.name), ['UK', 'News']);
    });

    test('movies', () {
      expect(c.movies.map((m) => m.name), ['Dune (2021)', 'Home Video']);
      expect(c.movies.first.year, 2021);
      expect(c.movies.first.stream.extension, 'mkv');
      expect(c.movies.first.id, '780853');
      expect(c.movieCategories.map((x) => x.id), ['Movies | Sci-Fi', 'Movies']);
    });

    test('series grouped from episodes, seasons sorted', () {
      expect(c.series.map((s) => s.name), ['My Show', 'Other Show']);
      final show = c.series.first;
      expect(show.posterUrl, 'http://img/show.jpg');
      final eps = c.episodes[show.id]!;
      expect(eps.keys.toList()..sort(), [1, 2]);
      expect(eps[1]!.map((e) => e.number), [1, 2]);
      expect(eps[2]!.single.durationSec, 2700);
    });
  });

  group('adapter', () {
    M3uAdapter adapter(String body, {int code = 200}) => M3uAdapter(
          const M3uCredentials(url: 'http://lists.example/my.m3u', epgUrl: 'http://epg.example/mine.xml'),
          http: ProviderHttp(client: MockClient((_) async => http.Response.bytes(utf8.encode(body), code)), backoffBase: Duration.zero),
        );

    test('connect, browse, details, play with the entry headers', () async {
      final a = adapter(sample);
      expect((await a.authenticate()).status, ConnectionStatus.active);
      expect(a.epgUrls.first, 'http://epg.example/mine.xml');
      expect(await a.liveChannels(categoryId: 'UK'), hasLength(1));
      expect(await a.movies(), hasLength(2));
      final show = (await a.series()).first;
      final d = await a.seriesDetails(show.id);
      expect(d.seasonNumbers, [1, 2]);
      final bbc = (await a.liveChannels()).first;
      final r = await a.resolveStream(bbc.stream);
      expect('${r.url}', 'http://host/live/u/p/1001.ts');
      expect(r.headers['User-Agent'], 'Mozilla/5.0 Test');
      expect('$r', isNot(contains('/u/p/')));
      expect((await a.movieDetails('780853')).movie.name, 'Dune (2021)');
      expect(a.capabilities.movies, isTrue);
    });

    test('not a playlist / empty / 401', () async {
      Future<ProviderFailureKind> kindOf(String body, {int code = 200}) async {
        try {
          await adapter(body, code: code).authenticate();
          return ProviderFailureKind.server;
        } on ProviderFailure catch (f) {
          return f.kind;
        }
      }

      expect(await kindOf('<html>error</html>'), ProviderFailureKind.badResponse);
      expect(await kindOf('#EXTM3U\n'), ProviderFailureKind.badResponse);
      expect(await kindOf('', code: 401), ProviderFailureKind.unauthorized);
    });

    test('downloads once; concurrent calls share it', () async {
      var calls = 0;
      final a = M3uAdapter(
        const M3uCredentials(url: 'http://lists.example/my.m3u'),
        http: ProviderHttp(client: MockClient((_) async {
          calls++;
          return http.Response.bytes(utf8.encode(sample), 200);
        })),
      );
      await Future.wait([a.liveChannels(), a.movies(), a.series(), a.liveCategories()]);
      expect(calls, 1);
      await a.authenticate(); // explicit re-check downloads again
      expect(calls, 2);
    });

    test('Neo-sized playlist (3k live, 15k movies, 60k episodes) parses in an isolate', () async {
      final b = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 3000; i++) {
        b
          ..writeln('#EXTINF:-1 tvg-id="c$i" tvg-logo="http://img/$i.png" group-title="AR| Live ${i % 113}",قناة $i HD')
          ..writeln('http://host/live/u/p/$i.ts');
      }
      for (var i = 0; i < 15000; i++) {
        b
          ..writeln('#EXTINF:-1 tvg-logo="http://img/m$i.jpg" group-title="Movies ${i % 90}",فيلم $i (20${10 + i % 15})')
          ..writeln('http://host/movie/u/p/${100000 + i}.mkv');
      }
      for (var i = 0; i < 60000; i++) {
        final show = i ~/ 30;
        b
          ..writeln('#EXTINF:-1 group-title="Series ${show % 95}",مسلسل $show S0${1 + (i % 30) ~/ 15}E${1 + i % 15}')
          ..writeln('http://host/series/u/p/${500000 + i}.mkv');
      }
      final sw = Stopwatch()..start();
      final a = adapter(b.toString());
      await a.authenticate();
      final ms = sw.elapsedMilliseconds;
      expect(await a.liveChannels(), hasLength(3000));
      expect(await a.movies(), hasLength(15000));
      final series = await a.series();
      expect(series, hasLength(2000));
      expect((await a.seriesDetails(series.first.id)).seasonNumbers, [1, 2]);
      expect((await a.liveChannels()).first.name, 'قناة 0 HD'); // UTF-8 kept
      // ignore: avoid_print
      print('Neo-sized playlist: ${(b.length / 1e6).toStringAsFixed(1)} MB → catalog in ${ms}ms');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ── LIVE: the panel's own M3U export (opt-in, see live_panel.dart). Many
  // panels disable it (Neo: 884) → the app must say "use the Xtream login".
  final live = livePanel();
  test('LIVE: panel M3U export through the M3U adapter (or a clear refusal)', () async {
    final c = live!;
    final url = c.baseUri!.replace(
      path: '${c.baseUri!.path}/get.php',
      queryParameters: {'username': c.username, 'password': c.password, 'type': 'm3u_plus', 'output': 'ts'},
    );
    final a = M3uAdapter(
      M3uCredentials(url: '$url'),
      http: ProviderHttp(limits: const ProviderLimits(requestTimeout: Duration(seconds: 150), retries: 0)),
    );
    final sw = Stopwatch()..start();
    try {
      await a.authenticate();
    } on ProviderFailure catch (f) {
      expect('$f', isNot(contains(c.password)));
      expect(f.kind, isIn([ProviderFailureKind.unsupported, ProviderFailureKind.unauthorized]));
      // ignore: avoid_print
      print('LIVE m3u: panel refused the export → ${f.kind.name} (${sw.elapsedMilliseconds}ms)');
      return;
    }
    final ms = sw.elapsedMilliseconds;
    final ch = await a.liveChannels();
    final mv = await a.movies();
    final se = await a.series();
    var eps = 0;
    for (final s in se) {
      eps += (await a.seriesDetails(s.id)).episodes.values.fold<int>(0, (n, l) => n + l.length);
    }
    // ignore: avoid_print
    print('LIVE m3u: download+catalog ${ms}ms\n'
        '  live ${ch.length} in ${(await a.liveCategories()).length} groups (epg ids ${ch.where((c) => c.epgId != null).length}, logos ${ch.where((c) => c.logoUrl != null).length})\n'
        '  movies ${mv.length} in ${(await a.movieCategories()).length} groups\n'
        '  series ${se.length} in ${(await a.seriesCategories()).length} groups, $eps episodes\n'
        '  epg urls in header: ${a.epgUrls.length}');
    expect(ch.length + mv.length + se.length, greaterThan(0));
    a.dispose();
  },
      skip: live == null ? liveSkip : false,
      timeout: const Timeout(Duration(minutes: 4)));
}
