import 'package:flutter/material.dart';

/// A warm, food-forward palette. Green reads as "healthy" without the clinical
/// feel of a medical app, and the amber accent picks up turmeric/spice tones.
const _seed = Color(0xFF2E7D52);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Colour used for a nutrient depending on how close it is to target.
///
/// With [overIsFine] — protein, fibre, iron, calcium — going over is shown as
/// good, not as a warning: only falling short of those is a problem.
Color nutrientStatusColor(ColorScheme scheme, double ratio,
    {bool overIsFine = false}) {
  final good = scheme.brightness == Brightness.dark
      ? const Color(0xFF6FCF97)
      : const Color(0xFF2E7D52);
  if (ratio < 0.85) return scheme.error;
  if (ratio < 0.95) return const Color(0xFFE08A00);
  if (ratio <= 1.25 || overIsFine) return good;
  return const Color(0xFFE08A00);
}
