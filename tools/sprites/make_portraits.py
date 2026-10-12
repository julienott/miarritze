#!/usr/bin/env python3
"""Vignettes de tête indexées (placeholder des portraits RD, SPEC §10.4) :
assets/fighters/<id>/portrait_small.png, 28×28, mode L (index de palette),
cadrées sur la tête de idle frame 0 (haut de la silhouette)."""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SIZE = 28


def make(fid):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    cell, cols = meta["cell"], meta.get("cols", 16)
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    i = meta["anims"]["idle"]["first"]
    idx = sheet[(i // cols) * cell:(i // cols + 1) * cell, (i % cols) * cell:(i % cols + 1) * cell]
    ys, xs = np.nonzero(idx)
    top = ys.min()
    # Centre horizontal de la tête : pixels des 18 premières rangées.
    head = xs[ys < top + 18]
    cx = int(round(head.mean())) if head.size else cell // 2
    y0 = max(0, top - 2)
    x0 = min(max(0, cx - SIZE // 2), cell - SIZE)
    crop = idx[y0:y0 + SIZE, x0:x0 + SIZE]
    out = np.zeros((SIZE, SIZE), np.uint8)
    out[:crop.shape[0], :crop.shape[1]] = crop
    Image.fromarray(out, "L").save(os.path.join(d, "portrait_small.png"))


if __name__ == "__main__":
    ids = sys.argv[1:] or sorted(x for x in os.listdir(os.path.join(ROOT, "assets", "fighters"))
                                  if os.path.exists(os.path.join(ROOT, "assets", "fighters", x, "anims.json")))
    for fid in ids:
        make(fid)
    print(len(ids), "vignettes")
