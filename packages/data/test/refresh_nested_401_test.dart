import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mid-playback "Invalid access token" cascade: refresh must not deadlock when
/// a nested authenticated call (PoP challenge) also returns 401 while refresh
/// is already in flight.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response json(int status, Map<String, Object?> body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('expired access: refresh skips PoP and recovers the session', () async {
    SharedPreferences.setMockInitialValues({});
    final tokens = TokenStore();
    // Client skew is 45s — expiresInSec: 1 is already "expired".
    await tokens.save(
      accessToken: 'old-access-token-value-xxxxxxxxxxxx',
      refreshToken: 'refresh-token-value-xxxxxxxxxxxx',
      expiresInSec: 1,
    );
    await tokens.saveDeviceId('device-1');

    var refreshCalls = 0;
    var challengeCalls = 0;
    final client = ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/auth/refresh')) {
          refreshCalls++;
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          expect(body['refreshToken'], isNotEmpty);
          expect(body.containsKey('popChallengeId'), isFalse);
          return json(200, {
            'success': true,
            'message': 'Token refreshed',
            'data': {
              'accessToken': 'new-access-token-value-xxxxxxxxxxx',
              'refreshToken': 'new-refresh-token-value-xxxxxxxxxx',
              'expiresIn': 900,
              'deviceId': 'device-1',
            },
          });
        }
        if (path.contains('/pop/challenge')) {
          challengeCalls++;
          return json(401, {
            'success': false,
            'message': 'Invalid access token',
            'data': null,
          });
        }
        if (r.headers['authorization'] !=
            'Bearer new-access-token-value-xxxxxxxxxxx') {
          return json(401, {
            'success': false,
            'message': 'Invalid access token',
            'data': null,
          });
        }
        return json(200, {
          'success': true,
          'message': 'OK',
          'data': {'ok': true},
        });
      }),
    );

    final repo = AppAuthRepository(tokenStore: tokens, client: client);
    await repo.client.get('/playback/active', auth: true);

    expect(refreshCalls, greaterThanOrEqualTo(1));
    expect(challengeCalls, 0);
    expect(
      (await tokens.read())?.accessToken,
      'new-access-token-value-xxxxxxxxxxx',
    );
  });

  test('nested auth 401 during onRefresh does not deadlock', () async {
    SharedPreferences.setMockInitialValues({});
    final tokens = TokenStore();
    await tokens.save(
      accessToken: 'old-access-token-value-xxxxxxxxxxxx',
      refreshToken: 'refresh-token-value-xxxxxxxxxxxx',
      expiresInSec: 900,
    );

    var nestedChallenge = 0;
    final client = ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path.contains('/pop/challenge')) {
          nestedChallenge++;
          return json(401, {
            'success': false,
            'message': 'Invalid access token',
            'data': null,
          });
        }
        if (r.headers['authorization'] ==
            'Bearer new-access-token-value-xxxxxxxxxxx') {
          return json(200, {
            'success': true,
            'message': 'OK',
            'data': {'ok': true},
          });
        }
        return json(401, {
          'success': false,
          'message': 'Invalid access token',
          'data': null,
        });
      }),
    );

    client.onRefresh = () async {
      // Same shape as DevicePop challenge during /auth/refresh.
      try {
        await client.post('/devices/device-1/pop/challenge', auth: true);
      } on ApiException {
        // Nested 401 must throw quickly, not wait on this refresh.
      }
      await tokens.save(
        accessToken: 'new-access-token-value-xxxxxxxxxxx',
        refreshToken: 'new-refresh-token-value-xxxxxxxxxx',
        expiresInSec: 900,
      );
      return true;
    };

    await client
        .get('/playback/active', auth: true)
        .timeout(const Duration(seconds: 5));

    expect(nestedChallenge, 1);
    expect(
      (await tokens.read())?.accessToken,
      'new-access-token-value-xxxxxxxxxxx',
    );
  });
}
