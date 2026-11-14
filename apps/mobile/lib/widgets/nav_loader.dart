import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Shows [AppLoader.page] while [action] runs, then dismisses the overlay.
Future<T> withPageLoader<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final label = '${AppCopy.ofContext(context).loading}…';
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Loading',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, __, ___) => Material(
      type: MaterialType.transparency,
      child: Center(child: AppLoader.page(label: label)),
    ),
  );
  try {
    return await action();
  } finally {
    if (nav.mounted && nav.canPop()) nav.pop();
  }
}
