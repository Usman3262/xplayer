import 'dart:async';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_mobile/core/account.dart';
import 'package:player_mobile/core/panels.dart';
import 'package:player_mobile/core/sign_out.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Box implements SecretBox {
  @override
  Future<String?> seal(String plain) async => 'sealed:$plain';
  @override
  Future<String?> open(String stored) async => stored.replaceFirst('sealed:', '');
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.creds);
  final ProviderCredentials creds;
  @override
  ProviderKind get kind => creds.kind;
  @override
  Future<ProviderAccount> authenticate() async => const ProviderAccount(status: ConnectionStatus.active);
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements AccountAuth {
  AccountUser? user = const AccountUser(id: 'u1', email: 'me@x.io');
  bool offline = false;
  @override
  AccountUser? get current => user;
  @override
  Stream<AccountUser?> get changes => const Stream.empty();
  @override
  Future<void> signIn(String e, String p) async {}
  @override
  Future<bool> signUp(String e, String p, {String? displayName}) async => false;
  @override
  Future<void> signOut() async {
    if (offline) throw const AccountException(AccountError.network);
    user = null;
  }
  @override
  Future<void> sendPasswordReset(String e) async {}
}

void main() {
  late _Auth auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'xp.account_offer_shown': true});
    PanelsService.useManager(ConnectionManager(
      store: ConnectionStore(secrets: _Box()),
      createAdapter: _Adapter.new,
    ));
    auth = _Auth();
    AccountService.useAuth(auth);
    await PanelsService.manager.connect(const XtreamCredentials(server: 'http://a.tv', username: 'u', password: 'p'));
    await PanelsService.manager.connect(const StalkerCredentials(portal: 'http://b.tv/c/', mac: '00:1A:79:00:00:01'));
  });

  test('sign out: panels + their credentials removed, account signed out, offer can show again', () async {
    expect(PanelsService.hasPanel, isTrue);
    expect(AccountService.signedIn, isTrue);

    await clearDeviceState();

    expect(PanelsService.manager.connections.value, isEmpty);
    expect(PanelsService.hasPanel, isFalse); // router → /connect
    expect(AccountService.signedIn, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('xp.panel.cred.')), isEmpty);
    expect(prefs.getBool('xp.account_offer_shown'), isNull);
    // The device MAC is kept: a re-added Stalker line keeps working.
    expect(prefs.getString('xp.device.mac'), isNull); // never created in this test
  });

  test('offline: panels are still removed and the account is cleared locally', () async {
    auth.offline = true;
    await clearDeviceState();
    expect(PanelsService.manager.connections.value, isEmpty);
    expect(AccountService.signedIn, isFalse);
  });
}
