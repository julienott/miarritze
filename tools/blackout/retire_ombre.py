#!/usr/bin/env python3
"""Retire l'ombre portée peinte sous les pieds dans les planches d'animation des persos (Julien
2026-10-20 : « Louis a une ombre dans l'illustration alors qu'une ombre est déjà ajoutée par le jeu »).

  retire_ombre.py [--ecrit] [<id> …]      sans --ecrit : compte seulement

L'ombre de pixelforge est une ellipse gris clair, sans couleur, posée sur la ligne des pieds. On efface,
dans la bande basse de chaque case (à partir de feet_anchor - BANDE_HAUT), les pixels gris
(écart entre canaux < ECART_MAX, luminosité entre GRIS_MIN et GRIS_MAX) reliés au bas de la bande ou
semi-transparents (contour de l'ellipse, loin de tout pixel plein) : les chaussures, pantalons blancs ou bottes noires ne sont pas touchés.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PERSOS = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "blackout", "persos"))
BANDE_HAUT = 14
ECART_MAX = 22
GRIS_MIN, GRIS_MAX = 120, 222
MIETTE_MAX = 40
TRAIT_HAUT_MAX = 3


def ombre(case, pied, traits_seuls=False):
    a = case.astype(int)
    rgb, al = a[..., :3], a[..., 3]
    gris = (rgb.max(-1) - rgb.min(-1) < ECART_MAX) & (rgb.mean(-1) >= GRIS_MIN) & (rgb.mean(-1) <= GRIS_MAX) & (al > 0)
    # Le contour de l'ellipse : pixels peu opaques loin de tout pixel plein du perso (le bord lissé
    # du perso, lui, touche toujours un pixel plein).
    gris_large = (rgb.max(-1) - rgb.min(-1) < ECART_MAX) & (rgb.mean(-1) >= 60) & (al > 0)
    plein = (al >= 200) & ~gris_large       # pixel plein ET coloré : chaussure, pied, contour sombre
    pres = plein.copy()
    for _ in range(2):
        p = pres.copy()
        p[1:] |= pres[:-1]; p[:-1] |= pres[1:]; p[:, 1:] |= pres[:, :-1]; p[:, :-1] |= pres[:, 1:]
        pres = p
    contour = (((al > 0) & (al < 200)) | gris_large) & ~pres
    m = np.zeros(al.shape, bool)
    if not traits_seuls:                    # traits_seuls : ne retirer que les traits isolés (chaussures claires)
        m[pied - BANDE_HAUT:] = (gris | contour)[pied - BANDE_HAUT:]
    # L'ellipse déborde des chaussures à gauche et à droite : hors de leur étendue, tout ce qui n'est
    # pas plein dans la bande est de l'ombre.
    y0b = pied - BANDE_HAUT
    xs = np.nonzero(plein[y0b:].any(0))[0]
    if len(xs) and not traits_seuls:
        cote = np.ones(al.shape[1], bool)
        cote[max(0, xs.min() - 1):xs.max() + 2] = False
        m[y0b:, cote] |= (al[y0b:, cote] > 0) & ~plein[y0b:, cote]
    # Miettes : petits îlots de la bande qui ne rejoignent pas le perso (haut de la bande).
    reste = (al > 0) & ~m
    y0 = pied - BANDE_HAUT
    vu = np.zeros(al.shape, bool)
    for y in range(y0, al.shape[0]):
        for x in np.nonzero(reste[y] & ~vu[y])[0]:
            pile, pts, haut = [(y, x)], [], False
            vu[y, x] = True
            while pile:
                cy, cx = pile.pop()
                pts.append((cy, cx))
                haut |= cy == y0
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if y0 <= ny < al.shape[0] and 0 <= nx < al.shape[1] and reste[ny, nx] and not vu[ny, nx]:
                        vu[ny, nx] = True
                        pile.append((ny, nx))
            ys = [q[0] for q in pts]
            trait = max(ys) - min(ys) <= TRAIT_HAUT_MAX     # trait d'ombre fin et isolé sous le perso
            if not haut and (len(pts) < MIETTE_MAX or trait):
                for py, px in pts:
                    m[py, px] = True
    return m


def traite(pid, anim, ecrit, traits_seuls=False):
    p = os.path.join(PERSOS, pid, anim + ".png")
    j = json.load(open(os.path.join(PERSOS, pid, anim + ".json")))
    cw, ch = j["cell"]
    pied = int(j["feet_anchor"][1])
    im = np.array(Image.open(p).convert("RGBA"))
    n = 0
    for x0 in range(0, im.shape[1], cw):
        case = im[:ch, x0:x0 + cw]
        m = ombre(case, pied, traits_seuls)
        n += int(m.sum())
        case[m] = 0
    if ecrit and n:
        Image.fromarray(im).save(p)
    return n


if __name__ == "__main__":
    ecrit = "--ecrit" in sys.argv
    ids = [a for a in sys.argv[1:] if not a.startswith("--")] or sorted(os.listdir(PERSOS))
    for pid in ids:
        d = os.path.join(PERSOS, pid)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".json"):
                n = traite(pid, f[:-5], ecrit)
                if n > 200:
                    print(pid, f[:-5], n, "px d'ombre" + (" retirés" if ecrit else ""))
