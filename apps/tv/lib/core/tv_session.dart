import 'dart:async';
import 'package:design_system/design_system.dart' show AppColors;
import 'dart:convert';

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Soft viewing profile (Usman `/profiles` + local color for TV tiles).
class TvProfile {
  const TvProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.color,
    this.avatar,
    this.isKids = false,
    this.hasPin = false,
    this.maturity = '18+',
  });

  /// Built-in avatar token (`app:avatar/<key>`), null = initials.
  final String? avatar;
  final String id;
  final String name;
  final String initials;
  final Color color;
  final bool isKids;
  final bool hasPin;
  final String maturity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initials': initials,
        'color': color.toARGB32(),
        'avatar': avatar,
        'isKids': isKids,
        'hasPin': hasPin,
        'maturity': maturity,
      };

  factory TvProfile.fromJson(Map<String, dynamic> json) {
    return TvProfile(
      id: jsonStr(json['id']) ?? '',
      name: jsonStr(json['name']) ?? '',
      initials: jsonStr(json['initials']) ?? '',
      color: Color(jsonInt(json['color']) ?? 0xFF00E5FF),
      avatar: jsonStr(json['avatar']),
      isKids: jsonBool(json['isKids']) ?? false,
      hasPin: jsonBool(json['hasPin']) ?? false,
      maturity: jsonStr(json['maturity']) ?? '18+',
    );
  }

  TvProfile copyWith({
    String? name,
    String? initials,
    Color? color,
    String? avatar,
    bool? isKids,
    bool? hasPin,
    String? maturity,
  }) {
    return TvProfile(
      id: id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      color: color ?? this.color,
      avatar: avatar ?? this.avatar,
      isKids: isKids ?? this.isKids,
      hasPin: hasPin ?? this.hasPin,
      maturity: maturity ?? this.maturity,
    );
  }
}

class TvSessionState {
  const TvSessionState({
    this.bootstrapped = false,
    this.loggedIn = false,
    this.profileSelected = false,
    this.activeProfileId,
    this.profiles = const [],
    this.autoplay = true,
    this.isVip = false,
    this.homeSections = TvSessionState.defaultHomeSections,
    this.primaryRecovery = true,
    this.playbackTakeover = true,
    this.deviceHeartbeat = true,
    this.offline = false,
  });

  /// Same section ids as mobile [SessionState.homeSections].
  /// Client 20 Oct: banner → Matches → CW → Top Movies/Series → Kids.
  static const defaultHomeSections = [
    "Today's Matches",
    'Continue Watching',
    'Top 10 in Your Region',
    'Kids',
    'Movies & 4K Blockbusters',
    'Series & Exclusive Seasons',
    'Live TV & Channels',
    'Arabic Originals',
  ];

  final bool bootstrapped;
  final bool loggedIn;
  final bool profileSelected;
  final String? activeProfileId;
  final List<TvProfile> profiles;
  final bool autoplay;
  final bool isVip;
  final List<String> homeSections;
  final bool primaryRecovery;
  final bool playbackTakeover;
  final bool deviceHeartbeat;

  /// Signed in from the saved session because the server could not be
  /// reached (client 18 Oct #4): downloads stay playable without internet.
  final bool offline;

  TvProfile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Default PIN when enabling lock without a custom code.
  static const demoPin = '1234';

  TvSessionState copyWith({
    bool? bootstrapped,
    bool? loggedIn,
    bool? profileSelected,
    String? activeProfileId,
    List<TvProfile>? profiles,
    bool? autoplay,
    bool? isVip,
    List<String>? homeSections,
    bool? primaryRecovery,
    bool? playbackTakeover,
    bool? deviceHeartbeat,
    bool? offline,
    bool clearActive = false,
  }) {
    return TvSessionState(
      bootstrapped: bootstrapped ?? this.bootstrapped,
      loggedIn: loggedIn ?? this.loggedIn,
      profileSelected: profileSelected ?? this.profileSelected,
      activeProfileId:
          clearActive ? null : (activeProfileId ?? this.activeProfileId),
      profiles: profiles ?? this.profiles,
      autoplay: autoplay ?? this.autoplay,
      isVip: isVip ?? this.isVip,
      homeSections: homeSections ?? this.homeSections,
      primaryRecovery: primaryRecovery ?? this.primaryRecovery,
      playbackTakeover: playbackTakeover ?? this.playbackTakeover,
      deviceHeartbeat: deviceHeartbeat ?? this.deviceHeartbeat,
      offline: offline ?? this.offline,
    );
  }
}

/// Thrown by [TvSessionController.selectProfile] when the Kids PIN is needed.
class TvKidsPinRequired implements Exception {
  const TvKidsPinRequired();
  @override
  String toString() => 'Kids PIN required';
}

class TvSessionController extends StateNotifier<TvSessionState> {
  TvSessionController(this._auth, this._media) : super(const TvSessionState()) {
    _bootstrap();
  }

  final AppAuthRepository _auth;
  final AppMediaRepository _media;

  static const _selectedKey = 'tv_profile_selected';
  static const _activeKey = 'tv_active_profile_id';
  static const _autoplayKey = 'tv_autoplay';
  static const _homeSectionsKey = 'tv_home_sections';
  static const _pinsKey = 'tv_profile_pins';
  static const _kidsPinKey = 'tv_kids_pin_on';
  static const _demoPinCleanupKey = 'tv_demo_pin_cleanup_v1';

  static final _palette = [
    Color(0xFF00E5FF),
    AppColors.magenta,
    Color(0xFFFFD700),
    Color(0xFF7CFFB2),
    Color(0xFFFF8A5B),
  ];

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      AccountDto? account;
      try {
        // Task #143 #16: honor Remember me across process death.
        final rememberMe = prefs.getBool(_kRememberMe) ?? true;
        if (!rememberMe) {
          try {
            await _auth.tokenStore.clear();
          } catch (_) {}
          account = null;
        } else {
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
      final loggedIn = account != null;
      final autoplay = prefs.getBool(_autoplayKey) ?? true;
      final homeSections = _readHomeSections(prefs);

      // No server, but the session was not rejected (tokens kept): sign in
      // offline with the saved profiles so downloads can be watched.
      if (!loggedIn && await _auth.tokenStore.read() != null) {
        final cached = _readOfflineProfiles(prefs);
        final active = prefs.getString(_activeKey);
        if ((prefs.getBool(_selectedKey) ?? false) &&
            active != null &&
            cached.any((p) => p.id == active)) {
          state = TvSessionState(
            bootstrapped: true,
            loggedIn: true,
            offline: true,
            profileSelected: true,
            activeProfileId: active,
            profiles: cached,
            autoplay: autoplay,
            homeSections: homeSections,
          );
          _scheduleOnlineRetry();
          return;
        }
      }

      List<TvProfile> profiles = const [];
      if (loggedIn) {
        // Device registration runs in the background: the splash only needs
        // the profiles (it used to wait for both, a few seconds on Railway).
        unawaited(() async {
          try {
            final name = await _auth.defaultDeviceName(tv: true);
            await _auth.ensureThisDeviceRegistered(
              name: name,
              platform: TvPlatformProfile.backendPlatform,
            );
          } catch (_) {}
        }());
        try {
          profiles = await _mapProfiles();
        } catch (_) {
          profiles = const [];
        }
      }

      var selected = loggedIn && (prefs.getBool(_selectedKey) ?? false);
      var active = loggedIn ? prefs.getString(_activeKey) : null;
      if (selected &&
          active != null &&
          profiles.every((p) => p.id != active)) {
        active = profiles.isEmpty ? null : profiles.first.id;
        if (active == null) selected = false;
      }

      if (loggedIn && profiles.isNotEmpty) {
        unawaited(_saveOfflineProfiles(profiles));
      }
      state = TvSessionState(
        bootstrapped: true,
        loggedIn: loggedIn,
        profileSelected: selected && active != null,
        activeProfileId: selected ? active : null,
        profiles: profiles,
        autoplay: autoplay,
        isVip: account != null,
        homeSections: homeSections,
        primaryRecovery: account?.features.primaryRecovery ?? true,
        playbackTakeover: account?.features.playbackTakeover ?? true,
        deviceHeartbeat: account?.features.deviceHeartbeat ?? true,
      );
    } catch (_) {
      // Always leave splash even if prefs/auth blow up unexpectedly.
      state = const TvSessionState(bootstrapped: true);
    }
  }

  List<String> _readHomeSections(SharedPreferences prefs) {
    final raw = prefs.getStringList(_homeSectionsKey);
    if (raw == null || raw.isEmpty) {
      return List<String>.from(TvSessionState.defaultHomeSections);
    }
    // Keep known ids; append any defaults the prefs list is missing.
    final known = TvSessionState.defaultHomeSections.toSet();
    final ordered = <String>[
      for (final id in raw)
        if (known.contains(id)) id,
    ];
    for (final id in TvSessionState.defaultHomeSections) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return ordered;
  }

  Future<Map<String, String>> _readPins() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pinsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = raw.split('\u001e');
      final map = <String, String>{};
      for (final entry in decoded) {
        final i = entry.indexOf('=');
        if (i <= 0) continue;
        map[entry.substring(0, i)] = entry.substring(i + 1);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePins(Map<String, String> pins) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = pins.entries.map((e) => '${e.key}=${e.value}').join('\u001e');
    await prefs.setString(_pinsKey, encoded);
  }

  Future<List<TvProfile>> _mapProfiles() async {
    final list = await _media.listProfiles();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final pins = await _readPins();
    // Kids profiles made on this TV used to get the demo PIN 1234 to ENTER
    // them; the Kids PIN now guards LEAVING Kids (server). Drop those once.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_demoPinCleanupKey) != true) {
      var changed = false;
      for (final p in list) {
        if (p.isKids && pins[p.id] == TvSessionState.demoPin) {
          pins.remove(p.id);
          changed = true;
        }
      }
      if (changed) await _writePins(pins);
      await prefs.setBool(_demoPinCleanupKey, true);
    }
    return [
      for (var i = 0; i < list.length; i++)
        TvProfile(
          id: list[i].id,
          name: list[i].name,
          initials: _initialsFor(list[i].name),
          color: _palette[i % _palette.length],
          avatar: list[i].avatarUrl,
          isKids: list[i].isKids,
          hasPin: pins.containsKey(list[i].id),
          maturity: list[i].isKids ? 'Kids' : '18+',
        ),
    ];
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static const _kRememberMe = 'app.remember_me';

  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final loginId = email.trim();
    if (loginId.isEmpty || password.isEmpty) {
      throw Exception('Username and password required');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRememberMe, rememberMe);
      final deviceName = await _auth.defaultDeviceName(tv: true);
      await _auth.login(
        login: loginId,
        password: password,
        platform: TvPlatformProfile.backendPlatform,
        deviceName: deviceName,
      );
      await _afterAuthTokens();
    } on MfaRequiredException {
      throw Exception(
        'This account requires MFA. Complete MFA on mobile Security, or use recovery login.',
      );
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
      await _afterAuthTokens(deviceIdHint: session.deviceId);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> claimLoginApproval({
    required String challengeId,
    required String password,
  }) async {
    try {
      final session = await _auth.claimLoginApproval(
        challengeId: challengeId,
        password: password,
      );
      await _afterAuthTokens(deviceIdHint: session.deviceId);
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
        platform: TvPlatformProfile.backendPlatform,
      );
      await _afterAuthTokens(deviceIdHint: session.deviceId);
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> sendDeviceHeartbeat({String? appVersion}) async {
    if (!state.loggedIn || !state.deviceHeartbeat) return;
    try {
      await _auth.deviceHeartbeat(
        platform: TvPlatformProfile.backendPlatform,
        appVersion: appVersion,
        osVersion: await DeviceCapabilitiesStore.instance.osVersionLabel(tv: true),
      );
    } catch (_) {}
  }

  Future<void> loginWithDeviceCode() async {
    final deviceName = await _auth.defaultDeviceName(tv: true);
    final created = await _auth.createDeviceCode(
      platform: TvPlatformProfile.backendPlatform,
      name: deviceName,
    );
    final session = await _auth.waitForDeviceCodeApproval(
      code: created.code,
      challengeId: created.challengeId,
      intervalSec: created.intervalSec,
    );
    // Tokens already persisted by waitForDeviceCodeApproval.
    await _afterAuthTokens(deviceIdHint: session.deviceId);
  }

  /// Starts a device-code session and returns the code payload for QR UI.
  /// Caller should poll via [completeDeviceCode] with the same code.
  Future<DeviceCodeDto> beginDeviceCodeLogin() async {
    final deviceName = await _auth.defaultDeviceName(tv: true);
    return _auth.createDeviceCode(
      platform: TvPlatformProfile.backendPlatform,
      name: deviceName,
    );
  }

  Future<void> completeDeviceCode(
    DeviceCodeDto code, {
    bool Function()? shouldContinue,
  }) async {
    final session = await _auth.waitForDeviceCodeApproval(
      code: code.code,
      challengeId: code.challengeId,
      intervalSec: code.intervalSec,
      shouldContinue: shouldContinue,
    );
    await _afterAuthTokens(deviceIdHint: session.deviceId);
  }

  Future<void> _afterAuthTokens({String? deviceIdHint}) async {
    try {
      if (deviceIdHint != null && deviceIdHint.isNotEmpty) {
        // Challenge/QR already adopted + orphan-revoked in the repository.
        await _auth.tokenStore.saveDeviceId(deviceIdHint);
      } else {
        final name = await _auth.defaultDeviceName(tv: true);
        await _auth.ensureThisDeviceRegistered(
          name: name,
          platform: TvPlatformProfile.backendPlatform,
        );
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_selectedKey, false);
    await prefs.remove(_activeKey);
    List<TvProfile> profiles = const [];
    try {
      profiles = await _mapProfiles();
    } catch (_) {}
    var isVip = false;
    var primaryRecovery = false;
    var playbackTakeover = false;
    var deviceHeartbeat = false;
    try {
      final me = await _auth.me();
      // Product UI: VIP badge on avatar for signed-in customers (client
      // 20 Oct — was role!=CUSTOMER and never showed for real users).
      isVip = true;
      primaryRecovery = me.features.primaryRecovery;
      playbackTakeover = me.features.playbackTakeover;
      deviceHeartbeat = me.features.deviceHeartbeat;
    } catch (_) {}
    if (profiles.isNotEmpty) unawaited(_saveOfflineProfiles(profiles));
    state = state.copyWith(
      loggedIn: true,
      offline: false,
      profileSelected: false,
      clearActive: true,
      profiles: profiles,
      isVip: isVip,
      primaryRecovery: primaryRecovery,
      playbackTakeover: playbackTakeover,
      deviceHeartbeat: deviceHeartbeat,
    );
  }

  static const _offlineProfilesKey = 'tv_offline_profiles';
  Timer? _onlineRetry;

  Future<void> _saveOfflineProfiles(List<TvProfile> profiles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _offlineProfilesKey,
        jsonEncode([for (final p in profiles) p.toJson()]),
      );
    } catch (_) {}
  }

  List<TvProfile> _readOfflineProfiles(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_offlineProfilesKey);
      if (raw == null) return const [];
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is Map) TvProfile.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// While offline, try the server every 20 s; on success leave offline mode.
  void _scheduleOnlineRetry() {
    _onlineRetry?.cancel();
    _onlineRetry = Timer.periodic(const Duration(seconds: 20), (t) async {
      if (!state.offline || !state.loggedIn) {
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
    List<TvProfile> profiles = state.profiles;
    try {
      profiles = await _mapProfiles();
      unawaited(_saveOfflineProfiles(profiles));
    } catch (_) {}
    if (!mounted) return false;
    state = state.copyWith(
      offline: false,
      profiles: profiles,
      isVip: true,
      primaryRecovery: account.features.primaryRecovery,
      playbackTakeover: account.features.playbackTakeover,
      deviceHeartbeat: account.features.deviceHeartbeat,
    );
    return true;
  }

  @override
  void dispose() {
    _onlineRetry?.cancel();
    super.dispose();
  }

  Future<void> logout() async {
    // Bound network wait so UI can reach login without a multi-second stall.
    try {
      await _auth.logout().timeout(const Duration(milliseconds: 1200));
    } catch (_) {
      try {
        await _auth.tokenStore.clear();
      } catch (_) {}
    }
    await _clearLocalAuthFlags();
  }

  /// Revoke / expired session → clear tokens and bounce to login.
  Future<void> handleAuthLoss(Object error) async {
    if (error is! ApiException) return;
    final m = error.message.toLowerCase();
    if (m.contains('invalid mfa') ||
        m.contains('mfa code') ||
        m.contains('invalid code') ||
        m.contains('wrong code') ||
        m.contains('password') ||
        m.contains('not allowed') ||
        m.contains('validation')) {
      return;
    }
    final lost = error.statusCode == 401 ||
        error.isDeviceRevoked ||
        AppAuthRepository.isDeviceGoneError(error) ||
        m.contains('no access token') ||
        m.contains('session expired') ||
        m.contains('refresh token reuse') ||
        m.contains('reuse detected') ||
        m.contains('invalid access token') ||
        m.contains('authentication required') ||
        m.contains('no refresh token');
    if (!lost) return;
    await _auth.tokenStore.clear();
    await _clearLocalAuthFlags();
  }

  Future<void> _clearLocalAuthFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_selectedKey, false);
    await prefs.remove(_activeKey);
    await prefs.remove(_offlineProfilesKey);
    _onlineRetry?.cancel();
    state = state.copyWith(
      offline: false,
      loggedIn: false,
      isVip: false,
      profileSelected: false,
      clearActive: true,
      profiles: const [],
    );
  }

  /// Kids PIN (server, one per account; set on the phone). Cached so it
  /// still applies when the TV starts offline.
  bool _kidsPinOn = false;
  bool get kidsPinOn => _kidsPinOn;

  /// Cache key per account (profile ids are unique per account).
  String? get _kidsPinCacheKey {
    if (state.profiles.isEmpty) return null;
    final ids = [for (final p in state.profiles) p.id]..sort();
    return '$_kidsPinKey.${ids.first}';
  }

  Future<bool> refreshKidsPin() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _kidsPinCacheKey;
    _kidsPinOn = key == null ? false : (prefs.getBool(key) ?? false);
    if (!state.loggedIn || key == null) return _kidsPinOn;
    try {
      _kidsPinOn = await _auth.parentalPinEnabled();
      await prefs.setBool(key, _kidsPinOn);
    } on ApiException catch (e) {
      // Offline: keep the cached value (fail closed). A server without the
      // Kids PIN feature (404) or any other answer: no PIN.
      if (!e.isNetwork) {
        _kidsPinOn = false;
        await prefs.setBool(key, false);
      }
    } catch (_) {
      // Keep the cached value.
    }
    return _kidsPinOn;
  }

  /// Leaving a Kids profile for a non-Kids profile needs the Kids PIN.
  bool needsKidsPin(String targetId) {
    if (!_kidsPinOn) return false;
    TvProfile? current;
    TvProfile? target;
    for (final p in state.profiles) {
      if (p.id == state.activeProfileId) current = p;
      if (p.id == targetId) target = p;
    }
    return current != null && current.isKids && target != null && !target.isKids;
  }

  Future<void> selectProfile(String id, {String? pin}) async {
    TvProfile? profile;
    for (final p in state.profiles) {
      if (p.id == id) {
        profile = p;
        break;
      }
    }
    if (profile == null) {
      throw Exception('Profile not found');
    }
    if (needsKidsPin(id)) {
      if (pin == null || pin.trim().isEmpty) {
        throw const TvKidsPinRequired();
      }
      // Throws ApiException (PIN_INVALID / PIN_LOCKED / NETWORK): stay on Kids.
      await _auth.verifyParentalPin(pin.trim());
    } else if (profile.hasPin) {
      if (pin == null || pin.trim().isEmpty) {
        throw Exception('Enter profile PIN to continue.');
      }
      final pins = await _readPins();
      final expected = pins[id];
      if (expected == null || pin.trim() != expected) {
        throw Exception('Incorrect PIN.');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
    await prefs.setBool(_selectedKey, true);
    state = state.copyWith(
      profileSelected: true,
      activeProfileId: id,
    );
  }

  Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_selectedKey, false);
    await prefs.remove(_activeKey);
    state = state.copyWith(profileSelected: false, clearActive: true);
  }

  Future<void> refreshProfiles() async {
    if (!state.loggedIn) return;
    try {
      final profiles = await _mapProfiles();
      state = state.copyWith(profiles: profiles);
      unawaited(refreshKidsPin());
    } on ApiException catch (e) {
      await handleAuthLoss(e);
      throw Exception(e.message);
    }
  }

  Future<void> addProfile({
    required String name,
    bool kids = false,
    bool withPin = false,
  }) async {
    if (state.profiles.length >= 5) {
      throw Exception('Maximum 5 profiles');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Name required');
    try {
      await _media.createProfile(name: trimmed, isKids: kids);
      await refreshProfiles();
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> updateProfile({
    required String id,
    String? name,
    bool? isKids,
    String? avatar,
  }) async {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw Exception('Name required');
    }
    try {
      await _media.updateProfile(
        id: id,
        name: trimmed,
        isKids: isKids,
        avatarUrl: avatar,
      );
      await refreshProfiles();
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> setProfilePin(String id, String pin) async {
    final cleaned = pin.trim();
    if (cleaned.length != 4 || int.tryParse(cleaned) == null) {
      throw Exception('PIN must be 4 digits.');
    }
    final pins = await _readPins();
    pins[id] = cleaned;
    await _writePins(pins);
    await refreshProfiles();
  }

  Future<void> clearProfilePin(String id) async {
    final pins = await _readPins();
    pins.remove(id);
    await _writePins(pins);
    await refreshProfiles();
  }

  Future<void> removeProfile(String id) async {
    if (state.profiles.length <= 1) {
      throw Exception('Keep at least one profile');
    }
    try {
      await _media.deleteProfile(id);
      final pins = await _readPins();
      if (pins.remove(id) != null) {
        await _writePins(pins);
      }
      if (state.activeProfileId == id) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_selectedKey, false);
        await prefs.remove(_activeKey);
        state = state.copyWith(
          profileSelected: false,
          clearActive: true,
        );
      }
      await refreshProfiles();
    } on ApiException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> setAutoplay(bool value) async {
    state = state.copyWith(autoplay: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayKey, value);
  }

  Future<void> reorderHomeSections(int oldIndex, int newIndex) async {
    final list = [...state.homeSections];
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 ||
        oldIndex >= list.length ||
        newIndex < 0 ||
        newIndex >= list.length) {
      return;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(homeSections: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_homeSectionsKey, list);
  }

  Future<void> moveHomeSection(int index, {required bool up}) async {
    final target = up ? index - 1 : index + 1;
    if (target < 0 || target >= state.homeSections.length) return;
    // reorderHomeSections expects drag-style newIndex (insert index before adjust).
    await reorderHomeSections(index, up ? target : target + 1);
  }
}

final tvAuthRepositoryProvider = Provider<AppAuthRepository>((ref) {
  final repo = AppAuthRepository();
  ref.onDispose(repo.dispose);
  // Signed config: backup API bases for failover (security point 5/7).
  repo.syncAppConfig().ignore();
  return repo;
});

final tvMediaRepositoryProvider = Provider<AppMediaRepository>((ref) {
  return AppMediaRepository.fromAuth(ref.watch(tvAuthRepositoryProvider));
});

final tvSessionProvider =
    StateNotifierProvider<TvSessionController, TvSessionState>((ref) {
  return TvSessionController(
    ref.watch(tvAuthRepositoryProvider),
    ref.watch(tvMediaRepositoryProvider),
  );
});
