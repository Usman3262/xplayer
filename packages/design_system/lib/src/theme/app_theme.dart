import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

/// [arabic]: the interface language is Arabic (button / menu weights).
ThemeData buildAppTheme({bool arabic = false}) {
  AppFonts.arabicUi = arabic;
  final control = WidgetStatePropertyAll(
    TextStyle(fontWeight: AppFonts.control(FontWeight.w700)),
  );
  final scheme = ColorScheme.dark(
    surface: AppColors.surface,
    primary: AppColors.cyan,
    secondary: AppColors.magenta,
    error: AppColors.danger,
    onPrimary: Colors.black,
    onSecondary: Colors.white,
    onSurface: AppColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    // Arabic text in every language (titles from the provider too).
    fontFamilyFallback: AppFonts.fallback,
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(textStyle: control),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(textStyle: control),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(textStyle: control),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(textStyle: control),
    ),
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      centerTitle: false,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: TextStyle(color: AppColors.textPrimary, height: 1.35),
      bodyMedium: TextStyle(color: AppColors.textSecondary, height: 1.35),
      labelLarge: TextStyle(
        fontWeight: AppFonts.control(FontWeight.w700),
        letterSpacing: 0.2,
        color: AppColors.textPrimary,
      ),
    ),
    dividerColor: AppColors.border,
    splashFactory: InkSparkle.splashFactory,
  );
}
