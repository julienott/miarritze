#!/usr/bin/env python3
"""Planches contact d'un combattant (SPEC-BORROKA §0.4, §11.3.5).

Usage : contact_sheet.py <id> [--scale 4]
Écrit dans tests/out/sheets/<id>/ :
- page_<n>.png : toutes les animations en grille (×4, nearest), nom à gauche,
  ligne de sol en pointillés ;
- boxes.png : idle + frames de coup avec hurtboxes (vert) / hitbox (rouge), ×2 ;
- costumes.png : idle 0 et coup de poing des 4 costumes côte à côte (×4) ;
- gif/<anim>.gif : chaque animation animée (×4).
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ROWS_PER_PAGE = 6
BG = (40, 44, 60, 255)
BG2 = (52, 58, 78, 255)


def load(fid: str):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = Image.open(os.path.join(d, "palettes.png")).convert("RGBA")
    pal = np.array(pal)
    with open(os.path.join(d, "anims.json")) as f:
        meta = json.load(f)
    return sheet, pal, meta


def cell(sheet, meta, name, i):
    c = meta["cell"]
    a = meta["anims"][name]
    if "first" in a:
        k = a["first"] + i
        cols = meta.get("cols", sheet.shape[1] // c)
        y, x = (k // cols) * c, (k % cols) * c
        return sheet[y:y + c, x:x + c]
    r = a["row"]
    return sheet[r * c:(r + 1) * c, i * c:(i + 1) * c]


def colorize(idx: np.ndarray, pal_row: np.ndarray, bg=(0, 0, 0, 0)) -> Image.Image:
    rgba = pal_row[idx]
    rgba[idx == 0] = bg
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def union_bbox(sheet, meta):
    ys, xs = [], []
    for name, a in meta["anims"].items():
        for i in range(a["frames"]):
            m = cell(sheet, meta, name, i) > 0
            yy, xx = np.nonzero(m)
            if len(yy):
                ys += [yy.min(), yy.max()]
                xs += [xx.min(), xx.max()]
    return max(min(xs) - 3, 0), max(min(ys) - 3, 0), min(max(xs) + 4, meta["cell"]), min(max(ys) + 4, meta["cell"])


def main(fid: str, scale: int = 4) -> list:
    sheet, pal, meta = load(fid)
    out_dir = os.path.join(ROOT, "tests", "out", "sheets", fid)
    os.makedirs(os.path.join(out_dir, "gif"), exist_ok=True)
    x0, y0, x1, y1 = union_bbox(sheet, meta)
    cw, ch = x1 - x0, y1 - y0
    names = list(meta["anims"].keys())
    maxf = max(a["frames"] for a in meta["anims"].values())
    label_w = 120
    written = []
    for p in range(0, len(names), ROWS_PER_PAGE):
        chunk = names[p:p + ROWS_PER_PAGE]
        W = label_w + maxf * cw * scale
        H = len(chunk) * (ch * scale + 6)
        page = Image.new("RGBA", (W, H), BG)
        dr = ImageDraw.Draw(page)
        for r, name in enumerate(chunk):
            a = meta["anims"][name]
            yy = r * (ch * scale + 6)
            dr.text((6, yy + 6), name, fill=(255, 240, 200, 255))
            dr.text((6, yy + 22), f"{a['frames']}f {a['fps']}fps", fill=(180, 180, 200, 255))
            if "hit_frame" in a:
                dr.text((6, yy + 38), f"hit={a['hit_frame']}", fill=(255, 120, 120, 255))
            for i in range(a["frames"]):
                bg = BG2 if i % 2 else BG
                img = colorize(cell(sheet, meta, name, i)[y0:y1, x0:x1], pal[0], bg)
                img = img.resize((cw * scale, ch * scale), Image.NEAREST)
                px = label_w + i * cw * scale
                page.paste(img, (px, yy))
                gy = yy + (meta["foot"][1] - y0) * scale
                for gx in range(px, px + cw * scale, 8):
                    dr.line([(gx, gy), (gx + 3, gy)], fill=(255, 200, 80, 255))
                if a.get("hit_frame") == i:
                    dr.rectangle([px, yy, px + cw * scale - 1, yy + ch * scale - 1], outline=(255, 90, 90, 255), width=2)
        path = os.path.join(out_dir, f"page_{p // ROWS_PER_PAGE + 1}.png")
        page.save(path)
        written.append(path)
    # GIFs
    for name in names:
        a = meta["anims"][name]
        frames = [colorize(cell(sheet, meta, name, i)[y0:y1, x0:x1], pal[0], (90, 96, 120, 255))
                  .resize((cw * scale, ch * scale), Image.NEAREST).convert("RGB") for i in range(a["frames"])]
        frames[0].save(os.path.join(out_dir, "gif", f"{name}.gif"), save_all=True,
                       append_images=frames[1:], duration=int(1000 / a["fps"]), loop=0)
    # Costumes
    picks = [("idle", 0), ("punch_1", meta["anims"]["punch_1"].get("hit_frame", 0)), ("kick", 3)]
    cos = Image.new("RGBA", (len(picks) * 4 * cw * scale, ch * scale + 20), BG)
    dr = ImageDraw.Draw(cos)
    for k in range(4):
        for j, (name, i) in enumerate(picks):
            img = colorize(cell(sheet, meta, name, i)[y0:y1, x0:x1], pal[k], BG)
            cos.paste(img.resize((cw * scale, ch * scale), Image.NEAREST), ((k * len(picks) + j) * cw * scale, 20))
        dr.text((k * len(picks) * cw * scale + 8, 4), f"costume {k + 1}", fill=(255, 240, 200, 255))
    path = os.path.join(out_dir, "costumes.png")
    cos.save(path)
    written.append(path)
    # Boîtes
    s2 = 2
    show = ["idle"] + [n for n in names if "hit_frame" in meta["anims"][n]]
    cols = 8
    rows = (len(show) + cols - 1) // cols
    bx = Image.new("RGBA", (cols * cw * s2, rows * (ch * s2 + 14)), BG)
    dr = ImageDraw.Draw(bx)
    fx, fy = meta["foot"]
    for n, name in enumerate(show):
        i = meta["anims"][name].get("hit_frame", 0)
        img = colorize(cell(sheet, meta, name, i)[y0:y1, x0:x1], pal[0], BG)
        ox, oy = (n % cols) * cw * s2, (n // cols) * (ch * s2 + 14)
        bx.paste(img.resize((cw * s2, ch * s2), Image.NEAREST), (ox, oy + 14))
        dr.text((ox + 2, oy + 1), name, fill=(255, 240, 200, 255))

        def rect(b, col):
            rx, ry, rw, rh = b
            ax = ox + (fx + rx - x0) * s2
            ay = oy + 14 + (fy + ry - y0) * s2
            dr.rectangle([ax, ay, ax + rw * s2 - 1, ay + rh * s2 - 1], outline=col, width=1)
        for b in meta["boxes"]["hurt"][name][i]:
            rect(b, (90, 230, 120, 255))
        if name in meta["boxes"]["hit"]:
            rect(meta["boxes"]["hit"][name], (255, 70, 70, 255))
    path = os.path.join(out_dir, "boxes.png")
    bx.save(path)
    written.append(path)
    return written


if __name__ == "__main__":
    scale = 4
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    for p in main(sys.argv[1], scale):
        print(p)
