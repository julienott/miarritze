#!/usr/bin/env python3
"""Lampe du chasseur : position de la main qui tient la lampe, image par image, dans l'animation
hunter_reveal des persos (Julien, 2026-10-20 : les faisceaux dessinés par l'IA « pas crédibles » ;
c'est le jeu qui dessine le cône de lumière, src/gordeka/gk_lampe.gd). Les PNG ne sont jamais
réécrits : le résultat va dans <anim>.json :

  "lampe": {"debut": <image où le faisceau s'allume>, "points": [[x, y] | null, …]}

(px de case, perso tourné vers la droite, avant frame_offsets : le jeu les applique à la case entière).

  lampe.py [<id>…] [--anim hunter_reveal] [--ecrire] [--planches <dossier>]

Sans --ecrire : mesure seulement. import_perso.py appelle corriger_perso() après chaque import.

Méthode, image par image (case 256×256) :
- le contour sombre du perso (gros trait bleu nuit) : le faisceau peint par l'IA n'en a pas, il est
  donc ignoré ; on garde la plus grande tache de contour (le corps, bras compris) ;
- au repos (image 0), bord droit de la silhouette ligne par ligne, dans la bande du bras (BANDE_K) ;
- main = pixel de contour le plus à droite parmi ceux qui dépassent ce bord de plus de TENDU_PX (la
  tête, le nez, la barbe ne dépassent pas leur propre bord du repos ; ce bord suit le dos du perso,
  qui se décale un peu d'une image à l'autre) ; aucun : bras baissé, point null ;
- médiane glissante des mains sur LISSAGE images (éclats de faisceau, secousses d'une image) ;
- debut = première image tendue à partir de laquelle la main bouge de moins de STABLE_PX pendant
  STABLE_N images (les secousses de la lampe passent avant).
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_json  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PERSOS = os.path.join(ROOT, "assets", "gordeka", "persos")

ANIMS = ("hunter_reveal",)
ALPHA_MIN = 128
SOMBRE = 95          # luminance max d'un pixel de contour
BANDE_K = (0.12, 0.66)  # bande du bras : part de la hauteur du perso, depuis le haut
TENDU_PX = 18        # la main dépasse le bord du repos d'au moins ça (px de case)
STABLE_PX = 7.0      # mouvement max de la main pour la dire stable
STABLE_N = 4         # pendant autant d'images
LISSAGE = 5          # fenêtre de la médiane glissante des mains (images)


def _contour(case: np.ndarray) -> np.ndarray:
    """Masque du contour sombre principal d'une case RGBA (plus grande tache, 8-connexité)."""
    rgb = case[..., :3].astype(np.float32)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    m = (case[..., 3] > ALPHA_MIN) & (lum < SOMBRE)
    lab = np.zeros(m.shape, np.int32)
    tailles = [0]
    for y, x in zip(*np.nonzero(m)):
        if lab[y, x]:
            continue
        n = len(tailles)
        pile = [(y, x)]
        lab[y, x] = n
        t = 0
        while pile:
            cy, cx = pile.pop()
            t += 1
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n
                        pile.append((ny, nx))
        tailles.append(t)
    if len(tailles) == 1:
        return m
    return lab == int(np.argmax(tailles))


def _gauche(a: np.ndarray, y0: int, y1: int) -> float:
    """Bord gauche (le dos) de la silhouette dans la bande, médiane des lignes."""
    xs = [int(np.argmax(r)) for r in a[y0:y1 + 1] if r.any()]
    return float(np.median(xs)) if xs else 0.0


def analyser(png: str, meta: dict) -> dict:
    """{"debut" (None si le bras n'est jamais tendu et stable), "points", "bruts" (mains avant le
    début comprises), "repos", "bande"} pour une planche ; {} si la planche est vide."""
    im = np.array(Image.open(png).convert("RGBA"))
    cw, ch = (meta.get("cell") or [256, 256])[:2]
    n = int(meta.get("frames", im.shape[1] // cw))
    cases = [im[:ch, i * cw:(i + 1) * cw] for i in range(n)]
    a0 = cases[0][..., 3] > ALPHA_MIN
    ys = np.nonzero(a0.any(axis=1))[0]
    if ys.size == 0:
        return {}
    haut, bas = int(ys.min()), int(ys.max())
    y0 = haut + int((bas - haut) * BANDE_K[0])
    y1 = haut + int((bas - haut) * BANDE_K[1])
    # Bord droit du repos, ligne par ligne (élargi de quelques lignes : la tête bouge un peu).
    bord = np.full(ch, -1, np.int32)
    for y in range(ch):
        xs0 = np.nonzero(a0[max(0, y - 4):y + 5].any(axis=0))[0]
        if xs0.size:
            bord[y] = xs0.max()
    repos = bord[y0:y1 + 1].tolist()
    gauche0 = _gauche(a0, y0, y1)
    points = []
    for c in cases:
        # Le perso se décale un peu d'une image à l'autre : le bord du repos suit son dos (bord gauche).
        dx = _gauche(c[..., 3] > ALPHA_MIN, y0, y1) - gauche0
        m = _contour(c)[y0:y1 + 1]
        cols = np.arange(cw)[None, :]
        m = m & (cols > (np.array(repos)[:, None] + dx + TENDU_PX))
        xs = np.nonzero(m.any(axis=0))[0]
        if xs.size == 0:
            points.append(None)
            continue
        x = int(xs.max())
        # Main : le bout du bras, centré verticalement sur les pixels de contour des 6 dernières colonnes.
        bout = m[:, max(0, x - 6):x + 1]
        yy = np.nonzero(bout.any(axis=1))[0]
        points.append([x, y0 + int(round((yy.min() + yy.max()) / 2.0))])
    # Médiane glissante sur LISSAGE images tendues : un éclat de faisceau cerné de sombre ou une
    # secousse d'une image ne fait pas sauter la lampe.
    lisse = []
    for i, p in enumerate(points):
        if p is None:
            lisse.append(None)
            continue
        v = [q for q in points[max(0, i - LISSAGE // 2):i + LISSAGE // 2 + 1] if q is not None]
        lisse.append([int(np.median([q[0] for q in v])), int(np.median([q[1] for q in v]))])
    points = lisse
    debut = None
    for i, p in enumerate(points):
        if p is None:
            continue
        suite = points[i:i + STABLE_N]
        if len(suite) < min(STABLE_N, n - i) or any(q is None for q in suite):
            continue
        if all(abs(q[0] - p[0]) <= STABLE_PX and abs(q[1] - p[1]) <= STABLE_PX for q in suite):
            debut = i
            break
    return {"debut": debut, "points": [p if debut is not None and i >= debut else None
                                       for i, p in enumerate(points)],
            "bruts": points, "repos": repos, "bande": [y0, y1]}


def ecrire(chemin: str, r: dict) -> bool:
    """Ajoute (ou retire) "lampe" dans le .json de l'anim ; le reste du fichier est conservé."""
    brut = open(chemin).read()
    j = json.loads(brut)
    j.pop("lampe", None)
    if r and r.get("debut") is not None:
        j["lampe"] = {"debut": r["debut"], "points": r["points"]}
    # Format commun des .json d'anim (anim_json.py).
    texte = anim_json.formater(j)
    if texte == brut:
        return False
    with open(chemin, "w") as fh:
        fh.write(texte)
    return True


def corriger_perso(pid: str, anims=ANIMS, ecrit: bool = True) -> dict:
    """Point d'entrée d'import_perso.py : mesure la lampe des anims du perso et l'écrit."""
    res = {}
    for anim in anims:
        base = os.path.join(PERSOS, pid, anim)
        if not (os.path.exists(base + ".png") and os.path.exists(base + ".json")):
            continue
        r = analyser(base + ".png", json.load(open(base + ".json")))
        res[f"{pid}/{anim}"] = r
        if ecrit:
            ecrire(base + ".json", r)
    return res


def planche(png: str, r: dict, sortie: str) -> None:
    """Planche de contrôle : chaque image, bande du bras (bleu), bord du repos (magenta), main (rouge
    avant le début, jaune ensuite) ; numéro d'image."""
    im = Image.open(png).convert("RGBA")
    n = im.width // 256
    cols = 11
    out = Image.new("RGBA", (cols * 256, ((n + cols - 1) // cols) * 256), (190, 190, 190, 255))
    for i in range(n):
        c = Image.new("RGBA", (256, 256), (190, 190, 190, 255))
        c.alpha_composite(im.crop((i * 256, 0, i * 256 + 256, 256)))
        d = ImageDraw.Draw(c)
        if r:
            y0, y1 = r["bande"]
            d.line([(0, y0), (255, y0)], fill=(60, 90, 255))
            d.line([(0, y1), (255, y1)], fill=(60, 90, 255))
            d.line([(x, y0 + k) for k, x in enumerate(r["repos"])], fill=(255, 0, 255))
            p = r["bruts"][i]
            if p:
                coul = (255, 220, 0) if r["points"][i] else (255, 0, 0)
                d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], outline=coul, width=3)
        d.text((4, 4), str(i), fill=(0, 0, 0))
        out.alpha_composite(c, ((i % cols) * 256, (i // cols) * 256))
    out.convert("RGB").save(sortie)


def main() -> None:
    args = sys.argv[1:]
    ecrit = "--ecrire" in args
    anims, dossier = ANIMS, None
    if "--anim" in args:
        anims = tuple(args[args.index("--anim") + 1].split(","))
    if "--planches" in args:
        dossier = args[args.index("--planches") + 1]
        os.makedirs(dossier, exist_ok=True)
    ids = [a for a in args if not a.startswith("--") and a not in anims and a != dossier]
    ids = ids or sorted(os.listdir(PERSOS))
    for pid in ids:
        res = corriger_perso(pid, anims, ecrit)
        for cle, r in res.items():
            if dossier and r:
                planche(os.path.join(PERSOS, pid, cle.split("/")[1] + ".png"), r,
                        os.path.join(dossier, cle.replace("/", "_") + ".png"))
            if not r or r["debut"] is None:
                print(f"{cle} : main tendue introuvable ({r.get('bruts') if r else ''})")
                continue
            nb = sum(1 for p in r["points"] if p)
            print(f"{cle} : début {r['debut']}, {nb} images éclairées, main {r['points'][r['debut']]}")


if __name__ == "__main__":
    main()
