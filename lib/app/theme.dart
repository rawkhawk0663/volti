import 'package:flutter/material.dart';

/// Farben von Volti: dunkle Karten mit leuchtenden Verläufen, dazu ein
/// gleichwertiger heller Modus (gleiche Gestaltung wie Conti).
///
/// Die Verläufe:
/// - [brand] Pink → Violett: Logo, Hauptknöpfe, aktive Auswahl
/// - [mint] Mint → Blau: erledigt, anwesend, gespeichert
/// - [sun] Gelb → Pink: fällig, Warnung, Geburtstage
/// - [sky] Türkis → Blau: Abgleich, Hinweise, Zeitleiste
@immutable
class VoltiColors extends ThemeExtension<VoltiColors> {
  const VoltiColors({
    required this.background,
    required this.card,
    required this.cardHigh,
    required this.line,
    required this.muted,
    required this.brand,
    required this.mint,
    required this.sun,
    required this.sky,
    required this.track,
  });

  final Color background;
  final Color card;
  final Color cardHigh;
  final Color line;
  final Color muted;
  final List<Color> brand;
  final List<Color> mint;
  final List<Color> sun;
  final List<Color> sky;

  /// Hintergrund von Balken und Ringen.
  final Color track;

  /// Fläche rund um die Notenseite (in beiden Modi dunkel, damit sich die
  /// weisse Seite klar abhebt).
  static const pageSurround = Color(0xFF15161A);

  /// Auswahl, Lasso und aktive Text-Notizen auf der (immer weissen) Notenseite.
  static const selection = Color(0xFF7A3CF0);

  static const dark = VoltiColors(
    background: Color(0xFF0D0E11),
    card: Color(0xFF18191D),
    cardHigh: Color(0xFF202126),
    line: Color(0xFF2A2C32),
    muted: Color(0xFF8E939D),
    brand: [Color(0xFFFF7AC6), Color(0xFF9A6BFF)],
    mint: [Color(0xFF6EF0B5), Color(0xFF4C7CF0)],
    sun: [Color(0xFFFFC83D), Color(0xFFFF6F91)],
    sky: [Color(0xFF5FE3E0), Color(0xFF5B8CFF)],
    track: Color(0xFF2A2C32),
  );

  static const light = VoltiColors(
    background: Color(0xFFF1F2F6),
    card: Color(0xFFFFFFFF),
    cardHigh: Color(0xFFF6F7FA),
    line: Color(0xFFE2E4EA),
    muted: Color(0xFF686D78),
    brand: [Color(0xFFF0479C), Color(0xFF7A3CF0)],
    mint: [Color(0xFF29D398), Color(0xFF3F6FF0)],
    sun: [Color(0xFFFFB400), Color(0xFFFF5A8A)],
    sky: [Color(0xFF34D6E0), Color(0xFF3F6FF0)],
    track: Color(0xFFECEEF2),
  );

  /// Verlauf von links nach rechts (bzw. [begin] → [end]).
  LinearGradient gradient(
    List<Color> c, {
    Alignment begin = Alignment.centerLeft,
    Alignment end = Alignment.centerRight,
  }) => LinearGradient(colors: c, begin: begin, end: end);

  @override
  VoltiColors copyWith() => this;

  @override
  VoltiColors lerp(ThemeExtension<VoltiColors>? other, double t) {
    if (other is! VoltiColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) => [c(a[0], b[0]), c(a[1], b[1])];
    return VoltiColors(
      background: c(background, other.background),
      card: c(card, other.card),
      cardHigh: c(cardHigh, other.cardHigh),
      line: c(line, other.line),
      muted: c(muted, other.muted),
      brand: l(brand, other.brand),
      mint: l(mint, other.mint),
      sun: l(sun, other.sun),
      sky: l(sky, other.sky),
      track: c(track, other.track),
    );
  }
}

extension VoltiThemeX on BuildContext {
  VoltiColors get volti => Theme.of(this).extension<VoltiColors>() ?? VoltiColors.dark;
}

/// Schriften der Oberfläche (Text-Notizen auf den Noten haben eigene).
const fontBody = 'Plex';
const fontDisplay = 'Sora';

ThemeData buildVoltiTheme(Brightness b) {
  final c = b == Brightness.dark ? VoltiColors.dark : VoltiColors.light;
  final dark = b == Brightness.dark;
  final ink = dark ? const Color(0xFFF3F4F6) : const Color(0xFF16171C);
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? const Color(0xFFB48CFF) : const Color(0xFF7A3CF0),
    onPrimary: dark ? const Color(0xFF14081F) : Colors.white,
    primaryContainer: dark ? const Color(0xFF2E2350) : const Color(0xFFEDE4FF),
    onPrimaryContainer: dark ? const Color(0xFFE9DDFF) : const Color(0xFF2A0F66),
    secondary: dark ? const Color(0xFF5FE3E0) : const Color(0xFF1B8FA0),
    onSecondary: dark ? const Color(0xFF00201F) : Colors.white,
    // Ruhige Knöpfe (tonal) im gleichen Violett wie aktive Auswahl.
    secondaryContainer: dark ? const Color(0xFF2E2350) : const Color(0xFFEDE4FF),
    onSecondaryContainer: dark ? const Color(0xFFE9DDFF) : const Color(0xFF2A0F66),
    tertiary: dark ? const Color(0xFFFFC83D) : const Color(0xFFB37400),
    onTertiary: Colors.black,
    tertiaryContainer: dark ? const Color(0xFF3D3214) : const Color(0xFFFFF0C8),
    onTertiaryContainer: dark ? const Color(0xFFFFE7A6) : const Color(0xFF3D2A00),
    error: dark ? const Color(0xFFFF6E7A) : const Color(0xFFC62839),
    onError: dark ? Colors.black : Colors.white,
    surface: c.card,
    onSurface: ink,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.card,
    surfaceContainer: c.card,
    surfaceContainerHigh: c.cardHigh,
    surfaceContainerHighest: c.cardHigh,
    surfaceTint: Colors.transparent,
    outline: dark ? const Color(0xFF4A4D55) : const Color(0xFFB9BDC7),
    outlineVariant: c.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontBody, brightness: b);
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w300, letterSpacing: -0.5),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontFamily: fontDisplay, fontWeight: FontWeight.w700),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontFamily: fontDisplay, fontWeight: FontWeight.w700),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: fontDisplay, fontWeight: FontWeight.w600),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w500),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: text,
    extensions: [c],
    visualDensity: VisualDensity.standard,
    // Langes Drücken mit Finger oder Stift ist überall der "Rechtsklick"
    // (Menüs, Favoriten entfernen …). Hinweise sollen ihn nicht abfangen; mit
    // der Maus erscheinen sie weiterhin beim Darüberfahren.
    tooltipTheme: const TooltipThemeData(triggerMode: TooltipTriggerMode.manual),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: ink,
    ),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.card,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: c.muted),
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: c.muted),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: c.line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primaryContainer : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : ink,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.cardHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.cardHigh,
      side: BorderSide(color: c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.cardHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.cardHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.line),
          ),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
