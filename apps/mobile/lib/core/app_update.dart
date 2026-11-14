import 'dart:io' show Platform;

import 'package:data/data.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-app update gate (force via minVersion, optional via builds[].version).
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.minBuild,
    required this.latestVersion,
    required this.message,
    required this.updateUrl,
    required this.required,
    this.offerUpdate = false,
    this.apkUrl,
    this.sha256,
  });

  final String currentVersion;
  final int currentBuild;

  /// Legacy field for older push handlers; prefer [required] + semver.
  final int minBuild;
  final String latestVersion;
  final String message;
  final String? updateUrl;
  final bool required;

  /// A newer build is published (optional "Update available", client 23 Oct).
  final bool offerUpdate;

  /// Direct APK for the in-app installer (sideloaded Android / Fire TV).
  final String? apkUrl;
  final String? sha256;
}

Future<AppUpdateInfo> checkAppUpdate({bool isTv = false}) async {
  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final api = AppVersionApi();
  try {
    final remote = await api.fetch();
    final ios = !isTv && Platform.isIOS;
    final gate = resolveAppUpdateGate(
      installedVersion: info.version,
      installedBuild: currentBuild,
      isTv: isTv,
      isIos: ios,
      remote: remote,
    );
    return AppUpdateInfo(
      currentVersion: gate.currentVersion,
      currentBuild: gate.currentBuild,
      minBuild: gate.required ? currentBuild + 1 : 0,
      latestVersion: gate.latestVersion,
      message: gate.message,
      updateUrl: gate.updateUrl ??
          (ios ? null : isTv ? AppReleaseUrls.tvApk : AppReleaseUrls.mobileApk),
      // iPhone without its own store link: never send it to an APK.
      required: gate.required && (!ios || (gate.updateUrl ?? '').isNotEmpty),
      offerUpdate: gate.offerUpdate,
      apkUrl: gate.apkUrl,
      sha256: gate.sha256,
    );
  } finally {
    api.close();
  }
}

/// Permanent APK link for this app (TV Downloader / update button).
String permanentApkUrl({required bool isTv}) =>
    isTv ? AppReleaseUrls.tvApk : AppReleaseUrls.mobileApk;
