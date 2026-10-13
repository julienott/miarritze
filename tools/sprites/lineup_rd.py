#!/usr/bin/env python3
"""Line-up depuis les feuilles finales (idle frame 0 de chaque perso, pieds
alignés, ×3) : tests/out/sheets/lineup.png. Contrairement à
tools/mannequin/lineup.py (rendu mannequin), lit assets/fighters/<id>/sheet.png.
Usage : lineup_rd.py [id …]"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
IDS = ["louis", "maia", "patxi", "xabi", "mattin", "amaia", "txomin", "kaio",
       "karramarro", "ramuntxo", "itsaso", "peio", "itsasargi", "hondar"]
BG = (66, 140, 200, 255)


def idle0(fid):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    a = json.load(open(os.path.join(d, "anims.json")))
    s = np.array(Image.open(os.path.join(d, "sheet.png")))
    s = s[..., 0] if s.ndim == 3 else s
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    C, cols, k = a["cell"], a["cols"], a["anims"]["idle"]["first"]
    t = s[(k // cols) * C:(k // cols + 1) * C, (k % cols) * C:(k % cols + 1) * C]
    fy = a["foot"][1]
    ys, xs = np.nonzero(t)
    crop = t[ys.min():fy + 1, xs.min():xs.max() + 1]
    img = pal[crop].astype(np.uint8)
    img[crop == 0] = BG
    return Image.fromarray(img, "RGBA"), fy - ys.min() + 1


def main(ids):
    tiles = [(f, *idle0(f)) for f in ids]
    H = max(t.height for _, t, _ in tiles) + 14
    W = sum(t.width + 8 for _, t, _ in tiles)
    sheet = Image.new("RGBA", (W, H), BG)
    dr = ImageDraw.Draw(sheet)
    x = 4
    for f, t, h in tiles:
        sheet.paste(t, (x, H - t.height))
        dr.text((x, 1), f"{f[:7]} {h}", fill=(255, 255, 255, 255))
        x += t.width + 8
    sheet = sheet.resize((W * 3, H * 3), Image.NEAREST)
    out = os.path.join(ROOT, "tests", "out", "sheets", "lineup.png")
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main(sys.argv[1:] or IDS)
