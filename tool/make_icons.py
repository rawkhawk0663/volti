"""Erzeugt die App-Symbole aus der Bildmarke (assets/brand/volti_mark.png):
Windows-Icon (.ico), Android-Startsymbole und ein grosses PNG.

Das Symbol ist ein Quadrat mit abgerundeten Ecken (Wunsch des Besitzers,
sieht auf dem Desktop und in der Taskleiste sauberer aus), aussen durchsichtig.

Aufruf (im Projektordner):  python3 tool/make_icons.py
Mit --white <ordner> entsteht zusätzlich eine weisse Fassung ohne Hintergrund
(z. B. für ein eigenes Taskleisten-Symbol); sie gehört nicht ins Projekt.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

MARK = Image.open("assets/brand/volti_mark.png").convert("RGBA")

# Rundung der Ecken (Anteil der Kantenlänge).
RADIUS = 0.22
# Grösse der Bildmarke im Quadrat.
SCALE = 0.68
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]


def _rounded_mask(size):
    """Maske für ein Quadrat mit runden Ecken, 4-fach gerechnet für glatte Kanten."""
    big = size * 4
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, big - 1, big - 1), radius=round(big * RADIUS), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def _place_mark(canvas, mark, scale):
    size = canvas.width
    f = size * scale / max(mark.size)
    m = mark.resize((max(1, round(mark.width * f)), max(1, round(mark.height * f))), Image.LANCZOS)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def icon(size):
    """Farbiges App-Symbol: Bildmarke auf hellem Mint-Verlauf, runde Ecken."""
    yy = np.linspace(0, 1, size)[:, None, None]
    top, bottom = np.array((246, 252, 250), np.float32), np.array((221, 241, 236), np.float32)
    bg = np.repeat(top * (1 - yy) + bottom * yy, size, axis=1).round().astype(np.uint8)
    canvas = Image.fromarray(np.dstack([bg, np.full((size, size), 255, np.uint8)]), "RGBA")
    _place_mark(canvas, MARK, SCALE)
    canvas.putalpha(_rounded_mask(size))
    return canvas


def white_icon(size):
    """Nur die Bildmarke in Weiss, ohne Hintergrund (durchsichtig)."""
    a = np.asarray(MARK)[..., 3]
    white = Image.fromarray(np.dstack([np.full(a.shape + (3,), 255, np.uint8), a]), "RGBA")
    return _place_mark(Image.new("RGBA", (size, size), (0, 0, 0, 0)), white, 0.86)


def save_ico(make, path):
    # Jede Grösse einzeln gerechnet, damit auch 16 und 24 Punkte scharf sind.
    images = [make(s) for s in ICO_SIZES]
    images[-1].save(path, sizes=[(s, s) for s in ICO_SIZES], append_images=images[:-1])


def main():
    icon(1024).save("assets/brand/volti_icon_1024.png")
    save_ico(icon, "windows/runner/resources/app_icon.ico")
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        icon(px).save(f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
    if "--white" in sys.argv:
        out = sys.argv[sys.argv.index("--white") + 1]
        os.makedirs(out, exist_ok=True)
        save_ico(white_icon, os.path.join(out, "Volti-weiss.ico"))
        white_icon(512).save(os.path.join(out, "Volti-weiss.png"))


if __name__ == "__main__":
    main()
