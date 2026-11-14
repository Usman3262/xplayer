import 'api_client.dart';
import 'api_exception.dart';
import 'json_read.dart';

/// In-app notification inbox (`GET /v1/notifications*`, backend 20 Oct 2026).
class AppNotificationDto {
  const AppNotificationDto({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.linkUrl,
    this.data = const {},
    this.createdAt,
    this.readAt,
  });

  final String id;
  /// `MESSAGE` | `UPDATE` (and any future kinds).
  final String kind;
  final String title;
  final String body;
  final String? linkUrl;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  String? get dataType => jsonStr(data['type']);

  factory AppNotificationDto.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppNotificationDto(
      id: jsonStr(json['id']) ?? '',
      kind: (jsonStr(json['kind']) ?? 'MESSAGE').toUpperCase(),
      title: jsonStr(json['title']) ?? '',
      body: jsonStr(json['body']) ?? '',
      linkUrl: jsonStr(json['linkUrl']),
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse(jsonStr(json['createdAt']) ?? ''),
      readAt: DateTime.tryParse(jsonStr(json['readAt']) ?? ''),
    );
  }
}

class NotificationsPage {
  const NotificationsPage({
    required this.unreadCount,
    required this.items,
  });

  final int unreadCount;
  final List<AppNotificationDto> items;
}

class NotificationsApi {
  NotificationsApi(this._client);

  final ApiClient _client;

  Future<NotificationsPage> list({int limit = 30}) async {
    try {
      final data = await _client.get(
        '/notifications',
        auth: true,
        query: {'limit': '$limit'},
      );
      if (data == null) {
        return const NotificationsPage(unreadCount: 0, items: []);
      }
      final itemsRaw = data['items'];
      final items = <AppNotificationDto>[];
      if (itemsRaw is List) {
        for (final row in itemsRaw) {
          if (row is Map) {
            items.add(
              AppNotificationDto.fromJson(Map<String, dynamic>.from(row)),
            );
          }
        }
      }
      return NotificationsPage(
        unreadCount: jsonInt(data['unreadCount']) ?? 0,
        items: items,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return const NotificationsPage(unreadCount: 0, items: []);
      }
      rethrow;
    }
  }

  Future<int> unreadCount() async {
    try {
      final data = await _client.get('/notifications/unread-count', auth: true);
      return jsonInt(data?['unreadCount']) ?? 0;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return 0;
      rethrow;
    }
  }

  Future<int> markRead(String id) async {
    try {
      final data = await _client.post(
        '/notifications/$id/read',
        auth: true,
      );
      return jsonInt(data?['unreadCount']) ?? 0;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return 0;
      rethrow;
    }
  }

  Future<int> markAllRead() async {
    try {
      final data = await _client.post(
        '/notifications/all/read',
        auth: true,
      );
      return jsonInt(data?['unreadCount']) ?? 0;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return 0;
      rethrow;
    }
  }
}

/// Compare app versions (`6.0.23` or `6.0.23+105`).
/// Returns negative if [a] < [b], 0 if equal, positive if [a] > [b].
/// Compares `x.y.z` first; compares `+build` only when both sides have one.
int compareAppVersions(String a, String b) {
  (List<int> semver, int? build) parse(String v) {
    final raw = v.trim();
    final plus = raw.indexOf('+');
    final core = plus >= 0 ? raw.substring(0, plus) : raw;
    final buildStr = plus >= 0 ? raw.substring(plus + 1) : null;
    final cleaned = core.split(RegExp(r'[^0-9.]')).first;
    final parts = cleaned
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final build = buildStr == null ? null : int.tryParse(buildStr.split(RegExp(r'\D')).first);
    return (parts, build);
  }

  final pa = parse(a);
  final pb = parse(b);
  final n = pa.$1.length > pb.$1.length ? pa.$1.length : pb.$1.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.$1.length ? pa.$1[i] : 0;
    final y = i < pb.$1.length ? pb.$1[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (pa.$2 != null && pb.$2 != null) {
    return pa.$2!.compareTo(pb.$2!);
  }
  return 0;
}

/// True when [remote] is a newer semver than [local] (e.g. `6.0.23` vs `6.0.18`).
bool isAppVersionNewer(String remote, String local) =>
    compareAppVersions(remote, local) > 0;
