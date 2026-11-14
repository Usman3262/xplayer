import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Usman 12 Nov: a reused connection that was already closed made catalog
/// lists wait 26–30 s and fail with "connection closed" while the server
/// answered in under 50 ms. A GET is asked once more on a fresh connection;
/// a POST is not (it may have reached the server).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ApiClient, List<String>)> client({required int failures}) async {
    SharedPreferences.setMockInitialValues({});
    final tokens = TokenStore();
    await tokens.save(accessToken: 'a' * 40, refreshToken: 'r' * 40, expiresInSec: 900);
    final calls = <String>[];
    var left = failures;
    final c = ApiClient(
      config: const ApiConfig(baseUrl: 'https://api.test/v1'),
      tokenStore: tokens,
      httpClient: MockClient((r) async {
        calls.add(r.method);
        if (left > 0) {
          left--;
          throw http.ClientException('Connection closed before full header was received', r.url);
        }
        return http.Response(
          jsonEncode({'success': true, 'message': 'OK', 'data': {'ok': true}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (c, calls);
  }

  test('a GET whose connection closed is asked once more and succeeds', () async {
    final (c, calls) = await client(failures: 1);
    final data = await c.get('/catalog/series', auth: true);
    expect(data?['ok'], isTrue);
    expect(calls, ['GET', 'GET']);
  });

  test('only once: a second broken connection is reported', () async {
    final (c, calls) = await client(failures: 2);
    await expectLater(c.get('/catalog/series', auth: true), throwsA(isA<ApiException>()));
    expect(calls, ['GET', 'GET']);
  });

  test('a POST is not sent twice', () async {
    final (c, calls) = await client(failures: 1);
    await expectLater(c.post('/playback/start', body: const {}, auth: true), throwsA(isA<ApiException>()));
    expect(calls, ['POST']);
  });
}
