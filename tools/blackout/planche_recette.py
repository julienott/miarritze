#!/usr/bin/env python3
"""Planches de recette (Julien, 2026-10-20 : « fais la recette de tout ce qui est sorti »).

  planche_recette.py anim <planche.png> <out.png> [--tenue <tenue.png>] [--cases 8]
  planche_recette.py perso <id> <out.png> [anims,…]     une ligne par animation (assets du jeu)
  planche_recette.py decor <dossier_job> <out.png>      variantes image_0N avec ombre, sur gris

Animation : cases réparties sur toute la boucle, fond blanc, ligne de sol à l'ancrage des pieds ;
les deux dernières cases sont teintées par le masque de tenue (vérifie qu'il ne prend pas la tête).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PERSOS = os.path.join(ROOT, "assets", "blackout", "persos")
CELL = 256
TAILLE = 128          # taille d'une case sur la planche
SOL_Y = 236


def cases(planche, n):
    im = Image.open(planche).convert("RGBA")
    total = max(1, im.width // CELL)
    idx = sorted({round(i * (total - 1) / max(1, n - 1)) for i in range(n)})
    return im, idx


def ligne_anim(planche, tenue=None, n=8, titre=""):
    im, idx = cases(planche, n)
    msk = Image.open(tenue).convert("L") if tenue and os.path.exists(tenue) else None
    out = Image.new("RGB", (TAILLE * len(idx) + 110, TAILLE), "white")
    d = ImageDraw.Draw(out)
    d.text((4, TAILLE // 2 - 6), titre[:16], fill="black")
    for j, i in enumerate(idx):
        c = im.crop((i * CELL, 0, (i + 1) * CELL, CELL))
        if msk is not None and j >= len(idx) - 2:
            m = np.array(msk.crop((i * CELL, 0, (i + 1) * CELL, CELL))) > 8
            a = np.array(c)
            a[m, 0], a[m, 1], a[m, 2] = 255, 0, 200
            c = Image.fromarray(a)
        fond = Image.new("RGBA", (CELL, CELL), "white")
        ImageDraw.Draw(fond).line((0, SOL_Y, CELL, SOL_Y), fill=(170, 200, 255), width=2)
        fond.alpha_composite(c)
        out.paste(fond.convert("RGB").resize((TAILLE, TAILLE), Image.LANCZOS), (110 + j * TAILLE, 0))
        d.line((110 + j * TAILLE, 0, 110 + j * TAILLE, TAILLE), fill=(220, 220, 220))
    return out


def empile(lignes, out):
    w = max(l.width for l in lignes)
    im = Image.new("RGB", (w, sum(l.height + 4 for l in lignes)), (200, 200, 200))
    y = 0
    for l in lignes:
        im.paste(l, (0, y))
        y += l.height + 4
    im.save(out)
    print(out)


def perso(pid, out, anims=None):
    if not anims:
        anims = sorted(f[:-5] for f in os.listdir(os.path.join(PERSOS, pid)) if f.endswith(".json"))
    lignes = []
    for a in anims:
        p = os.path.join(PERSOS, pid, a + ".png")
        if os.path.exists(p):
            lignes.append(ligne_anim(p, os.path.join(PERSOS, pid, a + "_tenue.png"), 8, a))
    empile(lignes, out)


def decor(dossier, out):
    imgs = sorted(f for f in os.listdir(dossier)
                  if f.startswith(("image_", "preview_")) and f.endswith(".png") and "_raw" not in f and "_shadow" not in f and "_base" not in f)
    vues = []
    for f in imgs:
        src = os.path.join(dossier, f.replace(".png", "_with_shadow.png"))
        im = Image.open(src if os.path.exists(src) else os.path.join(dossier, f)).convert("RGBA")
        im.thumbnail((360, 360))
        fond = Image.new("RGBA", (380, 400), (150, 160, 150, 255))
        fond.alpha_composite(im, ((380 - im.width) // 2, (380 - im.height) // 2))
        ImageDraw.Draw(fond).text((6, 384), f, fill="black")
        vues.append(fond)
    if not vues:
        print("rien dans", dossier)
        return
    planche = Image.new("RGB", (390 * len(vues), 400), "white")
    for i, v in enumerate(vues):
        planche.paste(v.convert("RGB"), (i * 390, 0))
    planche.save(out)
    print(out)


if __name__ == "__main__":
    cmd, a = sys.argv[1], sys.argv[2:]
    if cmd == "anim":
        t = a[a.index("--tenue") + 1] if "--tenue" in a else None
        n = int(a[a.index("--cases") + 1]) if "--cases" in a else 8
        empile([ligne_anim(a[0], t, n, os.path.basename(a[0])[:-4])], a[1])
    elif cmd == "perso":
        perso(a[0], a[1], a[2].split(",") if len(a) > 2 else None)
    else:
        decor(a[0], a[1])
