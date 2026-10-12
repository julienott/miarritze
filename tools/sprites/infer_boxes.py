#!/usr/bin/env python3
"""Hurtboxes / hitboxes automatiques (SPEC-BORROKA §11.6).

- hurt (par frame) : bbox opaque découpée en tête 25 % / torse 40 % /
  jambes 35 % de la hauteur, chaque bande réduite à ses pixels opaques puis
  rétrécie de 2 px (tolérance enfant).
- hit (frame `hit_frame` des attaques) : pixels opaques absents de l'idle
  frame 0 (même pied), plus grande composante connexe du côté avant ;
  bbox rétrécie de 1 px.
Coordonnées [x, y, w, h] relatives au pied (64,120), x vers l'avant.
"""
from __future__ import annotations

import numpy as np

FOOT = (64, 120)
REACH = 14          # rayon de la zone de frappe autour de l'extrémité (px)


def _bbox(mask):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def set_foot(foot) -> None:
    global FOOT
    FOOT = tuple(foot)


def _rel(x0, y0, x1, y1, shrink):
    x0, y0, x1, y1 = x0 + shrink, y0 + shrink, x1 - shrink, y1 - shrink
    if x1 - x0 < 2:
        c = (x0 + x1) // 2
        x0, x1 = c - 1, c + 1
    if y1 - y0 < 2:
        c = (y0 + y1) // 2
        y0, y1 = c - 1, c + 1
    return [int(x0 - FOOT[0]), int(y0 - FOOT[1]), int(x1 - x0), int(y1 - y0)]


def hurt_boxes(cell: np.ndarray) -> list:
    m = cell > 0
    bb = _bbox(m)
    if bb is None:
        return []
    x0, y0, x1, y1 = bb
    h = y1 - y0
    cuts = [y0, y0 + round(h * 0.25), y0 + round(h * 0.65), y1]
    boxes = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        band = np.zeros_like(m)
        band[a:b] = m[a:b]
        sub = _bbox(band)
        if sub is not None:
            boxes.append(_rel(*sub, shrink=2))
    return boxes


def _components(mask):
    """Étiquetage 8-connexe simple (pile)."""
    labels = np.zeros(mask.shape, np.int32)
    comps = []
    H, W = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if labels[y, x]:
            continue
        lab = len(comps) + 1
        stack = [(y, x)]
        labels[y, x] = lab
        pts = []
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = lab
                        stack.append((ny, nx))
        comps.append(pts)
    return comps


def hit_box(cell: np.ndarray, idle0: np.ndarray, direction: str = "fwd") -> list | None:
    """Pixels nouveaux par rapport à l'idle ; on garde la composante qui va
    le plus loin vers l'avant/le haut (le membre qui frappe), puis seulement
    son extrémité (rayon REACH autour du point le plus éloigné)."""
    diff = (cell > 0) & ~(idle0 > 0)
    comps = [c for c in _components(diff) if len(c) >= 4]
    cx, cy = FOOT[0], FOOT[1] - int(55 * FOOT[1] / 120)   # centre approximatif du corps

    def reach(p):
        dx = p[1] - cx
        up = cy - p[0]
        if direction == "up":
            return up + 0.3 * dx
        if direction == "low":
            return dx + 0.5 * p[0] - 0.0
        return dx

    if not comps:
        return None
    best = max(comps, key=lambda c: max(reach(p) for p in c))
    tip = max(best, key=reach)
    near = [p for p in best if (p[0] - tip[0]) ** 2 + (p[1] - tip[1]) ** 2 <= REACH * REACH]
    ys = [p[0] for p in near]
    xs = [p[1] for p in near]
    return _rel(min(xs), min(ys), max(xs) + 1, max(ys) + 1, shrink=1)


def infer(cells: dict, meta: dict) -> dict:
    idle0 = cells["idle"][0]
    hurt = {name: [hurt_boxes(c) for c in frames] for name, frames in cells.items()}
    hit = {}
    for name, m in meta.items():
        if "hit_frame" in m:
            box = hit_box(cells[name][m["hit_frame"]], idle0, m.get("hit_dir", "fwd"))
            if box is not None:
                hit[name] = box
    return {"hurt": hurt, "hit": hit}
