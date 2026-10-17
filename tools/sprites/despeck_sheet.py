#!/usr/bin/env python3
"""Retire les miettes flottantes d'une feuille de rig découpé (source « rd »).

Une miette = composante détachée du perso de MAX_PX pixels au plus (reste
de découpe des pièces). Les pixels d'accessoire (chistera, makila, rame…,
tools/pf/acc_mask.py) ne sont jamais retirés : un accessoire peut être
légitimement détaché de la main sur une image.
Usage : despeck_sheet.py <id> [<id> …] [--anim NOM] [--max PX] [--dry]
  (--anim : une seule animation ; --max : taille maximale d'un morceau retiré,
   ex. la balle orange que RD a dessinée dans le throw de Maïa)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "pf"))
import acc_mask  # noqa: E402

MAX_PX = 12


def comps(m):
    lab = np.zeros(m.shape, int)
    out = []
    for sy, sx in zip(*np.nonzero(m)):
        if lab[sy, sx]:
            continue
        stack, pts = [(sy, sx)], []
        lab[sy, sx] = len(out) + 1
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = len(out) + 1
                    stack.append((ny, nx))
        out.append(pts)
    return out


def despeck(fid, dry=False, only=None, max_px=MAX_PX):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    c, cols = meta["cell"], meta["cols"]
    acc = acc_mask.masks(fid)
    removed = 0
    for name, a in meta["anims"].items():
        if only and name != only:
            continue
        for i in range(a["frames"]):
            k = a["first"] + i
            y0, x0 = (k // cols) * c, (k % cols) * c
            f = sheet[y0:y0 + c, x0:x0 + c]
            cs = sorted(comps(f > 0), key=len)
            m = acc.get(name, [None] * a["frames"])[i] if name in acc else None
            for pts in cs[:-1]:
                if len(pts) > max_px:
                    continue
                if m is not None and m.shape == f.shape and any(m[p] for p in pts):
                    continue
                for p in pts:
                    f[p] = 0
                removed += len(pts)
    if not dry:
        Image.fromarray(sheet, "L").save(os.path.join(d, "sheet.png"), optimize=True)
    return removed


if __name__ == "__main__":
    opt = lambda k: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else None
    vals = {opt("--anim"), opt("--max")}
    only, mx = opt("--anim"), int(opt("--max") or MAX_PX)
    for fid in [a for a in sys.argv[1:] if not a.startswith("--") and a not in vals]:
        print(fid, despeck(fid, "--dry" in sys.argv, only, mx), "px retirés")
