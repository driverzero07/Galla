import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';

ThemeData buildGallaTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: GallaColors.ink,
    onPrimary: GallaColors.lime,
    secondary: GallaColors.lime,
    onSecondary: GallaColors.ink,
    error: GallaColors.danger,
    onError: Colors.white,
    surface: GallaColors.card,
    onSurface: GallaColors.ink,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: GallaRadius.card,
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: GallaColors.background,
    fontFamily: GallaFonts.body,
    textTheme: const TextTheme(
      displayLarge: GallaText.bigNumber,
      headlineMedium: GallaText.heading,
      titleLarge: GallaText.heading,
      titleMedium: GallaText.bodyMedium,
      bodyLarge: GallaText.body,
      bodyMedium: GallaText.body,
      bodySmall: GallaText.caption,
      labelLarge: GallaText.buttonLabel,
    ),
    splashFactory: InkRipple.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GallaColors.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: GallaRadius.card,
        borderSide: const BorderSide(color: GallaColors.ink, width: 2),
      ),
      hintStyle: GallaText.body.copyWith(color: GallaColors.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GallaColors.ink,
      contentTextStyle: GallaText.body.copyWith(color: GallaColors.lime),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: GallaRadius.card),
    ),
    dividerTheme: DividerThemeData(
      color: GallaColors.ink.withValues(alpha: 0.08),
      thickness: 1,
      space: 1,
    ),
  );
}
