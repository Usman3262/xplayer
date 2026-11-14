import 'json_read.dart';
class AccountFeatures {
  const AccountFeatures({
    this.deviceLoginApproval = false,
    this.tvDeviceCode = false,
    this.priorityDevice = false,
    // Usman env defaults FEATURE_* = true for these three.
    this.primaryRecovery = true,
    this.playbackTakeover = true,
    this.deviceHeartbeat = true,
  });

  final bool deviceLoginApproval;
  final bool tvDeviceCode;
  final bool priorityDevice;
  final bool primaryRecovery;
  final bool playbackTakeover;
  final bool deviceHeartbeat;

  factory AccountFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AccountFeatures();
    }
    return AccountFeatures(
      deviceLoginApproval: jsonBool(json['deviceLoginApproval']) ?? false,
      tvDeviceCode: jsonBool(json['tvDeviceCode']) ?? false,
      priorityDevice: jsonBool(json['priorityDevice']) ?? false,
      primaryRecovery: jsonBool(json['primaryRecovery']) ?? true,
      playbackTakeover: jsonBool(json['playbackTakeover']) ?? true,
      deviceHeartbeat: jsonBool(json['deviceHeartbeat']) ?? true,
    );
  }
}

class AccountDto {
  const AccountDto({
    required this.id,
    required this.role,
    required this.username,
    this.tenantPath,
    this.email,
    this.status,
    this.mfaEnabled = false,
    this.emailVerified = false,
    this.features = const AccountFeatures(),
  });

  final String id;
  final String role;
  final String username;
  final String? tenantPath;
  final String? email;
  final String? status;
  final bool mfaEnabled;
  final bool emailVerified;
  final AccountFeatures features;

  factory AccountDto.fromJson(Map<String, dynamic> json) {
    return AccountDto(
      id: jsonStr(json['id']) ?? '',
      role: jsonStr(json['role']) ?? 'CUSTOMER',
      username: jsonStr(json['username']) ?? '',
      tenantPath: jsonStr(json['tenantPath']),
      email: jsonStr(json['email']),
      status: jsonStr(json['status']),
      mfaEnabled: jsonBool(json['mfaEnabled']) ?? false,
      emailVerified: jsonBool(json['emailVerified']) ?? false,
      features: AccountFeatures.fromJson(
        json['features'] is Map
            ? Map<String, dynamic>.from(json['features'] as Map)
            : null,
      ),
    );
  }
}

class AuthSessionDto {
  const AuthSessionDto({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.account,
    this.sessionId,
    this.mfaRequired = false,
    this.mfaEnrollmentRequired = false,
    this.mfaChallengeId,
    this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String? sessionId;
  final AccountDto account;
  final bool mfaRequired;
  final bool mfaEnrollmentRequired;
  final String? mfaChallengeId;
  final String? deviceId;

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) {
    return AuthSessionDto(
      accessToken: jsonStr(json['accessToken']) ?? '',
      refreshToken: jsonStr(json['refreshToken']) ?? '',
      expiresIn: (jsonDouble(json['expiresIn']))?.toInt() ?? 900,
      sessionId: jsonStr(json['sessionId']),
      account: AccountDto.fromJson(
        Map<String, dynamic>.from(json['account'] as Map? ?? const {}),
      ),
      mfaRequired: jsonBool(json['mfaRequired']) ?? false,
      mfaEnrollmentRequired: jsonBool(json['mfaEnrollmentRequired']) ?? false,
      mfaChallengeId: jsonStr(json['mfaChallengeId']),
      deviceId: jsonStr(json['deviceId']),
    );
  }
}

class DeviceDto {
  const DeviceDto({
    required this.id,
    required this.platform,
    required this.name,
    required this.status,
    this.lastSeenAt,
    this.createdAt,
    this.isPriority = false,
    this.isCurrent = false,
    this.unreachable = false,
    this.hasPopKey = false,
  });

  final String id;
  final String platform;
  final String name;
  final String status;
  final String? lastSeenAt;
  final String? createdAt;
  final bool isPriority;
  final bool isCurrent;
  final bool unreachable;

  /// A hardware key (Keystore / Secure Enclave) is registered for this device.
  final bool hasPopKey;

  bool get isStale => status.toUpperCase() == 'STALE' || unreachable;

  factory DeviceDto.fromJson(Map<String, dynamic> json) {
    return DeviceDto(
      id: jsonStr(json['id']) ?? '',
      platform: jsonStr(json['platform']) ?? '',
      name: jsonStr(json['name']) ?? 'Device',
      status: jsonStr(json['status']) ?? 'ACTIVE',
      lastSeenAt: jsonStr(json['lastSeenAt']),
      createdAt: jsonStr(json['createdAt']),
      isPriority: jsonBool(json['isPriority']) ?? false,
      isCurrent: jsonBool(json['isCurrent']) ?? false,
      unreachable: jsonBool(json['unreachable']) ?? false,
      hasPopKey: jsonBool(json['hasPopKey']) ?? false,
    );
  }
}

class SessionRecordDto {
  const SessionRecordDto({
    required this.id,
    required this.status,
    this.deviceId,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String status;
  final String? deviceId;
  final String? createdAt;
  final String? lastUsedAt;
  final String? expiresAt;
  final String? revokedAt;

  factory SessionRecordDto.fromJson(Map<String, dynamic> json) {
    return SessionRecordDto(
      id: jsonStr(json['id']) ?? '',
      status: jsonStr(json['status']) ?? '',
      deviceId: jsonStr(json['deviceId']),
      createdAt: jsonStr(json['createdAt']),
      lastUsedAt: jsonStr(json['lastUsedAt']),
      expiresAt: jsonStr(json['expiresAt']),
      revokedAt: jsonStr(json['revokedAt']),
    );
  }
}

class MfaEnrollDto {
  const MfaEnrollDto({required this.secret, required this.otpauthUrl});

  final String secret;
  final String otpauthUrl;

  factory MfaEnrollDto.fromJson(Map<String, dynamic> json) {
    return MfaEnrollDto(
      secret: jsonStr(json['secret']) ?? '',
      otpauthUrl: jsonStr(json['otpauthUrl']) ?? '',
    );
  }
}

class MfaConfirmDto {
  const MfaConfirmDto({required this.recoveryCodes});

  final List<String> recoveryCodes;

  factory MfaConfirmDto.fromJson(Map<String, dynamic> json) {
    final raw = json['recoveryCodes'];
    final codes = raw is List
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];
    return MfaConfirmDto(recoveryCodes: codes);
  }
}

class RevokeAllDevicesResult {
  const RevokeAllDevicesResult({
    required this.revokedDeviceCount,
    this.revokedSessionCount,
    this.keptDeviceId,
    this.priorityDeviceId,
  });

  final int revokedDeviceCount;
  final int? revokedSessionCount;
  final String? keptDeviceId;
  final String? priorityDeviceId;

  factory RevokeAllDevicesResult.fromJson(Map<String, dynamic> json) {
    return RevokeAllDevicesResult(
      revokedDeviceCount: (jsonDouble(json['revokedDeviceCount']))?.toInt() ?? 0,
      revokedSessionCount: (jsonDouble(json['revokedSessionCount']))?.toInt(),
      keptDeviceId: jsonStr(json['keptDeviceId']),
      priorityDeviceId: jsonStr(json['priorityDeviceId']),
    );
  }
}

class LoginChallengeDto {
  const LoginChallengeDto({
    required this.challengeId,
    required this.status,
    this.type,
    this.platform,
    this.deviceName,
    this.createdAt,
    this.expiresAt,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.sessionId,
    this.deviceId,
    this.account,
    this.primaryUnreachable = false,
    this.recoveryAvailable = false,
    this.recoveryMethods = const [],
  });

  final String challengeId;
  final String status;
  final String? type;
  final String? platform;
  final String? deviceName;
  final String? createdAt;
  final String? expiresAt;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? sessionId;
  final String? deviceId;
  final AccountDto? account;
  final bool primaryUnreachable;
  final bool recoveryAvailable;
  final List<String> recoveryMethods;

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isDenied => status.toUpperCase() == 'DENIED';
  bool get isExpired => status.toUpperCase() == 'EXPIRED';

  bool get hasTokens =>
      (accessToken?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);

  bool get canOfferRecovery =>
      recoveryAvailable || primaryUnreachable || recoveryMethods.isNotEmpty;

  factory LoginChallengeDto.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) {
    final id = (jsonStr(json['challengeId'])) ??
        (jsonStr(json['id'])) ??
        fallbackId ??
        '';
    AccountDto? account;
    if (json['account'] is Map) {
      account = AccountDto.fromJson(
        Map<String, dynamic>.from(json['account'] as Map),
      );
    }
    final methodsRaw = json['recoveryMethods'];
    final methods = methodsRaw is List
        ? methodsRaw.map((e) => e.toString()).toList()
        : const <String>[];
    return LoginChallengeDto(
      challengeId: id,
      status: jsonStr(json['status']) ?? 'PENDING',
      type: jsonStr(json['type']),
      platform: jsonStr(json['platform']),
      deviceName: jsonStr(json['deviceName']),
      createdAt: jsonStr(json['createdAt']),
      expiresAt: jsonStr(json['expiresAt']),
      message: jsonStr(json['message']),
      accessToken: jsonStr(json['accessToken']),
      refreshToken: jsonStr(json['refreshToken']),
      expiresIn: (jsonDouble(json['expiresIn']))?.toInt(),
      sessionId: jsonStr(json['sessionId']),
      deviceId: jsonStr(json['deviceId']),
      account: account,
      primaryUnreachable: jsonBool(json['primaryUnreachable']) ?? false,
      recoveryAvailable: jsonBool(json['recoveryAvailable']) ?? false,
      recoveryMethods: methods,
    );
  }
}

class PrimaryRecoveryStartDto {
  const PrimaryRecoveryStartDto({
    required this.recoveryId,
    required this.methods,
    this.expiresAt,
  });

  final String recoveryId;
  final List<String> methods;
  final String? expiresAt;

  factory PrimaryRecoveryStartDto.fromJson(Map<String, dynamic> json) {
    final raw = json['methods'];
    return PrimaryRecoveryStartDto(
      recoveryId: jsonStr(json['recoveryId']) ?? '',
      methods: raw is List
          ? raw.map((e) => e.toString()).toList()
          : const <String>[],
      expiresAt: jsonStr(json['expiresAt']),
    );
  }
}

class DeviceCodeDto {
  const DeviceCodeDto({
    required this.code,
    required this.qrPayload,
    required this.expiresAt,
    this.intervalSec = 3,
    this.challengeId,
  });

  final String code;
  final String qrPayload;
  final String expiresAt;
  final int intervalSec;
  final String? challengeId;

  factory DeviceCodeDto.fromJson(Map<String, dynamic> json) {
    return DeviceCodeDto(
      code: jsonStr(json['code']) ?? '',
      qrPayload: jsonStr(json['qrPayload']) ?? '',
      expiresAt: jsonStr(json['expiresAt']) ?? '',
      intervalSec: (jsonDouble(json['intervalSec']))?.toInt() ?? 3,
      challengeId: jsonStr(json['challengeId']),
    );
  }
}

class DeviceCodeStatusDto {
  const DeviceCodeStatusDto({
    required this.status,
    this.expiresAt,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.sessionId,
    this.deviceId,
    this.account,
  });

  final String status;
  final String? expiresAt;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? sessionId;
  final String? deviceId;
  final AccountDto? account;

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isDenied => status.toLowerCase() == 'denied';

  bool get hasTokens =>
      (accessToken?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);

  factory DeviceCodeStatusDto.fromJson(Map<String, dynamic> json) {
    AccountDto? account;
    if (json['account'] is Map) {
      account = AccountDto.fromJson(
        Map<String, dynamic>.from(json['account'] as Map),
      );
    }
    return DeviceCodeStatusDto(
      status: jsonStr(json['status']) ?? 'pending',
      expiresAt: jsonStr(json['expiresAt']),
      message: jsonStr(json['message']),
      accessToken: jsonStr(json['accessToken']),
      refreshToken: jsonStr(json['refreshToken']),
      expiresIn: (jsonDouble(json['expiresIn']))?.toInt(),
      sessionId: jsonStr(json['sessionId']),
      deviceId: jsonStr(json['deviceId']),
      account: account,
    );
  }
}

List<Map<String, dynamic>> unwrapListData(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final raw = data['_'];
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  // Some endpoints return a bare JSON array under data — ApiClient may wrap.
  return const [];
}

List<Map<String, dynamic>> unwrapFlexibleList(Object? data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (data is Map<String, dynamic>) {
    return unwrapListData(data);
  }
  if (data is Map) {
    return unwrapListData(Map<String, dynamic>.from(data));
  }
  return const [];
}
