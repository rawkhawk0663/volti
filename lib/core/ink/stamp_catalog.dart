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
    StampGlyph(0xE536, 'sf', 0.0000, -0.1520, 0.6040, 0.4440),
    StampGlyph(0xE53A, 'sfp', 0.0000, -0.1520, 1.0760, 0.4440),
    StampGlyph(0xE53B, 'sffz', 0.0000, -0.1520, 0.9640, 0.4440),
    StampGlyph(0xE526, 'niente', -0.0230, -0.0100, 0.3080, 0.2740),
  ]),
  StampCategory('Artikulation', [
    StampGlyph(0xE4A0, 'Akzent', 0.0000, 0.0010, 0.3390, 0.2450),
    StampGlyph(0xE4A2, 'Staccato', 0.0000, 0.0000, 0.0840, 0.0840),
    StampGlyph(0xE4A4, 'Tenuto', -0.0010, 0.0000, 0.3380, 0.0480),
    StampGlyph(0xE4B2, 'Portato', -0.0010, 0.0000, 0.3380, 0.2400),
    StampGlyph(0xE4AC, 'Marcato', -0.0010, -0.0010, 0.2350, 0.2530),
    StampGlyph(0xE4A6, 'Staccatissimo', 0.0010, -0.0020, 0.1000, 0.2930),
    StampGlyph(0xE4B0, 'Akzent + Staccato', 0.0000, 0.0000, 0.3390, 0.4200),
    StampGlyph(0xE4C0, 'Fermate', 0.0030, -0.0030, 0.6050, 0.3290),
    StampGlyph(0xE4C1, 'Fermate unten', 0.0030, -0.3320, 0.6050, 0.0000),
    StampGlyph(0xE63C, 'Arpeggio', 0.0000, 0.0090, 0.1210, 1.3670),
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
    StampGlyph(0xE049, 'Coda (eckig)', 0.0000, -0.1540, 0.8220, 0.9030),
    StampGlyph(0xE040, 'Wiederholung Anfang', 0.0000, 0.0000, 0.3660, 1.0000),
    StampGlyph(0xE041, 'Wiederholung Ende', 0.0010, 0.0000, 0.3670, 1.0000),
    StampGlyph(0xE500, 'Simile', 0.0000, -0.2500, 0.5320, 0.2790),
    StampGlyph(0xE501, 'Simile 2 Takte', 0.0000, -0.2500, 0.7620, 0.2790),
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
    StampGlyph(0xE631, 'Bartók-Pizzicato', 0.0000, 0.0000, 0.2000, 0.3000),
    StampGlyph(0xE633, 'Pizzicato linke Hand', 0.0000, 0.0000, 0.2720, 0.2720),
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
    StampGlyph(0xE65B, 'Halbpedal', 0.0000, 0.0000, 0.4500, 0.2360),
    StampGlyph(0xE659, 'Sostenuto', 0.0000, -0.0150, 1.1070, 0.5910),
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
    StampGlyph(0xED16, 'T (Daumen)', 0.0200, 0.0000, 0.2260, 0.2500),
    StampGlyph(0xE847, 'Anschlag abwärts', 0.0000, 0.0000, 0.2280, 0.5270),
    StampGlyph(0xE846, 'Anschlag aufwärts', 0.0000, 0.0000, 0.2280, 0.5270),
    StampGlyph(0xE848, 'Barré', 0.0000, -0.0150, 0.3930, 0.4770),
    StampGlyph(0xE849, 'Halbes Barré', 0.0000, -0.0150, 0.8340, 0.4750),
    StampGlyph(0xEAB2, 'Vibrato', -0.0140, 0.0000, 0.1670, 0.1190),
    StampGlyph(0xE842, 'Golpe', 0.0010, 0.0000, 0.2700, 0.2820),
    StampGlyph(0xE0A9, 'Dead Note (x)', 0.0000, -0.1250, 0.2900, 0.1250),
    StampGlyph(0xE638, 'Abdämpfen', 0.0000, 0.0000, 0.3240, 0.3240),
  ]),
  StampCategory('Noten', [
    StampGlyph(0xECA0, 'Doppelganze', 0.0000, -0.1680, 0.6550, 0.1700),
    StampGlyph(0xECA2, 'Ganze Note', 0.0000, -0.1250, 0.4590, 0.1480),
    StampGlyph(0xECA3, 'Halbe Note', 0.0000, -0.1410, 0.3410, 0.6880),
    StampGlyph(0xECA5, 'Viertelnote', 0.0000, -0.1410, 0.3320, 0.6880),
    StampGlyph(0xECA7, 'Achtelnote', 0.0000, -0.1410, 0.5330, 0.6960),
    StampGlyph(0xECA9, 'Sechzehntel', 0.0000, -0.1410, 0.5210, 0.7000),
    StampGlyph(0xECAB, 'Zweiunddreissigstel', 0.0000, -0.1410, 0.5380, 0.9230),
    StampGlyph(0xECB7, 'Punkt (Verlängerung)', 0.0000, -0.0500, 0.1000, 0.0500),
    StampGlyph(0xECA4, 'Halbe (Hals unten)', 0.0000, -0.6880, 0.3410, 0.1410),
    StampGlyph(0xECA6, 'Viertel (Hals unten)', 0.0000, -0.6880, 0.3320, 0.1410),
    StampGlyph(0xECA8, 'Achtel (Hals unten)', 0.0000, -0.7060, 0.3320, 0.1410),
    StampGlyph(0xECAA, 'Sechzehntel (Hals unten)', 0.0000, -0.7060, 0.3320, 0.1410),
    StampGlyph(0xE0A4, 'Notenkopf', 0.0000, -0.1250, 0.2950, 0.1250),
    StampGlyph(0xE0A3, 'Notenkopf halb', 0.0000, -0.1250, 0.2950, 0.1250),
    StampGlyph(0xE0A2, 'Notenkopf ganz', 0.0000, -0.1250, 0.4220, 0.1250),
    StampGlyph(0xE0DD, 'Rautenkopf', 0.0000, -0.1410, 0.2820, 0.1410),
    StampGlyph(0xE0A9, 'Kreuzkopf (x)', 0.0000, -0.1250, 0.2900, 0.1250),
    StampGlyph(0xE883, 'Triole (3)', 0.0100, -0.0080, 0.3060, 0.3750),
    StampGlyph(0xE885, 'Quintole (5)', 0.0100, -0.0080, 0.3270, 0.3730),
    StampGlyph(0xE886, 'Sextole (6)', 0.0100, -0.0080, 0.3140, 0.3750),
  ]),
  StampCategory('Pausen', [
    StampGlyph(0xE4E2, 'Doppelganze Pause', 0.0000, 0.0000, 0.1250, 0.2500),
    StampGlyph(0xE4E3, 'Ganze Pause', 0.0000, -0.1350, 0.2820, 0.0090),
    StampGlyph(0xE4E4, 'Halbe Pause', 0.0000, -0.0020, 0.2820, 0.1420),
    StampGlyph(0xE4E5, 'Viertelpause', 0.0010, -0.3750, 0.2700, 0.3730),
    StampGlyph(0xE4E6, 'Achtelpause', 0.0000, -0.2510, 0.2470, 0.1740),
    StampGlyph(0xE4E7, 'Sechzehntelpause', 0.0000, -0.5000, 0.3200, 0.1790),
    StampGlyph(0xE4E8, 'Zweiunddreissigstelpause', 0.0000, -0.5000, 0.3630, 0.4260),
    StampGlyph(0xE4EE, 'Mehrtaktpause', 0.0000, -0.2710, 0.7820, 0.2610),
    StampGlyph(0xECB7, 'Punkt', 0.0000, -0.0500, 0.1000, 0.0500),
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
