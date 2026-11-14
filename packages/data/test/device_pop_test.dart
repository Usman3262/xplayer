import 'dart:convert';

import 'package:data/data.dart';
import 'package:data/src/security/device_pop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device PoP retry (client 3.4): server says POP_REQUIRED → the app gets a
/// one-time challenge, signs it with the device key, repeats the call once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response ok(Object data) => http.Response(
        jsonEncode({'success': true, 'message': 'OK', 'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );
  http.Response popRequired() => http.Response(
        jsonEncode({
          'success': false,
          'message': 'Device PoP signature required',
          'code': 'POP_REQUIRED',
          'data': null,
        }),
        403,
        headers: {'content-type': 'application/json'},
      );

  late List<Map<String, dynamic>> calls;
  late ApiClient client;
  late TokenStore tokens;

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tokens = TokenStore();
    await tokens.save(accessToken: 'a' * 40, refreshToken: 'r' * 40, expiresInSec: 900);
    calls = [];
    DevicePop.signOverride = (bytes) async => base64Encode(bytes.reversed.toList());
  });

  tearDown(() => DevicePop.signOverride = null);

  test('enforcement off: one call, no challenge', () async {
    client = make((r) async => ok({'playbackId': 'p1'}));
    final data = await DevicePop.post(
      client,
      '/playback/start',
      body: {'deviceId': 'd1'},
      auth: false,
      proof: () => DevicePop.forDevice(client, 'd1'),
    );
    expect(data?['playbackId'], 'p1');
    expect(calls.map((c) => c['path']), ['/v1/playback/start']);
  });

  test('POP_REQUIRED on refresh: challenge via refresh token, signed retry', () async {
    var refreshCalls = 0;
    client = make((r) async {
      if (r.url.path.endsWith('/auth/refresh/challenge')) {
        return ok({'challengeId': 'c1', 'challenge': 'abc', 'alg': 'ES256'});
      }
      refreshCalls += 1;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return body.containsKey('popSignature') ? ok({'accessToken': 'a2'}) : popRequired();
    });
    final data = await DevicePop.post(
      client,
      '/auth/refresh',
      body: {'refreshToken': 'r' * 30},
      auth: false,
      proof: () => DevicePop.forRefresh(client, 'r' * 30),
    );
    expect(data?['accessToken'], 'a2');
    expect(refreshCalls, 2);
    expect(calls.map((c) => c['path']), [
      '/v1/auth/refresh',
      '/v1/auth/refresh/challenge',
      '/v1/auth/refresh',
    ]);
    final signed = calls.last['body'] as Map<String, dynamic>;
    expect(signed['popChallengeId'], 'c1');
    // Signature over the UTF-8 bytes of the challenge string.
    expect(signed['popSignature'], base64Encode(utf8.encode('abc').reversed.toList()));
    expect(signed['refreshToken'], 'r' * 30);
  });

  test('device without a key: original error is kept, no retry loop', () async {
    DevicePop.signOverride = (_) async => null;
    client = make((r) async {
      if (r.url.path.endsWith('/auth/refresh/challenge')) {
        return ok({'challengeId': 'c1', 'challenge': 'abc'});
      }
      return popRequired();
    });
    await expectLater(
      DevicePop.post(
        client,
        '/playback/start',
        body: {'deviceId': 'd1'},
        auth: false,
        proof: () => DevicePop.forRefresh(client, 'r' * 30),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'POP_REQUIRED')),
    );
    expect(calls.where((c) => c['path'] == '/v1/playback/start').length, 1);
  });

  test('enrolment: posts the key once per device, then skips', () async {
    DevicePop.publicKeyOverride = () async => 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEabcdefghijklmnop';
    client = make((r) async => ok({'deviceId': 'd1', 'alg': 'ES256'}));
    await DevicePop.ensureEnrolled(client, 'd1');
    await DevicePop.ensureEnrolled(client, 'd1');
    DevicePop.publicKeyOverride = null;
    final posts = calls.where((c) => c['path'] == '/v1/devices/d1/pop/key').toList();
    expect(posts.length, 1);
    expect((posts.single['body'] as Map)['publicKey'], startsWith('MFkw'));
  });

  test('enrolment failure never throws and retries next time', () async {
    DevicePop.publicKeyOverride = () async => 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEzzzzzzzzzzzzzzzz';
    client = make((r) async => popRequired());
    await DevicePop.ensureEnrolled(client, 'd2');
    await DevicePop.ensureEnrolled(client, 'd2');
    DevicePop.publicKeyOverride = null;
    expect(calls.where((c) => c['path'] == '/v1/devices/d2/pop/key').length, 2);
  });

  test('other errors are not retried', () async {
    client = make((r) async => http.Response(
          jsonEncode({'success': false, 'message': 'Device limit', 'code': 'DEVICE_LIMIT_REACHED'}),
          409,
          headers: {'content-type': 'application/json'},
        ));
    await expectLater(
      DevicePop.post(
        client,
        '/playback/start',
        body: {'deviceId': 'd1'},
        auth: false,
        proof: () => DevicePop.forDevice(client, 'd1'),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(calls.length, 1);
  });
}
