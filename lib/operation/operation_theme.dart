import 'package:flutter/material.dart';

/// Approved E1 palette. Status colors are always paired with text or an icon.
abstract final class OperationPalette {
  static const Color background = Color(0xFF111827);
  static const Color panel = Color(0xFF1F2937);
  static const Color accent = Color(0xFFF59E0B);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color foreground = Color(0xFFF9FAFB);
}

/// Theme for the operational route.
///
/// Amber actions deliberately use the dark background color as foreground;
/// success and error remain accents around light text instead of becoming
/// color-only status signals.
ThemeData buildOperationTheme() {
  const colorScheme = ColorScheme.dark(
    primary: OperationPalette.accent,
    onPrimary: OperationPalette.background,
    secondary: OperationPalette.success,
    onSecondary: OperationPalette.background,
    error: OperationPalette.error,
    onError: OperationPalette.background,
    surface: OperationPalette.panel,
    onSurface: OperationPalette.foreground,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OperationPalette.background,
    cardColor: OperationPalette.panel,
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: OperationPalette.foreground,
          displayColor: OperationPalette.foreground,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: OperationPalette.background,
      foregroundColor: OperationPalette.foreground,
      elevation: 0,
    ),
    cardTheme: const CardTheme(
      color: OperationPalette.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? OperationPalette.panel
              : OperationPalette.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? OperationPalette.foreground
              : OperationPalette.background,
        ),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OperationPalette.accent,
      linearTrackColor: OperationPalette.panel,
    ),
  );
}
