class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.packageName = '',
    this.isVip = true,
    this.deviceLimit = 5,
    this.activeDevices = 3,
    this.role = 'CUSTOMER',
    this.mfaEnabled = false,
    this.emailVerified = true,
    this.deviceLoginApproval = false,
    this.tvDeviceCode = false,
    this.priorityDevice = false,
    this.primaryRecovery = true,
    this.playbackTakeover = true,
    this.deviceHeartbeat = true,
  });

  final String id;
  final String name;
  final String email;
  final String packageName;
  final bool isVip;
  final int deviceLimit;
  final int activeDevices;
  final String role;
  final bool mfaEnabled;
  final bool emailVerified;
  final bool deviceLoginApproval;
  final bool tvDeviceCode;
  final bool priorityDevice;
  final bool primaryRecovery;
  final bool playbackTakeover;
  final bool deviceHeartbeat;

  AuthUser copyWith({
    String? name,
    String? email,
    String? packageName,
    bool? isVip,
    int? deviceLimit,
    int? activeDevices,
    String? role,
    bool? mfaEnabled,
    bool? emailVerified,
    bool? deviceLoginApproval,
    bool? tvDeviceCode,
    bool? priorityDevice,
    bool? primaryRecovery,
    bool? playbackTakeover,
    bool? deviceHeartbeat,
  }) {
    return AuthUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      packageName: packageName ?? this.packageName,
      isVip: isVip ?? this.isVip,
      deviceLimit: deviceLimit ?? this.deviceLimit,
      activeDevices: activeDevices ?? this.activeDevices,
      role: role ?? this.role,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
      emailVerified: emailVerified ?? this.emailVerified,
      deviceLoginApproval: deviceLoginApproval ?? this.deviceLoginApproval,
      tvDeviceCode: tvDeviceCode ?? this.tvDeviceCode,
      priorityDevice: priorityDevice ?? this.priorityDevice,
      primaryRecovery: primaryRecovery ?? this.primaryRecovery,
      playbackTakeover: playbackTakeover ?? this.playbackTakeover,
      deviceHeartbeat: deviceHeartbeat ?? this.deviceHeartbeat,
    );
  }
}

class ViewingProfile {
  const ViewingProfile({
    required this.id,
    required this.name,
    required this.initials,
    this.avatar,
    this.isKids = false,
    this.hasPin = false,
    this.isActive = false,
  });

  final String id;
  final String name;
  final String initials;
  /// Built-in avatar token (`app:avatar/<key>`), null = initials.
  final String? avatar;
  final bool isKids;
  final bool hasPin;
  final bool isActive;

  ViewingProfile copyWith({
    String? name,
    String? initials,
    String? avatar,
    bool? isKids,
    bool? hasPin,
    bool? isActive,
  }) {
    return ViewingProfile(
      id: id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      avatar: avatar ?? this.avatar,
      isKids: isKids ?? this.isKids,
      hasPin: hasPin ?? this.hasPin,
      isActive: isActive ?? this.isActive,
    );
  }
}

class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActive,
    this.joinedAt,
    this.isThisDevice = false,
    this.isStreaming = false,
    this.isPriority = false,
    this.rawPlatform = '',
    this.unreachable = false,
    this.isStale = false,
    this.hasHardwareKey = false,
  });

  final String id;
  final String name;
  final String platform;
  final String lastActive;
  /// Join / register time when API sends `createdAt`.
  final String? joinedAt;
  final bool isThisDevice;
  final bool isStreaming;
  final bool isPriority;
  final String rawPlatform;
  final bool unreachable;
  final bool isStale;

  /// Signed in with a hardware-bound key (device proof of possession).
  final bool hasHardwareKey;

  bool get canBePriority {
    final p = rawPlatform.toUpperCase();
    return p == 'ANDROID' || p == 'IOS';
  }
}

class AuthSessionRecord {
  const AuthSessionRecord({
    required this.id,
    required this.status,
    required this.lastUsed,
    this.deviceId,
    this.isCurrent = false,
  });

  final String id;
  final String status;
  final String? deviceId;
  final String lastUsed;
  final bool isCurrent;
}
