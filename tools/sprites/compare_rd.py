#!/usr/bin/env python3
"""Planche comparative mannequin (ligne du haut) vs RD (ligne du bas) pour
quelques frames clés : tests/out/sheets/compare_rd.png (×2)."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
KEYS = [("idle", 0), ("walk", 2), ("punch_1", "hit"), ("kick", "hit"), ("uppercut", "hit"),
        ("sweep", "hit"), ("sp_neutral", "hit"), ("hit_high", 1), ("knockdown", 5), ("win", 0)]


def frame(d, sheet_name, meta_name, anim, i, cell_out):
    meta = json.load(open(os.path.join(d, meta_name)))
    sheet = np.array(Image.open(os.path.join(d, sheet_name)))
    c, cols = meta["cell"], meta.get("cols", 16)
    a = meta["anims"][anim]
    if i == "hit":
        i = a.get("hit_frame", a["frames"] // 2)
    k = a["first"] + i
    f = sheet[(k // cols) * c:(k // cols + 1) * c, (k % cols) * c:(k % cols + 1) * c]
    out = np.zeros((cell_out, cell_out), np.uint8)
    fx, fy = meta["foot"]
    ox, oy = cell_out // 2 - fx, cell_out - 8 - fy
    ys, xs = np.nonzero(f)
    for y, x in zip(ys, xs):
        if 0 <= y + oy < cell_out and 0 <= x + ox < cell_out:
            out[y + oy, x + ox] = f[y, x]
    return out


def sources(fid):
    """(dossier, feuille, anims, palette) mannequin puis RD. Phase 7 : le
    mannequin vient de tests/out/rig/mannequin/<id>/ (extrait du commit)."""
    d = os.path.join(ROOT, "assets", "fighters", fid)
    pal = os.path.join(d, "palettes.png")
    if os.path.exists(os.path.join(d, "sheet_mannequin.png")):
        man = (d, "sheet_mannequin.png", "anims_mannequin.json", pal)
    else:
        m = os.path.join(ROOT, "tests", "out", "rig", "mannequin", fid)
        man = (m, "sheet.png", "anims.json", os.path.join(m, "palettes.png"))
    return [man, (d, "sheet.png", "anims.json", pal)]


def main(ids, out="compare_rd.png"):
    C = max(json.load(open(os.path.join(ROOT, "assets", "fighters", f, "anims.json")))["cell"] for f in ids)
    rows = []
    for fid in ids:
        for d, sheet, meta, palp in sources(fid):
            pal = np.array(Image.open(palp).convert("RGBA"))[0]
            rows.append([Image.fromarray(pal[frame(d, sheet, meta, a, i, C)].astype(np.uint8), "RGBA") for a, i in KEYS])
    img = Image.new("RGBA", (len(KEYS) * C, len(rows) * C), (90, 96, 120, 255))
    dr = ImageDraw.Draw(img)
    for r, row in enumerate(rows):
        if r % 2 == 0:
            dr.rectangle([0, r * C, img.width, r * C + C - 1], fill=(74, 80, 104, 255))
        for k, t in enumerate(row):
            img.alpha_composite(t, (k * C, r * C))
    img = img.resize((img.width, img.height), Image.NEAREST)
    path = os.path.join(ROOT, "tests", "out", "sheets", out)
    img.save(path)
    print(path, img.size)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = "compare_rd.png"
    if "--out" in args:
        k = args.index("--out")
        out = args[k + 1]
        del args[k:k + 2]
    main(args or ["louis", "maia", "patxi", "xabi"], out)
