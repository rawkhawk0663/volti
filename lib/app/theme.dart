import 'package:flutter/material.dart';

/// Markenfarben von Volti: frisches Seegrün/Türkis.
class VoltiColors {
  /// Seegrün – die Markenfarbe (Logo, Verläufe, Akzente).
  static const seafoam = Color(0xFF3BA796);

  /// Tieferes Türkis für Knöpfe mit weisser Schrift (gut lesbar auf Weiss).
  static const deep = Color(0xFF1A8070);

  /// Helles Türkis für den Dunkelmodus.
  static const light = Color(0xFF5CC8B4);

  /// Hintergrund rund um die Notenseite – ruhig und leicht kühl, damit die
  /// Noten im Vordergrund stehen.
  static Color pageSurround(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A201F) : const Color(0xFFE6ECEA);

  /// Ganz sanfter Verlauf als Hintergrund der Bibliothek.
  static LinearGradient backgroundGradient(Brightness b) => b == Brightness.dark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17201E), Color(0xFF121816)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4FBF9), Color(0xFFE3F2EE)],
        );

  /// Leichter Verlauf für Leisten (Werkzeugleiste, Navigation).
  static LinearGradient barGradient(Brightness b) => b == Brightness.dark
      ? const LinearGradient(colors: [Color(0xFF1D2826), Color(0xFF1A2422)])
      : const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFEDF7F4)]);
}

ThemeData buildVoltiTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: VoltiColors.seafoam, brightness: brightness).copyWith(
    primary: dark ? VoltiColors.light : VoltiColors.deep,
    onPrimary: dark ? const Color(0xFF00382F) : Colors.white,
    // Sanftere, weniger grelle Akzentflächen (aktives Werkzeug, Knöpfe).
    primaryContainer: dark ? const Color(0xFF1F4A43) : const Color(0xFFCDEDE6),
    onPrimaryContainer: dark ? const Color(0xFFBDEDE3) : const Color(0xFF0E4F45),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    // Grundfarbe; Bibliothek und Setlists legen zusätzlich den Verlauf darunter.
    scaffoldBackgroundColor: dark ? const Color(0xFF151C1A) : const Color(0xFFECF7F4),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: Colors.transparent),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
  );
}

/// Legt den sanften Hintergrundverlauf unter einen Bildschirm.
/// Der Scaffold darin braucht `backgroundColor: Colors.transparent`.
class VoltiBackground extends StatelessWidget {
  const VoltiBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: VoltiColors.backgroundGradient(Theme.of(context).brightness)),
      child: child,
    );
  }
}
