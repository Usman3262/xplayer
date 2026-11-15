import '../../backend/json_util.dart';
import '../../remote/json_read.dart';
import '../provider_models.dart';

/// One saved panel on this device. [toJson] never contains credentials —
/// they live sealed in a separate entry (see `ConnectionStore`).
class PanelConnection {
  const PanelConnection({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
    required this.addedAt,
    this.expiresAt,
    this.lastCheckedAt,
    this.lastSyncAt,
    this.isPrimary = false,
    this.enabled = true,
    this.lastFailure,
    this.maxConnections,
  });

  final String id;
  final ProviderKind kind;

  /// Shown in the app; defaults to the panel host. User can rename.
  final String name;
  final ConnectionStatus status;
  final DateTime addedAt;
  final DateTime? expiresAt;
  final DateTime? lastCheckedAt;

  /// Last finished catalog sync (Phase 6).
  final DateTime? lastSyncAt;

  /// The panel the app opens on. Exactly one enabled panel is primary.
  final bool isPrimary;
  final bool enabled;

  /// Why the last check failed (ProviderFailureKind name), for the UI message.
  final String? lastFailure;
  final int? maxConnections;

  PanelConnection copyWith({
    String? name,
    ConnectionStatus? status,
    DateTime? expiresAt,
    bool clearExpiry = false,
    DateTime? lastCheckedAt,
    DateTime? lastSyncAt,
    bool? isPrimary,
    bool? enabled,
    String? lastFailure,
    bool clearFailure = false,
    int? maxConnections,
  }) =>
      PanelConnection(
        id: id,
        kind: kind,
        name: name ?? this.name,
        status: status ?? this.status,
        addedAt: addedAt,
        expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        isPrimary: isPrimary ?? this.isPrimary,
        enabled: enabled ?? this.enabled,
        lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
        maxConnections: maxConnections ?? this.maxConnections,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'status': status.name,
        'addedAt': addedAt.toUtc().toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
        if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
        if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toUtc().toIso8601String(),
        'isPrimary': isPrimary,
        'enabled': enabled,
        'lastFailure': ?lastFailure,
        'maxConnections': ?maxConnections,
      };

  /// Null for anything unreadable (bad data never crashes the app).
  static PanelConnection? fromJson(Object? raw) {
    final m = jsonMap(raw);
    final id = jsonStr(m['id']);
    final kind = ProviderKind.fromKey(jsonStr(m['kind']));
    if (id == null || id.isEmpty || kind == null) return null;
    return PanelConnection(
      id: id,
      kind: kind,
      name: jsonStr(m['name']) ?? '',
      status: jsonEnum(m['status'], ConnectionStatus.values, ConnectionStatus.pending),
      addedAt: jsonDate(m['addedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: jsonDate(m['expiresAt']),
      lastCheckedAt: jsonDate(m['lastCheckedAt']),
      lastSyncAt: jsonDate(m['lastSyncAt']),
      isPrimary: jsonBool(m['isPrimary']) ?? false,
      enabled: jsonBool(m['enabled']) ?? true,
      lastFailure: jsonStr(m['lastFailure']),
      maxConnections: jsonInt(m['maxConnections']),
    );
  }

  @override
  String toString() => 'PanelConnection($id ${kind.name} ${status.name})';
}
