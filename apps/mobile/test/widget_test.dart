import 'dart:convert';

import 'package:player_mobile/core/session_controller.dart';
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('login stores session from mocked auth API', () async {
    SharedPreferences.setMockInitialValues({});
    final mockHttp = MockClient((request) async {
      final path = request.url.path;
      Map<String, dynamic> ok(Object? data) => {
            'success': true,
            'message': 'ok',
            'data': data,
            'requestId': 'test',
          };

      if (path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode(
            ok({
              'mfaRequired': false,
              'mfaEnrollmentRequired': false,
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 900,
              'sessionId': 'sess-1',
              'account': {
                'id': 'acc-1',
                'role': 'CUSTOMER',
                'username': 'demo',
                'email': 'demo@example.com',
                'status': 'ACTIVE',
                'mfaEnabled': false,
                'emailVerified': true,
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/devices/register')) {
        return http.Response(
          jsonEncode(
            ok({
              'id': 'dev-1',
              'platform': 'ANDROID',
              'name': 'Android Phone',
              'status': 'ACTIVE',
              'lastSeenAt': null,
              'createdAt': '2026-01-01T00:00:00.000Z',
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/devices')) {
        return http.Response(
          jsonEncode(ok([])),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'success': false,
          'message': 'not found',
          'data': null,
          'requestId': 'test',
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    final tokens = TokenStore(memory: {});
    final repo = AppAuthRepository(
      config: const ApiConfig(baseUrl: 'https://example.test/v1'),
      tokenStore: tokens,
      client: ApiClient(
        config: const ApiConfig(baseUrl: 'https://example.test/v1'),
        tokenStore: tokens,
        httpClient: mockHttp,
      ),
    );

    final session = SessionController(
      repo,
      AppMediaRepository.fromAuth(repo),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await session.completeOnboarding();
    await session.login(
      email: 'demo@example.com',
      password: 'StrongPass1!',
    );

    expect(session.state.isLoggedIn, isTrue);
    expect(session.state.user?.email, 'demo@example.com');
    expect(await tokens.read(), isNotNull);
    repo.dispose();
  });
}
