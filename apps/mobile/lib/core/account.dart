import 'dart:async';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'remote_config.dart';

/// The signed-in app account (email + display name only; never the panel).
@immutable
class AccountUser {
  const AccountUser({required this.id, required this.email, this.displayName});
  final String id;
  final String email;
  final String? displayName;
}

/// Why sign-in / sign-up failed → one message each (AccountErrors.text).
enum AccountError { invalid, notConfirmed, exists, weakPassword, badEmail, rateLimit, signupOff, network, notConfigured, generic }

class AccountException implements Exception {
  const AccountException(this.error);
  final AccountError error;
  @override
  String toString() => 'AccountException(${error.name})';
}

/// What the app needs from an auth provider. Supabase in the app, a fake in tests.
abstract class AccountAuth {
  AccountUser? get current;
  Stream<AccountUser?> get changes;
  Future<void> signIn(String email, String password);

  /// True when the account still needs its email confirmed.
  Future<bool> signUp(String email, String password, {String? displayName});
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
}

class SupabaseAccountAuth implements AccountAuth {
  SupabaseAccountAuth(this._client);
  final SupabaseClient _client;

  static AccountUser? _map(User? u) =>
      u == null ? null : AccountUser(id: u.id, email: u.email ?? '', displayName: u.userMetadata?['display_name'] as String?);

  @override
  AccountUser? get current => _map(_client.auth.currentUser);

  @override
  Stream<AccountUser?> get changes => _client.auth.onAuthStateChange.map((s) => _map(s.session?.user));

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: email, password: password));

  @override
  Future<bool> signUp(String email, String password, {String? displayName}) async {
    final res = await _guard(() => _client.auth.signUp(
          email: email,
          password: password,
          data: {if ((displayName ?? '').trim().isNotEmpty) 'display_name': displayName!.trim()},
        ));
    // Supabase answers "success" without identities for an existing email
    // (no enumeration); treat it as "exists".
    if (res.user != null && (res.user!.identities ?? const []).isEmpty) {
      throw const AccountException(AccountError.exists);
    }
    return res.session == null;
  }

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _client.auth.resetPasswordForEmail(email));

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      final mapped = mapAuthError(e.code, e.statusCode, e.message);
      debugPrint('[ACCOUNT] Supabase auth error: ${e.runtimeType} code=${e.code} status=${e.statusCode} '
          'message="${e.message}" → ${mapped.name}');
      throw AccountException(mapped);
    } on AccountException {
      rethrow;
    } catch (e) {
      debugPrint('[ACCOUNT] request failed (treated as no internet): ${e.runtimeType}: $e');
      throw const AccountException(AccountError.network);
    }
  }
}

/// Supabase error code / status → our error (codes: supabase.com/docs/guides/auth/debugging/error-codes).
@visibleForTesting
AccountError mapAuthError(String? code, String? status, String message) {
  switch (code) {
    case 'invalid_credentials':
      return AccountError.invalid;
    case 'email_not_confirmed':
      return AccountError.notConfirmed;
    case 'user_already_exists':
    case 'email_exists':
      return AccountError.exists;
    case 'weak_password':
      return AccountError.weakPassword;
    case 'email_address_invalid':
    case 'validation_failed':
      return AccountError.badEmail;
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return AccountError.rateLimit;
    case 'signup_disabled':
    case 'email_provider_disabled':
      return AccountError.signupOff;
  }
  if (status == '429') return AccountError.rateLimit;
  final m = message.toLowerCase();
  if (m.contains('invalid login')) return AccountError.invalid;
  if (m.contains('not confirmed')) return AccountError.notConfirmed;
  if (m.contains('already registered')) return AccountError.exists;
  if (m.contains('socket') || m.contains('network') || m.contains('failed host')) return AccountError.network;
  return AccountError.generic;
}

extension AccountErrorText on AccountError {
  String text(AppCopy c) => switch (this) {
        AccountError.invalid => c.authErrInvalid,
        AccountError.notConfirmed => c.authErrNotConfirmed,
        AccountError.exists => c.authErrExists,
        AccountError.weakPassword => c.authErrWeakPassword,
        AccountError.badEmail => c.authErrBadEmail,
        AccountError.rateLimit => c.authErrRateLimit,
        AccountError.signupOff => c.authErrSignupOff,
        AccountError.network => c.authErrNetwork,
        AccountError.notConfigured => c.authErrNotConfigured,
        AccountError.generic => c.authErrGeneric,
      };
}

/// Sign-in policy from the admin panel (App customization → Access).
@immutable
class AccountPolicy {
  const AccountPolicy({required this.mode, required this.allowRegistration});

  factory AccountPolicy.of(RemoteConfig c) {
    var mode = c.authMode;
    // "Guests not allowed" means an account is required.
    if (mode == AuthMode.optional && !c.boolSetting('auth.guest_enabled', true)) mode = AuthMode.required;
    return AccountPolicy(mode: mode, allowRegistration: c.boolSetting('auth.allow_registration', true));
  }

  final AuthMode mode;
  final bool allowRegistration;

  bool get accountsOn => mode != AuthMode.disabled;
  bool get required => mode == AuthMode.required;
}

/// App account state. Nothing here touches the user's panels.
class AccountService {
  AccountService._();

  static AccountAuth? _auth;
  static final ValueNotifier<AccountUser?> user = ValueNotifier(null);
  static StreamSubscription<AccountUser?>? _sub;

  static AccountAuth? get auth => _auth ??= Backend.client == null ? null : SupabaseAccountAuth(Backend.client!);

  @visibleForTesting
  static void useAuth(AccountAuth? a) {
    _sub?.cancel();
    _auth = a;
    user.value = a?.current;
    _sub = a?.changes.listen((u) => user.value = u);
  }

  /// After Backend.init: current session (restored by Supabase) + changes.
  static void init() {
    final a = auth;
    if (a == null) return;
    user.value = a.current;
    _sub ??= a.changes.listen((u) => user.value = u);
  }

  static bool get signedIn => user.value != null;

  static AccountAuth _require() {
    final a = auth;
    if (a == null) {
      debugPrint('[ACCOUNT] no backend in this build (Supabase not configured / init failed)');
      throw const AccountException(AccountError.notConfigured);
    }
    return a;
  }

  static Future<void> signIn(String email, String password) async {
    final a = _require();
    await a.signIn(email.trim(), password);
    user.value = a.current;
  }

  /// Returns true when the user must confirm the email before signing in.
  static Future<bool> signUp(String email, String password, {String? displayName}) async {
    final a = _require();
    if (!_emailOk(email)) throw const AccountException(AccountError.badEmail);
    if (password.length < 8) throw const AccountException(AccountError.weakPassword);
    final needsConfirm = await a.signUp(email.trim(), password, displayName: displayName);
    user.value = a.current;
    return needsConfirm;
  }

  /// Always signs out on this device, even offline (the server-side revoke
  /// may fail; the local session is dropped either way).
  static Future<void> signOut() async {
    try {
      await auth?.signOut();
    } finally {
      user.value = null;
    }
  }

  static Future<void> sendPasswordReset(String email) async {
    final a = _require();
    if (!_emailOk(email)) throw const AccountException(AccountError.badEmail);
    await a.sendPasswordReset(email.trim());
  }

  static bool _emailOk(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(e.trim());

  /// The "save your stuff" offer is shown once, after the first panel.
  static const _offerKey = 'xp.account_offer_shown';
  static Future<bool> shouldOffer(AccountPolicy p) async {
    if (!p.accountsOn || p.required || signedIn) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_offerKey) ?? false);
  }

  /// After a full device sign-out the offer may show again.
  static Future<void> resetOffer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offerKey);
  }

  static Future<void> markOffered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offerKey, true);
  }
}

final accountUserProvider = Provider<AccountUser?>((ref) {
  void l() => ref.invalidateSelf();
  AccountService.user.addListener(l);
  ref.onDispose(() => AccountService.user.removeListener(l));
  return AccountService.user.value;
});

final accountPolicyProvider = Provider<AccountPolicy>((ref) => AccountPolicy.of(ref.watch(remoteConfigProvider)));
