#!/usr/bin/env python3
"""Contrôle (et correction) des bordures d'un sprite RGBA généré.

Défauts détectés :
- fente : pixel transparent comblé par une fermeture morphologique (rayon SLIT_R),
  c.-à-d. une entaille étroite où le fond passe (ex. entre menton et col) ;
  et tout petit trou fermé (≤ HOLE_MAX px) dans la silhouette ;
- îlot : composante opaque détachée de moins de ISLAND_MAX pixels ;
- bord clair : pixel opaque au bord de la silhouette qui n'est pas sombre
  (le contour attendu est un trait foncé continu).

Usage : check_borders.py <in.png> [--fix <out.png>] [--report <planche.png>]
Sans --fix : code de sortie 1 si un défaut est trouvé.
"""
from __future__ import annotations

import sys

import numpy as np
from PIL import Image

ISLAND_MAX = 24
# Un vrai vide (entre bras et tête…) doit rester transparent : on ne comble
# que les fentes d'1 px et les trous fermés minuscules.
SLIT_R = 1
HOLE_MAX = 6
DARK_MAX = 60 * 3      # somme R+G+B maximale d'un pixel de contour


def _shift_or(m: np.ndarray, r: int) -> np.ndarray:
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def _shift_and(m: np.ndarray, r: int) -> np.ndarray:
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            out &= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def _components(m: np.ndarray) -> list[np.ndarray]:
    h, w = m.shape
    seen = np.zeros_like(m)
    comps = []
    for sy, sx in zip(*np.nonzero(m)):
        if seen[sy, sx]:
            continue
        stack, pts = [(sy, sx)], []
        seen[sy, sx] = True
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        c = np.zeros_like(m)
        ys, xs = zip(*pts)
        c[list(ys), list(xs)] = True
        comps.append(c)
    return comps


def analyse(a: np.ndarray) -> dict:
    op = a[..., 3] > 0
    pad = np.pad(op, 3)
    closed = _shift_and(_shift_or(pad, SLIT_R), SLIT_R)[3:-3, 3:-3]
    slits = closed & ~op
    comps = _components(op)
    main = max(comps, key=lambda c: c.sum()) if comps else op
    islands = np.zeros_like(op)
    for c in comps:
        if c is not main and c.sum() <= ISLAND_MAX:
            islands |= c
    p = np.pad(op, 1)
    edge = op & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    light = edge & (a[..., :3].astype(int).sum(-1) > DARK_MAX)
    holes = np.zeros_like(op)
    for c in _components(~op):
        ys, xs = np.nonzero(c)
        touches = ys.min() == 0 or xs.min() == 0 or ys.max() == op.shape[0] - 1 or xs.max() == op.shape[1] - 1
        if not touches and c.sum() <= HOLE_MAX:
            holes |= c
    return {"slits": slits | holes, "islands": islands, "light": light, "edge": edge}


def outline_color(a: np.ndarray, edge: np.ndarray) -> tuple:
    vals = a[edge][:, :3].astype(int)
    dark = vals[vals.sum(-1) <= DARK_MAX]
    if len(dark) == 0:
        return (58, 38, 52)
    u, n = np.unique(dark, axis=0, return_counts=True)
    return tuple(int(v) for v in u[n.argmax()])


def fix(a: np.ndarray) -> np.ndarray:
    out = a.copy()
    r = analyse(out)
    out[r["islands"]] = 0
    oc = outline_color(out, r["edge"])
    # Fente : comblée au trait de contour (séparation menton / col, etc.) ;
    # combler peut créer une nouvelle petite fente voisine, d'où la boucle.
    for _ in range(4):
        if not r["slits"].any():
            break
        out[r["slits"], :3] = oc
        out[r["slits"], 3] = 255
        r = analyse(out)
    out[r["light"], :3] = oc
    return out


def report(a: np.ndarray, r: dict, path: str, scale: int = 5) -> None:
    bg = np.zeros_like(a)
    bg[...] = (120, 170, 210, 255)
    base = Image.fromarray(bg, "RGBA")
    base.alpha_composite(Image.fromarray(a, "RGBA"))
    img = np.array(base)
    marked = img.copy()
    marked[r["slits"]] = (255, 0, 255, 255)
    marked[r["islands"]] = (0, 255, 0, 255)
    marked[r["light"]] = (255, 230, 0, 255)
    both = np.concatenate([img, marked], axis=1)
    Image.fromarray(both, "RGBA").resize((both.shape[1] * scale, both.shape[0] * scale), Image.NEAREST).save(path)


def main() -> None:
    src = sys.argv[1]
    a = np.array(Image.open(src).convert("RGBA"))
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    r = analyse(a)
    n = {k: int(r[k].sum()) for k in ("slits", "islands", "light")}
    print(f"{src}: fentes {n['slits']} px, îlots {n['islands']} px, bords clairs {n['light']} px "
          f"(sur {int(r['edge'].sum())} px de bord)")
    if "--report" in sys.argv:
        report(a, r, sys.argv[sys.argv.index("--report") + 1])
    if "--fix" in sys.argv:
        out = fix(a)
        Image.fromarray(out, "RGBA").save(sys.argv[sys.argv.index("--fix") + 1])
        r2 = analyse(out)
        print("après correction :", {k: int(r2[k].sum()) for k in ("slits", "islands", "light")})
    elif any(n.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
