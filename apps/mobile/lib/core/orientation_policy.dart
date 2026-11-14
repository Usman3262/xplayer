import 'dart:ui';

import 'package:flutter/services.dart';

/// Orientations allowed outside the player (iPhone, 17 Oct): leaving a
/// landscape movie released every orientation, so with the phone still on
/// its side the screen underneath turned to landscape and back. On phones
/// only the player rotates; tablets keep free rotation.
List<DeviceOrientation> appOrientations() {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return const [DeviceOrientation.portraitUp];
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  final shortest = size.shortestSide;
  if (shortest >= 600) return DeviceOrientation.values;
  return const [DeviceOrientation.portraitUp];
}

void applyAppOrientations() =>
    SystemChrome.setPreferredOrientations(appOrientations());
