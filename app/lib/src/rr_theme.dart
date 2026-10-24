import 'package:flutter/widgets.dart';
import 'package:sofluffy_ui/sofluffy_ui.dart';

abstract final class RrColors {
  /// The icon's background, also in android/.../values/colors.xml.
  static const slate = Color(0xFF1F2933);
  static const amber = Color(0xFFFFB547);
}

FluffyThemeData rrTheme(Brightness brightness) {
  final fallback = FluffyThemeData.fallback(brightness: brightness);
  return fallback.copyWith(
    colors: fallback.colors.copyWith(
      primary: RrColors.amber,
      secondary: RrColors.slate,
    ),
    typography: fallback.typography.copyWith(fontFamily: 'Nunito'),
  );
}

extension RrThemeColors on FluffyThemeData {
  Color get background => switch (isDark) {
    true => colors.neutral7,
    false => colors.neutral1,
  };

  Color get muted => colors.neutral5;
}
