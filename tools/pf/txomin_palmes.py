#!/usr/bin/env python3
"""Modèle de Txomin avec ses palmes de sauveteur à la ceinture (retour de Julien :
palmes à la ceinture plutôt que la bouée dans le dos). Base : pose idle du rig
rendue SANS la bouée (acc_mask.renders) ; deux palmes identiques au projectile
(draw_palme.py), pointe en bas, accrochées derrière la hanche, dessinées sous
le corps. → tools/rd/out/txomin/modele_sans_acc.png (pris par from_rig.py).
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
import acc_mask  # noqa: E402
import from_rig  # noqa: E402
import redraw  # noqa: E402


def belt_y(body):
    """Ordonnée de la ceinture : première ligne où le rouge du short domine."""
    a = np.array(body)
    red = (a[..., 0] > 150) & (a[..., 1] < 90) & (a[..., 2] < 90) & (a[..., 3] > 0)
    rows = np.nonzero(red.sum(1) > 6)[0]
    return int(rows[0]) if len(rows) else 100


def main(dx=0, dy=0):
    meta, _, _, pal = redraw.load("txomin")
    bare = acc_mask.renders("txomin")[1]["idle"][0]
    body = from_rig.window(Image.fromarray(pal[bare].astype(np.uint8), "RGBA"), tuple(meta["foot"]))
    fin = Image.open(os.path.join(ROOT, "assets", "vfx", "txomin", "proj_palme.png")).convert("RGBA")
    fin = fin.rotate(-90, expand=True)          # sangle en haut, pointe jaune en bas
    a = np.array(body)
    xs = np.nonzero(a[..., 3].any(0))[0]
    by = belt_y(body)
    out = Image.new("RGBA", body.size)
    back = int(xs.min()) + 14 + dx               # derrière la hanche (il regarde à droite)
    for k, off in enumerate((0, 6)):
        out.alpha_composite(fin, (back - fin.width // 2 + off, by - 3 + dy + 2 * k))
    out.alpha_composite(body)
    p = os.path.join(ROOT, "tools", "rd", "out", "txomin", "modele_sans_acc.png")
    out.save(p)
    return p


if __name__ == "__main__":
    print(main(*[int(v) for v in sys.argv[1:3]]))
