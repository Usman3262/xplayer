import 'dart:convert';
import 'dart:io';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'live_panel.dart';

/// Real Neo replies, trimmed, credentials/host replaced (test/fixtures/xtream).
Object? fx(String name) =>
    jsonDecode(File('test/fixtures/xtream/$name.json').readAsStringSync());

const creds = XtreamCredentials(server: 'http://panel.example:8080', username: 'USER', password: 'P@ss/1');

void main() {
  final now = DateTime.utc(2026, 11, 15);

  group('account', () {
    test('real Neo login → active account', () {
      final a = XtreamAdapter.parseAccount(fx('account'), now: now);
      expect(a.status, ConnectionStatus.active);
      expect(a.maxConnections, 1);
      expect(a.activeConnections, 0);
      expect(a.isTrial, isFalse);
      expect(a.allowedOutputFormats, containsAll(['ts', 'm3u8']));
      expect(a.expiresAt!.isAfter(now), isTrue);
      expect(a.serverTimezone, 'Europe/Amsterdam');
    });

    test('wrong password shapes → unauthorized', () {
      for (final raw in [
        <dynamic>[],
        <String, dynamic>{},
        {'user_info': {'auth': 0}},
        {'user_info': {'auth': '0', 'status': 'Active'}},
        null,
      ]) {
        expect(
          () => XtreamAdapter.parseAccount(raw, now: now),
          throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.unauthorized)),
          reason: '$raw',
        );
      }
    });

    test('expired by status or by date; banned/disabled', () {
      ProviderFailureKind kindOf(Map<String, dynamic> ui) {
        try {
          XtreamAdapter.parseAccount({'user_info': {'auth': 1, ...ui}}, now: now);
          return ProviderFailureKind.server; // not thrown
        } on ProviderFailure catch (f) {
          return f.kind;
        }
      }

      expect(kindOf({'status': 'Expired'}), ProviderFailureKind.expired);
      expect(kindOf({'status': 'Active', 'exp_date': '1600000000'}), ProviderFailureKind.expired);
      expect(kindOf({'status': 'Banned'}), ProviderFailureKind.banned);
      expect(kindOf({'status': 'Disabled'}), ProviderFailureKind.banned);
      // Unlimited (null / "0" / missing expiry) is fine.
      final a = XtreamAdapter.parseAccount({'user_info': {'auth': 1, 'status': 'Active', 'exp_date': null}}, now: now);
      expect(a.expiresAt, isNull);
    });
  });

  group('lists (real Neo samples)', () {
    test('categories', () {
      final c = XtreamAdapter.parseCategories(fx('get_live_categories'));
      expect(c, hasLength(6));
      expect(c.first.id, isNotEmpty);
      expect(c.first.name, isNotEmpty);
      expect(c.first.parentId, isNull); // parent_id 0 = top level
    });

    test('live channels', () {
      final ch = XtreamAdapter.parseLiveStreams(fx('get_live_streams'));
      expect(ch, isNotEmpty);
      final c = ch.first;
      expect(int.tryParse(c.id), isNotNull); // numeric stream_id → string
      expect(c.stream.kind, MediaKind.live);
      expect(c.number, isNotNull);
      expect(c.logoUrl, startsWith('http'));
      expect(c.epgId, isNull); // "" on Neo
      expect(c.addedSec, greaterThan(1600000000));
    });

    test('movies', () {
      final m = XtreamAdapter.parseVodStreams(fx('get_vod_streams'));
      expect(m, isNotEmpty);
      final f = m.first;
      expect(f.stream.extension, 'mkv');
      expect(f.rating, 8);
      expect(f.tmdbId, 1077863);
      expect(f.addedSec, isNotNull);
    });

    test('series', () {
      final s = XtreamAdapter.parseSeries(fx('get_series'));
      expect(s, isNotEmpty);
      final f = s.first;
      expect(f.posterUrl, startsWith('https://'));
      expect(f.backdropUrl, startsWith('https://'));
      expect(f.genres, ['Drama', 'Comedy']);
      expect(f.year, 2026); // "2026-01-11 (مصر)"
      expect(f.addedSec, isNotNull); // last_modified
    });

    test('odd panel shapes never crash', () {
      expect(XtreamAdapter.parseLiveStreams(null), isEmpty);
      expect(XtreamAdapter.parseLiveStreams({'error': 'x'}), isEmpty);
      expect(XtreamAdapter.parseLiveStreams([1, 'x', {'name': 'no id'}]), isEmpty);
      final hdr = XtreamAdapter.parseLiveStreams([
        {'stream_id': 1, 'name': '##### SPORTS #####'},
        {'stream_id': '2', 'name': 'Sports 1', 'tv_archive': '1', 'tv_archive_duration': '7'},
      ]);
      expect(hdr.map((c) => c.id), ['2']);
      expect(hdr.single.catchupDays, 7);
      // Object keyed by index instead of a list.
      expect(XtreamAdapter.parseVodStreams({'0': {'stream_id': 9, 'name': 'X (1999)'}}).single.year, 1999);
    });
  });

  group('details (real Neo samples)', () {
    test('movie details', () {
      final d = XtreamAdapter.parseVodInfo(fx('get_vod_info'), '780853');
      expect(d.movie.id, '780853');
      expect(d.movie.name, isNotEmpty);
      expect(d.movie.year, 2023);
      expect(d.movie.tmdbId, 1077863);
      expect(d.durationSec, 6587);
      expect(d.genres, ['Adventure', 'Family', 'Fantasy']);
      expect(d.plot, isNotEmpty);
      expect(d.backdropUrl, startsWith('https://'));
      expect(d.trailerYoutubeId, isNull); // "" on this title
    });

    test('series details: seasons from episode groups (seasons list empty on Neo)', () {
      final d = XtreamAdapter.parseSeriesInfo(fx('get_series_info'), '13801');
      expect(d.seasonNumbers, isNotEmpty);
      final e = d.episodes[d.seasonNumbers.first]!.first;
      expect(e.seriesId, '13801');
      expect(e.number, 1);
      expect(e.stream.extension, 'mkv');
      expect(e.durationSec, 3241);
      expect(d.series.name, isNotEmpty);
    });

    test('flat episode list with season field', () {
      final d = XtreamAdapter.parseSeriesInfo({
        'info': {'name': 'S'},
        'episodes': [
          {'id': 3, 'season': 2, 'episode_num': '2', 'title': ''},
          {'id': 2, 'season': '2', 'episode_num': 1},
          {'id': 1, 'season': 1, 'episode_num': 1, 'info': {'duration': '00:45:00'}},
        ],
      }, '7');
      expect(d.seasonNumbers, [1, 2]);
      expect(d.episodes[2]!.map((e) => e.id), ['2', '3']);
      expect(d.episodes[2]!.last.title, ''); // app labels it
      expect(d.episodes[1]!.single.durationSec, 2700);
    });

    test('empty details reply → badResponse', () {
      expect(
        () => XtreamAdapter.parseVodInfo([], '1'),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.badResponse)),
      );
    });
  });

  test('short EPG: base64 titles, timestamps, sorted, bad rows skipped', () {
    String b(String s) => base64.encode(utf8.encode(s));
    final epg = XtreamAdapter.parseShortEpg({
      'epg_listings': [
        {'title': b('Sport'), 'description': b('Live'), 'start_timestamp': '1794733200', 'stop_timestamp': '1794736800'},
        {'title': b('أخبار'), 'start_timestamp': 1794729600, 'stop_timestamp': 1794733200},
        {'title': 'Plain Title', 'start': '2026-11-16 12:00:00', 'end': '2026-11-16 13:00:00'},
        {'title': b('broken'), 'start_timestamp': 5, 'stop_timestamp': 1},
      ],
    });
    expect(epg.map((e) => e.title), ['أخبار', 'Sport', 'Plain Title']);
    expect(epg[1].description, 'Live');
    expect(XtreamAdapter.parseShortEpg(fx('get_short_epg')), isEmpty); // Neo: no EPG for that channel
  });

  group('stream URLs', () {
    test('built on device, credentials path-encoded, never in toString', () async {
      final a = XtreamAdapter(creds);
      final live = await a.resolveStream(const StreamRef(kind: MediaKind.live, id: '286044'));
      expect('${live.url}', 'http://panel.example:8080/live/USER/P@ss%2F1/286044.ts');
      expect('$live', isNot(contains('P@ss')));
      final movie = a.streamUri(const StreamRef(kind: MediaKind.movie, id: '780853', extension: 'mkv'));
      expect(movie.path, '/movie/USER/P@ss%2F1/780853.mkv');
      final ep = a.streamUri(const StreamRef(kind: MediaKind.series, id: '596397'));
      expect(ep.path, '/series/USER/P@ss%2F1/596397.mp4');
    });

    test('live format: admin choice if allowed, else what the account allows', () async {
      Future<String> fmt(String pref, List<String> allowed) async {
        final a = XtreamAdapter(
          creds,
          preferredLiveFormat: pref,
          http: ProviderHttp(client: MockClient((_) async => http.Response(
                jsonEncode({'user_info': {'auth': 1, 'status': 'Active', 'allowed_output_formats': allowed}}),
                200,
              ))),
          clock: () => now,
        );
        await a.authenticate();
        return a.liveFormat;
      }

      expect(await fmt('m3u8', ['m3u8', 'ts']), 'm3u8');
      expect(await fmt('m3u8', ['ts']), 'ts');
      expect(await fmt('ts', ['m3u8']), 'm3u8');
      expect(await fmt('ts', []), 'ts');
    });

    test('panel installed under a path keeps it', () {
      final a = XtreamAdapter(const XtreamCredentials(server: 'https://p.tv/xc/', username: 'u', password: 'p'));
      expect(a.streamUri(const StreamRef(kind: MediaKind.live, id: '1')).toString(), 'https://p.tv/xc/live/u/p/1.ts');
    });
  });

  test('requests: right action/params, credentials only in the query', () async {
    final seen = <Uri>[];
    final a = XtreamAdapter(creds, http: ProviderHttp(client: MockClient((r) async {
      seen.add(r.url);
      final isInfo = r.url.queryParameters['action'] == 'get_series_info';
      return http.Response(isInfo ? '{"info":{"name":"S"},"episodes":{}}' : '[]', 200);
    })));
    await a.movies(categoryId: '156');
    await a.seriesDetails('13801');
    await a.liveChannels();
    expect(seen[0].path, '/player_api.php');
    expect(seen[0].queryParameters, {'username': 'USER', 'password': 'P@ss/1', 'action': 'get_vod_streams', 'category_id': '156'});
    expect(seen[1].queryParameters['series_id'], '13801');
    expect(seen[2].queryParameters.containsKey('category_id'), isFalse);
  });

  test('factory builds Xtream once registered', () {
    XtreamAdapter.register();
    final a = ProviderAdapterFactory.create(creds);
    expect(a, isA<XtreamAdapter>());
    a.dispose();
  });

  // ── LIVE: a real panel line (opt-in, see live_panel.dart). ──
  final live = livePanel();
  test('LIVE: login, lists, details through the adapter', () async {
    final a = XtreamAdapter(live!);
    final sw = Stopwatch()..start();
    final acc = await a.authenticate();
    final loginMs = sw.elapsedMilliseconds;
    expect(acc.status, ConnectionStatus.active);

    final liveCats = await a.liveCategories();
    final vodCats = await a.movieCategories();
    final serCats = await a.seriesCategories();
    expect(liveCats, isNotEmpty);
    expect(vodCats, isNotEmpty);
    expect(serCats, isNotEmpty);

    final channels = await a.liveChannels(categoryId: liveCats.first.id);
    final movies = await a.movies(categoryId: vodCats.first.id);
    final series = await a.series(categoryId: serCats.first.id);
    expect(channels.every((c) => c.id.isNotEmpty && c.name.isNotEmpty), isTrue);

    ProviderMovieDetails? md;
    if (movies.isNotEmpty) md = await a.movieDetails(movies.first.id);
    ProviderSeriesDetails? sd;
    if (series.isNotEmpty) sd = await a.seriesDetails(series.first.id);
    // Many Neo channels carry an EPG id but no listings: try a few.
    var epg = const <EpgEntry>[];
    for (final c in channels.where((c) => c.epgId != null).take(8)) {
      epg = await a.shortEpg(c);
      if (epg.isNotEmpty) break;
    }
    final nowT = DateTime.now();
    final onNow = epg.where((e) => e.isOnAt(nowT)).length;

    // Safe summary only: counts, flags, timings — no names of hosts/users.
    // ignore: avoid_print
    print('LIVE xtream: login ${loginMs}ms, expires ${acc.expiresAt?.toIso8601String().substring(0, 10)}, '
        'max ${acc.maxConnections}, formats ${acc.allowedOutputFormats}, live format ${a.liveFormat}\n'
        '  categories live ${liveCats.length} / movies ${vodCats.length} / series ${serCats.length}\n'
        '  first category: channels ${channels.length} (logos ${channels.where((c) => c.logoUrl != null).length}, '
        'epg ids ${channels.where((c) => c.epgId != null).length}, catch-up ${channels.where((c) => c.catchupDays > 0).length}), '
        'movies ${movies.length} (tmdb ${movies.where((m) => m.tmdbId != null).length}), series ${series.length}\n'
        '  movie details: year ${md?.movie.year}, ${md?.durationSec}s, genres ${md?.genres.length}, plot ${md?.plot != null}\n'
        '  series details: seasons ${sd?.seasonNumbers}, episodes ${sd?.episodes.values.fold<int>(0, (n, l) => n + l.length)}\n'
        '  short EPG (first channel with an EPG id): ${epg.length} entries, on now $onNow, '
        'titles ok ${epg.every((e) => e.title.isNotEmpty)}\n'
        '  total ${sw.elapsedMilliseconds}ms');
    a.dispose();
  },
      skip: live == null ? liveSkip : false,
      timeout: const Timeout(Duration(seconds: 90)));
}
