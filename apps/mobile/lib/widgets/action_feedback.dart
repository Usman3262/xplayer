import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Themed alerts / confirms / toasts for security & account actions.
/// Delegates to [AppAlerts] so snackbars include title + message (not icon-only).
///
/// Pass localized [title], [message], [confirmLabel], and [cancelLabel] from
/// [AppCopy] at call sites. Defaults for confirm/cancel/snack titles remain
/// English when omitted.
class ActionFeedback {
  ActionFeedback._();

  static String clean(Object error) => AppAlerts.clean(error);

  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      AppAlerts.success(context, title: title, message: message);

  static Future<void> error(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      AppAlerts.failure(context, title: title, message: message);

  static Future<void> warning(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      AppAlerts.warning(context, title: title, message: message);

  static Future<void> attention(
    BuildContext context, {
    required String title,
    required String message,
  }) =>
      AppAlerts.attention(context, title: title, message: message);

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) =>
      AppAlerts.confirm(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      );

  /// Prefer [toast] with title+message. Kept for call-site compatibility.
  static void snack(
    BuildContext context, {
    required String message,
    bool error = false,
    String? title,
  }) {
    if (error) {
      AppAlerts.toastFailure(
        context,
        title: title ?? AppCopy.ofContext(context).alertFailedTitle,
        message: message,
      );
    } else {
      AppAlerts.toastSuccess(
        context,
        title: title ?? AppCopy.ofContext(context).alertSuccessTitle,
        message: message,
      );
    }
  }

  static void toast(
    BuildContext context, {
    required AppAlertTone tone,
    required String title,
    required String message,
  }) =>
      AppAlerts.toast(
        context,
        tone: tone,
        title: title,
        message: message,
      );
}
