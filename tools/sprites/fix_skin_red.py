#!/usr/bin/env python3
"""Repeint les pixels rouges posés sur la peau (plis de doigts dessinés avec
le rouge du béret ou de la ceinture) : à l'échelle du jeu ils se lisent
comme des égratignures, à proscrire pour un public de 9 ans.

Un pixel est « rouge » si R > 1,6 × G et R > 1,6 × B ; il est repeint en
ombre de peau si la majorité de ses voisins non rouges (rayon 2) sont de la
peau (le contour sombre ne compte pas). Les zones --keep x0,y0,x1,y1 (bouche, joues) sont laissées telles quelles.
Usage : fix_skin_red.py <in.png> <out.png> --skin r,g,b;r,g,b… --shade r,g,b [--keep …]
"""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main() -> None:
    a = np.array(Image.open(sys.argv[1]).convert("RGBA"))
    skin = [tuple(map(int, c.split(","))) for c in arg("--skin").split(";")]
    shade = tuple(map(int, arg("--shade").split(",")))
    keeps = [tuple(map(int, k.split(","))) for k in sys.argv[sys.argv.index("--keep") + 1:]] if "--keep" in sys.argv else []
    rgb = a[..., :3].astype(int)
    op = a[..., 3] > 0
    red = op & (rgb[..., 0] > 1.6 * rgb[..., 1]) & (rgb[..., 0] > 1.6 * rgb[..., 2])
    is_skin = np.zeros_like(op)
    for c in skin:
        is_skin |= op & (np.abs(rgb - np.array(c)).sum(-1) <= 6)
    h, w = op.shape
    out = a.copy()
    n = 0
    for y, x in zip(*np.nonzero(red)):
        if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in keeps):
            continue
        y0, y1, x0, x1 = max(0, y - 2), min(h, y + 3), max(0, x - 2), min(w, x + 3)
        dark = rgb[y0:y1, x0:x1].sum(-1) <= 180
        neigh = op[y0:y1, x0:x1] & ~red[y0:y1, x0:x1] & ~dark
        if neigh.sum() and is_skin[y0:y1, x0:x1][neigh].mean() >= 0.5:
            out[y, x, :3] = shade
            n += 1
    Image.fromarray(out, "RGBA").save(sys.argv[2])
    print(f"{n} pixels rouges repeints sur la peau")


if __name__ == "__main__":
    main()
