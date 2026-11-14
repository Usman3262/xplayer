import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/in_app_update.dart';
import '../../core/session_controller.dart';

/// Blocking update gate when [AppUpdateInfo.required] (minVersion).
class UpdateAppScreen extends ConsumerWidget {
  const UpdateAppScreen({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(sessionProvider).language);
    final info = ref.watch(pendingUpdateProvider) ??
        AppUpdateInfo(
          currentVersion: '?',
          currentBuild: 0,
          minBuild: 1,
          latestVersion: '',
          message: copy.updateRequiredBody,
          updateUrl: AppReleaseUrls.mobileApk,
          required: true,
        );

    // An optional update can be left (Later / Back). Opened from a
    // notification it is the only page, so leaving goes Home (Back used to
    // close the app).
    void leave() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }

    return PopScope(
      canPop: !info.required && context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !info.required) leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppLogo(height: 72, alignToStart: true),
                ),
                const SizedBox(height: 28),
                Text(
                  copy.updateAppTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  info.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  copy.updateInstalledLine(
                    info.currentVersion,
                    info.currentBuild,
                    info.latestVersion.isNotEmpty ? info.latestVersion : '—',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: copy.updateAppTitle,
                  icon: Icons.system_update_alt_rounded,
                  onPressed: () => runInAppUpdate(context, info, isTv: false),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AppReleaseUrls.installPage),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    copy.updateOpenDownloadPage,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                if (!info.required)
                  TextButton(
                    onPressed: leave,
                    child: Text(
                      copy.updateLater,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  AppLegalCopy.copyright(copy.lang),
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
