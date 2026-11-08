import 'package:flutter/material.dart';

/// Markenfarben von Volti.
class VoltiColors {
  /// Terrakotta aus der Bildmarke.
  static const terracotta = Color(0xFFB5593A);

  /// Hintergrund rund um die Notenseite – neutral, damit die Noten im
  /// Vordergrund stehen.
  static Color pageSurround(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1D1C) : const Color(0xFFE9E6E2);
}

ThemeData buildVoltiTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: VoltiColors.terracotta,
    brightness: brightness,
  ).copyWith(primary: brightness == Brightness.light ? VoltiColors.terracotta : const Color(0xFFE08A6C));
  return ThemeData(colorScheme: scheme, useMaterial3: true, visualDensity: VisualDensity.standard);
}
