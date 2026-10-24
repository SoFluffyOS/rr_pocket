import 'package:flutter/material.dart';

abstract final class RrColors {
  /// The icon's background, also in android/.../values/colors.xml.
  static const slate = Color(0xFF1F2933);
  static const amber = Color(0xFFFFB547);
}

ThemeData rrTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: RrColors.slate,
    brightness: brightness,
  ).copyWith(tertiary: RrColors.amber);
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Nunito',
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.secondaryContainer,
      labelStyle: TextStyle(
        color: scheme.onSecondaryContainer,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
