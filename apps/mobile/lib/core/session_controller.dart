import 'dart:async';
import 'package:domain/domain.dart' show AppBrand;
import 'dart:convert';

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/session_models.dart';

class SessionState {
  const SessionState({
    this.bootstrapped = false,
    this.onboardingDone = false,
    this.isLoggedIn = false,
    this.profileSelected = false,
    this.user,
    this.profiles = const [],
    this.activeProfileId,
    this.devices = const [],
    this.sessions = const [],
    // Client 20 Oct Home order: banner (separate) → Matches → CW →
    // Top Movies/Series (weekly picks) → Kids → then other rails.
    this.homeSections = const [
      "Today's Matches",
      'Continue Watching',
      'Top 10 in Your Region',
      'Kids',
      'Movies & 4K Blockbusters',
      'Series & Exclusive Seasons',
      'Live TV & Channels',
      'Arabic Originals',
    ],
    this.parentalPinEnabled = false,
    this.autoplay = true,
    this.language = AppLocale.english,
    this.notificationsEnabled = true,
    this.playbackQuality = 'Auto',
    this.audioPref = 'Dolby Atmos',
    this.offline = false,
  });

  final bool bootstrapped;
  final bool onboardingDone;
  final bool isLoggedIn;
  final bool profileSelected;
  final AuthUser? user;
  final List<ViewingProfile> profiles;
  final String? activeProfileId;
  final List<RegisteredDevice> devices;
  final List<AuthSessionRecord> sessions;
  final List<String> homeSections;
  final bool parentalPinEnabled;
  final bool autoplay;
  final String language;
  final bool notificationsEnabled;
  final String playbackQuality;
  final String audioPref;

  /// Signed in from the saved session because the server could not be
  /// reached (client 18 Oct #4): downloads stay playable without internet.
  final bool offline;

  ViewingProfile? get activeProfile {
    if (activeProfileId == null) return null;
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return null;
  }

  SessionState copyWith({
    bool? bootstrapped,
    bool? onboardingDone,
    bool? isLoggedIn,
    bool? profileSelected,
    AuthUser? user,
    List<ViewingProfile>? profiles,
    String? activeProfileId,
    List<RegisteredDevice>? devices,
    List<AuthSessionRecord>? sessions,
    List<String>? homeSections,
    bool? parentalPinEnabled,
    bool? autoplay,
    String? language,
    bool? notificationsEnabled,
    String? playbackQuality,
    String? audioPref,
    bool? offline,
    bool clearUser = false,
    bool clearActiveProfile = false,
  }) {
    return SessionState(
      bootstrapped: bootstrapped ?? this.bootstrapped,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      profileSelected: profileSelected ?? this.profileSelected,
      user: clearUser ? null : (user ?? this.user),
      profiles: profiles ?? this.profiles,
      activeProfileId: clearActiveProfile
          ? null
          : (activeProfileId ?? this.activeProfileId),
      devices: devices ?? this.devices,
      sessions: sessions ?? this.sessions,
      homeSections: homeSections ?? this.homeSections,
      parentalPinEnabled: parentalPinEnabled ?? this.parentalPinEnabled,
      autoplay: autoplay ?? this.autoplay,
      language: language ?? this.language,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      playbackQuality: playbackQuality ?? this.playbackQuality,
      audioPref: audioPref ?? this.audioPref,
      offline: offline ?? this.offline,
    );
  }
}

/// Remote auth + devices + soft profiles (Usman API).
const _kOfflineIdentity = 'app.offline_identity';

/// Thrown by [SessionController.selectProfile] when the Kids PIN is needed.
class ParentalPinRequired implements Exception {
  const ParentalPinRequired();
  @override
  String toString() => 'Kids PIN required';
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._auth, this._media) : super(const SessionState()) {
    _bootstrap();
  }

  final AppAuthRepository _auth;
  final AppMediaRepository _media;

  AppMediaRepository get media => _media;
  AppAuthRepository get auth => _auth;

  static const _kOnboarding = 'app_onboarding_done';
  static const _kProfile = 'app_profile_selected';
  static const _kActiveProfile = 'app_active_profile_id';
  /// Last known Kids PIN state from the server, so leaving a Kids profile
  /// still needs the PIN when the app starts offline.
  static const _kParentalPin = 'app_parental_pin_on';
  /// Task #143 #16: when false, do not restore tokens after process death.
  static const _kRememberMe = 'app.remember_me';

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    // Bump clears a stale "onboarding done" restored by Android Auto Backup
    // after reinstall, which skipped onboarding and jumped to sign-in.
    const prefsGeneration = 2;
    const prefsGenKey = 'app_prefs_generation';
    final gen = prefs.getInt(prefsGenKey) ?? 0;
    if (gen < prefsGeneration) {
      await prefs.setInt(prefsGenKey, prefsGeneration);
      await prefs.remove(_kOnboarding);
    }

    final onboardingDone = prefs.getBool(_kOnboarding) ?? false;
    final profileSelected = prefs.getBool(_kProfile) ?? false;
    final activeProfileId = prefs.getString(_kActiveProfile);
    final language = AppLocale.fromPrefsCode(prefs.getString(AppLocale.prefsKey));
    final rememberMe = prefs.getBool(_kRememberMe) ?? true;

    AccountDto? account;
    try {
      if (!rememberMe) {
        try {
          await _auth.tokenStore.clear();
        } catch (_) {}
        account = null;
      } else {
        // Task #143 #16: one restore pass. restoreSession already retries
        // refresh once when appropriate; a second boot pass only helps
        // transient network and must not re-hit a dead 5xx refresh.
        account = await _auth.restoreSession();
        if (account == null) {
          final tokens = await _auth.tokenStore.read();
          if (tokens != null && !tokens.isAccessExpired) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            account = await _auth.restoreSession();
          }
        }
      }
    } catch (_) {
      account = null;
    }

    if (account != null) {
      await _applyAuthenticated(account, profileSelected, activeProfileId);
      state = state.copyWith(
        bootstrapped: true,
        onboardingDone: onboardingDone,
        language: language,
        offline: false,
      );
      unawaited(_saveOfflineIdentity());
      return;
    }

    // No server, but the session was not rejected (tokens kept): sign in
    // offline with the saved identity so downloads can be watched.
    if (rememberMe && await _auth.tokenStore.read() != null) {
      final offlineState = await _readOfflineIdentity();
      if (offlineState != null) {
        state = offlineState.copyWith(
          bootstrapped: true,
          onboardingDone: onboardingDone,
          language: language,
        );
        _scheduleOnlineRetry();
        return;
      }
    }

    state = state.copyWith(
      bootstrapped: true,
      onboardingDone: onboardingDone,
      isLoggedIn: false,
      profileSelected: false,
      profiles: const [],
      devices: const [],
      sessions: const [],
      language: language,
      clearUser: true,
    );
  }

  Future<void> _applyAuthenticated(
    AccountDto account,
    bool profileSelected,
    String? activeProfileId,
  ) async {
    // Keep login/bootstrap fast: profiles only. Devices/sessions load on Settings.
    // Device register is required for playback lease — run in parallel with profiles.
    List<ViewingProfile> profiles = const [];
    await Future.wait<void>([
      () async {
        try {
          await _auth.ensureThisDeviceRegistered();
        } catch (_) {}
      }(),
      () async {
        try {
          profiles = await _mapProfiles();
        } catch (_) {
          profiles = const [];
        }
      }(),
    ]);

    String? active = activeProfileId;
    if (profileSelected &&
        active != null &&
        profiles.every((p) => p.id != active)) {
      active = profiles.isEmpty ? null : profiles.first.id;
    }

    state = state.copyWith(
      isLoggedIn: true,
      profileSelected: profileSelected && active != null,
      user: _userFromAccount(account),
      profiles: [
        for (final p in profiles)
          p.copyWith(isActive: active != null && p.id == active),
      ],
      activeProfileId: profileSelected ? active : null,
    );

    // Background: devices/sessions for Settings, and /me so feature flags
    // (deviceLoginApproval / priorityDevice) hydrate when login omitted them.
    // ignore: unawaited_futures
    refreshDevicesAndSessions().catchError((_) {});
    // ignore: unawaited_futures
    _hydrateAccountFeatures().catchError((_) {});
    // ignore: unawaited_futures
    refreshParentalPin();
  }

  /// Login payload often omits `account.features`; Allow/Deny needs the flags.
  Future<void> _hydrateAccountFeatures() async {
    try {
      final me = await _auth.me();
      if (!state.isLoggedIn) return;
      state = state.copyWith(user: _userFromAccount(me));
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
    }
  }

  Future<void> _finishLogin(AuthSessionDto session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProfile, false);
    await prefs.remove(_kActiveProfile);
    await _applyAuthenticated(session.account, false, null);
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarding, true);
    state = state.copyWith(onboardingDone: true);
  }

  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final loginId = email.trim();
    if (loginId.isEmpty || password.isEmpty) {
      throw Exception('Please enter username and password.');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist preference before network login so kill mid-login still honors it.
      await prefs.setBool(_kRememberMe, rememberMe);
      final session = await _auth.login(login: loginId, password: password);
      await _finishLogin(session);
      await prefs.setBool(_kRememberMe, rememberMe);
    } on MfaRequiredException {
      rethrow;
    } on LoginApprovalRequiredException {
      rethrow;
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> completeLoginApproval(
    String challengeId, {
    void Function(LoginChallengeDto status)? onStatus,
  }) async {
    try {
      final session = await _auth.waitForLoginApproval(
        challengeId: challengeId,
        onStatus: onStatus,
      );
      await _finishLogin(session);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Wiped / lost priority phone: re-enter password on the wait screen.
  Future<void> claimLoginApproval({
    required String challengeId,
    required String password,
  }) async {
    try {
      final session = await _auth.claimLoginApproval(
        challengeId: challengeId,
        password: password,
      );
      await _finishLogin(session);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<PrimaryRecoveryStartDto> startPrimaryRecovery({
    String? challengeId,
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      return await _auth.startPrimaryRecovery(
        challengeId: challengeId,
        usernameOrEmail: usernameOrEmail,
        password: password,
      );
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> sendPrimaryRecoveryEmailOtp({required String recoveryId}) async {
    try {
      await _auth.sendPrimaryRecoveryEmailOtp(recoveryId: recoveryId);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> completePrimaryRecovery({
    required String recoveryId,
    required String method,
    required String code,
  }) async {
    try {
      final session = await _auth.completePrimaryRecovery(
        recoveryId: recoveryId,
        method: method,
        code: code,
      );
      await _finishLogin(session);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> sendDeviceHeartbeat({String? appVersion}) async {
    final user = state.user;
    if (user == null || !user.deviceHeartbeat) return;
    if (!state.isLoggedIn) return;
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'IOS'
          : 'ANDROID';
      final os = await DeviceCapabilitiesStore.instance.osVersionLabel();
      await _auth.deviceHeartbeat(platform: platform, appVersion: appVersion, osVersion: os);
    } catch (_) {}
  }

  Future<void> verifyMfa({
    required String mfaChallengeId,
    required String code,
  }) async {
    try {
      final session = await _auth.verifyMfa(
        mfaChallengeId: mfaChallengeId,
        code: code,
      );
      await _finishLogin(session);
    } on LoginApprovalRequiredException {
      rethrow;
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> setPriorityDevice(String deviceId) async {
    try {
      await _auth.setPriorityDevice(deviceId);
      state = state.copyWith(devices: await _mapDevices());
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      rethrow;
    }
  }

  Future<void> revokeAllDevices({bool keepCurrentDevice = true}) async {
    final devices = state.devices;
    final hasPriority = devices.any((d) => d.isPriority);
    final iAmPriority = devices.any((d) => d.isThisDevice && d.isPriority);
    if (!DeviceTrustPolicy.canRevokeAll(
      actorIsPriority: iAmPriority,
      accountHasPriority: hasPriority,
    )) {
      throw ApiException(
        'Primary phone required to revoke all devices',
        statusCode: 403,
        code: 'PRIORITY_REQUIRED',
      );
    }
    try {
      await _auth.revokeAllDevices(keepCurrentDevice: keepCurrentDevice);
      if (!keepCurrentDevice) {
        await signOut();
        return;
      }
      state = state.copyWith(devices: await _mapDevices());
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      rethrow;
    }
  }

  /// True after the server answered 403 (this phone is not the primary
  /// device, so it cannot approve logins). The poller slows down then.
  bool pendingChallengesForbidden = false;

  Future<List<LoginChallengeDto>> pendingLoginChallenges() async {
    try {
      final list = await _auth.listPendingLoginChallenges();
      pendingChallengesForbidden = false;
      return list;
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        pendingChallengesForbidden = true;
        return const [];
      }
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> allowLoginChallenge(String challengeId) async {
    try {
      await _auth.allowLoginChallenge(challengeId);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      rethrow;
    }
  }

  Future<void> denyLoginChallenge(String challengeId) async {
    try {
      await _auth.denyLoginChallenge(challengeId);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      rethrow;
    }
  }

  Future<void> approveTvDeviceCode(String code) async {
    try {
      await _auth.approveDeviceCode(code);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> denyTvDeviceCode(String code) async {
    try {
      await _auth.denyDeviceCode(code);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> recoveryLogin({
    required String login,
    required String password,
    required String recoveryCode,
  }) async {
    try {
      final session = await _auth.recoveryLogin(
        login: login.trim(),
        password: password,
        recoveryCode: recoveryCode,
      );
      await _finishLogin(session);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    throw Exception(
      'Self-register is disabled. Accounts are created from the Control Panel.',
    );
  }

  Future<String> forgotPassword(String login) async {
    try {
      return await _auth.forgotPassword(login: login);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _auth.resetPassword(token: token, newPassword: newPassword);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<AuthSessionDto> verifyEmail({
    required String login,
    required String code,
  }) async {
    try {
      final session = await _auth.verifyEmail(login: login, code: code);
      await _finishLogin(session);
      return session;
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<String> resendEmailVerification(String login) async {
    try {
      return await _auth.resendEmailVerification(login: login);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<MfaEnrollDto> enrollMfa() async {
    try {
      return await _auth.enrollMfa();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<List<String>> confirmMfa(String code) async {
    try {
      final result = await _auth.confirmMfa(code: code);
      await _refreshAccountOrOptimistic(mfaEnabled: true);
      return result.recoveryCodes;
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> disableMfa(String password) async {
    try {
      await _auth.disableMfa(password: password);
      // Backend may invalidate tokens after MFA change; keep UI consistent.
      await _refreshAccountOrOptimistic(mfaEnabled: false);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> _refreshAccountOrOptimistic({required bool mfaEnabled}) async {
    final user = state.user;
    if (user != null) {
      state = state.copyWith(user: user.copyWith(mfaEnabled: mfaEnabled));
    }
    try {
      final me = await _auth.me();
      state = state.copyWith(user: _userFromAccount(me));
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      if (!state.isLoggedIn) {
        throw Exception(
          mfaEnabled
              ? 'MFA enabled. Please sign in again.'
              : 'MFA disabled. Please sign in again.',
        );
      }
      rethrow;
    }
  }

  Future<void> refreshDevicesAndSessions() async {
    try {
      final devices = await _mapDevices();
      final sessions = await _mapSessions();
      state = state.copyWith(devices: devices, sessions: sessions);
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> renameDevice(String id, String name) async {
    try {
      await _auth.renameDevice(deviceId: id, name: name);
      state = state.copyWith(devices: await _mapDevices());
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> revokeSession(String id) async {
    try {
      await _auth.revokeSession(id);
      state = state.copyWith(sessions: await _mapSessions());
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> _handleAuthLoss(ApiException e) async {
    final m = e.message.toLowerCase();
    // Business 401s (wrong MFA/password) must not wipe the session.
    if (m.contains('invalid mfa') ||
        m.contains('mfa code') ||
        m.contains('invalid code') ||
        m.contains('wrong code') ||
        m.contains('password') ||
        m.contains('not allowed') ||
        m.contains('validation')) {
      return;
    }
    final lost = e.statusCode == 401 ||
        m.contains('no access token') ||
        m.contains('session expired') ||
        m.contains('refresh token reuse') ||
        m.contains('reuse detected') ||
        m.contains('invalid access token') ||
        m.contains('authentication required') ||
        m.contains('no refresh token');
    if (lost) {
      await _auth.tokenStore.clear();
      await _clearLocalAuthFlags();
    }
  }

  Future<void> selectProfile(String profileId, {String? pin}) async {
    if (needsParentalPin(profileId)) {
      if (pin == null || pin.trim().isEmpty) {
        throw const ParentalPinRequired();
      }
      // Throws ApiException (PIN_INVALID / PIN_LOCKED / NETWORK): stay on Kids.
      await _auth.verifyParentalPin(pin.trim());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProfile, true);
    await prefs.setString(_kActiveProfile, profileId);
    state = state.copyWith(
      profileSelected: true,
      activeProfileId: profileId,
      profiles: [
        for (final p in state.profiles) p.copyWith(isActive: p.id == profileId),
      ],
    );
    unawaited(_saveOfflineIdentity());
  }

  Future<void> refreshProfiles() async {
    if (!state.isLoggedIn) return;
    try {
      final profiles = await _mapProfiles();
      final active = state.activeProfileId;
      state = state.copyWith(
        profiles: [
          for (final p in profiles)
            p.copyWith(isActive: active != null && p.id == active),
        ],
      );
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> addProfile(String name, {bool kids = false}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Enter a profile name.');
    if (state.profiles.length >= 5) {
      throw Exception('Maximum of 5 profiles reached.');
    }
    try {
      await _media.createProfile(name: trimmed, isKids: kids);
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  /// Saves the profile's built-in avatar on the server (client 20 Oct).
  Future<void> setProfileAvatar(String id, String token) async {
    try {
      await _media.updateProfile(id: id, avatarUrl: token);
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> renameProfile(String id, String name) async {
    try {
      await _media.updateProfile(id: id, name: name.trim());
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  /// Kids mode on / off for one profile (client 23 Oct #3).
  Future<void> setProfileKids(String id, bool kids) async {
    try {
      await _media.updateProfile(id: id, isKids: kids);
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  /// Profile lock: opening this profile needs the account Kids PIN.
  Future<void> setProfileLocked(String id, bool locked) async {
    if (locked && !state.parentalPinEnabled) throw const ParentalPinRequired();
    try {
      await _media.updateProfile(id: id, pinLocked: locked);
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> deleteProfile(String id) async {
    if (state.profiles.length <= 1) {
      throw Exception('Cannot delete the last profile.');
    }
    try {
      await _media.deleteProfile(id);
      if (state.activeProfileId == id) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kProfile, false);
        await prefs.remove(_kActiveProfile);
        state = state.copyWith(
          profileSelected: false,
          clearActiveProfile: true,
        );
      }
      await refreshProfiles();
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> signOut() async {
    // Bound network wait so UI can reach auth without a multi-second stall.
    try {
      await _auth.logout().timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      try {
        await _auth.tokenStore.clear();
      } catch (_) {}
    }
    await _clearLocalAuthFlags();
  }

  Future<void> signOutAll() async {
    try {
      await _auth.logoutAll().timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      try {
        await _auth.tokenStore.clear();
      } catch (_) {}
    }
    await _clearLocalAuthFlags();
  }

  Future<void> _clearLocalAuthFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProfile, false);
    await prefs.remove(_kActiveProfile);
    await prefs.remove(_kOfflineIdentity);
    _onlineRetry?.cancel();
    state = state.copyWith(
      offline: false,
      isLoggedIn: false,
      profileSelected: false,
      clearUser: true,
      clearActiveProfile: true,
      profiles: const [],
      devices: const [],
      sessions: const [],
    );
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarding, false);
    state = state.copyWith(onboardingDone: false);
  }

  void reorderHomeSections(int oldIndex, int newIndex) {
    final list = [...state.homeSections];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(homeSections: list);
  }

  void setAutoplay(bool value) => state = state.copyWith(autoplay: value);

  void setNotifications(bool value) =>
      state = state.copyWith(notificationsEnabled: value);

  /// Kids PIN (one per account, on the server). Cached per account so it
  /// still applies when the app starts offline.
  String? get _parentalPinKey {
    final id = state.user?.id;
    return id == null || id.isEmpty ? null : '$_kParentalPin.$id';
  }

  Future<void> refreshParentalPin() async {
    final key = _parentalPinKey;
    if (key == null) {
      state = state.copyWith(parentalPinEnabled: false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(key) ?? false;
    if (cached != state.parentalPinEnabled) {
      state = state.copyWith(parentalPinEnabled: cached);
    }
    if (!state.isLoggedIn) return;
    try {
      final on = await _auth.parentalPinEnabled();
      await prefs.setBool(key, on);
      state = state.copyWith(parentalPinEnabled: on);
    } on ApiException catch (e) {
      // Offline: keep the cached value (fail closed). A server without the
      // Kids PIN feature (404) or any other answer: no PIN.
      if (e.isNetwork) return;
      await prefs.setBool(key, false);
      state = state.copyWith(parentalPinEnabled: false);
    } catch (_) {
      // Keep the cached value.
    }
  }

  /// Set, change or reset ("forgot PIN") with the account password.
  Future<void> setParentalPin({required String pin, required String password}) async {
    await _auth.setParentalPin(pin: pin, password: password);
    final prefs = await SharedPreferences.getInstance();
    final key = _parentalPinKey;
    if (key != null) await prefs.setBool(key, true);
    state = state.copyWith(parentalPinEnabled: true);
  }

  Future<void> removeParentalPin({required String password}) async {
    await _auth.removeParentalPin(password: password);
    final prefs = await SharedPreferences.getInstance();
    final key = _parentalPinKey;
    if (key != null) await prefs.setBool(key, false);
    state = state.copyWith(parentalPinEnabled: false);
  }

  /// Leaving a Kids profile for a non-Kids profile needs the Kids PIN.
  bool needsParentalPin(String targetProfileId) {
    if (!state.parentalPinEnabled) return false;
    ViewingProfile? current;
    ViewingProfile? target;
    for (final p in state.profiles) {
      if (p.id == state.activeProfileId) current = p;
      if (p.id == targetProfileId) target = p;
    }
    if (target == null || target.id == state.activeProfileId) return false;
    // A locked profile always needs the PIN; leaving Kids for a non-Kids one too.
    if (target.hasPin) return true;
    return current != null && current.isKids && !target.isKids;
  }

  Future<void> setLanguage(String value) async {
    final language = AppLocale.normalize(value);
    debugPrint(
      '[ACTION] language.set value=$language prefs=${AppLocale.toPrefsCode(language)}',
    );
    state = state.copyWith(language: language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppLocale.prefsKey, AppLocale.toPrefsCode(language));
  }

  /// Max quality preference: Auto | Data saver | Original
  void setPlaybackQuality(String value) =>
      state = state.copyWith(playbackQuality: value);


  void setAudioPref(String value) => state = state.copyWith(audioPref: value);

  Future<void> revokeDevice(String id) async {
    final target = state.devices.where((d) => d.id == id).firstOrNull;
    if (target != null &&
        !DeviceTrustPolicy.canRevokeDevice(targetIsPriority: target.isPriority)) {
      throw ApiException(
        'Cannot revoke the primary phone from another device',
        statusCode: 403,
        code: 'PRIORITY_REQUIRED',
      );
    }
    try {
      await _auth.revokeDevice(id, targetIsPriority: target?.isPriority ?? false);
      state = state.copyWith(devices: await _mapDevices());
    } on ApiException catch (e) {
      await _handleAuthLoss(e);
      rethrow;
    }
  }

  Future<List<ViewingProfile>> _mapProfiles() async {
    final list = await _media.listProfiles();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final p in list)
        ViewingProfile(
          id: p.id,
          name: p.name,
          initials: _initialsFor(p.name),
          avatar: p.avatarUrl,
          isKids: p.isKids,
          // Profile lock (server): opening it needs the Kids PIN.
          hasPin: p.pinLocked,
        ),
    ];
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    final a = parts.first.substring(0, 1);
    final b = parts.last.substring(0, 1);
    return '$a$b'.toUpperCase();
  }

  Future<List<RegisteredDevice>> _mapDevices() async {
    final list = await _auth.listDevices();
    final thisId = await _auth.thisDeviceId();
    return [
      for (final d in list)
        if (d.status.toUpperCase() == 'ACTIVE' ||
            d.status.toUpperCase() == 'STALE')
          RegisteredDevice(
            id: d.id,
            name: d.name,
            platform: _prettyPlatform(d.platform),
            lastActive: _prettyTime(d.lastSeenAt) ?? 'Unknown',
            joinedAt: _prettyTime(d.createdAt),
            isThisDevice: d.isCurrent || d.id == thisId,
            isPriority: d.isPriority,
            rawPlatform: d.platform,
            unreachable: d.unreachable,
            isStale: d.isStale,
            hasHardwareKey: d.hasPopKey,
          ),
    ];
  }

  Future<List<AuthSessionRecord>> _mapSessions() async {
    final list = await _auth.listSessions();
    final tokens = await _auth.tokenStore.read();
    final currentId = tokens?.sessionId;
    return [
      for (final s in list)
        AuthSessionRecord(
          id: s.id,
          status: s.status,
          deviceId: s.deviceId,
          lastUsed: _prettyTime(s.lastUsedAt) ?? 'Unknown',
          isCurrent: s.id == currentId,
        ),
    ];
  }

  static AuthUser _userFromAccount(AccountDto a) {
    return AuthUser(
      id: a.id,
      name: a.username.isNotEmpty ? a.username : (a.email ?? '${AppBrand.name} User'),
      email: a.email ?? '',
      // Do not show account role (e.g. CUSTOMER) as the package name.
      // Subscription screen uses /subscriptions packageName from the API.
      packageName: '',
      // APP customer accounts are VIP-tier in the product UI (client
      // design shows VIP on the avatar). Role CUSTOMER is still VIP.
      isVip: true,
      role: a.role,
      mfaEnabled: a.mfaEnabled,
      emailVerified: a.emailVerified,
      deviceLoginApproval: a.features.deviceLoginApproval,
      tvDeviceCode: a.features.tvDeviceCode,
      priorityDevice: a.features.priorityDevice,
      primaryRecovery: a.features.primaryRecovery,
      playbackTakeover: a.features.playbackTakeover,
      deviceHeartbeat: a.features.deviceHeartbeat,
    );
  }

  static String _prettyPlatform(String code) {
    switch (code.toUpperCase()) {
      case 'ANDROID':
        return 'Android';
      case 'IOS':
        return 'iOS';
      case 'ANDROID_TV':
        return 'Android TV';
      case 'FIRE_TV':
        return 'Fire TV';
      default:
        return code;
    }
  }

  static String? _prettyTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Timer? _onlineRetry;

  /// While offline, try the server every 20 s; on success leave offline mode.
  void _scheduleOnlineRetry() {
    _onlineRetry?.cancel();
    _onlineRetry = Timer.periodic(const Duration(seconds: 20), (t) async {
      if (!state.offline || !state.isLoggedIn) {
        t.cancel();
        return;
      }
      await retryOnline();
    });
  }

  /// Called by the retry timer and the offline banner's Retry button.
  Future<bool> retryOnline() async {
    AccountDto? account;
    try {
      account = await _auth.restoreSession();
    } catch (_) {
      account = null;
    }
    if (account == null || !mounted) return false;
    _onlineRetry?.cancel();
    await _applyAuthenticated(account, true, state.activeProfileId);
    state = state.copyWith(offline: false);
    unawaited(_saveOfflineIdentity());
    return true;
  }

  @override
  void dispose() {
    _onlineRetry?.cancel();
    super.dispose();
  }

  /// Name, profiles and active profile, for an offline start.
  Future<void> _saveOfflineIdentity() async {
    try {
      final st = state;
      final user = st.user;
      if (user == null || !st.profileSelected) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kOfflineIdentity,
        jsonEncode({
          'id': user.id,
          'name': user.name,
          'email': user.email,
          'packageName': user.packageName,
          'isVip': user.isVip,
          'activeProfileId': st.activeProfileId,
          'profiles': [
            for (final p in st.profiles)
              {
                'id': p.id,
                'name': p.name,
                'initials': p.initials,
                'isKids': p.isKids,
                'hasPin': p.hasPin,
              },
          ],
        }),
      );
    } catch (_) {}
  }

  Future<SessionState?> _readOfflineIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kOfflineIdentity);
      if (raw == null) return null;
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final active = jsonStr(j['activeProfileId']);
      final profiles = [
        for (final e in (j['profiles'] as List? ?? const []))
          if (e is Map)
            ViewingProfile(
              id: jsonStr(e['id']) ?? '',
              name: jsonStr(e['name']) ?? '',
              initials: jsonStr(e['initials']) ?? '',
              isKids: jsonBool(e['isKids']) ?? false,
              hasPin: jsonBool(e['hasPin']) ?? false,
              isActive: jsonStr(e['id']) == active,
            ),
      ];
      if (active == null || profiles.every((p) => p.id != active)) return null;
      return state.copyWith(
        isLoggedIn: true,
        profileSelected: true,
        offline: true,
        user: AuthUser(
          id: jsonStr(j['id']) ?? '',
          name: jsonStr(j['name']) ?? '',
          email: jsonStr(j['email']) ?? '',
          packageName: jsonStr(j['packageName']) ?? '',
          // AuthUser defaults to VIP; offline must not show a VIP badge
          // the account does not have.
          isVip: jsonBool(j['isVip']) ?? false,
        ),
        profiles: profiles,
        activeProfileId: active,
      );
    } catch (_) {
      return null;
    }
  }

}

final authRepositoryProvider = Provider<AppAuthRepository>((ref) {
  final repo = AppAuthRepository();
  ref.onDispose(repo.dispose);
  // Signed config: backup API bases for failover (security point 5/7).
  repo.syncAppConfig().ignore();
  return repo;
});

final mediaRepositoryProvider = Provider<AppMediaRepository>((ref) {
  return AppMediaRepository.fromAuth(ref.watch(authRepositoryProvider));
});

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(
    ref.watch(authRepositoryProvider),
    ref.watch(mediaRepositoryProvider),
  );
});
