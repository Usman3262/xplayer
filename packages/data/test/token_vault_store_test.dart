import 'dart:convert';

import 'package:data/src/remote/token_store.dart';
import 'package:data/src/security/token_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake platform vault: "sealing" = reverse bytes + marker, so the test can
/// see that SharedPreferences never holds the plain token.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/token_vault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void fakeVault({bool broken = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (broken) throw PlatformException(code: 'vault_error', message: 'code 7');
      final data = (call.arguments as Map)['data'] as Uint8List;
      if (call.method == 'seal') {
        return Uint8List.fromList([0xAA, ...data.reversed]);
      }
      if (data.first != 0xAA) throw PlatformException(code: 'vault_error');
      return Uint8List.fromList(data.sublist(1).reversed.toList());
    });
  }

  setUp(() {
    TokenVault.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('tokens are stored sealed and read back', () async {
    fakeVault();
    final store = TokenStore();
    await store.save(accessToken: 'acc-123', refreshToken: 'ref-456', expiresInSec: 600);
    final prefs = await SharedPreferences.getInstance();
    final rawAccess = prefs.getString('app_access_token')!;
    expect(rawAccess.startsWith('v1:'), isTrue);
    expect(rawAccess.contains('acc-123'), isFalse);
    expect(utf8.decode(base64.decode(rawAccess.substring(3)), allowMalformed: true)
        .contains('acc-123'), isFalse);
    TokenVault.resetForTest(); // drop cache: force a real open
    final t = await store.read();
    expect(t!.accessToken, 'acc-123');
    expect(t.refreshToken, 'ref-456');
  });

  test('broken Keystore keeps plain storage so sign-in still works', () async {
    fakeVault(broken: true);
    final store = TokenStore();
    await store.save(accessToken: 'acc-1', refreshToken: 'ref-1', expiresInSec: 600);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_access_token'), 'acc-1');
    expect((await store.read())!.accessToken, 'acc-1');
  });

  test('plain tokens from an older build are sealed on first read', () async {
    fakeVault();
    SharedPreferences.setMockInitialValues({
      'app_access_token': 'old-acc',
      'app_refresh_token': 'old-ref',
      'app_expires_at':
          '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}',
    });
    final store = TokenStore();
    expect((await store.read())!.accessToken, 'old-acc');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_access_token')!.startsWith('v1:'), isTrue);
    expect(prefs.getString('app_refresh_token')!.startsWith('v1:'), isTrue);
    expect((await store.read())!.refreshToken, 'old-ref');
  });
}
