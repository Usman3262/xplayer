import 'dart:convert';
import 'package:domain/domain.dart' show AppBrand;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../security/config_keys.dart';
import 'api_config.dart';
import 'json_read.dart';
import 'notifications_api.dart' show compareAppVersions, isAppVersionNewer;

export 'notifications_api.dart' show compareAppVersions, isAppVersionNewer;

/// One published build from `GET /v1/app/version` (backend 20 Oct 2026).
class AppReleaseBuildDto {
  const AppReleaseBuildDto({
    required this.id,
    required this.platform,
    required this.version,
    this.downloadUrl,
    this.latestUrl,
    this.sha256,
    this.sizeBytes,
  });

  final String id;
  final String platform;
  final String version;
  final String? downloadUrl;
  final String? latestUrl;
  final String? sha256;
  final int? sizeBytes;

  factory AppReleaseBuildDto.fromJson(Map<String, dynamic> json) {
    return AppReleaseBuildDto(
      id: jsonStr(json['id']) ?? '',
      platform: jsonStr(json['platform']) ?? '',
      version: jsonStr(json['version']) ?? '',
      downloadUrl: _absolute(jsonStr(json['downloadUrl']) ??
          jsonStr(json['downloadPath']) ??
          jsonStr(json['file'])),
      latestUrl: _absolute(jsonStr(json['latestUrl'])),
      sha256: jsonStr(json['sha256']),
      sizeBytes: jsonInt(json['sizeBytes']),
    );
  }

  /// releases.json lists paths relative to the download host ("tv.apk").
  static String? _absolute(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty) return null;
    if (v.contains('://')) return v;
    return '${AppReleaseUrls.installPage}/${v.replaceAll(RegExp(r'^/+'), '')}';
  }

  /// Direct APK link (versioned file first, then the permanent link) — never a store page.
  String? get apkUrl {
    for (final u in [downloadUrl, latestUrl]) {
      if (u != null && u.toLowerCase().split('?').first.endsWith('.apk')) return u;
    }
    return null;
  }

  bool get isTv {
    final p = platform.toLowerCase();
    final i = id.toLowerCase();
    return p.contains('tv') || i.contains('tv');
  }

  /// iPhone entry (App Store / TestFlight link), client 23 Oct.
  bool get isIos {
    final p = platform.toLowerCase();
    final i = id.toLowerCase();
    return p.contains('ios') || p.contains('iphone') || i.contains('ios');
  }

  bool get isMobile {
    final p = platform.toLowerCase();
    final i = id.toLowerCase();
    return !isTv &&
        !isIos &&
        (p.contains('android') ||
            p.contains('mobile') ||
            p.contains('phone') ||
            i.contains('mobile') ||
            i.contains('android'));
  }
}

class AppVersionDto {
  const AppVersionDto({
    this.minVersionMobile,
    this.minVersionTv,
    this.minVersionIos,
    this.builds = const [],
  });

  final String? minVersionMobile;
  final String? minVersionTv;
  final String? minVersionIos;
  final List<AppReleaseBuildDto> builds;

  factory AppVersionDto.fromJson(Map<String, dynamic> json) {
    final min = json['minVersion'];
    String? mobile;
    String? tv;
    String? ios;
    if (min is Map) {
      mobile = jsonStr(min['mobile']);
      tv = jsonStr(min['tv']);
      ios = jsonStr(min['ios']);
    }
    final builds = <AppReleaseBuildDto>[];
    final raw = json['builds'];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          builds.add(
            AppReleaseBuildDto.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    return AppVersionDto(
      minVersionMobile: mobile,
      minVersionTv: tv,
      minVersionIos: ios,
      builds: builds,
    );
  }

  AppReleaseBuildDto? buildFor({required bool tv, bool ios = false}) {
    for (final b in builds) {
      if (ios ? b.isIos : tv ? b.isTv : b.isMobile) return b;
    }
    return null;
  }

  String? minFor({required bool tv, bool ios = false}) =>
      ios ? minVersionIos : tv ? minVersionTv : minVersionMobile;
}

/// Public update check — no auth.
class AppVersionApi {
  AppVersionApi({http.Client? client, this.apiBase})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final String? apiBase;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<AppVersionDto?> fetch() async {
    final bases = <String>[
      if (apiBase != null && apiBase!.isNotEmpty) apiBase!,
      ApiConfig.defaultBaseUrl,
      ...ApiConfig.builtInBackupBaseUrls,
    ];
    for (final base in bases.where((b) => b.trim().isNotEmpty)) {
      final uri =
          Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/app/version');
      try {
        final res = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body);
        final data = body is Map && body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : body is Map
                ? Map<String, dynamic>.from(body)
                : null;
        if (data == null) continue;
        return AppVersionDto.fromJson(data);
      } catch (e) {
        debugPrint('[AppVersion] $uri failed: $e');
      }
    }
    // Static copy of the same list (only when a releases URL is set).
    if (AppReleaseUrls.releasesJson.isNotEmpty) try {
      final res = await _client
          .get(
            Uri.parse(AppReleaseUrls.releasesJson),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map) {
          return AppVersionDto.fromJson(Map<String, dynamic>.from(body));
        }
      }
    } catch (e) {
      debugPrint('[AppVersion] releases.json failed: $e');
    }
    return null;
  }
}

/// Result used by splash / update screens.
class AppUpdateGate {
  const AppUpdateGate({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.required,
    required this.offerUpdate,
    this.updateUrl,
    this.apkUrl,
    this.sha256,
    this.message =
        'A new version of the app is available. Please update to continue.',
  });

  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final bool required;
  final bool offerUpdate;
  final String? updateUrl;

  /// Direct APK for the in-app installer (Android sideload); [sha256] belongs to it.
  final String? apkUrl;
  final String? sha256;
  final String message;
}

/// Resolve force / optional update for the running app.
AppUpdateGate resolveAppUpdateGate({
  required String installedVersion,
  required int installedBuild,
  required bool isTv,
  AppVersionDto? remote,
  bool isIos = false,
}) {
  final installedLabel = installedBuild > 0
      ? '$installedVersion+$installedBuild'
      : installedVersion;
  final permanent =
      isTv ? AppReleaseUrls.tvApk : AppReleaseUrls.mobileApk;

  if (remote == null) {
    return AppUpdateGate(
      currentVersion: installedVersion,
      currentBuild: installedBuild,
      latestVersion: installedVersion,
      required: false,
      offerUpdate: false,
      updateUrl: permanent,
      apkUrl: isIos ? null : permanent,
    );
  }

  final minRaw = remote.minFor(tv: isTv, ios: isIos);
  final build = remote.buildFor(tv: isTv, ios: isIos);
  final latest = (build?.version ?? '').trim();
  // iPhone: only its own store link, never an Android APK.
  final url = isIos
      ? (build?.latestUrl ?? build?.downloadUrl)
      : build?.latestUrl ?? build?.downloadUrl ?? permanent;
  final apk = isIos ? null : (build?.apkUrl ?? permanent);
  // sha256 of the published build (a mismatch falls back to the link).
  final sha = build?.apkUrl != null ? build?.sha256 : null;

  final force = minRaw != null &&
      minRaw.trim().isNotEmpty &&
      compareAppVersions(installedLabel, minRaw.trim()) < 0;

  final optional = latest.isNotEmpty &&
      (url ?? '').isNotEmpty &&
      isAppVersionNewer(latest, installedLabel);

  return AppUpdateGate(
    currentVersion: installedVersion,
    currentBuild: installedBuild,
    latestVersion: latest.isNotEmpty ? latest : installedVersion,
    required: force,
    offerUpdate: force || optional,
    updateUrl: url,
    apkUrl: apk,
    sha256: sha,
    message: force
        ? 'Please update ${AppBrand.name} to continue.'
        : 'A new version of ${AppBrand.name} ($latest) is available.',
  );
}
