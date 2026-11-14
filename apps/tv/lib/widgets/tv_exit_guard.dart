import 'package:data/data.dart' show TvPlatformProfile;
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/tv_demo_mode.dart';
import '../core/tv_locale.dart';
import 'tv_ui.dart';

bool _exitDialogOpen = false;
DateTime? _exitDialogClosedAt;

/// Tests only: forget the open/just-closed state between test cases.
@visibleForTesting
void resetTvExitDialogGuard() {
  _exitDialogOpen = false;
  _exitDialogClosedAt = null;
}

/// "Exit the app?" with Cancel focused first. Closes the app on Exit.
///
/// TV buttons (cyan focus ring, OK/Select via ActivateIntent) instead of
/// Material Text/FilledButton, whose focus highlight was barely visible on the
/// TV. Cancel, Back and Exit all close the dialog; focus returns to where it
/// was. A second Back delivered right after closing (key event + system back)
/// no longer reopens the dialog.
Future<void> confirmTvExit(BuildContext context, WidgetRef ref) async {
  // Demo: Back on Home leaves the demo for the sign-in screen, not the app.
  if (ref.read(tvDemoModeProvider)) {
    ref.read(tvDemoModeProvider.notifier).state = false;
    context.go('/login');
    return;
  }
  if (_exitDialogOpen) return;
  final closedAt = _exitDialogClosedAt;
  if (closedAt != null &&
      DateTime.now().difference(closedAt) < const Duration(milliseconds: 500)) {
    return;
  }
  _exitDialogOpen = true;
  final copy = AppCopy.ofLanguage(ref.read(tvLanguageProvider));
  bool? leave;
  try {
    leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1F2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.exitAppTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.exitAppMessage,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TvButton(
                        autofocus: true,
                        label: copy.cancel,
                        onTap: () => Navigator.of(ctx).pop(false),
                      ),
                      const SizedBox(width: TvUi.buttonGap),
                      TvButton(
                        primary: true,
                        icon: Icons.power_settings_new_rounded,
                        label: copy.exitAppConfirm,
                        onTap: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } finally {
    _exitDialogOpen = false;
    _exitDialogClosedAt = DateTime.now();
  }
  if (leave == true) {
    final exit = TvPlatformProfile.exitApp;
    if (exit != null) {
      exit();
    } else {
      SystemNavigator.pop();
    }
  }
}

/// For screens outside the main shell (login, profiles): Back goes to the
/// previous page when there is one, otherwise asks before closing the app.
/// Before, Back on these screens closed the app at once.
class TvExitGuard extends ConsumerWidget {
  const TvExitGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
          return;
        }
        confirmTvExit(context, ref);
      },
      child: child,
    );
  }
}
