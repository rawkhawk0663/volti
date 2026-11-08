"""Erzeugt die Logo-Assets (transparente PNGs + Windows-Icon) aus der
Original-Vorlage. Aufruf: python3 tool/extract_brand.py <vorlage.jpg>"""
import sys
import numpy as np
from PIL import Image

src = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float32)
bg = np.median(src[5:60, 5:60].reshape(-1, 3), axis=0)  # Papierfarbe

def extract(box, color, gradient=None):
    x0, y0, x1, y1 = box
    crop = src[y0:y1, x0:x1]
    # Deckkraft = wie weit sich der Pixel vom Hintergrund unterscheidet.
    dist = np.abs(crop - bg).max(axis=2)
    alpha = np.clip((dist - 12) / (np.ptp(dist) * 0.55), 0, 1)
    ys, xs = np.where(alpha > 0.05)
    pad = 4
    alpha = alpha[max(ys.min()-pad, 0):ys.max()+pad, max(xs.min()-pad, 0):xs.max()+pad]
    out = np.zeros(alpha.shape + (4,), np.uint8)
    if gradient is None:
        out[..., :3] = color
    else:
        # Sanfter Verlauf von oben rechts (hell) nach unten links (tief).
        h, w = alpha.shape
        yy, xx = np.mgrid[0:h, 0:w]
        t = np.clip(((yy / h) + (1 - xx / w)) / 2, 0, 1)[..., None]
        top, bottom = np.array(gradient[0], np.float32), np.array(gradient[1], np.float32)
        out[..., :3] = (top * (1 - t) + bottom * t).round().astype(np.uint8)
    out[..., 3] = (alpha * 255).round()
    return Image.fromarray(out, "RGBA")

# Seegrün: hell #52BFAA → tief #1A8070
SEAFOAM = ((82, 191, 170), (26, 128, 112))
mark = extract((240, 180, 590, 600), None, gradient=SEAFOAM)
word = extract((590, 255, 1300, 540), (27, 38, 36))
mark.save("assets/brand/volti_mark.png")
word.save("assets/brand/volti_wordmark.png")

# Quadratisches App-Icon: Bildmarke zentriert auf hellem Grund.
def icon(size, scale=0.72):
    # Ganz heller, sanfter Mint-Verlauf als Hintergrund.
    yy = np.linspace(0, 1, size)[:, None, None]
    top, bottom = np.array((246, 252, 250), np.float32), np.array((221, 241, 236), np.float32)
    bg = np.repeat(top * (1 - yy) + bottom * yy, size, axis=1)
    canvas = Image.fromarray(np.dstack([bg.round().astype(np.uint8), np.full((size, size), 255, np.uint8)]), "RGBA")
    f = size * scale / max(mark.size)  # auch vergrössern, nicht nur verkleinern
    m = mark.resize((max(1, round(mark.width * f)), max(1, round(mark.height * f))), Image.LANCZOS)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas

icon(1024).save("assets/brand/volti_icon_1024.png")
icon(256).save("windows/runner/resources/app_icon.ico",
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    icon(px).convert("RGB").save(f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
print("mark", mark.size, "word", word.size)
