import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'live_panel.dart';

/// Real portal replies (2026-11-15), MAC/host/token replaced. Shape: {"js": …}.
Map<String, dynamic> fx(String name) =>
    jsonDecode(File('test/fixtures/stalker/$name.json').readAsStringSync()) as Map<String, dynamic>;
Object? js(String name) => fx(name)['js'];

http.Response _res(String body, int code) => http.Response.bytes(utf8.encode(body), code);

const creds = StalkerCredentials(portal: 'http://portal.example/c/', mac: '00-1a-79-f0-06-3b');

void main() {
  group('parsing (real portal samples)', () {
    test('profile OK / blocked / not authorised', () {
      StalkerAdapter.checkProfile(js('get_profile') as Map<String, dynamic>);
      expect(
        () => StalkerAdapter.checkProfile({'status': 0, 'blocked': '1'}),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.banned)),
      );
      expect(
        () => StalkerAdapter.checkProfile({'status': 2}),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.unauthorized)),
      );
      expect(() => StalkerAdapter.checkProfile({}), throwsA(isA<ProviderFailure>()));
    });

    test('expiry from account_info.phone ("November 16, 2026, 9:29 am") and other shapes', () {
      final d = StalkerAdapter.parseExpiry(js('account_info') as Map<String, dynamic>, {});
      expect(d, DateTime(2026, 11, 16, 9, 29));
      expect(StalkerAdapter.parseExpiry({'end_date': '2027-01-02 10:00:00'}, {}), DateTime(2027, 1, 2, 10));
      expect(StalkerAdapter.parseExpiry({'phone': 'Dec 1, 2026, 12:05 pm'}, {}), DateTime(2026, 12, 1, 12, 5));
      expect(StalkerAdapter.parseExpiry({'phone': 'Unlimited'}, {'expire_billing_date': '0000-00-00 00:00:00'}), isNull);
      expect(StalkerAdapter.parseExpiry({'phone': '+44 7700 900000'}, {}), isNull); // a real phone number
    });

    test('channels: header rows skipped, ids, logos, epg id, command kept', () {
      final raw = jsonMapList((js('itv_ordered_list') as Map)['data']);
      final ch = StalkerAdapter.parseChannels(raw);
      expect(raw.first['name'], contains('#####'));
      expect(ch.every((c) => !c.name.contains('#####')), isTrue);
      expect(ch, isNotEmpty);
      expect(ch.first.stream.command, startsWith('ffmpeg http'));
      expect(ch.first.logoUrl, startsWith('http'));
    });

    test('relative logo resolved against the portal', () {
      final ch = StalkerAdapter.parseChannels([
        {'id': '5', 'name': 'X', 'logo': 'misc/logos/320/5.jpg'},
      ], portal: Uri.parse('http://p.tv/c/'));
      expect(ch.single.logoUrl, 'http://p.tv/stalker_portal/misc/logos/320/5.jpg');
    });

    test('movie: imdb rating, year from date, tmdb, added, base64 cmd, details from the list item', () {
      final m0 = jsonMapList((js('vod_ordered_list') as Map)['data']).first;
      final m = StalkerAdapter.parseMovie(m0)!;
      expect(m.year, 2026);
      expect(m.tmdbId, 1654566);
      expect(m.rating, 5.2);
      expect(m.addedSec, isNotNull);
      expect(StalkerAdapter.decodeVodCmd(m.stream.command!)!['type'], 'movie');
      final d = StalkerAdapter.parseMovieDetails(m0)!;
      expect(d.genres, ['Action', 'Comedy', 'Drama']);
      expect(d.durationSec, 145 * 60);
      expect(d.plot, isNotEmpty);
    });

    test('series item + seasons → episodes from the season "series" numbers', () {
      final s0 = jsonMapList((js('series_ordered_list') as Map)['data']).first;
      final s = StalkerAdapter.parseSeries(s0)!;
      expect(s.id, '49938:49938');
      expect(s.year, 2026);
      final seasons = jsonMapList((js('series_seasons') as Map)['data']);
      final d = StalkerAdapter.parseSeasons(seasons, s.id, s);
      expect(d.seasonNumbers, [1]);
      final e = d.episodes[1]!.first;
      expect(e.id, '49938:1#1');
      expect(e.number, 1);
      expect(e.title, ''); // app labels it
      expect(e.stream.command, isNotEmpty);
    });

    test('multi-season, unsorted numbers, seasons without cmd skipped', () {
      final d = StalkerAdapter.parseSeasons([
        {'id': '7:2', 'name': 'Season 2', 'cmd': 'c2', 'series': [3, 1, '2']},
        {'id': '7:1', 'name': 'Season 1', 'cmd': 'c1', 'series': [1]},
        {'id': '7:3', 'name': 'Season 3', 'cmd': '', 'series': [1]},
      ], '7', const ProviderSeries(id: '7', name: 'S'));
      expect(d.seasonNumbers, [1, 2]);
      expect(d.episodes[2]!.map((e) => e.number), [1, 2, 3]);
    });

    test('short EPG (real sample)', () {
      final epg = StalkerAdapter.parseShortEpg(js('itv_short_epg_real'));
      expect(epg, hasLength(4));
      expect(epg.first.title, isNotEmpty);
      expect(epg.first.end.isAfter(epg.first.start), isTrue);
      expect(StalkerAdapter.parseShortEpg(js('itv_short_epg')), isEmpty);
    });

    test('links: prefix stripped; empty stream= detected (real broken live link)', () {
      final broken = StalkerAdapter.cleanLink((js('itv_create_link') as Map)['cmd'] as String)!;
      expect(broken.path, '/play/live.php');
      expect(StalkerAdapter.hasEmptyStreamParam(broken), isTrue);
      final movie = StalkerAdapter.cleanLink((js('vod_create_link') as Map)['cmd'] as String)!;
      expect(movie.path, '/play/movie.php');
      expect(StalkerAdapter.hasEmptyStreamParam(movie), isFalse);
      expect(StalkerAdapter.cleanLink('auto http://h/x.ts')!.host, 'h');
      expect(StalkerAdapter.cleanLink(''), isNull);
    });
  });

  test('endpoint candidates from what users paste', () {
    final a = StalkerAdapter(const StalkerCredentials(portal: 'http://p.tv:8080/c/', mac: '001A79F0063B'));
    expect(a.endpointCandidates.map((u) => '$u'), [
      'http://p.tv:8080/portal.php',
      'http://p.tv:8080/server/load.php',
      'http://p.tv:8080/stalker_portal/server/load.php',
    ]);
    final b = StalkerAdapter(const StalkerCredentials(portal: 'http://p.tv/stalker_portal/c', mac: '001A79F0063B'));
    expect(b.endpointCandidates.first.path, '/stalker_portal/portal.php');
  });

  group('flow against a fake portal', () {
    late List<Uri> calls;
    late List<Map<String, String>> sentHeaders;
    var tokenExpiresAfter = -1; // calls with the first token before "Authorization failed"
    var handshakes = 0;

    http.Response route(http.Request r) {
      calls.add(r.url);
      sentHeaders.add(r.headers);
      final q = r.url.queryParameters;
      if (r.url.path != '/portal.php') return _res('Not found', 404);
      String body(Object? o) => jsonEncode({'js': o});
      switch ('${q['type']}/${q['action']}') {
        case 'stb/handshake':
          handshakes++;
          return _res(body({'token': 'T$handshakes'}), 200);
        case 'stb/get_profile':
          return _res(jsonEncode(fx('get_profile')), 200);
        case 'account_info/get_main_info':
          return _res(body({'mac': 'x', 'phone': 'November 16, 2030, 9:29 am'}), 200);
        case 'itv/get_genres':
          if (tokenExpiresAfter == 0 && r.headers['Authorization'] == 'Bearer T1') {
            return _res('Authorization failed.', 200);
          }
          return _res(jsonEncode(fx('itv_genres')), 200);
        case 'vod/get_ordered_list':
          final p = int.parse(q['p']!);
          return _res(body({
            'total_items': 30,
            'max_page_items': 14,
            'data': [for (var i = 0; i < (p < 3 ? 14 : 2); i++) {'id': '${p * 100 + i}', 'name': 'M$p-$i', 'cmd': 'b64', 'is_series': i == 0 ? 1 : 0}],
          }), 200);
        case 'itv/create_link':
          // List cmd → empty stream=, localhost form → full link (as measured).
          final ok = q['cmd']!.contains('localhost/ch/');
          return _res(body({'cmd': 'ffmpeg http://portal.example/play/live.php?mac=x&stream=${ok ? '42' : ''}&extension=ts&play_token=abc'}), 200);
        case 'vod/create_link':
          return _res(body({'cmd': 'ffmpeg http://portal.example/play/movie.php?id=1&series=${q['series']}'}), 200);
      }
      return _res(body(null), 200);
    }

    StalkerAdapter make() => StalkerAdapter(
          creds,
          http: ProviderHttp(client: MockClient((r) async => route(r)), backoffBase: Duration.zero),
          clock: () => DateTime(2026, 11, 15),
        );

    setUp(() {
      calls = [];
      sentHeaders = [];
      tokenExpiresAfter = -1;
      handshakes = 0;
    });

    test('login: handshake → profile → account; MAG headers + MAC cookie; MAC normalised', () async {
      final a = make();
      final acc = await a.authenticate();
      expect(acc.status, ConnectionStatus.active);
      expect(acc.expiresAt, DateTime(2030, 11, 16, 9, 29));
      expect(calls.first.queryParameters['action'], 'handshake');
      expect(sentHeaders.first['Cookie'], contains('mac=00%3A1A%3A79%3AF0%3A06%3A3B'));
      expect(sentHeaders.first['User-Agent'], contains('MAG200'));
      expect(sentHeaders[1]['Authorization'], 'Bearer T1');
    });

    test('expired line → expired', () async {
      final a = StalkerAdapter(
        creds,
        http: ProviderHttp(client: MockClient((r) async => route(r))),
        clock: () => DateTime(2031, 1, 1),
      );
      await expectLater(
        a.authenticate(),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.expired)),
      );
    });

    test('expired token → one new handshake, then the call succeeds', () async {
      final a = make();
      await a.authenticate();
      tokenExpiresAfter = 0;
      final cats = await a.liveCategories();
      expect(cats, isNotEmpty);
      expect(cats.any((c) => c.id == '*'), isFalse); // "All" pseudo-genre dropped
      expect(handshakes, 2);
    });

    test('paging: 30 items / 14 per page → 3 pages; series rows skipped from movies', () async {
      final a = make();
      final m = await a.movies(categoryId: '5');
      final pages = calls.where((u) => u.queryParameters['action'] == 'get_ordered_list').map((u) => u.queryParameters['p']).toSet();
      expect(pages, {'1', '2', '3'});
      expect(m, hasLength(14 + 14 + 2 - 3));
      expect((await a.movieDetails(m.first.id)).movie.name, m.first.name);
    });

    test('"all" lists are capped (big portals)', () async {
      final a = StalkerAdapter(creds, http: ProviderHttp(client: MockClient((r) async => route(r))), allPagesLimit: 2);
      await a.movies();
      final pages = calls.where((u) => u.queryParameters['action'] == 'get_ordered_list').map((u) => u.queryParameters['p']).toSet();
      expect(pages, {'1', '2'});
      expect(calls.last.queryParameters['category'], '*');
    });

    test('live link: list cmd gives empty stream= → falls back to localhost/ch form', () async {
      final a = make();
      final r = await a.resolveStream(const StreamRef(kind: MediaKind.live, id: '42', command: 'ffmpeg http://portal.example/play/live.php?stream=42'));
      expect(r.url.queryParameters['stream'], '42');
      expect(r.headers['User-Agent'], contains('MAG200'));
      final cmds = calls.where((u) => u.queryParameters['action'] == 'create_link').map((u) => u.queryParameters['cmd']).toList();
      expect(cmds.last, 'ffmpeg http://localhost/ch/42_');
      expect('$r', isNot(contains('play_token')));
    });

    test('episode link sends the episode number', () async {
      final a = make();
      final r = await a.resolveStream(const StreamRef(kind: MediaKind.series, id: '49938:1#3', command: 'seasoncmd'));
      expect(r.url.queryParameters['series'], '3');
    });

    test('wrong endpoint path falls through to the next candidate', () async {
      final asked = <String>[];
      final a = StalkerAdapter(
        const StalkerCredentials(portal: 'http://portal.example/stalker_portal/c/', mac: '001A79F0063B'),
        http: ProviderHttp(client: MockClient((r) async {
          asked.add(r.url.path);
          if (r.url.path == '/portal.php') return route(r);
          return http.Response('<html>404</html>', 404);
        })),
        clock: () => DateTime(2026, 11, 15),
      );
      await a.authenticate();
      expect(asked.take(3), ['/stalker_portal/portal.php', '/stalker_portal/server/load.php', '/portal.php']);
      expect(asked, contains('/portal.php'));
    });
  });

  // ── LIVE: the user's MAG line (opt-in; env/test_panels.json "stalker"). ──
  final live = liveStalker();
  test('LIVE: Stalker login, lists, details, links that really play', () async {
    final a = StalkerAdapter(live!);
    final sw = Stopwatch()..start();
    final acc = await a.authenticate();
    final loginMs = sw.elapsedMilliseconds;
    final liveCats = await a.liveCategories();
    final vodCats = await a.movieCategories();
    final serCats = await a.seriesCategories();
    final channels = await a.liveChannels(categoryId: liveCats[1].id);
    final movies = await a.movies(categoryId: vodCats.first.id);
    final series = await a.series(categoryId: serCats.first.id);
    final sd = series.isEmpty ? null : await a.seriesDetails(series.first.id);
    final epgCh = channels.where((c) => c.epgId != null).firstOrNull ?? channels.first;
    final epg = await a.shortEpg(epgCh);

    Future<String> probe(ResolvedStream r) async {
      final c = HttpClient();
      try {
        final req = await c.getUrl(r.url);
        r.headers.forEach(req.headers.set);
        final res = await req.close().timeout(const Duration(seconds: 20));
        final first = await res.first.timeout(const Duration(seconds: 20));
        return 'HTTP ${res.statusCode} ${first.isNotEmpty && first[0] == 0x47 ? 'MPEG-TS' : 'bytes ${first.length}'}';
      } catch (e) {
        return 'failed ${e.runtimeType}';
      } finally {
        c.close(force: true);
      }
    }

    final liveLink = await probe(await a.resolveStream(channels.first.stream));
    await Future<void>.delayed(const Duration(seconds: 2)); // 1 connection per line
    final movieLink = movies.isEmpty ? 'n/a' : await probe(await a.resolveStream(movies.first.stream));
    await Future<void>.delayed(const Duration(seconds: 2));
    final ep = sd?.episodes.values.firstOrNull?.firstOrNull;
    final epLink = ep == null ? 'n/a' : await probe(await a.resolveStream(ep.stream));

    // ignore: avoid_print
    print('LIVE stalker: login ${loginMs}ms, expires ${acc.expiresAt}\n'
        '  categories live ${liveCats.length} / movies ${vodCats.length} / series ${serCats.length}\n'
        '  channels ${channels.length} (epg ids ${channels.where((c) => c.epgId != null).length}), movies ${movies.length}, series ${series.length}\n'
        '  series details: seasons ${sd?.seasonNumbers}, episodes ${sd?.episodes.values.fold<int>(0, (n, l) => n + l.length)}\n'
        '  short EPG ${epg.length}\n'
        '  play: live $liveLink | movie $movieLink | episode $epLink\n'
        '  total ${sw.elapsedMilliseconds}ms');
    expect(acc.status, ConnectionStatus.active);
    expect(liveLink, startsWith('HTTP 200'));
    a.dispose();
  }, skip: live == null ? liveSkip : false, timeout: const Timeout(Duration(minutes: 3)));
}
