#!/usr/bin/env python3
"""Nettoyage procédural d'une sheet de combattant.

- Bouche les petits trous d'alpha (pixel transparent avec ≥7/8 voisins opaques)
  en reprenant la couleur dominante des voisins opaques.
- Enlève les pixels isolés (opaque avec 0 voisin opaque).
- Travaille cellule par cellule (160×160) : jamais à cheval entre deux frames.
- Travaille sur une COPIE : la sheet originale est sauvegardée en
  sheet.orig.png si elle ne l'est pas déjà.

Usage : clean_alpha.py <id>  (ou `all`)
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def neighbors8(y: int, x: int, h: int, w: int):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w:
                yield ny, nx


def neighbors4(y: int, x: int, h: int, w: int):
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w:
            yield ny, nx


def _flood_labels(alpha: np.ndarray) -> tuple[np.ndarray, dict]:
    """Composantes connexes 4-voisins (0 = transparent, 1..N = labels)."""
    h, w = alpha.shape
    labels = np.zeros((h, w), dtype=np.int32)
    sizes: dict[int, int] = {}
    cur = 0
    for sy in range(h):
        for sx in range(w):
            if alpha[sy, sx] and labels[sy, sx] == 0:
                cur += 1
                stack = [(sy, sx)]
                sz = 0
                while stack:
                    y, x = stack.pop()
                    if labels[y, x] != 0 or not alpha[y, x]:
                        continue
                    labels[y, x] = cur
                    sz += 1
                    for ny, nx in neighbors4(y, x, h, w):
                        if labels[ny, nx] == 0 and alpha[ny, nx]:
                            stack.append((ny, nx))
                sizes[cur] = sz
    return labels, sizes


def _dilate(mask: np.ndarray) -> np.ndarray:
    """Dilatation 8-voisins d'un masque booléen."""
    pad = np.pad(mask, 1, constant_values=False)
    return (pad[:-2, :-2] | pad[:-2, 1:-1] | pad[:-2, 2:]
            | pad[1:-1, :-2] | pad[1:-1, 1:-1] | pad[1:-1, 2:]
            | pad[2:, :-2] | pad[2:, 1:-1] | pad[2:, 2:])


def clean_cell(cell: np.ndarray) -> tuple[np.ndarray, int, int]:
    """Nettoie une cellule.
    Pipeline (du plus sûr au plus large) :
    1. Bouche TOUT trou totalement enclos (composante transparente qui ne
       touche aucun bord de la frame ET dont le bbox est à l'intérieur du
       bbox du sprite) : les trous dans le corps, grands ou petits.
    2. « Fermeture morphologique » légère de l'alpha (dilate puis erode 1 px)
       pour recoller les quasi-trous d'1 px de large (effet « poil manquant »).
    3. Enlève les pixels opaques isolés (0 voisin opaque 8).
    Retourne (nouvelle_cellule, pixels gagnés, pixels isolés retirés).
    """
    out = cell.copy()
    h, w = out.shape
    alpha = out > 0
    if not alpha.any():
        return out, 0, 0
    # 1. Trous enclos par le sprite (plus de limite de taille).
    inv_labels, inv_sizes = _flood_labels(~alpha)
    edge_labels: set[int] = set()
    for y in (0, h - 1):
        for x in range(w):
            if inv_labels[y, x] != 0:
                edge_labels.add(int(inv_labels[y, x]))
    for x in (0, w - 1):
        for y in range(h):
            if inv_labels[y, x] != 0:
                edge_labels.add(int(inv_labels[y, x]))
    enclosed = np.zeros_like(alpha)
    for lab in inv_sizes:
        if lab in edge_labels:
            continue
        enclosed |= inv_labels == lab
    # 2. Fermeture morphologique : nouveaux pixels = (dilate ∩ erode-dilate)
    # autrement dit, les transparents dont les 4 voisins cardinaux sont tous
    # opaques (ou dilaté puis érodé). On garde une version ultra-conservatrice.
    pad = np.pad(alpha, 1, constant_values=False).astype(int)
    neigh4 = pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
    close_fill = (~alpha) & (neigh4 == 4)
    # Les trous enclos + la fermeture : on fusionne.
    to_fill = enclosed | close_fill
    holes_filled = 0
    for y, x in zip(*np.where(to_fill)):
        votes = Counter()
        for ny, nx in neighbors8(y, x, h, w):
            v = int(out[ny, nx])
            if v != 0:
                votes[v] += 1
        if votes:
            out[y, x] = votes.most_common(1)[0][0]
            holes_filled += 1
    # 3. Pixels opaques isolés (0 voisin opaque 8).
    pad = np.pad(out > 0, 1, constant_values=False).astype(int)
    neigh8 = (pad[:-2, :-2] + pad[:-2, 1:-1] + pad[:-2, 2:]
              + pad[1:-1, :-2] + pad[1:-1, 2:]
              + pad[2:, :-2] + pad[2:, 1:-1] + pad[2:, 2:])
    isolated = (out > 0) & (neigh8 == 0)
    isolated_removed = int(isolated.sum())
    out[isolated] = 0
    return out, holes_filled, isolated_removed


def process(fid: str) -> dict:
    d = os.path.join(ROOT, "assets", "fighters", fid)
    sheet_path = os.path.join(d, "sheet.png")
    orig_path = os.path.join(d, "sheet.orig.png")
    if not os.path.exists(orig_path):
        # Première passe : on garde l'original intact.
        Image.open(sheet_path).save(orig_path)
    im = np.array(Image.open(orig_path))
    meta = json.load(open(os.path.join(d, "anims.json")))
    cell = meta["cell"]
    cols = meta.get("cols", im.shape[1] // cell)
    rows = im.shape[0] // cell
    out = im.copy()
    total_filled = 0
    total_isolated = 0
    for ry in range(rows):
        for rx in range(cols):
            y0, x0 = ry * cell, rx * cell
            frame = out[y0:y0 + cell, x0:x0 + cell]
            if (frame > 0).sum() == 0:
                continue
            new, f, i = clean_cell(frame)
            out[y0:y0 + cell, x0:x0 + cell] = new
            total_filled += f
            total_isolated += i
    Image.fromarray(out, mode="L").save(sheet_path)
    stats = {"holes_filled": total_filled, "isolated_removed": total_isolated}
    print(f"{fid}: {stats}")
    return stats


def main() -> None:
    args = sys.argv[1:] or ["all"]
    if args == ["all"]:
        args = [
            "louis", "maia", "patxi", "xabi", "mattin", "amaia",
            "txomin", "kaio", "karramarro", "ramuntxo", "itsaso", "peio",
            "itsasargi", "hondar",
        ]
    for fid in args:
        process(fid)


if __name__ == "__main__":
    main()
