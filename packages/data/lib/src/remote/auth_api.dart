import 'dart:async';

import 'api_client.dart';
import 'api_exception.dart';
import 'auth_models.dart';
import 'token_store.dart';
import 'json_read.dart';
import '../downloads/offline_policy.dart';
import '../security/device_attestation.dart';
import '../security/device_pop.dart';

class AuthApi {
  AuthApi(this._client, this._tokens);

  final ApiClient _client;
  final TokenStore _tokens;
  Future<AuthSessionDto>? _refreshInFlight;

  Future<AuthSessionDto> _persistSession(Map<String, dynamic> data) async {
    final session = AuthSessionDto.fromJson(data);
    if (session.accessToken.isEmpty || session.refreshToken.isEmpty) {
      throw ApiException('Response did not include tokens');
    }
    await _tokens.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresInSec: session.expiresIn,
      sessionId: session.sessionId,
    );
    if (session.deviceId != null && session.deviceId!.isNotEmpty) {
      await _tokens.saveDeviceId(session.deviceId!);
      // Device PoP: register this device's hardware key if the server lacks it.
      unawaited(DevicePop.ensureEnrolled(_client, session.deviceId!));
      // Key Attestation (Android only, silent, at most once a day).
      DeviceAttestation.runIfDue(_client, session.deviceId);
    }
    return session;
  }

  void _throwLoginGates(Map<String, dynamic> data) {
    if (data['mfaRequired'] == true) {
      final challengeId = jsonStr(data['mfaChallengeId']);
      if (challengeId == null || challengeId.isEmpty) {
        throw ApiException('MFA required but challenge id missing');
      }
      throw MfaRequiredException(
        mfaChallengeId: challengeId,
        account: Map<String, dynamic>.from(data['account'] as Map? ?? {}),
      );
    }
    if (data['loginApprovalRequired'] == true) {
      final challengeId = jsonStr(data['challengeId']);
      if (challengeId == null || challengeId.isEmpty) {
        throw ApiException('Login approval required but challenge id missing');
      }
      throw LoginApprovalRequiredException(
        challengeId: challengeId,
        expiresAt: jsonStr(data['expiresAt']),
        message: jsonStr(data['message']),
      );
    }
  }

  Map<String, dynamic> _deviceLoginFields({
    String? platform,
    String? deviceName,
    String? publicKey,
    String? trustedDeviceId,
  }) {
    final body = <String, dynamic>{};
    if (platform != null && platform.isNotEmpty) body['platform'] = platform;
    if (deviceName != null && deviceName.isNotEmpty) {
      body['deviceName'] = deviceName;
    }
    if (publicKey != null && publicKey.isNotEmpty) {
      body['publicKey'] = publicKey;
    }
    if (trustedDeviceId != null && trustedDeviceId.isNotEmpty) {
      body['trustedDeviceId'] = trustedDeviceId;
    }
    return body;
  }

  Future<AuthSessionDto> login({
    required String login,
    required String password,
    String? platform,
    String? deviceName,
    String? publicKey,
    String? trustedDeviceId,
  }) async {
    final body = <String, dynamic>{
      'login': login.trim(),
      'password': password,
      ..._deviceLoginFields(
        platform: platform,
        deviceName: deviceName,
        publicKey: publicKey,
        trustedDeviceId: trustedDeviceId,
      ),
    };
    final data = await _client.post('/auth/login', body: body);
    if (data == null) throw ApiException('Empty login response');
    _throwLoginGates(data);
    return _persistSession(data);
  }

  Future<AuthSessionDto> verifyMfa({
    required String mfaChallengeId,
    required String code,
    String? platform,
    String? deviceName,
    String? publicKey,
    String? trustedDeviceId,
  }) async {
    final body = <String, dynamic>{
      'mfaChallengeId': mfaChallengeId,
      'code': code.trim(),
      ..._deviceLoginFields(
        platform: platform,
        deviceName: deviceName,
        publicKey: publicKey,
        trustedDeviceId: trustedDeviceId,
      ),
    };
    final data = await _client.post('/auth/mfa/verify', body: body);
    if (data == null) throw ApiException('Empty MFA verify response');
    _throwLoginGates(data);
    return _persistSession(data);
  }

  Future<AuthSessionDto> recoveryLogin({
    required String login,
    required String password,
    required String recoveryCode,
  }) async {
    final data = await _client.post(
      '/auth/recovery',
      body: {
        'login': login.trim(),
        'password': password,
        'recoveryCode': recoveryCode.trim(),
      },
    );
    if (data == null) throw ApiException('Empty recovery response');
    return _persistSession(data);
  }

  /// Single-flight refresh so concurrent 401s cannot burn the refresh family.
  Future<AuthSessionDto> refresh() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refreshOnce();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<AuthSessionDto> _refreshOnce({bool afterRace = false}) async {
    final current = await _tokens.read();
    if (current == null) {
      throw ApiException('No refresh token', statusCode: 401);
    }
    try {
      // Signed with the device key only when the server asks (device PoP).
      final data = await DevicePop.post(
        _client,
        '/auth/refresh',
        body: {'refreshToken': current.refreshToken},
        auth: false,
        proof: () => DevicePop.forRefresh(_client, current.refreshToken),
      );
      if (data == null) throw ApiException('Empty refresh response');
      return await _persistSession(data);
    } on ApiException catch (e) {
      // 409 REFRESH_RACE: another part of the app (or a background task)
      // refreshed with the same token a moment ago. The server kept that
      // newer sign-in, so use the newest stored token once instead of
      // signing out (backend #20).
      if (e.statusCode != 409 || e.code != 'REFRESH_RACE' || afterRace) rethrow;
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final latest = await _tokens.read();
        if (latest != null && latest.refreshToken != current.refreshToken) {
          return _refreshOnce(afterRace: true);
        }
      }
      throw ApiException(
        'Could not refresh your session right now. Please try again.',
        statusCode: 503,
        code: 'SESSION_REFRESH_RETRY',
      );
    }
  }

  Future<void> logout() async {
    unawaited(OfflineDownloadPolicy.signedOut());
    try {
      await _client.post('/auth/logout', auth: true);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
    } finally {
      await _tokens.clear();
    }
  }

  Future<void> logoutAll() async {
    unawaited(OfflineDownloadPolicy.signedOut());
    try {
      await _client.post('/auth/logout-all', auth: true);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
    } finally {
      await _tokens.clear();
    }
  }

  Future<AccountDto> me() async {
    final data = await _client.get('/me', auth: true);
    if (data == null) throw ApiException('Empty profile response');
    // Offline-download rule (P17): who owns the downloads, subscription end, check-in time.
    await OfflineDownloadPolicy.recordOnline(data);
    return AccountDto.fromJson(data);
  }

  Future<AuthSessionDto> verifyEmail({
    required String login,
    required String code,
  }) async {
    final data = await _client.post(
      '/auth/email/verify',
      body: {'login': login.trim(), 'code': code.trim()},
    );
    if (data == null) throw ApiException('Empty email verify response');
    return _persistSession(data);
  }

  Future<String> resendEmailVerification({required String login}) async {
    final data = await _client.post(
      '/auth/email/resend',
      body: {'login': login.trim()},
    );
    return jsonStr(data?['message']) ??
        'If the account exists, a code was sent';
  }

  /// Kids PIN for the signed-in account (one per account).
  Future<bool> parentalPinEnabled() async {
    final data = await _client.get('/parental-pin');
    return data?['enabled'] == true;
  }

  /// Set, change or reset ("forgot PIN") with the account password.
  Future<void> setParentalPin({required String pin, required String password}) async {
    await _client.put('/parental-pin', body: {'pin': pin, 'password': password});
  }

  Future<void> removeParentalPin({required String password}) async {
    await _client.post('/parental-pin/remove', body: {'password': password}, auth: true);
  }

  /// Throws [ApiException] with [ApiException.isPinInvalid] / [ApiException.isPinLocked].
  Future<void> verifyParentalPin(String pin) async {
    await _client.post('/parental-pin/verify', body: {'pin': pin}, auth: true);
  }

  /// Login screen "Need help with your subscription?" form (no sign-in).
  /// Throws [ApiException] when the server does not accept it.
  Future<void> sendSupportRequest({
    required String contact,
    required String message,
    required String platform,
    String? appVersion,
    String? language,
  }) async {
    await _client.post(
      '/support/requests',
      body: {
        'contact': contact.trim(),
        'message': message.trim(),
        'platform': platform,
        if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
        if (language != null && language.isNotEmpty) 'language': language,
      },
    );
  }

  Future<String> forgotPassword({required String login}) async {
    final data = await _client.post(
      '/auth/password/forgot',
      body: {'login': login.trim()},
    );
    return jsonStr(data?['message']) ??
        'If the account exists, reset instructions were sent';
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.post(
      '/auth/password/reset',
      body: {'token': token.trim(), 'newPassword': newPassword},
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/auth/password/change',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      auth: true,
    );
  }

  Future<MfaEnrollDto> enrollMfa() async {
    final data = await _client.post('/auth/mfa/enroll', auth: true);
    if (data == null) throw ApiException('Empty MFA enroll response');
    return MfaEnrollDto.fromJson(data);
  }

  Future<MfaConfirmDto> confirmMfa({required String code}) async {
    final data = await _client.post(
      '/auth/mfa/confirm',
      body: {'code': code.trim()},
      auth: true,
    );
    if (data == null) throw ApiException('Empty MFA confirm response');
    return MfaConfirmDto.fromJson(data);
  }

  Future<void> disableMfa({required String password}) async {
    await _client.post(
      '/auth/mfa/disable',
      body: {'password': password},
      auth: true,
    );
  }

  Future<List<SessionRecordDto>> listSessions({String? status}) async {
    final query = status == null || status.isEmpty
        ? null
        : {'status': status};
    final data =
        await _client.get('/auth/sessions', auth: true, query: query);
    return unwrapListData(data).map(SessionRecordDto.fromJson).toList();
  }

  Future<void> revokeSession(String sessionId) async {
    await _client.post('/auth/sessions/$sessionId/revoke', auth: true);
  }

  Future<LoginChallengeDto> pollLoginChallenge(String challengeId) async {
    final data = await _client.get(
      '/auth/login-challenges/$challengeId',
      auth: false,
    );
    if (data == null) throw ApiException('Empty login challenge response');
    return LoginChallengeDto.fromJson(data, fallbackId: challengeId);
  }

  /// Long-poll (server 21 Oct): answers as soon as the phone allows / denies,
  /// or after [timeoutSec] with the still-pending status. Keep [timeoutSec]
  /// below the client's 30 s request timeout.
  Future<LoginChallengeDto> waitLoginChallenge(
    String challengeId, {
    int timeoutSec = 20,
  }) async {
    final data = await _client.get(
      '/auth/login-challenges/$challengeId/wait',
      auth: false,
      query: {'timeoutSec': '$timeoutSec'},
    );
    if (data == null) throw ApiException('Empty login challenge response');
    return LoginChallengeDto.fromJson(data, fallbackId: challengeId);
  }

  Future<List<LoginChallengeDto>> listPendingLoginChallenges() async {
    final data = await _client.get(
      '/auth/login-challenges/pending',
      auth: true,
    );
    return unwrapFlexibleList(data)
        .map(LoginChallengeDto.fromJson)
        .toList();
  }

  Future<LoginChallengeDto> allowLoginChallenge(
    String challengeId, {
    String? deviceName,
  }) async {
    final body = <String, dynamic>{};
    if (deviceName != null && deviceName.isNotEmpty) {
      body['deviceName'] = deviceName;
    }
    final data = await _client.post(
      '/auth/login-challenges/$challengeId/allow',
      body: body,
      auth: true,
    );
    if (data == null) {
      return LoginChallengeDto(
        challengeId: challengeId,
        status: 'APPROVED',
      );
    }
    return LoginChallengeDto.fromJson(data, fallbackId: challengeId);
  }

  Future<LoginChallengeDto> denyLoginChallenge(String challengeId) async {
    final data = await _client.post(
      '/auth/login-challenges/$challengeId/deny',
      auth: true,
    );
    if (data == null) {
      return LoginChallengeDto(challengeId: challengeId, status: 'DENIED');
    }
    return LoginChallengeDto.fromJson(data, fallbackId: challengeId);
  }

  /// Password reclaim when the priority phone was wiped / lost (no Bearer).
  Future<LoginChallengeDto> claimLoginChallenge({
    required String challengeId,
    required String password,
  }) async {
    final data = await _client.post(
      '/auth/login-challenges/$challengeId/claim',
      body: {'password': password},
      auth: false,
    );
    if (data == null) {
      throw ApiException('Empty login challenge claim response');
    }
    return LoginChallengeDto.fromJson(data, fallbackId: challengeId);
  }

  Future<PrimaryRecoveryStartDto> startPrimaryRecovery({
    String? challengeId,
    required String usernameOrEmail,
    required String password,
  }) async {
    final body = <String, dynamic>{
      'usernameOrEmail': usernameOrEmail.trim(),
      'password': password,
    };
    if (challengeId != null && challengeId.isNotEmpty) {
      body['challengeId'] = challengeId;
    }
    final data = await _client.post(
      '/auth/primary-recovery/start',
      body: body,
      auth: false,
    );
    if (data == null) {
      throw ApiException('Empty primary recovery start response');
    }
    return PrimaryRecoveryStartDto.fromJson(data);
  }

  Future<void> sendPrimaryRecoveryEmailOtp({
    required String recoveryId,
  }) async {
    await _client.post(
      '/auth/primary-recovery/email-otp/send',
      body: {'recoveryId': recoveryId},
      auth: false,
    );
  }

  Future<AuthSessionDto> completePrimaryRecovery({
    required String recoveryId,
    required String method,
    required String code,
    String? platform,
    String? deviceName,
    String? publicKey,
    String? trustedDeviceId,
    bool revokeOldPrimary = true,
  }) async {
    final body = <String, dynamic>{
      'recoveryId': recoveryId,
      'method': method,
      'code': code.trim(),
      'revokeOldPrimary': revokeOldPrimary,
      ..._deviceLoginFields(
        platform: platform,
        deviceName: deviceName,
        publicKey: publicKey,
        trustedDeviceId: trustedDeviceId,
      ),
    };
    final data = await _client.post(
      '/auth/primary-recovery/complete',
      body: body,
      auth: false,
    );
    if (data == null) {
      throw ApiException('Empty primary recovery complete response');
    }
    return _persistSession(data);
  }

  Future<DeviceCodeDto> createDeviceCode({
    required String platform,
    required String name,
    String? publicKey,
  }) async {
    final body = <String, dynamic>{
      'platform': platform,
      'name': name,
    };
    if (publicKey != null && publicKey.isNotEmpty) {
      body['publicKey'] = publicKey;
    }
    final data = await _client.post('/auth/device/code', body: body);
    if (data == null) throw ApiException('Empty device code response');
    return DeviceCodeDto.fromJson(data);
  }

  Future<DeviceCodeStatusDto> pollDeviceCode(String code) async {
    final data = await _client.get(
      '/auth/device/code/${Uri.encodeComponent(code)}',
      auth: false,
    );
    if (data == null) throw ApiException('Empty device code poll response');
    return DeviceCodeStatusDto.fromJson(data);
  }

  /// Long-poll for a TV QR / code sign-in, by the challenge id from
  /// [createDeviceCode] (not the 6-digit code shown on screen).
  Future<DeviceCodeStatusDto> waitDeviceChallenge(
    String challengeId, {
    int timeoutSec = 20,
  }) async {
    final data = await _client.get(
      '/auth/device/challenges/${Uri.encodeComponent(challengeId)}/wait',
      auth: false,
      query: {'timeoutSec': '$timeoutSec'},
    );
    if (data == null) throw ApiException('Empty device code poll response');
    return DeviceCodeStatusDto.fromJson(data);
  }

  Future<void> approveDeviceCode(String code) async {
    await _client.post(
      '/auth/device/approve',
      body: {'code': code.trim()},
      auth: true,
    );
  }

  Future<void> denyDeviceCode(String code) async {
    await _client.post(
      '/auth/device/deny',
      body: {'code': code.trim()},
      auth: true,
    );
  }

  /// Persist tokens returned from challenge / device-code poll (one-time).
  Future<AuthSessionDto> claimPolledSession(Map<String, dynamic> data) {
    return _persistSession(data);
  }
}
