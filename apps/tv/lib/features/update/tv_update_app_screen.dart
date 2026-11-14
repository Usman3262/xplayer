import 'package:data/data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_update.dart';
import '../../core/app_update_provider.dart';
import '../../core/in_app_update.dart';
import '../../core/tv_locale.dart';
import '../../widgets/tv_ui.dart';

/// Blocking TV update gate when minVersion.tv forces an update.
class TvUpdateAppScreen extends ConsumerWidget {
  const TvUpdateAppScreen({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = AppCopy.ofLanguage(ref.watch(tvLanguageProvider));
    final info = ref.watch(pendingUpdateProvider) ??
        AppUpdateInfo(
          currentVersion: '?',
          currentBuild: 0,
          minBuild: 1,
          latestVersion: '',
          message: copy.updateRequiredBody,
          updateUrl: AppReleaseUrls.tvApk,
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
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppLogo(height: 80),
                  const SizedBox(height: 32),
                  Text(
                    copy.updateAppTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    info.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                      fontSize: 16,
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
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 36),
                  // The focus on the button itself: on the wrapper around it
                  // the remote's OK reached nothing.
                  PrimaryButton(
                    autofocus: true,
                    label: copy.updateAppTitle,
                    icon: Icons.system_update_alt_rounded,
                    onPressed: () => runInAppUpdate(context, info),
                  ),
                  if (!info.required) ...[
                    const SizedBox(height: 12),
                    TvButton(label: copy.updateLater, onTap: leave),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    copy.updateDownloaderHint(AppReleaseUrls.tvApk),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
