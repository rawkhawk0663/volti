"""Erzeugt feste (nicht variable) Roboto-Schnitte für die PDFs, die Volti
selbst schreibt (Stundenplan, Absenzenliste, Hausaufgaben).
Regular, Bold, Italic und BoldItalic.

Variable Schriften zeigen manche PDF-Programme unter Windows gar nicht an
(leere Seite). Deshalb feste Schnitte, auf Lateinisch
und gängige Zeichen verkleinert.

    python3 tool/make_pdf_fonts.py
"""
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset

SRC = 'assets/fonts/Roboto.ttf'
UNICODES = (
    list(range(0x20, 0x7F)) + list(range(0xA0, 0x180)) + list(range(0x2010, 0x2040))
    + [0x20AC, 0x2190, 0x2192, 0x2022, 0x25E6, 0x2713, 0x00D7]
)

for src, name, weight in [
    (SRC, 'Regular', 400),
    (SRC, 'Bold', 700),
    ('assets/fonts/Roboto-Italic.ttf', 'Italic', 400),
    ('assets/fonts/Roboto-Italic.ttf', 'BoldItalic', 700),
]:
    font = instantiateVariableFont(TTFont(src), {'wght': weight, 'wdth': 100}, updateFontNames=True)
    opts = subset.Options()
    opts.layout_features = ['kern', 'liga']
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    out = f'assets/fonts/pdf/RobotoPdf-{name}.ttf'
    font.save(out)
    print(out)
