import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'device_trust_policy.dart';
import 'devices_api.dart';
import 'json_read.dart';
import 'token_store.dart';
import '../device/device_capabilities_store.dart';
import '../device/tv_platform_profile.dart';
import '../security/device_attestation.dart';
import '../security/device_binding_key.dart';

/// Facade for Flutter apps: full auth + devices surface from Usman API.
class AppAuthRepository {
  AppAuthRepository({
    ApiConfig? config,
    TokenStore? tokenStore,
    ApiClient? client,
  })  : _tokens = tokenStore ?? TokenStore(),
        _config = config ?? ApiConfig.fromEnvironment() {
    _client = client ??
        ApiClient(
          config: _config,
          tokenStore: _tokens,
          endpoints: ApiEndpoints.instance,
        );
    _client.onRefresh = () async {
      try {
        await _auth.refresh();
        return true;
      } on ApiException catch (e) {
        // Sign out only when the server rejected the refresh token (401:
        // invalid, expired, reused, account inactive). A network blip, a
        // 429 rate limit or a 5xx must keep the sign-in: a 429 on a shared
        // carrier IP signed customers out while watching (client 20 Oct).
        if (e.statusCode == 401) {
          await _tokens.clear();
        }
        return false;
      } catch (_) {
        return false;
      }
    };
    _auth = AuthApi(_client, _tokens);
    _devices = DevicesApi(_client);
  }

  final ApiConfig _config;
  final TokenStore _tokens;
  late final ApiClient _client;
  late final AuthApi _auth;
  late final DevicesApi _devices;

  TokenStore get tokenStore => _tokens;

  ApiClient get client => _client;

  static bool _configSyncStarted = false;

  /// Once per app run: restore and refresh the signed config so backup API
  /// bases are known before the primary becomes unreachable. Never throws.
  Future<void> syncAppConfig() async {
    if (_configSyncStarted) return;
    _configSyncStarted = true;
    // Every known API base failing: ask the mirrors (throttled inside).
    ApiEndpoints.instance.onAllBasesFailing ??=
        () => syncFromConfigMirrors().ignore();
    await syncSignedAppConfig(() => _client.get('/config/app', auth: false));
  }

  Future<Map<String, String?>> _loginDeviceContext({
    String? platform,
    String? deviceName,
  }) async {
    final platformCode = platform ?? _platformCode();
    final name = deviceName ?? await _defaultDeviceName();
    final trusted = await _tokens.readDeviceId();
    String? publicKey;
    try {
      publicKey = await DeviceBindingKey.publicKeySpkiBase64();
    } catch (_) {
      publicKey = null;
    }
    return {
      'platform': platformCode,
      'deviceName': name,
      'trustedDeviceId': trusted,
      'publicKey': publicKey,
    };
  }

  Future<AuthSessionDto> login({
    required String login,
    required String password,
    String? platform,
    String? deviceName,
  }) async {
    final ctx = await _loginDeviceContext(
      platform: platform,
      deviceName: deviceName,
    );
    final previous = ctx['trustedDeviceId'];
    final session = await _auth.login(
      login: login,
      password: password,
      platform: ctx['platform'],
      deviceName: ctx['deviceName'],
      publicKey: ctx['publicKey'],
      trustedDeviceId: previous,
    );
    // Persist server deviceId (auth_api also saves when present). If login
    // minted a new id, drop the orphan local binding.
    await _adoptDeviceId(session.deviceId);
    if (session.deviceId != null &&
        previous != null &&
        previous.isNotEmpty &&
        previous != session.deviceId) {
      try {
        await _devices.revoke(previous);
      } catch (_) {}
    }
    // The server did not attach the remembered device (it belongs to another
    // account or server): forget it, so this install registers a fresh device
    // with its hardware key instead of keeping a session with no device.
    if ((session.deviceId == null || session.deviceId!.isEmpty) &&
        previous != null &&
        previous.isNotEmpty) {
      await _tokens.clearDeviceId();
    }
    return session;
  }

  Future<AuthSessionDto> verifyMfa({
    required String mfaChallengeId,
    required String code,
    String? platform,
    String? deviceName,
  }) async {
    final ctx = await _loginDeviceContext(
      platform: platform,
      deviceName: deviceName,
    );
    return _auth.verifyMfa(
      mfaChallengeId: mfaChallengeId,
      code: code,
      platform: ctx['platform'],
      deviceName: ctx['deviceName'],
      publicKey: ctx['publicKey'],
      trustedDeviceId: ctx['trustedDeviceId'],
    );
  }

  Future<AuthSessionDto> recoveryLogin({
    required String login,
    required String password,
    required String recoveryCode,
  }) {
    return _auth.recoveryLogin(
      login: login,
      password: password,
      recoveryCode: recoveryCode,
    );
  }

  Future<void> logout() => _auth.logout();

  Future<void> logoutAll() => _auth.logoutAll();

  Future<AccountDto?> restoreSession() async {
    final tokens = await _tokens.read();
    if (tokens == null) return null;
    var alreadyTriedRefresh = false;
    try {
      if (tokens.isAccessExpired) {
        try {
          alreadyTriedRefresh = true;
          await _auth.refresh();
        } on ApiException catch (e) {
          // Dead refresh family (reuse / invalid) — clear once, never retry
          // the same token (that is what burned the family in the logs).
          if (_isRefreshFamilyDead(e)) {
            await _tokens.clear();
            return null;
          }
          // Server 5xx / transient: keep tokens, do not hammer /auth/refresh.
          if (_isServerError(e)) return null;
          rethrow;
        }
      }
      final me = await _auth.me();
      unawaited(_attestOnStart());
      return me;
    } on ApiException catch (e) {
      if (_isRefreshFamilyDead(e)) {
        await _tokens.clear();
        return null;
      }
      if (_isServerError(e) || alreadyTriedRefresh) return null;
      // Access token rejected: one refresh attempt, then give up.
      try {
        await _auth.refresh();
        final me = await _auth.me();
        unawaited(_attestOnStart());
        return me;
      } on ApiException catch (e2) {
        if (_isRefreshFamilyDead(e2) || e2.statusCode == 401) {
          await _tokens.clear();
        }
        return null;
      } catch (_) {
        // Network blip after tokens still look valid — keep them for next boot.
        return null;
      }
    } catch (_) {
      // Network / prefs noise — do not wipe a good session.
      return null;
    }
  }

  /// App start while signed in: Key Attestation (Android only, silent,
  /// at most once a day). Never throws.
  Future<void> _attestOnStart() async {
    try {
      DeviceAttestation.runIfDue(_client, await _tokens.readDeviceId());
    } catch (_) {}
  }

  static bool _isServerError(ApiException e) {
    final s = e.statusCode;
    return s != null && s >= 500;
  }

  static bool _isRefreshFamilyDead(ApiException e) {
    final m = e.message.toLowerCase();
    return m.contains('reuse detected') ||
        m.contains('refresh token reuse') ||
        m.contains('invalid refresh') ||
        m.contains('no refresh token') ||
        (e.code?.toLowerCase().contains('reuse') ?? false);
  }

  Future<AccountDto> me() => _auth.me();

  Future<AuthSessionDto> verifyEmail({
    required String login,
    required String code,
  }) {
    return _auth.verifyEmail(login: login, code: code);
  }

  Future<String> resendEmailVerification({required String login}) {
    return _auth.resendEmailVerification(login: login);
  }

  Future<bool> parentalPinEnabled() => _auth.parentalPinEnabled();
  Future<void> setParentalPin({required String pin, required String password}) =>
      _auth.setParentalPin(pin: pin, password: password);
  Future<void> removeParentalPin({required String password}) =>
      _auth.removeParentalPin(password: password);
  Future<void> verifyParentalPin(String pin) => _auth.verifyParentalPin(pin);

  Future<void> sendSupportRequest({
    required String contact,
    required String message,
    required String platform,
    String? appVersion,
    String? language,
  }) {
    return _auth.sendSupportRequest(
      contact: contact,
      message: message,
      platform: platform,
      appVersion: appVersion,
      language: language,
    );
  }

  Future<String> forgotPassword({required String login}) {
    return _auth.forgotPassword(login: login);
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) {
    return _auth.resetPassword(token: token, newPassword: newPassword);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _auth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<MfaEnrollDto> enrollMfa() => _auth.enrollMfa();

  Future<MfaConfirmDto> confirmMfa({required String code}) {
    return _auth.confirmMfa(code: code);
  }

  Future<void> disableMfa({required String password}) {
    return _auth.disableMfa(password: password);
  }

  Future<List<SessionRecordDto>> listSessions({String status = 'ACTIVE'}) =>
      _auth.listSessions(status: status);

  Future<List<DeviceDto>> listDevices({String status = 'ACTIVE'}) =>
      _devices.list(status: status);

  Future<void> revokeSession(String sessionId) =>
      _auth.revokeSession(sessionId);

  Future<LoginChallengeDto> pollLoginChallenge(String challengeId) =>
      _auth.pollLoginChallenge(challengeId);

  Future<List<LoginChallengeDto>> listPendingLoginChallenges() =>
      _auth.listPendingLoginChallenges();

  Future<LoginChallengeDto> allowLoginChallenge(
    String challengeId, {
    String? deviceName,
  }) {
    return _auth.allowLoginChallenge(challengeId, deviceName: deviceName);
  }

  Future<LoginChallengeDto> denyLoginChallenge(String challengeId) =>
      _auth.denyLoginChallenge(challengeId);

  /// Reclaim a pending challenge with account password (wiped priority phone).
  Future<AuthSessionDto> claimLoginApproval({
    required String challengeId,
    required String password,
  }) async {
    final status = await _auth.claimLoginChallenge(
      challengeId: challengeId,
      password: password,
    );
    if (status.isApproved && status.hasTokens) {
      return _claimPolledTokens(status);
    }
    // Claim stores tokens for poll — finish via the normal wait path.
    return waitForLoginApproval(
      challengeId: challengeId,
      timeout: const Duration(seconds: 30),
    );
  }

  /// Server long-poll for TV sign-in waits; switched off for the session
  /// when an older server does not have the endpoint.
  bool _signInLongPoll = true;
  Duration _signInBackoff = Duration.zero;

  /// The endpoint itself is missing (older server: Express HTML 404, or the
  /// JSON "Route not found"), as opposed to an unknown / expired code.
  static bool isMissingRoute(ApiException e) {
    if (e.statusCode != 404) return false;
    final m = e.message.toLowerCase();
    return m.contains('route not found') ||
        m.contains('invalid response') ||
        m.contains('unexpected response');
  }

  /// Worth waiting and asking again (busy server, rate limit, network
  /// blip, a deploy restarting) instead of failing the sign-in screen.
  static bool isTransientSignInError(ApiException e) {
    final s = e.statusCode;
    if (s == null || s == 0 || s == 408 || s == 429 || s >= 500) return true;
    if (e.code == 'RATE_LIMITED' || e.code == 'RATE_LIMIT') return true;
    return e.message.toLowerCase().contains('invalid response');
  }

  /// Server's Retry-After when it sent one, else 3 → 6 → 12 → 15 s.
  Duration _nextSignInBackoff(ApiException e) {
    final retryAfter = jsonInt(e.data?['retryAfterSec']);
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 30));
    }
    final next = _signInBackoff == Duration.zero
        ? const Duration(seconds: 3)
        : _signInBackoff * 2;
    _signInBackoff = next > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : next;
    return _signInBackoff;
  }

  /// Poll until approved (with tokens), denied, expired, or [timeout].
  /// [shouldContinue] returning false ends with [ApiException] code `CANCELLED`.
  /// [onStatus] receives each pending poll (recovery fields for UI).
  Future<AuthSessionDto> waitForLoginApproval({
    required String challengeId,
    Duration interval = const Duration(seconds: 4),
    Duration timeout = const Duration(minutes: 6),
    bool Function()? shouldContinue,
    void Function(LoginChallengeDto status)? onStatus,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (shouldContinue != null && !shouldContinue()) {
        throw ApiException(
          'Cancelled',
          statusCode: 499,
          code: 'CANCELLED',
        );
      }
      // Long-poll when the server has it (one request per ~20 s, answer the
      // moment the phone taps Allow); the old 2 s polling went over the
      // server's limit and showed "Invalid response from server" (21 Oct).
      final usedLongPoll = _signInLongPoll;
      LoginChallengeDto status;
      try {
        status = usedLongPoll
            ? await _auth.waitLoginChallenge(challengeId)
            : await pollLoginChallenge(challengeId);
        _signInBackoff = Duration.zero;
      } on ApiException catch (e) {
        if (usedLongPoll && isMissingRoute(e)) {
          _signInLongPoll = false;
          continue;
        }
        if (!isTransientSignInError(e)) rethrow;
        await Future<void>.delayed(_nextSignInBackoff(e));
        continue;
      }
      onStatus?.call(status);
      if (shouldContinue != null && !shouldContinue()) {
        throw ApiException(
          'Cancelled',
          statusCode: 499,
          code: 'CANCELLED',
        );
      }
      if (status.isApproved && status.hasTokens) {
        return await _claimPolledTokens(status);
      }
      if (status.isDenied) {
        throw ApiException(
          status.message ?? 'Sign-in was denied on your priority device',
          statusCode: 403,
          code: 'LOGIN_DENIED',
        );
      }
      if (status.isExpired) {
        throw ApiException(
          status.message ?? 'Sign-in approval expired. Try again.',
          statusCode: 410,
          code: 'LOGIN_EXPIRED',
        );
      }
      // The long-poll already waited on the server; ask again at once.
      if (!usedLongPoll) await Future<void>.delayed(interval);
    }
    throw ApiException(
      'Timed out waiting for approval',
      statusCode: 408,
      code: 'LOGIN_TIMEOUT',
    );
  }

  Future<PrimaryRecoveryStartDto> startPrimaryRecovery({
    String? challengeId,
    required String usernameOrEmail,
    required String password,
  }) =>
      _auth.startPrimaryRecovery(
        challengeId: challengeId,
        usernameOrEmail: usernameOrEmail,
        password: password,
      );

  Future<void> sendPrimaryRecoveryEmailOtp({required String recoveryId}) =>
      _auth.sendPrimaryRecoveryEmailOtp(recoveryId: recoveryId);

  Future<AuthSessionDto> completePrimaryRecovery({
    required String recoveryId,
    required String method,
    required String code,
    bool revokeOldPrimary = true,
    String? platform,
    String? deviceName,
  }) async {
    final ctx = await _loginDeviceContext(
      platform: platform,
      deviceName: deviceName,
    );
    final session = await _auth.completePrimaryRecovery(
      recoveryId: recoveryId,
      method: method,
      code: code,
      platform: ctx['platform'],
      deviceName: ctx['deviceName'],
      publicKey: ctx['publicKey'],
      trustedDeviceId: ctx['trustedDeviceId'],
      revokeOldPrimary: revokeOldPrimary,
    );
    await _adoptDeviceId(session.deviceId);
    return session;
  }

  /// Sends the connection-test speed to the server. Never throws.
  Future<void> reportSpeed(double mbps) async {
    try {
      final deviceId = await _tokens.readDeviceId();
      if (deviceId == null || deviceId.isEmpty || mbps <= 0) return;
      await _devices.reportSpeed(deviceId: deviceId, mbps: mbps);
    } catch (_) {}
  }

  Future<void> deviceHeartbeat({
    required String platform,
    String? appVersion,
    String? osVersion,
  }) async {
    var deviceId = await _tokens.readDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      final d = await ensureThisDeviceRegistered(platform: platform);
      deviceId = d.id;
    }
    try {
      await _devices.heartbeat(
        deviceId: deviceId,
        trustedDeviceId: deviceId,
        platform: platform,
        appVersion: appVersion,
        osVersion: osVersion,
      );
    } on ApiException catch (e) {
      // Only when the server says this device is gone; any other 404 (a
      // proxy page, an older route) used to mint a new device row.
      if (!isDeviceGoneError(e)) rethrow;
      final fresh = await forceReregisterDevice(platform: platform);
      await _devices.heartbeat(
        deviceId: fresh,
        trustedDeviceId: fresh,
        platform: platform,
        appVersion: appVersion,
      );
    }
  }

  Future<DeviceCodeDto> createDeviceCode({
    String? platform,
    String? name,
  }) async {
    final platformCode = platform ?? 'ANDROID_TV';
    final deviceName = name ?? await _defaultDeviceName(tv: true);
    String? publicKey;
    try {
      publicKey = await DeviceBindingKey.publicKeySpkiBase64();
    } catch (_) {
      publicKey = null;
    }
    return _auth.createDeviceCode(
      platform: platformCode,
      name: deviceName,
      publicKey: publicKey,
    );
  }

  Future<DeviceCodeStatusDto> pollDeviceCode(String code) =>
      _auth.pollDeviceCode(code);

  /// [challengeId] (from [createDeviceCode]) enables the server long-poll;
  /// without it, or on an older server, the code is polled every few seconds.
  Future<AuthSessionDto> waitForDeviceCodeApproval({
    required String code,
    String? challengeId,
    int intervalSec = 4,
    Duration timeout = const Duration(minutes: 11),
    bool Function()? shouldContinue,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final interval = Duration(seconds: intervalSec.clamp(4, 10));
    while (DateTime.now().isBefore(deadline)) {
      if (shouldContinue != null && !shouldContinue()) {
        throw ApiException(
          'Cancelled',
          statusCode: 499,
          code: 'CANCELLED',
        );
      }
      final usedLongPoll =
          _signInLongPoll && challengeId != null && challengeId.isNotEmpty;
      try {
        final status = usedLongPoll
            ? await _auth.waitDeviceChallenge(challengeId)
            : await pollDeviceCode(code);
        _signInBackoff = Duration.zero;
        if (shouldContinue != null && !shouldContinue()) {
          throw ApiException(
            'Cancelled',
            statusCode: 499,
            code: 'CANCELLED',
          );
        }
        if (status.isApproved && status.hasTokens) {
          return await _claimPolledDeviceCode(status);
        }
        if (status.isDenied) {
          throw ApiException(
            status.message ?? 'TV pairing was denied',
            statusCode: 403,
            code: 'DEVICE_CODE_DENIED',
          );
        }
        // The long-poll already waited on the server; ask again at once.
        if (usedLongPoll) continue;
      } on ApiException catch (e) {
        if (e.code == 'CANCELLED') rethrow;
        if (usedLongPoll && isMissingRoute(e)) {
          _signInLongPoll = false;
          continue;
        }
        if (isTransientSignInError(e)) {
          await Future<void>.delayed(_nextSignInBackoff(e));
          continue;
        }
        if (e.statusCode == 404 || e.statusCode == 410) {
          throw ApiException(
            e.message.isNotEmpty
                ? e.message
                : 'Code expired. Request a new code.',
            statusCode: e.statusCode,
            code: 'DEVICE_CODE_EXPIRED',
          );
        }
        rethrow;
      }
      await Future<void>.delayed(interval);
    }
    throw ApiException(
      'Timed out waiting for TV pairing',
      statusCode: 408,
      code: 'DEVICE_CODE_TIMEOUT',
    );
  }

  Future<void> approveDeviceCode(String code) =>
      _auth.approveDeviceCode(code);

  Future<void> denyDeviceCode(String code) => _auth.denyDeviceCode(code);

  Future<AuthSessionDto> _claimPolledTokens(LoginChallengeDto status) async {
    await _tokens.save(
      accessToken: status.accessToken!,
      refreshToken: status.refreshToken!,
      expiresInSec: status.expiresIn ?? 900,
      sessionId: status.sessionId,
    );
    await _adoptDeviceId(status.deviceId);
    final account = status.account ?? await _auth.me();
    return AuthSessionDto(
      accessToken: status.accessToken!,
      refreshToken: status.refreshToken!,
      expiresIn: status.expiresIn ?? 900,
      sessionId: status.sessionId,
      account: account,
      deviceId: status.deviceId,
    );
  }

  Future<AuthSessionDto> _claimPolledDeviceCode(
    DeviceCodeStatusDto status,
  ) async {
    await _tokens.save(
      accessToken: status.accessToken!,
      refreshToken: status.refreshToken!,
      expiresInSec: status.expiresIn ?? 900,
      sessionId: status.sessionId,
    );
    await _adoptDeviceId(status.deviceId);
    final account = status.account ?? await _auth.me();
    return AuthSessionDto(
      accessToken: status.accessToken!,
      refreshToken: status.refreshToken!,
      expiresIn: status.expiresIn ?? 900,
      sessionId: status.sessionId,
      account: account,
      deviceId: status.deviceId,
    );
  }

  /// Persist the server deviceId for this install. If login-approval minted a
  /// *new* id while we still had a prior binding, revoke the orphan so the
  /// Devices list does not stack duplicate TVs.
  Future<void> _adoptDeviceId(String? newId) async {
    if (newId == null || newId.isEmpty) return;
    final previous = await _tokens.readDeviceId();
    await _tokens.saveDeviceId(newId);
    // Fresh install: attest now instead of at the next app start (Usman,
    // 9 Nov). Fire-and-forget, at most once a day, never blocks sign-in.
    DeviceAttestation.runIfDue(_client, newId);
    if (previous == null || previous.isEmpty || previous == newId) return;
    try {
      await _devices.revoke(previous);
    } catch (_) {
      // Best-effort cleanup; list may still show a stale row until next refresh.
    }
  }

  Future<DeviceDto> setPriorityDevice(String deviceId) =>
      _devices.setPriority(deviceId);

  Future<void> clearPriorityDevice() => _devices.clearPriority();

  Future<RevokeAllDevicesResult> revokeAllDevices({
    bool keepCurrentDevice = true,
    String? password,
  }) async {
    // Client fail-closed: secondary must not wipe primary via revoke-all.
    try {
      final list = await _devices.list();
      final mine = await _tokens.readDeviceId();
      final hasPriority = list.any((d) => d.isPriority);
      final iAmPriority = list.any(
        (d) => d.isPriority && (d.isCurrent || d.id == mine),
      );
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
    } on ApiException {
      rethrow;
    } catch (_) {
      // List failed — still call API; server must enforce the same rule.
    }
    final result = await _devices.revokeAll(
      keepCurrentDevice: keepCurrentDevice,
      password: password,
    );
    if (!keepCurrentDevice) {
      await _tokens.clear();
      await _tokens.clearDeviceId();
    } else if (result.keptDeviceId != null) {
      await _tokens.saveDeviceId(result.keptDeviceId!);
    }
    return result;
  }

  Future<void> registerPushToken({
    required String token,
    String provider = 'FCM',
  }) async {
    final deviceId = await _tokens.readDeviceId();
    if (deviceId == null || deviceId.isEmpty) return;
    if (token.isEmpty) return;
    await _devices.registerPushToken(
      deviceId: deviceId,
      token: token,
      provider: provider,
    );
  }

  Future<DeviceDto> ensureThisDeviceRegistered({
    String? name,
    String? platform,
  }) async {
    final platformCode = platform ?? _platformCode();
    final existing = await _tokens.readDeviceId();
    final wantName = name ?? await _defaultDeviceName();

    // Local id can be stale (simulator wipe, server purge, env switch).
    // iOS log 20 Oct: devices=[] while TokenStore still had a UUID → pop/key
    // + heartbeat 404 + "Session is not bound to a device".
    if (existing != null && existing.isNotEmpty) {
      await _migrateLegacySharedDeviceNameIfNeeded();
      try {
        final list = await _devices.list();
        if (list.any((d) => d.id == existing)) {
          return DeviceDto(
            id: existing,
            platform: platformCode,
            name: wantName,
            status: 'ACTIVE',
          );
        }
      } catch (_) {
        // List failed (network blip, busy server): keep the id we have. This
        // used to register a new device each time, and the old one kept a
        // slot, which filled the 5-device limit (21 Oct). A really stale id
        // is caught on the next successful check.
        return DeviceDto(
          id: existing,
          platform: platformCode,
          name: wantName,
          status: 'ACTIVE',
        );
      }
      await _tokens.clearDeviceId();
    }

    // Never reclaim another install's device by shared display name
    // (all phones used to be "Android Phone" → same deviceId).
    final device = await _registerDevice(
      platform: platformCode,
      name: wantName,
    );
    await _tokens.saveDeviceId(device.id);
    return device;
  }

  /// Playback-safe device id: use cached id; do not GET /devices on every play.
  /// On 403/404 from startPlayback, caller should [forceReregisterDevice] once.
  Future<String> ensurePlaybackDeviceId({
    String? name,
    String? platform,
  }) async {
    await _migrateLegacySharedDeviceNameIfNeeded();
    final existing = await _tokens.readDeviceId();
    if (existing != null && existing.isNotEmpty) {
      // Best-effort: register PoP key on existing devices that never did.
      // Stale ids are fixed at login via [ensureThisDeviceRegistered].
      return existing;
    }
    final wantName = name ?? await _defaultDeviceName();
    final platformCode = platform ?? _platformCode();
    final device = await _registerDevice(
      platform: platformCode,
      name: wantName,
    );
    await _tokens.saveDeviceId(device.id);
    return device.id;
  }

  /// Old builds bound every Android phone as "Android Phone", so two installs
  /// could share one lease. Mark migration done without minting a second row
  /// (re-register here was creating duplicate TVs / phones on every login).
  Future<void> _migrateLegacySharedDeviceNameIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('app_device_unique_v1') == true) return;
      await prefs.setBool('app_device_unique_v1', true);
    } catch (_) {
      // Best-effort flag only.
    }
  }

  /// Clear local device binding and register a fresh ACTIVE device.
  Future<String> forceReregisterDevice({
    String? name,
    String? platform,
  }) async {
    await _tokens.clearDeviceId();
    final device = await _registerDevice(
      platform: platform ?? _platformCode(),
      name: name ?? await _defaultDeviceName(),
    );
    await _tokens.saveDeviceId(device.id);
    return device.id;
  }

  Future<DeviceDto> _registerDevice({
    required String platform,
    required String name,
  }) async {
    final spki = await DeviceBindingKey.publicKeySpkiBase64();
    Map<String, dynamic>? capsPayload;
    try {
      final caps = await DeviceCapabilitiesStore.instance.ensureLoaded();
      capsPayload = {
        'model': caps.model,
        'brand': caps.brand,
        'soc': caps.socModel,
        'ramMb': caps.totalRamMb,
        'hevcMaxRes': caps.hevc == null
            ? null
            : '${caps.hevc!.width}x${caps.hevc!.height}',
        'avcMaxRes': caps.avc == null
            ? null
            : '${caps.avc!.width}x${caps.avc!.height}',
        'tier': caps.tier.name,
        'sdkInt': caps.sdkInt,
      };
    } catch (_) {
      capsPayload = null;
    }
    return _devices.register(
      platform: platform,
      name: name,
      publicKey: spki,
      deviceCaps: capsPayload,
    );
  }

  static bool isDeviceGoneError(Object error) {
    final msg = error.toString().toLowerCase();
    final code = error is ApiException ? error.statusCode : null;
    if (code == 403 || code == 404) {
      return msg.contains('device') &&
          (msg.contains('not registered') ||
              msg.contains('revoked') ||
              msg.contains('not found'));
    }
    return msg.contains('device is not registered') ||
        (msg.contains('device') && msg.contains('revoked'));
  }

  Future<DeviceDto> renameDevice({
    required String deviceId,
    required String name,
  }) {
    return _devices.rename(deviceId: deviceId, name: name);
  }

  Future<void> revokeDevice(String id, {bool? targetIsPriority}) async {
    var isPriority = targetIsPriority;
    if (isPriority == null) {
      try {
        final list = await _devices.list();
        isPriority = list.any((d) => d.id == id && d.isPriority);
      } catch (_) {
        // If list fails, still attempt revoke — server must enforce.
        isPriority = false;
      }
    }
    if (!DeviceTrustPolicy.canRevokeDevice(targetIsPriority: isPriority)) {
      throw ApiException(
        'Cannot revoke the primary phone from another device',
        statusCode: 403,
        code: 'PRIORITY_REQUIRED',
      );
    }
    try {
      await _devices.revoke(id);
    } on ApiException catch (e) {
      // Already revoked / gone — treat as success so UI can refresh.
      if (e.statusCode != 404) rethrow;
    }
    final mine = await _tokens.readDeviceId();
    if (mine == id) {
      await _tokens.clearDeviceId();
    }
  }

  Future<String?> thisDeviceId() => _tokens.readDeviceId();

  /// Public unique install name (TV / phone) for register + login payloads.
  Future<String> defaultDeviceName({bool tv = false}) =>
      _defaultDeviceName(tv: tv);

  static String _platformCode({bool tv = false}) {
    if (tv) return TvPlatformProfile.backendPlatform;
    if (Platform.isIOS) return 'IOS';
    return 'ANDROID';
  }

  /// Unique per install so two phones never silently share one lease deviceId.
  static Future<String> _defaultDeviceName({bool tv = false}) async {
    final caps = DeviceCapabilitiesStore.instance.current;
    var model = (caps?.model ?? '').trim();
    // iPhone / iPad: capability probe is Android-only ("non-android").
    if (model == 'non-android') model = '';
    final shortModel = model.isEmpty
        ? (tv
            ? TvPlatformProfile.deviceName
            : (Platform.isIOS ? 'iPhone' : 'Android'))
        : model;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('app_install_id');
      if (id == null || id.isEmpty) {
        id = List.generate(8, (_) => _hex[_rand.nextInt(16)]).join();
        await prefs.setString('app_install_id', id);
      }
      return '$shortModel ($id)';
    } catch (_) {
      return shortModel;
    }
  }

  static final _rand = Random();
  static const _hex = '0123456789abcdef';

  void dispose() => _client.close();
}
