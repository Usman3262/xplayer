import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Themed alerts for TV security actions (D-pad friendly dialogs).
class TvActionFeedback {
  TvActionFeedback._();

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
