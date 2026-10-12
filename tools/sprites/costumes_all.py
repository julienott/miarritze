#!/usr/bin/env python3
"""Planche des 4 costumes de tout le roster (idle frame 0, ×2) :
tests/out/sheets/costumes_all.png. Deux persos par ligne, 4 costumes chacun."""
import json, os
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
IDS = ["louis", "maia", "patxi", "xabi", "mattin", "amaia", "txomin", "kaio",
       "karramarro", "ramuntxo", "itsaso", "peio", "itsasargi", "hondar"]
W, H = 76, 150   # case par costume, à l'échelle 1


def frame(fid, k):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    cell, cols, foot = meta["cell"], meta.get("cols", 16), meta["foot"]
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))
    i = meta["anims"]["idle"]["first"]
    idx = sheet[(i // cols) * cell:(i // cols + 1) * cell, (i % cols) * cell:(i % cols + 1) * cell]
    img = Image.fromarray(pal[k][idx].astype(np.uint8), "RGBA")
    return img.crop((foot[0] - W // 2, foot[1] - H + 4, foot[0] + W // 2, foot[1] + 4))


out = Image.new("RGBA", (2 * 4 * W + 16, ((len(IDS) + 1) // 2) * H), (64, 70, 96, 255))
for r, fid in enumerate(IDS):
    for k in range(4):
        out.alpha_composite(frame(fid, k), ((r % 2) * (4 * W + 16) + k * W, (r // 2) * H))
out = out.resize((out.width * 2, out.height * 2), Image.NEAREST)
out.save(os.path.join(ROOT, "tests", "out", "sheets", "costumes_all.png"))
print(out.size)
