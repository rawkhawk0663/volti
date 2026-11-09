"""Erzeugt lib/core/ink/stamp_catalog.dart aus der Schrift Bravura (SMuFL).

Für jedes Zeichen wird die tatsächliche Ausdehnung (Tinte) aus der Schrift
berechnet, damit Stempel genau mittig dort landen, wo man tippt.
Aufruf: python3 tool/make_stamps.py <glyphnames.json>
"""
import json, sys
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen

CATALOG = [
    ("Dynamik", [
        ("dynamicPPP", "ppp"), ("dynamicPP", "pp"), ("dynamicPiano", "p"), ("dynamicMP", "mp"),
        ("dynamicMF", "mf"), ("dynamicForte", "f"), ("dynamicFF", "ff"), ("dynamicFFF", "fff"),
        ("dynamicFortePiano", "fp"), ("dynamicSforzato", "sfz"), ("dynamicForzando", "fz"),
        ("dynamicRinforzando2", "rfz"), ("dynamicSforzando1", "sf"), ("dynamicSforzatoPiano", "sfp"),
        ("dynamicSforzatoFF", "sffz"), ("dynamicNiente", "niente"),
    ]),
    ("Artikulation", [
        ("articAccentAbove", "Akzent"), ("articStaccatoAbove", "Staccato"), ("articTenutoAbove", "Tenuto"),
        ("articTenutoStaccatoAbove", "Portato"), ("articMarcatoAbove", "Marcato"),
        ("articStaccatissimoAbove", "Staccatissimo"), ("articAccentStaccatoAbove", "Akzent + Staccato"),
        ("fermataAbove", "Fermate"), ("fermataBelow", "Fermate unten"), ("arpeggiato", "Arpeggio"),
        ("breathMarkComma", "Atemzeichen"), ("caesura", "Zäsur"),
    ]),
    ("Vorzeichen", [
        ("accidentalFlat", "b"), ("accidentalNatural", "Auflöser"), ("accidentalSharp", "Kreuz"),
        ("accidentalDoubleFlat", "Doppel-b"), ("accidentalDoubleSharp", "Doppelkreuz"),
    ]),
    ("Form", [
        ("segno", "Segno"), ("coda", "Coda"), ("dalSegno", "D.S."), ("daCapo", "D.C."),
        ("codaSquare", "Coda (eckig)"), ("repeatLeft", "Wiederholung Anfang"), ("repeatRight", "Wiederholung Ende"),
        ("repeat1Bar", "Simile"), ("repeat2Bars", "Simile 2 Takte"),
    ]),
    ("Verzierungen", [
        ("ornamentTrill", "Triller"), ("ornamentShortTrill", "Pralltriller"), ("ornamentMordent", "Mordent"),
        ("ornamentTurn", "Doppelschlag"),
    ]),
    ("Streicher", [
        ("stringsDownBow", "Abstrich"), ("stringsUpBow", "Aufstrich"), ("stringsHarmonic", "Flageolett"),
        ("stringsThumbPosition", "Daumenaufsatz"), ("pluckedSnapPizzicatoAbove", "Bartók-Pizzicato"),
        ("pluckedLeftHandPizzicato", "Pizzicato linke Hand"),
    ]),
    ("Bläser & Gesang", [
        ("breathMarkComma", "Atemzeichen"), ("breathMarkTick", "Atemzeichen (Häkchen)"),
        ("brassMuteClosed", "gestopft (+)"), ("brassMuteOpen", "offen (o)"),
    ]),
    ("Tasten", [
        ("keyboardPedalPed", "Pedal"), ("keyboardPedalUp", "Pedal loslassen"), ("keyboardPedalHalf2", "Halbpedal"),
        ("keyboardPedalSost", "Sostenuto"),
    ]),
    ("Gitarre", [
        ("fingering0", "0"), ("fingering1", "1"), ("fingering2", "2"), ("fingering3", "3"), ("fingering4", "4"),
        ("fingeringPLower", "p"), ("fingeringILower", "i"), ("fingeringMLower", "m"), ("fingeringALower", "a"),
        ("guitarString1", "Saite 1"), ("guitarString2", "Saite 2"), ("guitarString3", "Saite 3"),
        ("guitarString4", "Saite 4"), ("guitarString5", "Saite 5"), ("guitarString6", "Saite 6"),
        ("fingeringTUpper", "T (Daumen)"), ("guitarStrumDown", "Anschlag abwärts"), ("guitarStrumUp", "Anschlag aufwärts"),
        ("guitarBarreFull", "Barré"), ("guitarBarreHalf", "Halbes Barré"), ("guitarVibratoStroke", "Vibrato"),
        ("guitarGolpe", "Golpe"), ("noteheadXBlack", "Dead Note (x)"), ("pluckedDamp", "Abdämpfen"),
    ]),
    ("Noten", [
        ("metNoteDoubleWhole", "Doppelganze"), ("metNoteWhole", "Ganze Note"), ("metNoteHalfUp", "Halbe Note"),
        ("metNoteQuarterUp", "Viertelnote"), ("metNote8thUp", "Achtelnote"), ("metNote16thUp", "Sechzehntel"),
        ("metNote32ndUp", "Zweiunddreissigstel"), ("metAugmentationDot", "Punkt (Verlängerung)"),
        ("metNoteHalfDown", "Halbe (Hals unten)"), ("metNoteQuarterDown", "Viertel (Hals unten)"),
        ("metNote8thDown", "Achtel (Hals unten)"), ("metNote16thDown", "Sechzehntel (Hals unten)"),
        ("noteheadBlack", "Notenkopf"), ("noteheadHalf", "Notenkopf halb"), ("noteheadWhole", "Notenkopf ganz"),
        ("noteheadDiamondWhite", "Rautenkopf"), ("noteheadXBlack", "Kreuzkopf (x)"),
        ("tuplet3", "Triole (3)"), ("tuplet5", "Quintole (5)"), ("tuplet6", "Sextole (6)"),
    ]),
    ("Pausen", [
        ("restDoubleWhole", "Doppelganze Pause"), ("restWhole", "Ganze Pause"), ("restHalf", "Halbe Pause"),
        ("restQuarter", "Viertelpause"), ("rest8th", "Achtelpause"), ("rest16th", "Sechzehntelpause"),
        ("rest32nd", "Zweiunddreissigstelpause"), ("restHBar", "Mehrtaktpause"), ("metAugmentationDot", "Punkt"),
    ]),
]

names = json.load(open(sys.argv[1]))
font = TTFont("assets/fonts/Bravura.otf")
upem = font["head"].unitsPerEm
cmap = font.getBestCmap()
glyphs = font.getGlyphSet()

out = []
missing = []
for cat, entries in CATALOG:
    items = []
    for name, label in entries:
        info = names.get(name)
        if not info:
            missing.append(name); continue
        cp = int(info["codepoint"][2:], 16)
        gname = cmap.get(cp)
        if gname is None:
            missing.append(name); continue
        pen = BoundsPen(glyphs)
        glyphs[gname].draw(pen)
        if pen.bounds is None:
            missing.append(name); continue
        x0, y0, x1, y1 = (v / upem for v in pen.bounds)
        items.append(f"      StampGlyph(0x{cp:X}, '{label}', {x0:.4f}, {y0:.4f}, {x1:.4f}, {y1:.4f}),")
    out.append(f"    StampCategory('{cat}', [\n" + "\n".join(items) + "\n    ]),")

dart = f'''// Erzeugt mit tool/make_stamps.py – nicht von Hand ändern.
// Zeichen aus der Schrift Bravura (SMuFL, SIL Open Font License).

/// Ein Musiksymbol als Stempel.
///
/// [left]..[top] ist die Ausdehnung der Tinte in "em" (1 em = Schriftgrösse),
/// gemessen ab dem Ursprung auf der Grundlinie, y nach oben.
class StampGlyph {{
  const StampGlyph(this.codepoint, this.label, this.left, this.bottom, this.right, this.top);
  final int codepoint;
  final String label;
  final double left, bottom, right, top;

  String get char => String.fromCharCode(codepoint);
  double get width => right - left;
  double get height => top - bottom;
}}

class StampCategory {{
  const StampCategory(this.name, this.glyphs);
  final String name;
  final List<StampGlyph> glyphs;
}}

const stampCatalog = <StampCategory>[
{chr(10).join(out)}
];

/// Sucht ein Zeichen in der Sammlung (für gespeicherte Stempel).
StampGlyph? stampGlyph(int codepoint) {{
  for (final c in stampCatalog) {{
    for (final g in c.glyphs) {{
      if (g.codepoint == codepoint) return g;
    }}
  }}
  return null;
}}
'''
open("lib/core/ink/stamp_catalog.dart", "w").write(dart)
print("fehlend:", missing)
