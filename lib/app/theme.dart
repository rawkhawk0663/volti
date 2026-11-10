import 'package:flutter/material.dart';

/// Markenfarben von Volti: frisches Seegrün/Türkis.
class VoltiColors {
  /// Seegrün – die Markenfarbe (Logo, Verläufe, Akzente).
  static const seafoam = Color(0xFF3BA796);

  /// Tieferes Türkis für Knöpfe mit weisser Schrift (gut lesbar auf Weiss).
  static const deep = Color(0xFF1A8070);

  /// Helles Türkis für den Dunkelmodus.
  static const light = Color(0xFF5CC8B4);

  /// Hintergrund rund um die Notenseite: Anthrazit. Die weisse Seite und die
  /// hellen Werkzeugleisten heben sich davon klar ab.
  static const anthracite = Color(0xFF2B2F2E);

  static Color pageSurround(BuildContext context) => anthracite;

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
          // Hell: sanftes, neutrales Grau (Seegrün bleibt für die Akzente).
          colors: [Color(0xFFF5F6F6), Color(0xFFE6E9E8)],
        );

  /// Leichter Verlauf für Leisten (Werkzeugleiste, Navigation).
  static LinearGradient barGradient(Brightness b) => b == Brightness.dark
      ? const LinearGradient(colors: [Color(0xFF1D2826), Color(0xFF1A2422)])
      : const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF0F2F2)]);
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
  // Hellmodus: Flächen in sanftem, neutralem Grau statt grünlich getönt –
  // das helle Seegrün bleibt für aktive Knöpfe und Akzente.
  final light = dark
      ? scheme
      : scheme.copyWith(
          surface: const Color(0xFFF7F8F8),
          onSurface: const Color(0xFF1B1E1E),
          onSurfaceVariant: const Color(0xFF4A504F),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF1F3F3),
          surfaceContainer: const Color(0xFFECEEEE),
          surfaceContainerHigh: const Color(0xFFE6E8E8),
          surfaceContainerHighest: const Color(0xFFDFE2E2),
          surfaceDim: const Color(0xFFD9DCDC),
          surfaceBright: const Color(0xFFF9FAFA),
          outline: const Color(0xFF7A807F),
          outlineVariant: const Color(0xFFC6CBCA),
          secondaryContainer: const Color(0xFFDDE6E4),
          onSecondaryContainer: const Color(0xFF1F3330),
          surfaceTint: Colors.transparent,
        );
  return ThemeData(
    colorScheme: light,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    // Grundfarbe; Bibliothek und Setlists legen zusätzlich den Verlauf darunter.
    scaffoldBackgroundColor: dark ? const Color(0xFF151C1A) : const Color(0xFFEFF1F1),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: Colors.transparent),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
    // Langes Drücken mit Finger oder Stift ist überall der "Rechtsklick"
    // (Menüs, Favoriten entfernen …). Hinweise sollen ihn nicht abfangen; mit
    // der Maus erscheinen sie weiterhin beim Darüberfahren.
    tooltipTheme: const TooltipThemeData(triggerMode: TooltipTriggerMode.manual),
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
