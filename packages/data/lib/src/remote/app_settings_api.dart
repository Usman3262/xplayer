import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Settings only the owner changes in the Control Panel (client 27 Oct).
/// Missing or unreadable values keep the safe defaults: protection on.
class AppSettingsDto {
  const AppSettingsDto({this.screenProtection = true, this.lineups = true});

  /// Block screenshots / screen recording. Customers have no switch for it.
  final bool screenProtection;

  /// Show the Lineups section of the match page.
  final bool lineups;

  factory AppSettingsDto.fromJson(Map<String, dynamic> json) => AppSettingsDto(
        screenProtection: json['screenProtection'] is bool ? json['screenProtection'] as bool : true,
        lineups: json['lineups'] is bool ? json['lineups'] as bool : true,
      );

  Map<String, dynamic> toJson() => {'screenProtection': screenProtection, 'lineups': lineups};

  @override
  bool operator ==(Object other) =>
      other is AppSettingsDto && other.screenProtection == screenProtection && other.lineups == lineups;

  @override
  int get hashCode => Object.hash(screenProtection, lineups);
}

/// Public `GET /v1/app/settings` (no sign-in), tried on each API address.
class AppSettingsApi {
  AppSettingsApi({http.Client? client, this.apiBase}) : _client = client ?? http.Client();

  final http.Client _client;
  final String? apiBase;

  Future<AppSettingsDto?> fetch() async {
    final bases = <String>[
      if (apiBase != null && apiBase!.isNotEmpty) apiBase!,
      ApiConfig.defaultBaseUrl,
      ...ApiConfig.builtInBackupBaseUrls,
    ];
    for (final base in bases.where((b) => b.trim().isNotEmpty)) {
      final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/app/settings');
      try {
        final res = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body);
        final data = body is Map && body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : null;
        if (data == null) continue;
        return AppSettingsDto.fromJson(data);
      } catch (e) {
        debugPrint('[AppSettings] $uri failed: $e');
      }
    }
    return null;
  }
}
