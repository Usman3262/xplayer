import 'package:data/data.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// TV update gate — same contract as mobile ([AppUpdateInfo]).
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
  final int minBuild;
  final String latestVersion;
  final String message;
  final String? updateUrl;
  final bool required;

  /// A newer build is published (optional update, client 23 Oct).
  final bool offerUpdate;

  /// Direct APK for the in-app installer (sideloaded Android / Fire TV).
  final String? apkUrl;
  final String? sha256;
}

Future<AppUpdateInfo> checkAppUpdate() async {
  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final api = AppVersionApi();
  try {
    final remote = await api.fetch();
    final gate = resolveAppUpdateGate(
      installedVersion: info.version,
      installedBuild: currentBuild,
      isTv: true,
      remote: remote,
    );
    return AppUpdateInfo(
      currentVersion: gate.currentVersion,
      currentBuild: gate.currentBuild,
      minBuild: gate.required ? currentBuild + 1 : 0,
      latestVersion: gate.latestVersion,
      message: gate.message,
      updateUrl: gate.updateUrl ?? AppReleaseUrls.tvApk,
      required: gate.required,
      offerUpdate: gate.offerUpdate,
      apkUrl: gate.apkUrl,
      sha256: gate.sha256,
    );
  } finally {
    api.close();
  }
}
