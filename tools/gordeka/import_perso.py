#!/usr/bin/env python3
"""Rapatrie les animations 2D d'un perso produites par pixelforge (pf_2d__anim) dans le jeu.

  import_perso.py <id> <taches.json>

taches.json : {"idle": "<task_id>", "walk": "<task_id>", …} (un task_id par chorégraphie).
Pour chaque animation, on enregistre dans assets/gordeka/persos/<id>/ :
  <anim>.png (planche), <anim>_tenue.png (masque de tenue), <anim>.json (fps, boucle, ancrage).
Un GIF d'aperçu par animation va dans tools/rd/out/<id>/gk2d/pf/<anim>/ pour la relecture.
"""
import io
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

ROLES = {"spritesheet_00.png": "{a}.png", "tenue_sheet_00.png": "{a}_tenue.png", "animation_00.json": "{a}.json"}


def nettoyer_tenue(sheet_png: bytes, mask_png: bytes, cell: int = 256) -> bytes:
    """Le masque de tenue de pixelforge prend aussi le blanc des yeux (et d'autres petites taches
    claires) : la couleur du joueur teintait les yeux (Julien, 2026-10-19). Par case, on ne garde que
    les grandes plaques (≥ 15 % de la plus grande) dont le centre n'est pas dans le haut du
    perso (la tête, ~45 % de la hauteur)."""
    sheet = np.array(Image.open(io.BytesIO(sheet_png)).convert("RGBA"))
    mask = np.array(Image.open(io.BytesIO(mask_png)).convert("RGBA"))
    out = mask.copy()
    for x0 in range(0, mask.shape[1], cell):
        m = mask[:, x0:x0 + cell, 0] > 8
        alpha = sheet[:, x0:x0 + cell, 3] > 20
        if not m.any() or not alpha.any():
            continue
        ys = np.where(alpha.any(axis=1))[0]
        tete = ys.min() + (ys.max() - ys.min()) * 0.45      # la tête fait près de la moitié du perso
        lab = np.zeros(m.shape, np.int32)
        comps = []
        for y, x in zip(*np.nonzero(m)):
            if lab[y, x]:
                continue
            n = len(comps) + 1
            pile, pts = [(y, x)], []
            lab[y, x] = n
            while pile:
                cy, cx = pile.pop()
                pts.append((cy, cx))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n
                        pile.append((ny, nx))
            comps.append(pts)
        big = max(len(c) for c in comps)
        keep = np.zeros(m.shape, bool)
        for c in comps:
            cy = sum(p[0] for p in c) / len(c)
            if len(c) >= 0.15 * big and cy >= tete:
                for y, x in c:
                    keep[y, x] = True
        # Le masque pixelforge ne couvre qu'une partie de la chemise (Julien : « à moitié colorée ») :
        # on l'étend à tous les pixels clairs et peu saturés (le blanc de la tenue et son ombrage)
        # voisins de la plaque gardée, hors de la tête.
        zone = keep.copy()
        for _ in range(10):
            z = zone.copy()
            z[1:, :] |= zone[:-1, :]
            z[:-1, :] |= zone[1:, :]
            z[:, 1:] |= zone[:, :-1]
            z[:, :-1] |= zone[:, 1:]
            zone = z
        rgb = sheet[:, x0:x0 + cell, :3].astype(float)
        hi, lo = rgb.max(axis=2), rgb.min(axis=2)
        clair = alpha & (hi > 125) & ((hi - lo) < 0.2 * hi + 8)
        rows = np.arange(m.shape[0])[:, None] >= tete
        final = (keep | (clair & zone)) & rows
        val = np.where(keep, mask[:, x0:x0 + cell, 0], np.clip(hi * 1.05, 0, 255)).astype(np.uint8)
        val[~final] = 0
        out[:, x0:x0 + cell, 0] = out[:, x0:x0 + cell, 1] = out[:, x0:x0 + cell, 2] = val
        out[:, x0:x0 + cell, 3] = 255
    buf = io.BytesIO()
    Image.fromarray(out).save(buf, "PNG")
    return buf.getvalue()


def main() -> None:
    pid, taches = sys.argv[1], json.load(open(sys.argv[2]))
    dest = os.path.join(ROOT, "assets", "gordeka", "persos", pid)
    revue = os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "pf")
    os.makedirs(dest, exist_ok=True)
    for anim, tid in taches.items():
        r = json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
        if r.get("status") != "succeeded":
            print(f"{anim} : tâche {tid} {r.get('status')}, ignorée")
            continue
        got = {}
        for f in r["result"]["pixelforge"]["files"]:
            data = None
            if f["name"] in ROLES:
                got[f["name"]] = urllib.request.urlopen(f["url"], timeout=120).read()
            elif f["name"] == "animation_00.gif":
                os.makedirs(os.path.join(revue, anim), exist_ok=True)
                data = urllib.request.urlopen(f["url"], timeout=120).read()
                open(os.path.join(revue, anim, f["name"]), "wb").write(data)
        if "spritesheet_00.png" in got and "tenue_sheet_00.png" in got:
            got["tenue_sheet_00.png"] = nettoyer_tenue(got["spritesheet_00.png"], got["tenue_sheet_00.png"])
        for name, data in got.items():
            open(os.path.join(dest, ROLES[name].format(a=anim)), "wb").write(data)
        print(f"{anim} : ok")


if __name__ == "__main__":
    main()
