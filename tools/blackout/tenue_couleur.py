#!/usr/bin/env python3
"""Masque de tenue calculé par la couleur, pour les persos dont la peau se confond avec la tenue aux yeux
de SAM (Itsaso : peau d'eau cyan pâle, robe bleu profond bordée d'écume blanche). Remplace
assets/blackout/persos/<perso>/<anim>_tenue.png.

  tenue_couleur.py <perso> [anim…]        (sans anim : toutes les planches du perso)

Règle par perso dans prompts_anims.json → persos.<id>.tenue_couleur :
  {"teinte": [h_min, h_max], "sat_min": s, "val_min": v0, "val_max": v, "liseré_px": n}
La tenue = pixels de la teinte voulue assez saturés, ni trop clairs ni aussi sombres que le contour, plus les pixels presque blancs à moins de
liseré_px de ceux-ci (l'écume du bord de la robe).
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PERSOS = os.path.join(ROOT, "assets", "blackout", "persos")


def regle(pid):
    d = json.load(open(os.path.join(HERE, "prompts_anims.json")))
    return d["persos"][pid].get("tenue_couleur")


def masque(sheet, r):
    a = np.asarray(sheet.convert("RGBA")).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    # teinte (0-360) vectorisée
    rr, gg, bb = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == rr, (gg - bb) / d % 6, np.where(mx == gg, (bb - rr) / d + 2, (rr - gg) / d + 4)) * 60
    h0, h1 = r["teinte"]
    tissu = (al > 0.5) & (h >= h0) & (h <= h1) & (sat >= r["sat_min"]) & (mx <= r["val_max"]) & (mx >= r.get("val_min", 0))
    blanc = (al > 0.5) & (sat < 0.08) & (mx > 0.88)
    n = int(r.get("liseré_px", 0))
    if n:
        pres = np.asarray(Image.fromarray((tissu * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * n + 1))) > 0
        tissu = tissu | (blanc & pres)
    out = np.zeros(tissu.shape + (4,), np.uint8)
    out[..., :3] = (tissu * 255).astype(np.uint8)[..., None]
    out[..., 3] = 255
    return Image.fromarray(out)


def traite(pid, anims=None):
    r = regle(pid)
    if not r:
        return []
    faites = []
    for p in sorted(glob.glob(os.path.join(PERSOS, pid, "*_tenue.png"))):
        a = os.path.basename(p)[:-len("_tenue.png")]
        if anims and a not in anims:
            continue
        sheet = os.path.join(PERSOS, pid, a + ".png")
        if os.path.exists(sheet):
            masque(Image.open(sheet), r).save(p)
            faites.append(a)
    return faites


if __name__ == "__main__":
    print(traite(sys.argv[1], sys.argv[2:] or None))
