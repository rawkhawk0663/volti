// Erzeugt mit tool/make_stamps.py – nicht von Hand ändern.
// Zeichen aus der Schrift Bravura (SMuFL, SIL Open Font License).

/// Ein Musiksymbol als Stempel.
///
/// [left]..[top] ist die Ausdehnung der Tinte in "em" (1 em = Schriftgrösse),
/// gemessen ab dem Ursprung auf der Grundlinie, y nach oben.
class StampGlyph {
  const StampGlyph(this.codepoint, this.label, this.left, this.bottom, this.right, this.top);
  final int codepoint;
  final String label;
  final double left, bottom, right, top;

  String get char => String.fromCharCode(codepoint);
  double get width => right - left;
  double get height => top - bottom;
}

class StampCategory {
  const StampCategory(this.name, this.glyphs);
  final String name;
  final List<StampGlyph> glyphs;
}

const stampCatalog = <StampCategory>[
  StampCategory('Dynamik', [
    StampGlyph(0xE52A, 'ppp', -0.0920, -0.1420, 1.0730, 0.2740),
    StampGlyph(0xE52B, 'pp', -0.0820, -0.1420, 0.7280, 0.2740),
    StampGlyph(0xE520, 'p', -0.0890, -0.1420, 0.3660, 0.2740),
    StampGlyph(0xE52C, 'mp', -0.0200, -0.1420, 0.8250, 0.2740),
    StampGlyph(0xE52D, 'mf', -0.0200, -0.1650, 0.8180, 0.4310),
    StampGlyph(0xE522, 'f', -0.1410, -0.1520, 0.3640, 0.4440),
    StampGlyph(0xE52F, 'ff', -0.1350, -0.1520, 0.6100, 0.4440),
    StampGlyph(0xE530, 'fff', -0.1550, -0.1520, 0.8300, 0.4440),
    StampGlyph(0xE534, 'fp', -0.1410, -0.1520, 0.6190, 0.4440),
    StampGlyph(0xE539, 'sfz', 0.0000, -0.1520, 0.7330, 0.4440),
    StampGlyph(0xE535, 'fz', -0.1410, -0.1520, 0.4970, 0.4440),
    StampGlyph(0xE53D, 'rfz', -0.0200, -0.1520, 0.7440, 0.4440),
  ]),
  StampCategory('Artikulation', [
    StampGlyph(0xE4A0, 'Akzent', 0.0000, 0.0010, 0.3390, 0.2450),
    StampGlyph(0xE4A2, 'Staccato', 0.0000, 0.0000, 0.0840, 0.0840),
    StampGlyph(0xE4A4, 'Tenuto', -0.0010, 0.0000, 0.3380, 0.0480),
    StampGlyph(0xE4B2, 'Portato', -0.0010, 0.0000, 0.3380, 0.2400),
    StampGlyph(0xE4AC, 'Marcato', -0.0010, -0.0010, 0.2350, 0.2530),
    StampGlyph(0xE4A6, 'Staccatissimo', 0.0010, -0.0020, 0.1000, 0.2930),
    StampGlyph(0xE4C0, 'Fermate', 0.0030, -0.0030, 0.6050, 0.3290),
    StampGlyph(0xE4C1, 'Fermate unten', 0.0030, -0.3320, 0.6050, 0.0000),
    StampGlyph(0xE4CE, 'Atemzeichen', 0.0010, 0.0020, 0.1520, 0.2510),
    StampGlyph(0xE4D1, 'Zäsur', 0.0000, -0.0010, 0.3840, 0.5320),
  ]),
  StampCategory('Vorzeichen', [
    StampGlyph(0xE260, 'b', 0.0000, -0.1750, 0.2260, 0.4390),
    StampGlyph(0xE261, 'Auflöser', 0.0000, -0.3350, 0.1680, 0.3410),
    StampGlyph(0xE262, 'Kreuz', 0.0000, -0.3480, 0.2490, 0.3500),
    StampGlyph(0xE264, 'Doppel-b', 0.0000, -0.1750, 0.4110, 0.4370),
    StampGlyph(0xE263, 'Doppelkreuz', 0.0000, -0.1250, 0.2470, 0.1270),
  ]),
  StampCategory('Form', [
    StampGlyph(0xE047, 'Segno', 0.0040, -0.0270, 0.5500, 0.7590),
    StampGlyph(0xE048, 'Coda', -0.0040, -0.1580, 0.9550, 0.8980),
    StampGlyph(0xE045, 'D.S.', 0.0110, -0.0090, 1.0820, 0.4420),
    StampGlyph(0xE046, 'D.C.', 0.0110, -0.0090, 1.0820, 0.4420),
    StampGlyph(0xE040, 'Wiederholung Anfang', 0.0000, 0.0000, 0.3660, 1.0000),
    StampGlyph(0xE041, 'Wiederholung Ende', 0.0010, 0.0000, 0.3670, 1.0000),
    StampGlyph(0xE500, 'Simile', 0.0000, -0.2500, 0.5320, 0.2790),
  ]),
  StampCategory('Verzierungen', [
    StampGlyph(0xE566, 'Triller', 0.0000, -0.0100, 0.5210, 0.3900),
    StampGlyph(0xE56C, 'Pralltriller', 0.0000, 0.0000, 0.7250, 0.2450),
    StampGlyph(0xE56D, 'Mordent', 0.0010, -0.0730, 0.7290, 0.3190),
    StampGlyph(0xE567, 'Doppelschlag', 0.0000, 0.0000, 0.4600, 0.2180),
  ]),
  StampCategory('Streicher', [
    StampGlyph(0xE610, 'Abstrich', 0.0000, 0.0000, 0.3120, 0.3180),
    StampGlyph(0xE612, 'Aufstrich', 0.0010, 0.0010, 0.2490, 0.4950),
    StampGlyph(0xE614, 'Flageolett', 0.0000, 0.0000, 0.2000, 0.2000),
    StampGlyph(0xE624, 'Daumenaufsatz', 0.0000, 0.0000, 0.1720, 0.2960),
  ]),
  StampCategory('Bläser & Gesang', [
    StampGlyph(0xE4CE, 'Atemzeichen', 0.0010, 0.0020, 0.1520, 0.2510),
    StampGlyph(0xE4CF, 'Atemzeichen (Häkchen)', 0.0000, 0.0000, 0.5000, 0.5020),
    StampGlyph(0xE5E5, 'gestopft (+)', 0.0000, 0.0000, 0.2720, 0.2720),
    StampGlyph(0xE5E7, 'offen (o)', 0.0000, 0.0000, 0.3040, 0.3040),
  ]),
  StampCategory('Tasten', [
    StampGlyph(0xE650, 'Pedal', 0.0000, -0.0080, 1.0190, 0.5550),
    StampGlyph(0xE655, 'Pedal loslassen', 0.0000, 0.0000, 0.4500, 0.4500),
  ]),
  StampCategory('Gitarre', [
    StampGlyph(0xED10, '0', 0.0200, -0.0010, 0.2350, 0.2510),
    StampGlyph(0xED11, '1', 0.0200, 0.0000, 0.1370, 0.2540),
    StampGlyph(0xED12, '2', 0.0200, -0.0030, 0.2220, 0.2530),
    StampGlyph(0xED13, '3', 0.0200, 0.0000, 0.2050, 0.2520),
    StampGlyph(0xED14, '4', 0.0200, 0.0010, 0.2160, 0.2530),
    StampGlyph(0xED17, 'p', -0.0540, -0.1530, 0.2720, 0.2570),
    StampGlyph(0xED19, 'i', -0.0130, -0.0070, 0.1640, 0.3850),
    StampGlyph(0xED1A, 'm', -0.0080, -0.0040, 0.4150, 0.2570),
    StampGlyph(0xED1B, 'a', 0.0000, -0.0050, 0.2670, 0.2580),
    StampGlyph(0xE834, 'Saite 1', 0.0000, 0.0000, 0.5400, 0.5390),
    StampGlyph(0xE835, 'Saite 2', 0.0000, 0.0000, 0.5400, 0.5390),
    StampGlyph(0xE836, 'Saite 3', 0.0000, 0.0000, 0.5400, 0.5390),
    StampGlyph(0xE837, 'Saite 4', 0.0010, 0.0000, 0.5410, 0.5390),
    StampGlyph(0xE838, 'Saite 5', 0.0000, 0.0000, 0.5400, 0.5390),
    StampGlyph(0xE839, 'Saite 6', 0.0000, 0.0000, 0.5400, 0.5390),
  ]),
  StampCategory('Weiteres', [
    StampGlyph(0xECA5, 'Viertelnote', 0.0000, -0.1410, 0.3320, 0.6880),
    StampGlyph(0xECA3, 'Halbe Note', 0.0000, -0.1410, 0.3410, 0.6880),
    StampGlyph(0xECA7, 'Achtelnote', 0.0000, -0.1410, 0.5330, 0.6960),
    StampGlyph(0xE0A4, 'Notenkopf', 0.0000, -0.1250, 0.2950, 0.1250),
  ]),
];

/// Sucht ein Zeichen in der Sammlung (für gespeicherte Stempel).
StampGlyph? stampGlyph(int codepoint) {
  for (final c in stampCatalog) {
    for (final g in c.glyphs) {
      if (g.codepoint == codepoint) return g;
    }
  }
  return null;
}
