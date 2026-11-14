import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device key channel (Android / iPhone / Windows TPM). Any failure on the
/// native side must mean "no key": no exception, no extra request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/device_binding');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(Future<Object?> Function(MethodCall c)? handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => mock(null));

  group('channel answers', () {
    test(
      'public key and storage come from the channel (Windows TPM)',
      () async {
        mock(
          (c) async => switch (c.method) {
            'getPublicKeySpkiBase64' => 'MFkw EwYH\nKoZI',
            'getPopKeyStorage' => 'tee',
            _ => null,
          },
        );
        expect(await DeviceBindingKey.publicKeySpkiBase64(), 'MFkwEwYHKoZI');
        expect(await DeviceBindingKey.popKeyStorage(), 'tee');
      },
    );

    test('signature string is passed through; nonce sent as bytes', () async {
      Object? sent;
      mock((c) async {
        sent = (c.arguments as Map)['nonce'];
        return 'r_s-sig';
      });
      final sig = await DeviceBindingKey.signRawNonce(
        Uint8List.fromList(utf8.encode('challenge')),
      );
      expect(sig, 'r_s-sig');
      expect(sent, isA<Uint8List>());
      expect(utf8.decode(sent! as Uint8List), 'challenge');
    });

    test(
      'signature bytes (Android) become base64url without padding',
      () async {
        mock((c) async => Uint8List.fromList([0xfb, 0xff, 0x01, 0x02]));
        final sig = await DeviceBindingKey.signRawNonce(
          Uint8List.fromList([1]),
        );
        expect(sig, '-_8BAg');
      },
    );
  });

  group('failures mean no key, never an exception', () {
    test('no native handler (MissingPluginException)', () async {
      mock(null);
      expect(await DeviceBindingKey.publicKeySpkiBase64(), isNull);
      expect(await DeviceBindingKey.popKeyStorage(), 'none');
      expect(
        await DeviceBindingKey.signRawNonce(Uint8List.fromList([1])),
        isNull,
      );
    });

    test('native error (PlatformException)', () async {
      mock((c) async => throw PlatformException(code: 'binding_error'));
      expect(await DeviceBindingKey.publicKeySpkiBase64(), isNull);
      expect(await DeviceBindingKey.popKeyStorage(), 'none');
      expect(
        await DeviceBindingKey.signRawNonce(Uint8List.fromList([1])),
        isNull,
      );
    });

    test('native null (TPM and software provider both failed)', () async {
      mock((c) async => c.method == 'getPopKeyStorage' ? 'none' : null);
      expect(await DeviceBindingKey.publicKeySpkiBase64(), isNull);
      expect(await DeviceBindingKey.popKeyStorage(), 'none');
      expect(
        await DeviceBindingKey.signRawNonce(Uint8List.fromList([1])),
        isNull,
      );
    });

    test('empty nonce is never sent to the channel', () async {
      var called = false;
      mock((c) async {
        called = true;
        return 'x';
      });
      expect(await DeviceBindingKey.signRawNonce(Uint8List(0)), isNull);
      expect(called, isFalse);
    });

    test(
      'enrolment without a key makes no request and does not throw',
      () async {
        SharedPreferences.setMockInitialValues({});
        mock((c) async => throw PlatformException(code: 'binding_error'));
        final calls = <String>[];
        final tokens = TokenStore();
        final client = ApiClient(
          config: const ApiConfig(baseUrl: 'https://api.test/v1'),
          tokenStore: tokens,
          httpClient: MockClient((r) async {
            calls.add(r.url.path);
            return http.Response('{}', 200);
          }),
        );
        await DevicePop.ensureEnrolled(client, 'dev-win-1');
        expect(calls, isEmpty);
      },
    );

    test('enrolment sends the Windows key once', () async {
      SharedPreferences.setMockInitialValues({});
      mock(
        (c) async => c.method == 'getPublicKeySpkiBase64'
            ? 'MFkwEwYHKoZIzj0CAQYIKoZI'
            : null,
      );
      final calls = <String>[];
      final tokens = TokenStore();
      await tokens.save(
        accessToken: 'a' * 40,
        refreshToken: 'r' * 40,
        expiresInSec: 900,
      );
      final client = ApiClient(
        config: const ApiConfig(baseUrl: 'https://api.test/v1'),
        tokenStore: tokens,
        httpClient: MockClient((r) async {
          calls.add(r.url.path);
          return http.Response(
            jsonEncode({'success': true, 'message': 'OK', 'data': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await DevicePop.ensureEnrolled(client, 'dev-win-2');
      await DevicePop.ensureEnrolled(client, 'dev-win-2');
      expect(calls, ['/v1/devices/dev-win-2/pop/key']);
    });
  });
}
