#!/usr/bin/env python3
"""Prépare les sprites d'effets des coups spéciaux (assets/vfx/<id>/).

Chaque effet part d'une proposition RD choisie (cache versionné), recadrée
sur son contenu, réduite par vote majoritaire si demandé, puis passée au
contrôle des bordures (check_borders). Usage : prep_vfx.py <id>
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "rig"))
import check_borders as cb  # noqa: E402

CACHE = os.path.join(ROOT, "tools", "rd", "cache")

# effet -> (image RD retenue, facteur de réduction, retouche)
CHOICES = {
    "louis": {
        "proj_espadrille": ("260fe11fba4869728767b97268db8fb20439b237_0.png", 2, None),
        "sp_forward": ("4a645bf97ee05b627892fb238ee14ad61aca99c0_0.png", 1, None),
        "sp_down": ("2a996c6b54da0223bb2ed95d975e45fe12c9882c_2.png", 1, None),
        "super": ("be9dfc98c1b599d3b3af270a5a93020c4cfdf9ba_0.png", 1, "lauburu"),
    },
}


def binarize(a: np.ndarray) -> np.ndarray:
    a = a.copy()
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    return a


def crop(a: np.ndarray) -> np.ndarray:
    ys, xs = np.nonzero(a[..., 3])
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def vote_down(a: np.ndarray, k: int) -> np.ndarray:
    """Réduction ×k : chaque bloc prend sa couleur opaque majoritaire, ou
    devient transparent si moins de la moitié du bloc est opaque."""
    h, w = a.shape[0] // k, a.shape[1] // k
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        for x in range(w):
            blk = a[y * k:(y + 1) * k, x * k:(x + 1) * k].reshape(-1, 4)
            op = blk[blk[:, 3] > 0]
            if len(op) * 2 < len(blk):
                continue
            u, n = np.unique(op, axis=0, return_counts=True)
            out[y, x] = u[n.argmax()]
    return out


def lauburu() -> np.ndarray:
    """Lauburu du logo du jeu : composante connexe centrée sur (61, 41)."""
    logo = binarize(np.array(Image.open(os.path.join(ROOT, "assets", "ui", "logo_0.png")).convert("RGBA")))
    region = logo[28:56, 44:78]
    op = region[..., 3] > 0
    seen = np.zeros_like(op)
    stack = [(13, 17)]
    while stack:
        y, x = stack.pop()
        if not (0 <= y < op.shape[0] and 0 <= x < op.shape[1]) or seen[y, x] or not op[y, x]:
            continue
        seen[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    out = region.copy()
    out[~seen] = 0
    return crop(out)


def add_lauburu(a: np.ndarray) -> np.ndarray:
    """Remplace la croix centrale du soleil par le lauburu du logo."""
    out = a.copy()
    h, w = out.shape[:2]
    cy, cx = h // 2, w // 2
    rgb = out[..., :3].astype(int)
    yy, xx = np.mgrid[0:h, 0:w]
    disc = (yy - cy) ** 2 + (xx - cx) ** 2 <= (min(h, w) * 0.30) ** 2
    # tout ce qui n'est pas doré dans le disque (croix, son contour) est repeint
    red = (out[..., 3] > 0) & ~((rgb[..., 0] > 190) & (rgb[..., 1] > 140))
    gold = np.median(rgb[(out[..., 3] > 0) & disc & ~red], axis=0).astype(np.uint8)
    out[red & disc, :3] = gold
    lb = lauburu()
    oy, ox = cy - lb.shape[0] // 2, cx - lb.shape[1] // 2
    m = lb[..., 3] > 0
    out[oy:oy + lb.shape[0], ox:ox + lb.shape[1]][m] = lb[m]
    return out


def main() -> None:
    fid = sys.argv[1]
    dst = os.path.join(ROOT, "assets", "vfx", fid)
    os.makedirs(dst, exist_ok=True)
    for name, (src, k, retouch) in CHOICES[fid].items():
        a = binarize(np.array(Image.open(os.path.join(CACHE, src)).convert("RGBA")))
        a = crop(a)
        if retouch == "lauburu":
            a = add_lauburu(a)
        if k > 1:
            a = vote_down(a, k)
        a = cb.fix(a)
        r = cb.analyse(a)
        Image.fromarray(a, "RGBA").save(os.path.join(dst, f"{name}.png"))
        print(f"{name}: {a.shape[1]}×{a.shape[0]}  fentes {int(r['slits'].sum())} îlots {int(r['islands'].sum())}")


if __name__ == "__main__":
    main()
