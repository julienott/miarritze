#!/usr/bin/env python3
"""Nettoyage procédural d'une sheet de combattant.

- Bouche les micro-trous d'alpha enclos (≤ MAX_HOLE px) avec la couleur
  dominante des voisins opaques ; les trous plus grands sont de vrais vides.
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


# Au-delà, un trou enclos est un vrai vide (entre bras et corps…) : tous les
# trous des sheets sont bordés de contour, on ne peut pas deviner leur couleur.
MAX_HOLE = 3
# Exception : un trou presque parfaitement rectangulaire est un artefact de
# génération (rectangle découpé dans le maillot de Peio), pas une forme.
RECT_MIN = 20
RECT_FILL = 0.9
# Peio : le rectangle du maillot est parfois un peu rogné (0,75–0,87).
RECT_FILL_BY_FIGHTER = {"peio": 0.75}


def _dilate(mask: np.ndarray) -> np.ndarray:
    pad = np.pad(mask, 1, constant_values=False)
    return (pad[:-2, :-2] | pad[:-2, 1:-1] | pad[:-2, 2:]
            | pad[1:-1, :-2] | pad[1:-1, 2:]
            | pad[2:, :-2] | pad[2:, 1:-1] | pad[2:, 2:] | mask)


def clean_cell(cell: np.ndarray, rect_fill: float = RECT_FILL) -> tuple[np.ndarray, int, int]:
    """Nettoie une cellule : bouche les micro-trous enclos (≤ MAX_HOLE px) avec
    la couleur voisine dominante, enlève les pixels opaques isolés.
    Retourne (nouvelle_cellule, pixels gagnés, pixels isolés retirés).
    """
    out = cell.copy()
    h, w = out.shape
    alpha = out > 0
    if not alpha.any():
        return out, 0, 0
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
    for lab, size in inv_sizes.items():
        if lab in edge_labels or size > MAX_HOLE:
            continue
        enclosed |= inv_labels == lab
    to_fill = enclosed
    holes_filled = 0
    for lab, size in inv_sizes.items():
        if lab in edge_labels or size < RECT_MIN:
            continue
        m = inv_labels == lab
        ys, xs = np.where(m)
        if size / ((np.ptp(ys) + 1) * (np.ptp(xs) + 1)) < rect_fill:
            continue
        # Trou rectangulaire = artefact : on le comble, liseré de contour
        # compris, avec la couleur dominante du tissu juste autour.
        ring1 = _dilate(m) & ~m
        far = _dilate(_dilate(_dilate(ring1))) & ~ring1 & ~m
        votes = Counter(int(v) for v in out[far] if v > 1)
        if votes:
            patch = m | ring1
            out[patch] = votes.most_common(1)[0][0]
            holes_filled += int(m.sum())
    for y, x in zip(*np.where(to_fill)):
        votes = Counter()
        for ny, nx in neighbors8(y, x, h, w):
            v = int(out[ny, nx])
            if v != 0:
                votes[v] += 1
        if votes:
            out[y, x] = votes.most_common(1)[0][0]
            holes_filled += 1
    # Pixels opaques isolés (0 voisin opaque 8).
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
            new, f, i = clean_cell(frame, RECT_FILL_BY_FIGHTER.get(fid, RECT_FILL))
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
