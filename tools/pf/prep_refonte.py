#!/usr/bin/env python3
"""Préparation d'un perso à refaire entièrement (from_mannequin.py), par Kontext :

  garde <id> "<accessoire>" [graines…]  modèle en garde, poings levés, SANS l'accessoire
                                        → tools/rd/out/<id>/garde_<g>.png (+ _brut)
  boule <id> [graines…]                 position groupée de salto depuis le modèle choisi
                                        → tools/rd/out/<id>/boule_<g>.png (+ _brut)
  retire <id> "<accessoire>" [graines…]  modèle = pose d'origine moins l'accessoire (proportions gardées)
  accroupi <id> [graines…]              modèle accroupi en garde (référence des anims accroupies)
  choisir <id> garde|boule|accroupi <graine> → modele_sans_acc.png / boule.png / modele_accroupi.png
Planches : tests/out/pf/<id>_garde.png, <id>_boule.png.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import extras_pf as ex  # noqa: E402
import from_rig  # noqa: E402
import model_sans_acc as M  # noqa: E402

GARDE = ("remove the {acc} completely, both hands are small bare fists (no bigger than the ear) raised in front of the chest in a "
         "fighting guard, side view facing right, keep exactly the same character, face, hair, clothes, "
         "colors, legs and stance, pixel art style, plain white background")
GARDE_SANS = ("both hands are small bare fists (no bigger than the ear) raised in front of the chest in a fighting guard, side view facing "
              "right, keep exactly the same character, face, hair, clothes, colors, legs and stance, pixel art "
              "style, plain white background")
ACCROUPI = ("the same character squatting down very low like a crouching fighting game character: thighs "
            "horizontal, knees bent at a right angle, hips almost at knee height, the whole body a third shorter than "
            "standing, back straight, both small fists raised in front of the chest, side view facing right, keep exactly "
            "the same face, hair, clothes and colors, pixel art style, plain white background")
# Proportions d'origine : on retire seulement l'accessoire, la main reste à sa place
# (lever les poings au prompt fait grossir bras et poings, retours de Julien).
RETIRE = ("remove only the {acc}; the hand that held it stays exactly at the same place as a small closed fist "
          "of normal size, same arm length and thickness; do not change anything else: same character, face, hair, "
          "clothes, colors, pose, proportions and pixel art style, plain white background")
BOULE = ("cannonball pose: the same character crouched into a compact round ball, knees bent tight against "
         "the chest, feet tucked under, both arms wrapped around the knees, head down on the knees, no leg "
         "extended, compact tucked body, no bubble, no circle drawn around, side view facing right, same face, hair, clothes and "
         "colors, pixel art style, plain white background")


def od(fid):
    return os.path.join(ROOT, "tools", "rd", "out", fid)


def unshadow(im):
    """Ombre grise portée sous les pieds retirée (bas de l'image)."""
    a = np.array(im)
    rows = np.nonzero((a[..., 3] > 0).any(1))[0]
    if not len(rows):
        return im
    low = rows.max()
    r, g, b = (a[..., i].astype(int) for i in range(3))
    grey = (np.abs(r - b) < 24) & (np.abs(r - g) < 14) & (r > 110) & (r < 215)
    a[low - 7:low + 1][grey[low - 7:low + 1]] = 0
    out = Image.fromarray(a)
    return out


def run(fid, what, src, prompt, seeds, extra=None):
    bg = Image.new("RGBA", src.size, (255, 255, 255, 255))
    bg.alpha_composite(src)
    inp = bg.convert("RGB").resize((320, 320), Image.NEAREST)
    items = [("source", src)]
    for s in seeds:
        im = ex.infer({"prompt_style": "pf__edit", "input_image": ex.b64(inp), "width": 320, "height": 320,
                       "seed": s, "quality": "high", "prompt": prompt, "remove_shadow": True,
                       # pixelforge 2026-10-18 : proportions surveillées (poings), perso tourné à droite
                       "keep_proportions": True, "facing": "right", "priority": "high", **(extra or {})})[0]
        im.save(os.path.join(od(fid), f"{what}_{s}_brut.png"))
        c = unshadow(M.clean(im.resize((160, 160), Image.NEAREST)))
        c.save(os.path.join(od(fid), f"{what}_{s}.png"))
        items.append((str(s), c))
    return ex.sheet(fid, what, items, 3)


def main():
    cmd, fid = sys.argv[1], sys.argv[2]
    if cmd == "choisir":
        what, s = sys.argv[3], sys.argv[4]
        dst = {"garde": "modele_sans_acc.png", "boule": "boule.png", "accroupi": "modele_accroupi.png"}[what]
        im = Image.open(os.path.join(od(fid), f"{what}_{s}.png"))
        if what in ("boule", "accroupi"):
            im = im.crop(im.getbbox())
        im.save(os.path.join(od(fid), dst))
        print(os.path.join(od(fid), dst))
        return
    if cmd == "garde":
        acc = sys.argv[3]
        seeds = [int(x) for x in sys.argv[4:]] or [951, 952, 953]
        prompt = GARDE.format(acc=acc) if acc else GARDE_SANS
        print(run(fid, "garde", from_rig.model(fid), prompt, seeds))
    elif cmd == "retire":
        acc = sys.argv[3]
        seeds = [int(x) for x in sys.argv[4:]] or [991, 992, 993]
        print(run(fid, "garde", from_rig.model(fid), RETIRE.format(acc=acc), seeds,
                  {"remove_held_object": acc}))
    elif cmd == "accroupi":
        seeds = [int(x) for x in sys.argv[3:]] or [981, 982, 983]
        src = Image.open(os.path.join(od(fid), "modele_sans_acc.png")).convert("RGBA")
        print(run(fid, "accroupi", src, ACCROUPI, seeds))
    elif cmd == "boule":
        seeds = [int(x) for x in sys.argv[3:]] or [961, 962, 963]
        src = Image.open(os.path.join(od(fid), "modele_sans_acc.png")).convert("RGBA")
        print(run(fid, "boule", src, BOULE, seeds))


if __name__ == "__main__":
    main()
