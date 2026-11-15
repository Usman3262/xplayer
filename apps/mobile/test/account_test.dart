import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_mobile/core/account.dart';
import 'package:player_mobile/core/panels.dart';
import 'package:player_mobile/core/remote_config.dart';
import 'package:player_mobile/features/connect/account_offer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth implements AccountAuth {
  AccountUser? user;
  final _ctl = StreamController<AccountUser?>.broadcast();
  bool confirmRequired = true;
  final calls = <String>[];
  AccountError? failWith;

  @override
  AccountUser? get current => user;
  @override
  Stream<AccountUser?> get changes => _ctl.stream;

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn $email');
    if (failWith != null) throw AccountException(failWith!);
    user = AccountUser(id: '1', email: email);
  }

  @override
  Future<bool> signUp(String email, String password, {String? displayName}) async {
    calls.add('signUp $email ${displayName ?? ''}');
    if (failWith != null) throw AccountException(failWith!);
    if (!confirmRequired) user = AccountUser(id: '2', email: email, displayName: displayName);
    return confirmRequired;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    user = null;
  }

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset $email');
}

RemoteConfig cfg(Map<String, dynamic> settings) => RemoteConfig.tryParse({'version': 2, 'settings': settings})!;

void main() {
  late FakeAuth auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuth();
    AccountService.useAuth(auth);
  });

  test('Supabase error codes → our messages', () {
    expect(mapAuthError('invalid_credentials', '400', ''), AccountError.invalid);
    expect(mapAuthError('email_not_confirmed', '400', ''), AccountError.notConfirmed);
    expect(mapAuthError('user_already_exists', '422', ''), AccountError.exists);
    expect(mapAuthError('weak_password', '422', ''), AccountError.weakPassword);
    expect(mapAuthError('over_email_send_rate_limit', '429', ''), AccountError.rateLimit);
    expect(mapAuthError('signup_disabled', '422', ''), AccountError.signupOff);
    expect(mapAuthError(null, '429', 'x'), AccountError.rateLimit);
    expect(mapAuthError(null, '400', 'Invalid login credentials'), AccountError.invalid);
    expect(mapAuthError(null, null, 'SocketException: failed host lookup'), AccountError.network);
    expect(mapAuthError('something_new', '500', 'x'), AccountError.generic);
    final copy = AppCopy.ofLanguage('ar');
    for (final e in AccountError.values) {
      expect(e.text(copy), isNotEmpty);
    }
  });

  test('admin policy: optional / required / disabled; guests off = required', () {
    expect(AccountPolicy.of(RemoteConfig.empty).mode, AuthMode.optional);
    expect(AccountPolicy.of(cfg({'auth.mode': 'required'})).required, isTrue);
    expect(AccountPolicy.of(cfg({'auth.mode': 'disabled'})).accountsOn, isFalse);
    expect(AccountPolicy.of(cfg({'auth.guest_enabled': false})).required, isTrue);
    expect(AccountPolicy.of(cfg({'auth.allow_registration': false})).allowRegistration, isFalse);
    expect(AccountPolicy.of(cfg({'auth.mode': 'bogus'})).mode, AuthMode.optional);
  });

  test('sign-up checks email and password locally (no call)', () async {
    await expectLater(AccountService.signUp('not-an-email', 'longenough'),
        throwsA(isA<AccountException>().having((e) => e.error, 'error', AccountError.badEmail)));
    await expectLater(AccountService.signUp('a@b.co', 'short'),
        throwsA(isA<AccountException>().having((e) => e.error, 'error', AccountError.weakPassword)));
    expect(auth.calls, isEmpty);
  });

  test('sign-up: email confirmation → not signed in yet; without → signed in', () async {
    expect(await AccountService.signUp(' a@b.co ', 'password1', displayName: 'Ali'), isTrue);
    expect(auth.calls.single, 'signUp a@b.co Ali');
    expect(AccountService.signedIn, isFalse);
    auth.confirmRequired = false;
    expect(await AccountService.signUp('c@d.co', 'password1'), isFalse);
    expect(AccountService.user.value!.email, 'c@d.co');
  });

  test('sign-in / sign-out update the account; errors pass through', () async {
    await AccountService.signIn('me@x.io', 'pw');
    expect(AccountService.signedIn, isTrue);
    await AccountService.signOut();
    expect(AccountService.signedIn, isFalse);
    auth.failWith = AccountError.invalid;
    await expectLater(AccountService.signIn('me@x.io', 'bad'),
        throwsA(isA<AccountException>().having((e) => e.error, 'error', AccountError.invalid)));
  });

  test('no backend configured → clear network error, no crash', () async {
    AccountService.useAuth(null);
    // Backend is not initialised in tests → no Supabase client.
    await expectLater(AccountService.signIn('a@b.co', 'x'), throwsA(isA<AccountException>()));
  });

  test('offer shown once, never when signed in / required / disabled', () async {
    const optional = AccountPolicy(mode: AuthMode.optional, allowRegistration: true);
    expect(await AccountService.shouldOffer(optional), isTrue);
    await AccountService.markOffered();
    expect(await AccountService.shouldOffer(optional), isFalse);

    SharedPreferences.setMockInitialValues({});
    expect(await AccountService.shouldOffer(const AccountPolicy(mode: AuthMode.required, allowRegistration: true)), isFalse);
    expect(await AccountService.shouldOffer(const AccountPolicy(mode: AuthMode.disabled, allowRegistration: true)), isFalse);
    await AccountService.signIn('me@x.io', 'pw');
    expect(await AccountService.shouldOffer(optional), isFalse);
  });

  Widget offerApp(RemoteConfig c) {
    final router = GoRouter(initialLocation: '/account-offer', routes: [
      GoRoute(path: '/account-offer', builder: (_, _) => const AccountOfferScreen()),
      GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
      GoRoute(path: '/auth/register', builder: (_, _) => const Text('REGISTER')),
      GoRoute(path: '/auth/login', builder: (_, _) => const Text('LOGIN')),
    ]);
    return ProviderScope(
      overrides: [
        panelUiLanguageProvider.overrideWithValue('en'),
        remoteConfigProvider.overrideWithValue(c),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('offer screen: create / sign in / not now; marks itself shown', (t) async {
    await t.pumpWidget(offerApp(RemoteConfig.empty));
    await t.pumpAndSettle();
    final copy = AppCopy.ofLanguage('en');
    expect(find.text(copy.accountOfferTitle), findsOneWidget);
    expect(find.byKey(const Key('offer-create')), findsOneWidget);
    await t.tap(find.byKey(const Key('offer-skip')));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('xp.account_offer_shown'), isTrue);
  });

  testWidgets('offer screen hides "Create account" when the admin closed sign-ups', (t) async {
    await t.pumpWidget(offerApp(cfg({'auth.allow_registration': false})));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('offer-create')), findsNothing);
    await t.tap(find.byKey(const Key('offer-signin')));
    await t.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
