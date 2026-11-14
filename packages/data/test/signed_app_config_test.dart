import 'dart:convert';
import 'dart:io';

import 'package:data/src/security/signed_app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envelopes produced by the real backend signer
/// (backend Script: signedConfigService.buildSignedAppConfig, test key).
void main() {
  final fx = jsonDecode(
    File('test/fixtures/signed_config_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final keys = {fx['kid'] as String: fx['publicKey'] as String};
  final t0 = DateTime.fromMillisecondsSinceEpoch(fx['t0'] as int);
  final older = Map<String, dynamic>.from(fx['older'] as Map);
  final newer = Map<String, dynamic>.from(fx['newer'] as Map);
  const fresh = ConfigCheckState();

  test('accepts a server-signed config and keeps only https origins', () async {
    final cfg = await verifyAppConfig(older,
        trustedKeys: keys, state: fresh, now: t0.add(const Duration(minutes: 1)));
    expect(cfg, isNotNull);
    expect(cfg!.apiBaseUrls,
        ['https://api.example.com', 'https://backup.example.net']);
    expect(cfg.downloads, isTrue);
  });

  test('rejects a modified payload', () async {
    final p = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(older['payload'] as String))))
        as Map<String, dynamic>;
    p['apiBaseUrls'] = ['https://attacker.example'];
    final forged = {
      ...older,
      'payload': base64Url.encode(utf8.encode(jsonEncode(p))).replaceAll('=', ''),
    };
    expect(
        await verifyAppConfig(forged, trustedKeys: keys, state: fresh, now: t0), isNull);
  });

  test('rejects unknown key id and wrong key', () async {
    expect(
        await verifyAppConfig({...older, 'kid': 'nope'},
            trustedKeys: keys, state: fresh, now: t0),
        isNull);
    expect(
        await verifyAppConfig(older,
            trustedKeys: {fx['kid'] as String: base64.encode(List.filled(32, 7))},
            state: fresh,
            now: t0),
        isNull);
  });

  test('rejects an expired config', () async {
    expect(
        await verifyAppConfig(older,
            trustedKeys: keys, state: fresh, now: t0.add(const Duration(hours: 7))),
        isNull);
  });

  test('rejects rollback to an older config, accepts newer', () async {
    final n = await verifyAppConfig(newer,
        trustedKeys: keys, state: fresh, now: t0.add(const Duration(hours: 1)));
    expect(n, isNotNull);
    final after = ConfigCheckState(lastSeq: n!.seq);
    expect(
        await verifyAppConfig(older,
            trustedKeys: keys, state: after, now: t0.add(const Duration(hours: 1))),
        isNull);
  });

  test('rejects a config below the revocation floor', () async {
    final o = await verifyAppConfig(older, trustedKeys: keys, state: fresh, now: t0);
    expect(
        await verifyAppConfig(older,
            trustedKeys: keys,
            state: ConfigCheckState(lastMinSeq: o!.seq + 1),
            now: t0),
        isNull);
  });

  test('rejects a non-Ed25519 envelope', () async {
    expect(
        await verifyAppConfig({...older, 'alg': 'HS256'},
            trustedKeys: keys, state: fresh, now: t0),
        isNull);
  });
}
