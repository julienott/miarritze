#!/usr/bin/env python3
"""Relecture d'un perso refait par from_rig.py : pour chaque animation, ligne
« rig d'origine » puis ligne « redessin », ×3 nearest ; pixels détachés de la
plus grande composante en magenta (4-connexité, comme la QA serveur), ce qui
permet de trier vrais débris / accessoire séparé / fausse alerte.
Usage : inspect_lot.py <id> [anim …]   → tests/out/pf/<id>_inspect.png
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
import from_rig  # noqa: E402
import pieces  # noqa: E402
import redraw  # noqa: E402
from despeck_sheet import comps  # noqa: E402

Z = 3
BG = (214, 236, 246, 255)


def detached(f):
    """Masque des pixels hors de la plus grande composante (8-connexité : un
    trait en diagonale n'est pas un débris)."""
    m = np.array(f)[..., 3] > 127
    cs = comps8(m)
    out = np.zeros(m.shape, bool)
    if len(cs) < 2:
        return out
    big = max(cs, key=len)
    for c in cs:
        if c is not big:
            ys, xs = zip(*c)
            out[list(ys), list(xs)] = True
    return out


def comps8(m):
    lab = np.zeros(m.shape, int)
    out = []
    for sy, sx in zip(*np.nonzero(m)):
        if lab[sy, sx]:
            continue
        stack, pts = [(sy, sx)], []
        lab[sy, sx] = len(out) + 1
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = len(out) + 1
                        stack.append((ny, nx))
        out.append(pts)
    return out


def tile(f, mark=None):
    bg = Image.new("RGBA", f.size, BG)
    bg.alpha_composite(f)
    a = np.array(bg)
    if mark is not None:
        a[mark] = (255, 0, 255, 255)
    return Image.fromarray(a).resize((f.width * Z, f.height * Z), Image.NEAREST)


def main():
    fid = sys.argv[1]
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    done = json.load(open(os.path.join(od, "anims.json")))
    verdicts = json.load(open(os.path.join(od, "pf", "verdicts.json")))
    meta, data, idx, pal = redraw.load(fid)
    foot = tuple(meta["foot"])
    names = [a for a in sys.argv[2:]] or list(done)
    rows = []
    stats = {}
    for name in names:
        strip = Image.open(done[name]).convert("RGBA")
        new = [strip.crop((i * pieces.CELL, 0, (i + 1) * pieces.CELL, pieces.CELL))
               for i in range(strip.width // pieces.CELL)]
        old = [from_rig.window(f, foot) for f in redraw.frames(meta, idx, pal, name)]
        dets = [detached(f) for f in new]
        stats[name] = max(int(d.sum()) for d in dets)
        rows.append((f"{name}  détachés(8c)={stats[name]}  {verdicts.get(name, '')[:90]}",
                     [tile(f) for f in old], [tile(f, d) for f, d in zip(new, dets)]))
    W = max(len(r[1]) for r in rows) * pieces.CELL * Z
    H = sum(16 + 2 * pieces.CELL * Z for _ in rows)
    sheet = Image.new("RGBA", (W, H), (24, 20, 28, 255))
    d = ImageDraw.Draw(sheet)
    y = 0
    for title, olds, news in rows:
        d.text((4, y + 2), title, fill=(255, 210, 90, 255))
        y += 16
        for i, t in enumerate(olds):
            sheet.paste(t, (i * t.width, y))
        y += pieces.CELL * Z
        for i, t in enumerate(news):
            sheet.paste(t, (i * t.width, y))
        y += pieces.CELL * Z
    out = os.path.join(ROOT, "tests", "out", "pf", f"{fid}_inspect.png")
    sheet.save(out)
    print(out)
    print(json.dumps(stats))


if __name__ == "__main__":
    main()
