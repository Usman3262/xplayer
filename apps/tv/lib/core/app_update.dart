import 'package:data/data.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'remote_config.dart';

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
  // Rules come from the admin panel (App customization → Versions), via the
  // published app config. A short wait lets a just-published rule apply.
  final info = await PackageInfo.fromPlatform();
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  await RemoteConfigService.refresh().timeout(const Duration(seconds: 3), onTimeout: () => false);
  final policy = RemoteConfigService.current.versionPolicy;
  final need = policy?.check(info.version) ?? UpdateRequirement.none;
  final url = (policy?.updateUrl ?? '').trim();
  return AppUpdateInfo(
    currentVersion: info.version,
    currentBuild: currentBuild,
    minBuild: need == UpdateRequirement.required ? currentBuild + 1 : 0,
    latestVersion: policy?.latest ?? policy?.recommended ?? policy?.min ?? info.version,
    message: policy?.notes ?? '',
    updateUrl: url.isEmpty ? null : url,
    required: need == UpdateRequirement.required,
    offerUpdate: need == UpdateRequirement.recommended && url.isNotEmpty,
    apkUrl: url.toLowerCase().endsWith('.apk') ? url : null,
  );
}
