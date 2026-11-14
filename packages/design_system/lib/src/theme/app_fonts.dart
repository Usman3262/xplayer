import 'package:flutter/widgets.dart';

/// Arabic typography (client 17 Oct): IBM Plex Sans Arabic, bundled with the
/// app (no download at runtime), the same on TV, Android and iPhone.
/// Latin text keeps the platform font; Arabic glyphs fall back to Plex.
///
/// Weights in Arabic: Regular 400 for descriptions and supporting text,
/// Medium 500 for navigation, menus and buttons, SemiBold 600 for headings.
/// Only those three files are bundled, so any heavier weight in the code
/// (700-900) renders as SemiBold; nothing renders thin or decorative.
abstract final class AppFonts {
  static const arabicFamily = 'packages/design_system/IBMPlexSansArabic';
  /// Weekly-picks rank digits — Playfair Display Black (serif, client mockup).
  static const rankFamily = 'packages/design_system/PlayfairDisplay';
  /// Ranked-row numbers as on LG (client 4 Nov) — Bebas Neue.
  static const rankLgFamily = 'packages/design_system/BebasNeue';
  /// 'sans-serif' first: on Android 16 the theme's 'Roboto' does not
  /// resolve, and Latin text would otherwise fall through to Plex (its
  /// Latin letters). The system sans has no Arabic, so Arabic goes to Plex.
  /// On iOS the theme's system font resolves before this list.
  static const fallback = <String>['sans-serif', arabicFamily];

  /// Set by the app theme for the current interface language.
  static bool arabicUi = false;

  /// Navigation, menus, buttons: Medium 500 in Arabic, [latin] otherwise.
  static FontWeight control(FontWeight latin) =>
      arabicUi ? FontWeight.w500 : latin;

  /// Headings and section titles: SemiBold 600 in Arabic.
  static FontWeight heading(FontWeight latin) =>
      arabicUi ? FontWeight.w600 : latin;
}
