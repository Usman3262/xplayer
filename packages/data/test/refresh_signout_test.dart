import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client 20 Oct / C1: "error while watching, then the app logged me out".
/// A refresh that fails for a temporary reason (429 rate limit, 5xx) must
/// keep the sign-in; only a rejected refresh token (401) signs out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response json(int status, Map<String, Object?> body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  late TokenStore tokens;

  Future<AppAuthRepository> repo(int refreshStatus) async {
    SharedPreferences.setMockInitialValues({});
    tokens = TokenStore();
    // Access token rejected by the server (expired), refresh token present.
    await tokens.save(
      accessToken: 'a' * 40,
      refreshToken: 'r' * 40,
      expiresInSec: 900,
    );
    final client = ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          return refreshStatus == 200
              ? json(200, {
                  'success': true,
                  'message': 'Token refreshed',
                  'data': {
                    'accessToken': 'n' * 40,
                    'refreshToken': 'm' * 40,
                    'expiresIn': 900,
                  },
                })
              : json(refreshStatus, {
                  'success': false,
                  'message': refreshStatus == 401
                      ? 'Refresh token reuse detected'
                      : 'Too many requests',
                  'data': null,
                });
        }
        // The old access token is rejected; the refreshed one works.
        if (r.headers['authorization'] != 'Bearer ${'n' * 40}') {
          return json(401, {
            'success': false,
            'message': 'Access token expired',
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
    return AppAuthRepository(tokenStore: tokens, client: client);
  }

  Future<ApiException?> call(AppAuthRepository r) async {
    try {
      await r.client.get('/playback/active', auth: true);
      return null;
    } on ApiException catch (e) {
      return e;
    }
  }

  test('refresh 429 (shared carrier IP): stays signed in, asks to retry',
      () async {
    final r = await repo(429);
    final e = await call(r);
    expect(e?.statusCode, 503);
    expect(e?.code, 'SESSION_REFRESH_RETRY');
    expect(await tokens.read(), isNotNull);
  });

  test('refresh 503 (server busy): stays signed in', () async {
    final r = await repo(503);
    final e = await call(r);
    expect(e?.code, 'SESSION_REFRESH_RETRY');
    expect(await tokens.read(), isNotNull);
  });

  test('refresh 401 (token rejected / reused): signs out', () async {
    final r = await repo(401);
    final e = await call(r);
    expect(e?.statusCode, 401);
    expect(await tokens.read(), isNull);
  });

  test('refresh 200: call succeeds with the new token', () async {
    final r = await repo(200);
    expect(await call(r), isNull);
    expect((await tokens.read())?.accessToken, 'n' * 40);
  });
}
