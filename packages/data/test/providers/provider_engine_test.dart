import 'dart:async';
import 'dart:convert';

import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('panel input (instant local checks)', () {
    test('parsePanelUrl normalises what users paste', () {
      expect(parsePanelUrl('neo.example.com:8080')!.toString(), 'http://neo.example.com:8080');
      expect(parsePanelUrl(' https://p.tv/ ')!.toString(), 'https://p.tv');
      expect(
        parsePanelUrl('http://p.tv:8080/player_api.php?username=a&password=b')!.toString(),
        'http://p.tv:8080',
      );
      expect(parsePanelUrl('http://p.tv/stalker_portal/c/')!.path, '/stalker_portal/c');
      expect(parsePanelUrl(''), isNull);
      expect(parsePanelUrl('ftp://p.tv'), isNull);
      expect(parsePanelUrl('http://'), isNull);
    });

    test('Xtream credentials: required fields and URL', () {
      expect(const XtreamCredentials(server: 'p.tv', username: 'u', password: 'p').validate(), isEmpty);
      final bad = const XtreamCredentials(server: 'ftp://x', username: ' ', password: '').validate();
      expect(bad, {
        'server': ProviderInputError.invalidUrl,
        'username': ProviderInputError.required,
        'password': ProviderInputError.required,
      });
    });

    test('Stalker MAC accepts common formats, rejects junk', () {
      String? mac(String m) => StalkerCredentials(portal: 'p.tv', mac: m).normalizedMac;
      expect(mac('00:1a:79:ab:cd:ef'), '00:1A:79:AB:CD:EF');
      expect(mac('00-1A-79-AB-CD-EF'), '00:1A:79:AB:CD:EF');
      expect(mac('001A79ABCDEF'), '00:1A:79:AB:CD:EF');
      expect(mac('00:1A:79:AB:CD'), isNull);
      expect(mac('00:1A:79:AB:CD:EG'), isNull);
      expect(
        const StalkerCredentials(portal: 'p.tv', mac: 'xx').validate(),
        {'mac': ProviderInputError.invalidMac},
      );
    });

    test('M3U: URL required, optional EPG URL checked', () {
      expect(const M3uCredentials(url: 'http://p.tv/list.m3u').validate(), isEmpty);
      expect(const M3uCredentials(url: '').validate(), {'url': ProviderInputError.required});
      expect(
        const M3uCredentials(url: 'http://p.tv/a.m3u', epgUrl: 'not a url').validate(),
        {'epgUrl': ProviderInputError.invalidUrl},
      );
    });

    test('storage round trip; toString never shows secrets', () {
      const c = XtreamCredentials(server: 'http://p.tv:8080', username: 'alice', password: 's3cret');
      final back = ProviderCredentials.fromStorage(c.toStorage()) as XtreamCredentials;
      expect(back.password, 's3cret');
      expect('$c', 'xtream(p.tv)');
      expect('$c', isNot(contains('s3cret')));
      expect('$c', isNot(contains('alice')));
      expect(ProviderCredentials.fromStorage({'kind': 'unknown'}), isNull);
    });
  });

  group('status model (spec §3.5)', () {
    test('failure → connection status', () {
      expect(const ProviderFailure(ProviderFailureKind.unauthorized).status, ConnectionStatus.unauthorized);
      expect(const ProviderFailure(ProviderFailureKind.expired).status, ConnectionStatus.expired);
      expect(const ProviderFailure(ProviderFailureKind.banned).status, ConnectionStatus.unauthorized);
      expect(const ProviderFailure(ProviderFailureKind.timeout).status, ConnectionStatus.temporarilyUnavailable);
      expect(const ProviderFailure(ProviderFailureKind.invalidInput).status, ConnectionStatus.invalidConfiguration);
      expect(const ProviderFailure(ProviderFailureKind.timeout).isRetryable, isTrue);
      expect(const ProviderFailure(ProviderFailureKind.unauthorized).isRetryable, isFalse);
      expect(ConnectionStatus.active.isUsable, isTrue);
      expect(ConnectionStatus.expired.isUsable, isFalse);
    });

    test('ProviderKind.fromKey matches admin panel-type keys', () {
      expect(ProviderKind.fromKey('Xtream'), ProviderKind.xtream);
      expect(ProviderKind.fromKey('stalker'), ProviderKind.stalker);
      expect(ProviderKind.fromKey('enigma2'), isNull);
    });

    test('expiresSoon', () {
      final now = DateTime(2026, 11, 15);
      ProviderAccount a(DateTime? e) => ProviderAccount(status: ConnectionStatus.active, expiresAt: e);
      expect(a(now.add(const Duration(days: 2))).expiresSoon(now), isTrue);
      expect(a(now.add(const Duration(days: 30))).expiresSoon(now), isFalse);
      expect(a(null).expiresSoon(now), isFalse);
    });

    test('factory: invalid input and unregistered kinds fail clearly', () {
      expect(
        () => ProviderAdapterFactory.create(const XtreamCredentials(server: '', username: 'u', password: 'p')),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.invalidInput)),
      );
      expect(
        () => ProviderAdapterFactory.create(const StalkerCredentials(portal: 'p.tv', mac: '001A79ABCDEF')),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.unsupported)),
      );
    });
  });

  group('ProviderHttp', () {
    ProviderHttp make(MockClientHandler h, {ProviderLimits limits = const ProviderLimits()}) =>
        ProviderHttp(client: MockClient(h), limits: limits, backoffBase: Duration.zero);
    final uri = Uri.parse('http://p.tv/player_api.php?username=u&password=secret');

    test('decodes JSON (small and isolate-sized)', () async {
      final big = List.generate(30000, (i) => {'stream_id': i, 'name': 'Ch $i'});
      final h = make((r) async => http.Response(
            r.url.path == '/big' ? jsonEncode(big) : '{"ok":1}',
            200,
          ));
      expect(await h.getJson(uri), {'ok': 1});
      final list = await h.getJson(uri.replace(path: '/big')) as List;
      expect(list.length, 30000);
    });

    test('status codes → failure kinds; HTML instead of JSON = badResponse', () async {
      Future<ProviderFailureKind> kindFor(int code, [String body = '']) async {
        final h = make((_) async => http.Response(body, code),
            limits: const ProviderLimits(retries: 0));
        try {
          await h.getJson(uri);
          fail('should throw');
        } on ProviderFailure catch (f) {
          return f.kind;
        }
      }

      expect(await kindFor(401), ProviderFailureKind.unauthorized);
      expect(await kindFor(403), ProviderFailureKind.unauthorized);
      expect(await kindFor(429), ProviderFailureKind.rateLimited);
      expect(await kindFor(884), ProviderFailureKind.unsupported);
      expect(await kindFor(503), ProviderFailureKind.server);
      expect(await kindFor(404), ProviderFailureKind.badResponse);
      expect(await kindFor(200, '<html>blocked</html>'), ProviderFailureKind.badResponse);
    });

    test('retries retryable failures, then succeeds', () async {
      var calls = 0;
      final h = make((_) async {
        calls++;
        return calls < 3 ? http.Response('', 502) : http.Response('[1]', 200);
      });
      expect(await h.getJson(uri), [1]);
      expect(calls, 3);
    });

    test('no retry on login or on wrong password', () async {
      var calls = 0;
      final h = make((_) async {
        calls++;
        return http.Response('', 503);
      });
      await expectLater(h.getJson(uri, auth: true), throwsA(isA<ProviderFailure>()));
      expect(calls, 1);
      calls = 0;
      final h2 = make((_) async {
        calls++;
        return http.Response('', 401);
      });
      await expectLater(h2.getJson(uri), throwsA(isA<ProviderFailure>()));
      expect(calls, 1);
    });

    test('login uses the short timeout and reports timeout', () async {
      final h = make(
        (_) => Completer<http.Response>().future, // never answers
        limits: const ProviderLimits(authTimeout: Duration(milliseconds: 50)),
      );
      await expectLater(
        h.getJson(uri, auth: true),
        throwsA(isA<ProviderFailure>().having((f) => f.kind, 'kind', ProviderFailureKind.timeout)),
      );
    });

    test('network errors never carry the URL (credentials)', () async {
      final h = make((_) async => throw http.ClientException('failed: $uri', uri),
          limits: const ProviderLimits(retries: 0));
      try {
        await h.getJson(uri);
        fail('should throw');
      } on ProviderFailure catch (f) {
        expect(f.kind, ProviderFailureKind.network);
        expect('$f', isNot(contains('secret')));
        expect('$f', contains('p.tv'));
      }
    });

    test('concurrency cap is never exceeded', () async {
      var inFlight = 0;
      var peak = 0;
      final h = make((_) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return http.Response('1', 200);
      }, limits: const ProviderLimits(concurrency: 3));
      await Future.wait([for (var i = 0; i < 20; i++) h.getJson(uri)]);
      expect(peak, 2); // background work keeps one of the 3 slots free for the user
    });

    test('priority lane: user requests jump the queue while background work is busy', () async {
      final order = <String>[];
      final h = make((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(r.url.path);
        return http.Response('1', 200);
      }, limits: const ProviderLimits(concurrency: 3));
      final background = [for (var i = 0; i < 10; i++) h.getJson(uri.replace(path: '/bg$i'))];
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final user = h.getJson(uri.replace(path: '/user'), priority: true);
      await user;
      await Future.wait(background);
      // The user request finished long before the 10 queued background ones.
      expect(order.indexOf('/user'), lessThan(4));
    });

    test('priority requests fail fast (no retries)', () async {
      var calls = 0;
      final h = make((_) async {
        calls++;
        return http.Response('', 503);
      });
      await expectLater(h.getJson(uri, priority: true), throwsA(isA<ProviderFailure>()));
      expect(calls, 1);
    });

    test('limits come from the admin config, clamped to safe ranges', () {
      final c = RemoteConfig.tryParse({
        'version': 1,
        'settings': {
          'providers.connect_timeout_ms': 5000,
          'providers.request_timeout_ms': 999999,
          'providers.request_concurrency': 0,
        },
      })!;
      final l = ProviderLimits.fromConfig(c);
      expect(l.authTimeout, const Duration(seconds: 5));
      expect(l.requestTimeout, const Duration(seconds: 120));
      expect(l.concurrency, 1);
      final d = ProviderLimits.fromConfig(RemoteConfig.empty);
      expect(d.authTimeout, const Duration(seconds: 8));
      expect(d.concurrency, 4);
    });
  });

  group('mappers → existing domain entities', () {
    const ref = StreamRef(kind: MediaKind.movie, id: '77', extension: 'mkv');

    test('movie', () {
      final m = providerMovieToDomain(
        const ProviderMovie(id: '77', name: 'Dune', stream: ref, rating: 0, posterUrl: 'not-a-url', year: 2021, addedSec: 100),
        details: const ProviderMovieDetails(
          movie: ProviderMovie(id: '77', name: 'Dune', stream: ref),
          plot: '  ',
          durationSec: 9360,
          genres: ['Sci-Fi'],
        ),
      );
      expect(m.kind, MediaKind.movie);
      expect(m.rating, isNull); // 0 = no rating
      expect(m.posterUrl, isNull);
      expect(m.synopsis, isNull);
      expect(m.durationLabel, '2h 36m');
      expect(m.containerExtension, 'mkv');
      expect(m.streamUrl, isNull); // resolved at play time only
      expect(m.addedSec, 100);
    });

    test('series + episode', () {
      final s = providerSeriesToDomain(const ProviderSeries(id: '5', name: 'Show', rating: 8.1));
      expect(s.kind, MediaKind.series);
      expect(s.seriesId, '5');
      expect(s.rating, 8.1);
      final e = providerEpisodeToDomain(const ProviderEpisode(
        id: '901', seriesId: '5', season: 2, number: 3, title: 'Ep',
        stream: StreamRef(kind: MediaKind.series, id: '901', extension: 'mp4'),
      ));
      expect(e.durationLabel, ''); // never invent a duration
      expect(e.season, 2);
      expect(e.containerExtension, 'mp4');
    });

    test('live channel with EPG now/next', () {
      final now = DateTime(2026, 11, 15, 20, 30);
      final ch = providerChannelToDomain(
        const ProviderChannel(
          id: '1', name: 'News HD', number: 101, logoUrl: 'http://p.tv/l.png',
          stream: StreamRef(kind: MediaKind.live, id: '1'),
        ),
        now: now,
        epg: [
          EpgEntry(title: 'Later', start: DateTime(2026, 11, 15, 22), end: DateTime(2026, 11, 15, 23)),
          EpgEntry(title: 'Evening News', start: DateTime(2026, 11, 15, 20), end: DateTime(2026, 11, 15, 21)),
          EpgEntry(title: 'Sport', start: DateTime(2026, 11, 15, 21), end: DateTime(2026, 11, 15, 22)),
        ],
      );
      expect(ch.code, '101');
      expect(ch.nowTitle, 'Evening News');
      expect(ch.nextTitle, 'Sport');
      expect(ch.progress, closeTo(0.5, 0.001));
      expect(ch.imageUrl, 'http://p.tv/l.png');
      expect(ch.streamUrl, isNull);
    });

    test('live channel without EPG falls back to its name', () {
      final ch = providerChannelToDomain(const ProviderChannel(
        id: '2', name: 'Movies 1', stream: StreamRef(kind: MediaKind.live, id: '2'),
      ));
      expect(ch.code, 'LIVE');
      expect(ch.nowTitle, ch.name);
      expect(ch.nextTitle, '');
    });
  });

  group('[PANEL] logs', () {
    late List<String> lines;
    late DebugPrintCallback saved;
    setUp(() {
      lines = [];
      saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    });
    tearDown(() => debugPrint = saved);

    const creds = XtreamCredentials(server: 'http://panel.example:8080', username: 'alice99', password: 'S3cr3tPw');

    test('success: host, path, action, status, size — never the credentials', () async {
      final a = XtreamAdapter(creds, http: ProviderHttp(client: MockClient((_) async => http.Response(
            '{"user_info":{"username":"alice99","password":"S3cr3tPw","auth":1,"status":"Active"}}', 200))));
      await a.authenticate();
      final log = lines.where((l) => l.startsWith('[PANEL]')).join(' | ');
      expect(log, contains('GET http://panel.example:8080/player_api.php → HTTP 200'));
      expect(log, isNot(contains('alice99')));
      expect(log, isNot(contains('S3cr3tPw')));
    });

    test('network error: the real reason is logged, URL query/credentials masked', () async {
      final a = XtreamAdapter(creds, http: ProviderHttp(
        client: MockClient((r) async => throw http.ClientException(
            "Failed host lookup: 'panel.example' (OS Error: No address associated with hostname)", r.url)),
      ));
      await expectLater(a.authenticate(), throwsA(isA<ProviderFailure>()));
      final log = lines.where((l) => l.startsWith('[PANEL]')).join(' | ');
      expect(log, contains('NETWORK ERROR'));
      expect(log, contains('Failed host lookup'));
      expect(log, isNot(contains('S3cr3tPw')));
    });

    test('refused login says why (fields, not values)', () async {
      final a = XtreamAdapter(creds, http: ProviderHttp(client: MockClient((_) async => http.Response(
            '{"user_info":{"username":"alice99","password":"S3cr3tPw","auth":0}}', 200))));
      await expectLater(a.authenticate(), throwsA(isA<ProviderFailure>()));
      final log = lines.where((l) => l.startsWith('[PANEL]')).join(' | ');
      expect(log, contains('xtream login refused (unauthorized)'));
      expect(log, contains('auth=0'));
      expect(log, isNot(contains('S3cr3tPw')));
      expect(log, isNot(contains('alice99')));
    });

    test('panelUrl masks Xtream stream paths and keeps only action/type', () {
      expect(Diag.panelUrl(Uri.parse('http://h:8080/live/alice99/S3cr3tPw/1.ts')), 'http://h:8080/live/***/***/1.ts');
      expect(Diag.panelUrl(Uri.parse('http://h/player_api.php?username=a&password=b&action=get_live_streams')),
          'http://h/player_api.php?action=get_live_streams');
      expect(Diag.panelText('see http://h/play/live.php?mac=00:1A:79:AA:BB:CC&stream=5 and password=xyz'),
          'see http://h/play/live.php and password=***');
    });

    test('old backend noise is off by default', () {
      Diag.api('GET /catalog/top10 → LOCAL miss');
      Diag.dev('SPORTS_DATA getSportsMatches FAILED');
      expect(lines.where((l) => l.contains('LOCAL miss') || l.contains('SPORTS_DATA')), isEmpty);
    });
  });

  group('https → http fallback (panels without https)', () {
    test('refused on https → same request over http works; host remembered; streams follow', () async {
      final asked = <String>[];
      final h = ProviderHttp(client: MockClient((r) async {
        asked.add('${r.url.scheme}://${r.url.host}${r.url.hasPort ? ':${r.url.port}' : ''}${r.url.path}');
        if (r.url.scheme == 'https') throw http.ClientException('Connection refused', r.url);
        return http.Response('#EXTM3U http://x/1.ts', 200);
      }), backoffBase: Duration.zero);
      final t = await h.getText(Uri.parse('https://pro.example/get.php?username=u&password=p&type=m3u_plus'));
      expect(t, startsWith('#EXTM3U'));
      expect(asked, ['https://pro.example/get.php', 'http://pro.example/get.php']);
      // Next call goes straight to http.
      await h.getText(Uri.parse('https://pro.example/other'));
      expect(asked.last, 'http://pro.example/other');
      expect(h.effective(Uri.parse('https://pro.example:8443/live/u/p/1.ts')).toString(), 'http://pro.example:8443/live/u/p/1.ts');
      expect(h.effective(Uri.parse('https://elsewhere.example/a')).scheme, 'https');
    });

    test('Xtream stream URLs use http after the API fell back', () async {
      final a = XtreamAdapter(
        const XtreamCredentials(server: 'https://panel.example', username: 'u', password: 'p'),
        http: ProviderHttp(client: MockClient((r) async {
          if (r.url.scheme == 'https') throw http.ClientException('HandshakeException: wrong version number', r.url);
          return http.Response('{"user_info":{"auth":1,"status":"Active"}}', 200);
        })),
      );
      await a.authenticate();
      expect(a.streamUri(const StreamRef(kind: MediaKind.live, id: '5')).toString(), 'http://panel.example/live/u/p/5.ts');
    });

    test('a real "not found" on https is not retried over http', () async {
      var calls = 0;
      final h = ProviderHttp(client: MockClient((r) async {
        calls++;
        return http.Response('nope', 404);
      }));
      await expectLater(h.getText(Uri.parse('https://p.example/x')), throwsA(isA<ProviderFailure>()));
      expect(calls, 1);
    });
  });

  test('remote log sink gets only scrubbed lines (uploaded to the server)', () async {
    final sent = <String>[];
    Diag.remoteSink = (tag, msg) => sent.add('[$tag] $msg');
    addTearDown(() => Diag.remoteSink = null);
    final a = XtreamAdapter(
      const XtreamCredentials(server: 'http://panel.example', username: 'alice99', password: 'S3cr3tPw'),
      http: ProviderHttp(client: MockClient((r) async => throw http.ClientException('refused: ${r.url}', r.url))),
    );
    await expectLater(a.authenticate(), throwsA(isA<ProviderFailure>()));
    Diag.event('ACCOUNT', 'login for http://x/get.php?username=alice99&password=S3cr3tPw failed');
    final all = sent.join(' | ');
    expect(sent, isNotEmpty);
    expect(all, contains('[PANEL] GET http://panel.example/player_api.php'));
    expect(all, isNot(contains('S3cr3tPw')));
    expect(all, isNot(contains('alice99')));
  });
}
