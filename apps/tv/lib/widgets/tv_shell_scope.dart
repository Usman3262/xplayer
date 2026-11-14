import 'package:flutter/material.dart';

/// Lets content tiles hand focus to the top TV nav, and nav hand focus back
/// into the page body (rails / chips).
class TvShellScope extends InheritedWidget {
  const TvShellScope({
    super.key,
    required this.focusSidebar,
    required this.focusContent,
    required super.child,
  });

  final VoidCallback focusSidebar;
  final VoidCallback focusContent;

  static TvShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvShellScope>();
  }

  @override
  bool updateShouldNotify(TvShellScope oldWidget) =>
      focusSidebar != oldWidget.focusSidebar ||
      focusContent != oldWidget.focusContent;
}
