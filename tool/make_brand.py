"""Färbt die Logo-Dateien im Markenverlauf ein (Türkis → Violett):
die Bildmarke (zwei Blätter) und den Schriftzug. Grundlage ist jeweils nur
die Form (Deckkraft) der bestehenden Dateien. Danach entstehen die
App-Symbole neu (tool/make_icons.py).

Aufruf (im Projektordner):  python3 tool/make_brand.py
"""
import os
import sys

import numpy as np
from PIL import Image

# Markenverlauf: Türkis oben rechts → Violett unten links.
TURQUOISE = np.array((34, 201, 211), np.float32)
VIOLET = np.array((139, 85, 245), np.float32)
# Schriftzug: neutrales Dunkel (im Dunkelmodus färbt Volti ihn weiss).
INK = (22, 23, 28)


def recolor_gradient(path):
    im = np.asarray(Image.open(path).convert("RGBA"))
    h, w = im.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    t = np.clip(((yy / h) + (1 - xx / w)) / 2, 0, 1)[..., None]
    rgb = (TURQUOISE * (1 - t) + VIOLET * t).round().astype(np.uint8)
    Image.fromarray(np.dstack([rgb, im[..., 3]]), "RGBA").save(path)


def recolor_flat(path, color):
    im = np.asarray(Image.open(path).convert("RGBA"))
    rgb = np.empty(im.shape[:2] + (3,), np.uint8)
    rgb[...] = color
    Image.fromarray(np.dstack([rgb, im[..., 3]]), "RGBA").save(path)


if __name__ == "__main__":
    recolor_gradient("assets/brand/volti_mark.png")
    recolor_flat("assets/brand/volti_wordmark.png", INK)
    sys.path.insert(0, os.path.dirname(__file__))
    import make_icons  # noqa: E402  (liest assets/brand/volti_mark.png)

    make_icons.main()
    print("ok")
