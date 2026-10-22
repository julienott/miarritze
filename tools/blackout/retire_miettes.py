#!/usr/bin/env python3
"""Retire les petits îlots détachés du perso (artefacts, ex. points roses d'Amaia « trouvé ») dans une planche.

  retire_miettes.py <id> <anim> [--ecrit]      îlots de moins de TAILLE_MAX px, case par case

Le masque de tenue est nettoyé aux mêmes pixels.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PERSOS = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "blackout", "persos"))
TAILLE_MAX = 400


def traite(pid, anim, ecrit):
    p = os.path.join(PERSOS, pid, anim + ".png")
    im = np.array(Image.open(p).convert("RGBA"))
    t = os.path.join(PERSOS, pid, anim + "_tenue.png")
    tm = np.array(Image.open(t).convert("RGBA")) if os.path.exists(t) else None
    n = 0
    for x0 in range(0, im.shape[1], 256):
        al = im[:256, x0:x0 + 256, 3] > 20
        lab = np.zeros(al.shape, np.int32)
        comps = []
        for y, x in zip(*np.nonzero(al)):
            if lab[y, x]:
                continue
            pile, pts = [(y, x)], []
            lab[y, x] = len(comps) + 1
            while pile:
                cy, cx = pile.pop()
                pts.append((cy, cx))
                for ny in (cy - 1, cy, cy + 1):
                    for nx in (cx - 1, cx, cx + 1):
                        if 0 <= ny < 256 and 0 <= nx < 256 and al[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = len(comps) + 1
                            pile.append((ny, nx))
            comps.append(pts)
        if len(comps) < 2:
            continue
        grand = max(range(len(comps)), key=lambda i: len(comps[i]))
        for i, pts in enumerate(comps):
            if i == grand or len(pts) >= TAILLE_MAX:
                continue
            for y, x in pts:                       # avec une marge de 2 px (halo d'antialias)
                im[max(0, y - 1):y + 2, x0 + max(0, x - 1):x0 + x + 2] = 0
                if tm is not None:
                    tm[max(0, y - 1):y + 2, x0 + max(0, x - 1):x0 + x + 2] = 0
            n += len(pts)
    if ecrit and n:
        Image.fromarray(im).save(p)
        if tm is not None:
            Image.fromarray(tm).save(t)
    return n


if __name__ == "__main__":
    print(traite(sys.argv[1], sys.argv[2], "--ecrit" in sys.argv), "px retirés")
