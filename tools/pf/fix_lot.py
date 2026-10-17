#!/usr/bin/env python3
"""Post-traitement d'un perso refait par from_rig.py (avant build_rd_anims.py).

1. Accessoire raccordé : l'accessoire est recollé tel quel par le serveur
   (keep_masks) mais la main redessinée s'arrête souvent à 1–3 px du manche
   (makila d'Amaia) → on reprend, autour de l'accessoire flottant, les pixels
   du rig d'origine (main, contour) jusqu'à ce qu'il touche le corps (rayon ≤ 4).
2. Miettes : composantes de SPECK px ou moins hors accessoire retirées.
   Choix à l'œil : pf/choix.json {anim: fichier} prime sur le score.
3. Bilan : pixels encore détachés (8-connexité, accessoire compris) par
   animation → vrais défauts à relancer (from_rig.py --graine) ou à garder
   du rig (from_rig.py --rig).
Écrit <anim>_..._fix.png à côté de l'original et met à jour anims.json.
Usage : fix_lot.py <id> [anim …]
"""
import glob
import json
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
import pieces  # noqa: E402
import redraw  # noqa: E402
from inspect_lot import comps8  # noqa: E402

SPECK = 12
RADIUS = 4


def dilate(m, r=1):
    out = m.copy()
    for _ in range(r):
        o = out.copy()
        o[1:] |= out[:-1]
        o[:-1] |= out[1:]
        o[:, 1:] |= out[:, :-1]
        o[:, :-1] |= out[:, 1:]
        out = o
    return out


def fix_frame(new, old, acc):
    a = np.array(new).copy()
    o = np.array(old)
    op = a[..., 3] > 127
    a[~op] = 0
    a[op, 3] = 255
    cs = comps8(op)
    if len(cs) > 1:
        big = max(cs, key=len)
        bigm = np.zeros(op.shape, bool)
        ys, xs = zip(*big)
        bigm[list(ys), list(xs)] = True
        for c in cs:
            if c is big:
                continue
            cm = np.zeros(op.shape, bool)
            ys, xs = zip(*c)
            cm[list(ys), list(xs)] = True
            if acc is not None and (cm & dilate(acc, 1)).any():
                # accessoire flottant : pixels du rig autour, jusqu'au contact
                joined = False
                for r in range(1, RADIUS + 1):
                    ring = dilate(cm, r) & ~(a[..., 3] > 0) & (o[..., 3] > 127)
                    if not ring.any():
                        continue
                    if (dilate(cm | ring, 1) & bigm).any():
                        a[ring] = o[ring]
                        a[ring, 3] = 255
                        joined = True
                        break
                if not joined:
                    # sinon l'accessoire glisse (≤ RADIUS px) jusqu'à la main, la main devant
                    by, bx = np.nonzero(bigm)
                    cy, cx = np.array(ys), np.array(xs)
                    d2 = (cy[:, None] - by[None]) ** 2 + (cx[:, None] - bx[None]) ** 2
                    i, j = np.unravel_index(d2.argmin(), d2.shape)
                    dy, dx = int(by[j] - cy[i]), int(bx[j] - cx[i])
                    dy -= int(np.sign(dy)) if abs(dy) >= abs(dx) else 0
                    dx -= int(np.sign(dx)) if abs(dx) > abs(dy) else 0
                    if max(abs(dy), abs(dx)) <= RADIUS:
                        px = a[cy, cx].copy()
                        a[cy, cx] = 0
                        ny, nx = np.clip(cy + dy, 0, a.shape[0] - 1), np.clip(cx + dx, 0, a.shape[1] - 1)
                        free = a[ny, nx, 3] == 0
                        a[ny[free], nx[free]] = px[free]
            elif len(c) <= SPECK:
                a[cm] = 0
    return Image.fromarray(a)


def cells(strip):
    return [strip.crop((i * pieces.CELL, 0, (i + 1) * pieces.CELL, pieces.CELL))
            for i in range(strip.width // pieces.CELL)]


def residual(f):
    m = np.array(f)[..., 3] > 127
    cs = comps8(m)
    return sum(len(c) for c in cs) - max((len(c) for c in cs), default=0)


def main():
    fid = sys.argv[1]
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    reg = os.path.join(od, "anims.json")
    done = json.load(open(reg))
    verdicts = json.load(open(os.path.join(od, "pf", "verdicts.json")))
    meta, data, idx, pal = redraw.load(fid)
    foot = tuple(meta["foot"])
    accm = acc_mask.masks(fid)
    cp = os.path.join(od, "pf", "choix.json")
    choix = json.load(open(cp)) if os.path.exists(cp) else {}
    names = sys.argv[2:] or list(done)
    report = {}
    for name in names:
        src = done[name]
        if src.endswith("_rig.png"):
            report[name] = "rig"
            continue
        old = [from_rig.window(f, foot) for f in redraw.frames(meta, idx, pal, name)]
        masks = accm.get(name)
        accs = [np.array(from_rig.window(Image.fromarray(np.where(m, 255, 0).astype(np.uint8)).convert("RGBA"),
                                         foot))[..., 0] > 0 for m in masks] if masks else [None] * len(old)
        best = None
        # toutes les générations de l'animation (première passe + relances --graine) : la plus propre
        cands = sorted(glob.glob(os.path.join(od, "pf", f"{name}_r[0-9]*.png")))
        if name in choix:           # choix à l'œil (pf/choix.json) : prime sur le score
            cands = [os.path.join(od, "pf", choix[name])]
        for src in cands:
            if src.endswith(("_fix.png", "_ctl.png", "_msk.png")):
                continue
            strip = Image.open(src).convert("RGBA")
            new = cells(strip)
            if len(new) != len(old):
                continue
            ref, acc = old, accs
            if os.path.exists(src[:-4] + "_ctl.png"):     # contrôle refait (--accroupi) : raccord pris dedans
                ref = cells(Image.open(src[:-4] + "_ctl.png").convert("RGBA"))
                mp = src[:-4] + "_msk.png"
                acc = [np.array(m)[..., 0] > 0 for m in cells(Image.open(mp).convert("RGBA"))] \
                    if os.path.exists(mp) else [None] * len(new)
            out = [fix_frame(n, o, m) for n, o, m in zip(new, ref, acc)]
            score = max(residual(f) for f in out)
            if best is None or score < best[0]:
                best = (score, src, out)
        if best is None:
            report[name] = "aucune"
            continue
        dst = best[1][:-4] + "_fix.png"
        pieces.strip(best[2]).save(dst)
        done[name] = dst
        report[name] = best[0]
    json.dump(done, open(reg, "w"), indent=1)
    print(json.dumps(report))
    bad = {k: v for k, v in report.items() if v != "rig" and v > SPECK}
    print("encore détachés :", bad)


if __name__ == "__main__":
    main()
