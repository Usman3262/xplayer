import 'dart:convert';
import 'dart:io';

import 'package:data/src/remote/api_endpoints.dart';
import 'package:data/src/security/signed_app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client scenario 1 (19 Oct): a fresh install whose primary API is
/// unreachable learns a backup API from a static mirror, and only from a
/// correctly signed config. Envelope made by the real backend signer
/// (buildSignedAppConfig, 7-day mirror validity, throwaway key).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fx = jsonDecode(
    File('test/fixtures/mirror_config_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final keys = {fx['kid'] as String: fx['publicKey'] as String};
  final t0 = DateTime.fromMillisecondsSinceEpoch(fx['t0'] as int);
  final envelope = Map<String, dynamic>.from(fx['mirror'] as Map);
  const primary = 'https://api.example.com/v1';
  const mirrorA = 'https://mirror-a.example.org/config.json';
  const mirrorB = 'https://mirror-b.example.org/config.json';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiEndpoints.instance.resetForTest();
    ApiEndpoints.instance.ensurePrimary(primary);
  });

  SignedAppConfigStore store() =>
      SignedAppConfigStore(trustedKeys: keys, clock: () => t0.add(const Duration(days: 2)));

  test('fresh install, primary down: first good mirror supplies the backup API', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add(req.url.host);
      if (req.url.host == 'mirror-a.example.org') return http.Response('down', 503);
      return http.Response(jsonEncode(envelope), 200);
    });
    await syncSignedAppConfig(
      () async => throw Exception('primary unreachable'),
      store: store(),
      mirrors: const [mirrorA, mirrorB],
      client: client,
    );
    expect(hits, ['mirror-a.example.org', 'mirror-b.example.org']);
    expect(ApiEndpoints.instance.bases, contains('https://backup.example.net/v1'));
    // Now a network failure on the primary moves to the backup.
    expect(ApiEndpoints.instance.reportNetworkFailure(primary), 'https://backup.example.net/v1');
  });

  test('tampered mirror config is rejected', () async {
    final p = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(envelope['payload'] as String))))
        as Map<String, dynamic>;
    p['apiBaseUrls'] = ['https://attacker.example'];
    final forged = {...envelope, 'payload': base64Url.encode(utf8.encode(jsonEncode(p))).replaceAll('=', '')};
    final client = MockClient((_) async => http.Response(jsonEncode(forged), 200));
    final ok = await syncFromConfigMirrors(
      store: store(),
      mirrors: const [mirrorA],
      client: client,
      force: true,
    );
    expect(ok, isFalse);
    expect(ApiEndpoints.instance.bases, [primary]);
  });

  test('http mirrors are ignored', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response(jsonEncode(envelope), 200);
    });
    final ok = await syncFromConfigMirrors(
      store: store(),
      mirrors: const ['http://mirror-a.example.org/config.json'],
      client: client,
      force: true,
    );
    expect(ok, isFalse);
    expect(called, isFalse);
  });

  test('API shape { data: envelope } on a mirror is accepted too', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'data': envelope}), 200));
    final ok = await syncFromConfigMirrors(
      store: store(),
      mirrors: const [mirrorB],
      client: client,
      force: true,
    );
    expect(ok, isTrue);
  });
}
