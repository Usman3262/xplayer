import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backend #20 (usman123 signed out 20 Oct 23:33): when two parts of the app
/// refresh with the same token, the server answers 409 REFRESH_RACE to the
/// second one instead of revoking the sign-in. The app must use the newest
/// stored token, and never sign out on it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response json(int status, Map<String, Object?> body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  final oldRefresh = 'r' * 40;
  final otherRefresh = 'q' * 40;

  late TokenStore tokens;

  /// [otherPartRefreshes]: another part of the app stored new tokens just
  /// before our refresh was answered.
  Future<AppAuthRepository> repo({required bool otherPartRefreshes}) async {
    SharedPreferences.setMockInitialValues({});
    tokens = TokenStore();
    await tokens.save(accessToken: 'a' * 40, refreshToken: oldRefresh, expiresInSec: 900);
    final client = ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          final sent = (jsonDecode(r.body) as Map)['refreshToken'];
          if (sent == oldRefresh) {
            if (otherPartRefreshes) {
              await tokens.save(accessToken: 'x' * 40, refreshToken: otherRefresh, expiresInSec: 900);
            }
            return json(409, {
              'success': false,
              'message': 'Refresh token was already used; retry with the newest token',
              'code': 'REFRESH_RACE',
              'data': null,
            });
          }
          return json(200, {
            'success': true,
            'message': 'Token refreshed',
            'data': {'accessToken': 'n' * 40, 'refreshToken': 'm' * 40, 'expiresIn': 900},
          });
        }
        if (r.headers['authorization'] != 'Bearer ${'n' * 40}') {
          return json(401, {'success': false, 'message': 'Access token expired', 'data': null});
        }
        return json(200, {'success': true, 'message': 'OK', 'data': {'ok': true}});
      }),
    );
    return AppAuthRepository(tokenStore: tokens, client: client);
  }

  test('409 REFRESH_RACE: retries with the newest stored token and stays signed in', () async {
    final r = await repo(otherPartRefreshes: true);
    await r.client.get('/playback/active', auth: true);
    final now = await tokens.read();
    expect(now, isNotNull);
    expect(now!.refreshToken, 'm' * 40);
  });

  test('409 REFRESH_RACE without a newer token: temporary error, sign-in kept', () async {
    final r = await repo(otherPartRefreshes: false);
    ApiException? error;
    try {
      await r.client.get('/playback/active', auth: true);
    } on ApiException catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error!.statusCode, isNot(401));
    expect(await tokens.read(), isNotNull, reason: 'a race must never clear the tokens');
  });
}
