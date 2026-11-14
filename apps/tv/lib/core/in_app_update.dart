import 'dart:io' show Platform;

import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';

/// Update button action: Play installs open Play; sideloaded installs download
/// the APK with progress and open the installer; the link is the last resort.
Future<void> runInAppUpdate(BuildContext context, AppUpdateInfo info) async {
  final fallback = (info.updateUrl ?? AppReleaseUrls.tvApk).trim();
  final apk = (info.apkUrl ?? AppReleaseUrls.tvApk).trim();
  if (Platform.isAndroid && apk.isNotEmpty) {
    final progress = ValueNotifier<double?>(null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = AppCopy.ofContext(context);
    var dialogOpen = false;
    if (!await ApkUpdater.installedFromPlay() && context.mounted) {
      dialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1F2A),
            title: Text(copy.updateDownloading,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            content: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, v, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: v, color: AppColors.cyan),
                  const SizedBox(height: 12),
                  Text(v == null ? copy.updateStarting : '${(v * 100).round()} %',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final outcome = await ApkUpdater.update(
      apkUrl: apk,
      sha256: info.sha256,
      onProgress: (r, t) => progress.value = t != null && t > 0 ? r / t : null,
    );
    if (dialogOpen && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    switch (outcome) {
      case AppUpdateOutcome.openedStore:
      case AppUpdateOutcome.installerOpened:
        return;
      case AppUpdateOutcome.needsPermission:
        messenger?.showSnackBar(SnackBar(content: Text(copy.updateAllowInstall)));
        return;
      case AppUpdateOutcome.failed:
        break;
    }
  }
  final uri = Uri.tryParse(fallback);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}
