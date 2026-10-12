#!/usr/bin/env python3
"""Planche de revue condensée d'un combattant (×2) : une rangée par
animation clé, frame de coup encadrée. Usage : review_sheet.py <id> [...]"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
KEY_ANIMS = ["idle", "walk", "punch_1", "punch_2", "kick", "uppercut", "sweep", "throw", "hit_high",
             "knockdown", "ko", "win", "sp_neutral", "sp_forward", "sp_down", "sp_up", "super", "finisher"]


def main(fid, scale=2):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))
    c, cols = meta["cell"], meta["cols"]

    def cell(name, i):
        k = meta["anims"][name]["first"] + i
        return sheet[(k // cols) * c:(k // cols) * c + c, (k % cols) * c:(k % cols) * c + c]
    m = np.zeros((c, c), bool)
    for name in KEY_ANIMS:
        for i in range(meta["anims"][name]["frames"]):
            m |= cell(name, i) > 0
    ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    cw, ch = x1 - x0, y1 - y0
    maxf = max(meta["anims"][n]["frames"] for n in KEY_ANIMS)
    lab = 70
    img = Image.new("RGBA", (lab + maxf * cw, len(KEY_ANIMS) * ch), (40, 44, 60, 255))
    dr = ImageDraw.Draw(img)
    for r, name in enumerate(KEY_ANIMS):
        a = meta["anims"][name]
        dr.text((2, r * ch + 2), name, fill=(255, 240, 200, 255))
        for i in range(a["frames"]):
            idx = cell(name, i)[y0:y1, x0:x1]
            rgba = pal[0][idx].copy()
            rgba[idx == 0] = (64, 150, 210, 255) if i % 2 == 0 else (56, 132, 190, 255)
            t = Image.fromarray(rgba.astype(np.uint8))
            img.paste(t, (lab + i * cw, r * ch))
            if a.get("hit_frame") == i:
                dr.rectangle([lab + i * cw, r * ch, lab + (i + 1) * cw - 1, (r + 1) * ch - 1], outline=(255, 60, 60, 255))
    out = os.path.join(ROOT, "tests", "out", "sheets", fid, "review.png")
    img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(out)
    print(out)


if __name__ == "__main__":
    for fid in sys.argv[1:]:
        main(fid)
