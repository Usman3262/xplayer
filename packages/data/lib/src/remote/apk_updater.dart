import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'apk_sha256.dart';

enum AppUpdateOutcome {
  /// Installed from Google Play: the Play Store page was opened.
  openedStore,

  /// APK downloaded and verified; the system installer is showing.
  installerOpened,

  /// Android asked the user to allow installs from APP 4K first.
  needsPermission,

  /// Not possible in-app (iOS, no channel, download/verify failed).
  failed,
}

/// In-app update without a browser: Play installs go to Play, sideloaded
/// installs (Downloader code, Fire TV, Control Panel links) download the APK,
/// verify its sha256 and open the system installer.
class ApkUpdater {
  static const _ch = MethodChannel('app/app_update');
  static const playStorePackage = 'com.android.vending';

  static Future<String?> installerPackage() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('installerPackage');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> installedFromPlay() async =>
      await installerPackage() == playStorePackage;

  /// Google Play (and its services) exist on this device — false on Fire TV.
  static Future<bool> hasGooglePlay() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('hasPackage', {'id': playStorePackage}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<AppUpdateOutcome> update({
    required String apkUrl,
    String? sha256,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (!Platform.isAndroid) return AppUpdateOutcome.failed;
    try {
      if (await installedFromPlay()) {
        final ok = await _ch.invokeMethod<bool>('openStore') ?? false;
        return ok ? AppUpdateOutcome.openedStore : AppUpdateOutcome.failed;
      }
      final can = await _ch.invokeMethod<bool>('canInstall') ?? false;
      if (!can) {
        await _ch.invokeMethod<bool>('openInstallSettings');
        return AppUpdateOutcome.needsPermission;
      }
      final dir = await _ch.invokeMethod<String>('updatesDir');
      if (dir == null) return AppUpdateOutcome.failed;
      final dest = File('$dir/app-update.apk');
      if (dest.existsSync()) dest.deleteSync();
      await downloadApkVerified(
        url: apkUrl,
        dest: dest,
        expectedSha256: sha256,
        onProgress: onProgress,
      );
      final ok = await _ch.invokeMethod<bool>('installApk', {'path': dest.path}) ?? false;
      return ok ? AppUpdateOutcome.installerOpened : AppUpdateOutcome.failed;
    } catch (e) {
      debugPrint('[ApkUpdater] $e');
      return AppUpdateOutcome.failed;
    }
  }
}
