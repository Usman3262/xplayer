import 'package:flutter/material.dart';

import '../locale/app_locale.dart';
import '../theme/app_colors.dart';

enum AppAlertTone { success, failure, warning, attention }

/// Advanced branded alerts: dialogs + floating toasts with title + message.
class AppAlerts {
  AppAlerts._();

  static String clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  static Color colorFor(AppAlertTone tone) => switch (tone) {
        AppAlertTone.success => AppColors.match,
        AppAlertTone.failure => AppColors.danger,
        AppAlertTone.warning => AppColors.gold,
        AppAlertTone.attention => AppColors.cyan,
      };

  static IconData iconFor(AppAlertTone tone) => switch (tone) {
        AppAlertTone.success => Icons.check_circle_rounded,
        AppAlertTone.failure => Icons.error_outline_rounded,
        AppAlertTone.warning => Icons.warning_amber_rounded,
        AppAlertTone.attention => Icons.info_outline_rounded,
      };

  static String labelFor(AppAlertTone tone) => switch (tone) {
        AppAlertTone.success => 'SUCCESS',
        AppAlertTone.failure => 'FAILED',
        AppAlertTone.warning => 'WARNING',
        AppAlertTone.attention => 'ATTENTION',
      };

  /// [labelFor] in the screen's language (Arabic showed "FAILED").
  static String localLabelFor(BuildContext context, AppAlertTone tone) {
    final copy = AppCopy.ofContext(context);
    return switch (tone) {
      AppAlertTone.success => copy.alertSuccess,
      AppAlertTone.failure => copy.alertFailed,
      AppAlertTone.warning => copy.alertWarning,
      AppAlertTone.attention => copy.alertAttention,
    };
  }

  static Future<void> show(
    BuildContext context, {
    required AppAlertTone tone,
    required String title,
    required String message,
    String? primaryLabel,
  }) {
    final accent = colorFor(tone);
    // Default buttons in the screen's language (they were English).
    final copy = AppCopy.ofContext(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _AlertCard(
          tone: tone,
          title: title,
          message: message,
          accent: accent,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor:
                    tone == AppAlertTone.failure ? Colors.white : Colors.black,
                minimumSize: const Size(120, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                primaryLabel ?? copy.ok,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      show(
        context,
        tone: AppAlertTone.success,
        title: title,
        message: message,
      );

  static Future<void> failure(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      show(
        context,
        tone: AppAlertTone.failure,
        title: title,
        message: message,
      );

  static Future<void> warning(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      show(
        context,
        tone: AppAlertTone.warning,
        title: title,
        message: message,
      );

  static Future<void> attention(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      show(
        context,
        tone: AppAlertTone.attention,
        title: title,
        message: message,
      );

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
    AppAlertTone tone = AppAlertTone.attention,
  }) async {
    final copy = AppCopy.ofContext(context);
    final effective = destructive ? AppAlertTone.failure : tone;
    final accent = colorFor(effective);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _AlertCard(
          tone: effective,
          // Destructive confirms use the red style, but nothing has failed
          // ("FAILED" showed on "Sign out?", 19 Oct).
          label: destructive ? copy.alertConfirm : null,
          title: title,
          message: message,
          accent: accent,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                cancelLabel ?? copy.cancel,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor:
                    destructive ? Colors.white : Colors.black,
                minimumSize: const Size(120, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                confirmLabel ?? copy.confirm,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  /// Floating toast with **badge + title + message** (not icon-only).
  static void toast(
    BuildContext context, {
    required AppAlertTone tone,
    required String title,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    final accent = colorFor(tone);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: _ToastCard(
          tone: tone,
          title: title,
          message: message,
          accent: accent,
        ),
      ),
    );
  }

  static void toastSuccess(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      toast(
        context,
        tone: AppAlertTone.success,
        title: title,
        message: message,
      );

  static void toastFailure(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      toast(
        context,
        tone: AppAlertTone.failure,
        title: title,
        message: message,
      );

  static void toastWarning(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      toast(
        context,
        tone: AppAlertTone.warning,
        title: title,
        message: message,
      );

  static void toastAttention(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      toast(
        context,
        tone: AppAlertTone.attention,
        title: title,
        message: message,
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.tone,
    required this.title,
    required this.message,
    required this.accent,
    required this.actions,
    this.label,
  });

  final AppAlertTone tone;
  final String title;
  final String message;
  final Color accent;
  final List<Widget> actions;

  /// Badge text; defaults to the tone's label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: const Color(0xFF0E121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.2),
                  accent,
                  accent.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(
                    AppAlerts.iconFor(tone),
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label ?? AppAlerts.localLabelFor(context, tone),
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.tone,
    required this.title,
    required this.message,
    required this.accent,
  });

  final AppAlertTone tone;
  final String title;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111622),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(AppAlerts.iconFor(tone), color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        AppAlerts.localLabelFor(context, tone),
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
