class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.requestId,
    this.code,
    this.data,
  });

  final String message;
  final int? statusCode;
  final String? requestId;
  /// Structured backend code e.g. DEVICE_LIMIT_REACHED, PLAYBACK_LEASE_HELD.
  final String? code;
  /// Optional error payload (e.g. lease holder on 409).
  final Map<String, dynamic>? data;

  /// The request never got an answer (no route, DNS, timeout).
  bool get isNetwork => code == 'NETWORK';
  bool get isDeviceLimit => code == 'DEVICE_LIMIT_REACHED';
  bool get isPlaybackLeaseHeld => code == 'PLAYBACK_LEASE_HELD';
  bool get isPriorityRequired => code == 'PRIORITY_REQUIRED';
  bool get isPrimaryUnreachable => code == 'PRIMARY_UNREACHABLE_USE_RECOVERY';

  /// Control Panel stop — do not auto-renew like [LEASE_EXPIRED].
  bool get isPlaybackStoppedByAdmin => code == 'PLAYBACK_STOPPED_BY_ADMIN';

  bool get isDeviceRevoked => code == 'DEVICE_REVOKED';

  /// Kids PIN (server, 23 Oct): wrong PIN / too many tries / wrong password.
  bool get isPinInvalid => code == 'PIN_INVALID';
  bool get isPinLocked => code == 'PIN_LOCKED';
  bool get isPasswordInvalid => code == 'PASSWORD_INVALID';
  int? get pinAttemptsLeft => (data?['attemptsLeft'] as num?)?.toInt();
  bool get isPopRequired => code == 'POP_REQUIRED';
  bool get isPopKeyMissing => code == 'POP_KEY_MISSING';
  bool get isPopChallengeInvalid => code == 'POP_CHALLENGE_INVALID';
  bool get isPopSigInvalid => code == 'POP_SIG_INVALID';
  bool get isPopUnavailable => code == 'POP_UNAVAILABLE';

  /// Fetch a fresh challenge and retry once.
  bool get isPopChallengeRetry =>
      isPopRequired || isPopChallengeInvalid;

  Map<String, dynamic>? get holder {
    final raw = data?['holder'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  @override
  String toString() => message;
}

/// Login returned an MFA challenge instead of tokens.
class MfaRequiredException extends ApiException {
  MfaRequiredException({
    required this.mfaChallengeId,
    required this.account,
    String? message,
  }) : super(message ?? 'Multi-factor authentication required.');

  final String mfaChallengeId;
  final Map<String, dynamic> account;
}

/// Login needs approval on the priority device (no tokens yet).
class LoginApprovalRequiredException extends ApiException {
  LoginApprovalRequiredException({
    required this.challengeId,
    this.expiresAt,
    String? message,
  }) : super(
          message ?? 'Approve this sign-in on your priority device',
        );

  final String challengeId;
  final String? expiresAt;
}
