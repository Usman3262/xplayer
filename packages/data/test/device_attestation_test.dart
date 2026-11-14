import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android Key Attestation (security point 18): silent, once a day, one
/// retry at playback start when the server is in Block mode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response ok(Object? data) => http.Response(
        jsonEncode({'success': true, 'message': 'OK', 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );
  http.Response err(int status, String code) => http.Response(
        jsonEncode({'success': false, 'message': code, 'code': code, 'data': null}),
        status,
        headers: {'content-type': 'application/json'},
      );

  late List<Map<String, dynamic>> calls;
  late TokenStore tokens;
  late DateTime now;

  ApiClient make(Future<http.Response> Function(http.Request r) handler) {
    return ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        calls.add({
          'path': r.url.path,
          'body': r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body),
        });
        return handler(r);
      }),
    );
  }

  Future<http.Response> passServer(http.Request r) async {
    if (r.url.path.endsWith('/attestation/challenge')) {
      return ok({'challenge': 'Q2hhbGxlbmdl', 'expiresInSec': 300, 'mode': 'log'});
    }
    if (r.url.path.endsWith('/attestation')) {
      return ok({'verdict': 'pass', 'reasons': [], 'mode': 'log'});
    }
    return ok({});
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tokens = TokenStore();
    await tokens.save(accessToken: 'a' * 40, refreshToken: 'r' * 40, expiresInSec: 900);
    calls = [];
    now = DateTime(2026, 11, 5, 12);
    DeviceAttestation.resetForTest();
    DeviceAttestation.isAndroidOverride = true;
    DeviceAttestation.nowOverride = () => now;
    DeviceAttestation.chainOverride = (c) async => ['TEFFRg==', 'SU5URVI=', 'Uk9PVA=='];
  });

  tearDown(() {
    DeviceAttestation.isAndroidOverride = null;
    DeviceAttestation.installerOverride = null;
    DeviceAttestation.playIntegrityOverride = null;
    DeviceAttestation.isIOSOverride = null;
    DeviceAttestation.appAttestOverride = null;
    DeviceAttestation.nowOverride = null;
    DeviceAttestation.chainOverride = null;
  });

  test('posts challenge, key_attestation method and chain (leaf first)', () async {
    String? seenChallenge;
    DeviceAttestation.chainOverride = (c) async {
      seenChallenge = c;
      return ['TEFFRg==', 'SU5URVI='];
    };
    final client = make(passServer);
    expect(await DeviceAttestation.run(client, 'd1'), isTrue);
    expect(seenChallenge, 'Q2hhbGxlbmdl');
    expect(calls.map((c) => c['path']), [
      '/v1/devices/d1/attestation/challenge',
      '/v1/devices/d1/attestation',
    ]);
    expect(calls[1]['body'], {
      'challenge': 'Q2hhbGxlbmdl',
      'method': 'key_attestation',
      'certificateChain': ['TEFFRg==', 'SU5URVI='],
    });
  });

  test('24 h throttle after a pass', () async {
    final client = make(passServer);
    expect(await DeviceAttestation.run(client, 'd1'), isTrue);
    calls.clear();
    now = now.add(const Duration(hours: 23));
    expect(await DeviceAttestation.run(client, 'd1'), isFalse);
    expect(calls, isEmpty);
    now = now.add(const Duration(hours: 2));
    expect(await DeviceAttestation.run(client, 'd1'), isTrue);
    expect(calls, hasLength(2));
  });

  test('concurrent runs share one flight', () async {
    final client = make(passServer);
    final a = DeviceAttestation.run(client, 'd1');
    final b = DeviceAttestation.run(client, 'd1');
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(calls, hasLength(2));
  });

  test('errors are swallowed: network, 400, 404, fail verdict, no chain', () async {
    final cases = <Future<http.Response> Function(http.Request)>[
      (r) async => throw http.ClientException('offline'),
      (r) async => err(400, 'ATTESTATION_CHALLENGE_INVALID'),
      (r) async => err(404, 'NOT_FOUND'),
      (r) async => r.url.path.endsWith('/challenge')
          ? ok({'challenge': 'x'})
          : ok({'verdict': 'fail', 'reasons': ['bad_root']}),
      (r) async => ok(null),
    ];
    for (final h in cases) {
      DeviceAttestation.resetForTest();
      expect(await DeviceAttestation.run(make(h), 'd1'), isFalse);
    }
    DeviceAttestation.resetForTest();
    DeviceAttestation.chainOverride = (c) async => throw Exception('no keystore');
    expect(await DeviceAttestation.run(make(passServer), 'd1'), isFalse);
    DeviceAttestation.resetForTest();
    DeviceAttestation.chainOverride = (c) async => null;
    expect(await DeviceAttestation.run(make(passServer), 'd1'), isFalse);
    // runIfDue never throws either.
    DeviceAttestation.runIfDue(make((r) async => throw Exception('x')), 'd1');
    DeviceAttestation.runIfDue(make(passServer), null);
    await Future<void>.delayed(Duration.zero);
  });

  test('non-Android: no requests at all', () async {
    DeviceAttestation.isAndroidOverride = false;
    final client = make(passServer);
    expect(await DeviceAttestation.run(client, 'd1', force: true), isFalse);
    DeviceAttestation.runIfDue(client, 'd1');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });

  group('playback start in Block mode', () {
    test('ATTESTATION_REQUIRED: attest once, retry start once', () async {
      var starts = 0;
      final client = make((r) async {
        if (r.url.path.endsWith('/playback/start')) {
          starts += 1;
          return starts == 1
              ? err(403, 'ATTESTATION_REQUIRED')
              : ok({'playbackId': 'p1', 'streamUrl': 'https://s/x.m3u8'});
        }
        return passServer(r);
      });
      final s = await PlaybackApi(client).start(
        deviceId: 'd1',
        contentType: 'live',
        streamId: '1',
      );
      expect(s.playbackId, 'p1');
      expect(calls.map((c) => c['path']), [
        '/v1/playback/start',
        '/v1/devices/d1/attestation/challenge',
        '/v1/devices/d1/attestation',
        '/v1/playback/start',
      ]);
    });

    test('still required after one retry: original error surfaces, no loop', () async {
      final client = make((r) async {
        if (r.url.path.endsWith('/playback/start')) {
          return err(403, 'ATTESTATION_REQUIRED');
        }
        return passServer(r);
      });
      await expectLater(
        PlaybackApi(client).start(deviceId: 'd1', contentType: 'live', streamId: '1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ATTESTATION_REQUIRED')),
      );
      expect(calls.where((c) => c['path'] == '/v1/playback/start'), hasLength(2));
    });

    test('other errors pass through untouched', () async {
      final client = make((r) async => err(409, 'PLAYBACK_LEASE_HELD'));
      await expectLater(
        PlaybackApi(client).start(deviceId: 'd1', contentType: 'live', streamId: '1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PLAYBACK_LEASE_HELD')),
      );
      expect(calls, hasLength(1));
    });
  });

  group('Android Play Integrity', () {
    Future<http.Response> playServer(http.Request r) async {
      if (r.url.path.endsWith('/attestation/challenge')) {
        return ok({
          'challenge': 'Q2hhbGxlbmdl',
          'expiresInSec': 300,
          'methods': ['play_integrity', 'key_attestation'],
          'mode': 'log',
        });
      }
      return passServer(r);
    }

    test('installed from Google Play: sends a Play Integrity token with the challenge as nonce', () async {
      String? nonceSeen;
      DeviceAttestation.installerOverride = () async => 'com.android.vending';
      DeviceAttestation.playIntegrityOverride = (n) async {
        nonceSeen = n;
        return 'PLAY.TOKEN';
      };
      final ok = await DeviceAttestation.run(make(playServer), 'd1');
      expect(ok, isTrue);
      expect(nonceSeen, 'Q2hhbGxlbmdl');
      final body = calls.last['body'];
      expect(body['method'], 'play_integrity');
      expect(body['integrityToken'], 'PLAY.TOKEN');
      expect(body.containsKey('certificateChain'), isFalse);
    });

    test('Play install but no token (no Play services / error): falls back to Key Attestation', () async {
      DeviceAttestation.installerOverride = () async => 'com.android.vending';
      DeviceAttestation.playIntegrityOverride = (n) async => null;
      final ok = await DeviceAttestation.run(make(playServer), 'd1');
      expect(ok, isTrue);
      expect(calls.last['body']['method'], 'key_attestation');
    });

    test('direct download (other installer): Key Attestation, Play Integrity never asked', () async {
      var asked = false;
      DeviceAttestation.installerOverride = () async => 'com.google.android.packageinstaller';
      DeviceAttestation.playIntegrityOverride = (n) async {
        asked = true;
        return 'X';
      };
      final ok = await DeviceAttestation.run(make(playServer), 'd1');
      expect(ok, isTrue);
      expect(asked, isFalse);
      expect(calls.last['body']['method'], 'key_attestation');
    });

    test('server does not list play_integrity: Key Attestation', () async {
      DeviceAttestation.installerOverride = () async => 'com.android.vending';
      DeviceAttestation.playIntegrityOverride = (n) async => 'PLAY.TOKEN';
      final ok = await DeviceAttestation.run(make(passServer), 'd1');
      expect(ok, isTrue);
      expect(calls.last['body']['method'], 'key_attestation');
    });
  });

  group('iPhone App Attest', () {
    setUp(() {
      DeviceAttestation.isAndroidOverride = false;
      DeviceAttestation.isIOSOverride = true;
    });

    test('posts keyId + attestation as app_attest and stores the pass', () async {
      DeviceAttestation.appAttestOverride =
          (c) async => {'keyId': 'S2V5SWQ=', 'attestation': 'QXR0ZXN0'};
      final ok = await DeviceAttestation.run(make(passServer), 'd1');
      expect(ok, isTrue);
      final submit = calls.last;
      expect(submit['path'], endsWith('/devices/d1/attestation'));
      expect(submit['body']['method'], 'app_attest');
      expect(submit['body']['challenge'], 'Q2hhbGxlbmdl');
      expect(submit['body']['keyId'], 'S2V5SWQ=');
      expect(submit['body']['attestation'], 'QXR0ZXN0');
      expect(submit['body'].containsKey('certificateChain'), isFalse);
    });

    test('no App Attest on this device: nothing submitted, no error', () async {
      DeviceAttestation.appAttestOverride = (c) async => null;
      final ok = await DeviceAttestation.run(make(passServer), 'd1');
      expect(ok, isFalse);
      expect(calls.where((c) => (c['path'] as String).endsWith('/attestation')), isEmpty);
    });

    test('neither Android nor iPhone: no request at all', () async {
      DeviceAttestation.isIOSOverride = false;
      final ok = await DeviceAttestation.run(make(passServer), 'd1');
      expect(ok, isFalse);
      expect(calls, isEmpty);
    });
  });
}
