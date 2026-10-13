#!/usr/bin/env python3
"""Comparaison focalisée : UNE frame représentative par combattant, zoom ×6,
avant à gauche / après à droite. Image compacte à partager vite.

Usage : compare_focus.py <id> [anim] [frame]  (défaut : idle 0)
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PINK = (255, 0, 190, 255)
LIGHT = (240, 240, 240, 255)
HOLE = (255, 32, 32, 255)
TILE = 8
SCALE = 6


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


def crop_bbox(cell_img: np.ndarray, pad: int = 4):
    ys, xs = np.where(cell_img > 0)
    if len(ys) == 0:
        return cell_img
    y0 = max(0, ys.min() - pad)
    y1 = min(cell_img.shape[0], ys.max() + pad + 1)
    x0 = max(0, xs.min() - pad)
    x1 = min(cell_img.shape[1], xs.max() + pad + 1)
    return cell_img[y0:y1, x0:x1]


def colorize_hole(idx: np.ndarray, pal_row: np.ndarray) -> np.ndarray:
    rgba = pal_row[idx].astype(np.uint8)
    rgba[idx == 0] = (0, 0, 0, 0)
    alpha = idx > 0
    pad = np.pad(alpha, 1, constant_values=False)
    n = (pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1].astype(int)
         + pad[1:-1, :-2].astype(int) + pad[1:-1, 2:].astype(int))
    holes = (~alpha) & (n >= 3)
    rgba[holes] = HOLE
    return rgba


def checker(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), LIGHT)
    draw = ImageDraw.Draw(img)
    for y in range(0, h, TILE):
        for x in range(0, w, TILE):
            if ((x // TILE) + (y // TILE)) & 1:
                draw.rectangle((x, y, x + TILE - 1, y + TILE - 1), PINK)
    return img


def render(idx: np.ndarray, pal_row: np.ndarray) -> Image.Image:
    rgba = colorize_hole(idx, pal_row)
    img = Image.fromarray(rgba, "RGBA")
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    bg = checker(img.width, img.height)
    bg.alpha_composite(img)
    return bg


def main() -> None:
    fid = sys.argv[1]
    anim = sys.argv[2] if len(sys.argv) > 2 else "idle"
    frame = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    orig = np.array(Image.open(os.path.join(d, "sheet.orig.png")))
    new = np.array(Image.open(os.path.join(d, "sheet.png")))
    cell_b = crop_bbox(cell(orig, meta, anim, frame))
    cell_a = crop_bbox(cell(new, meta, anim, frame))
    # Même taille (unifier pour alignement visuel)
    h = max(cell_b.shape[0], cell_a.shape[0])
    w = max(cell_b.shape[1], cell_a.shape[1])
    def pad(c):
        out = np.zeros((h, w), dtype=np.uint8)
        out[:c.shape[0], :c.shape[1]] = c
        return out
    img_b = render(pad(cell_b), pal)
    img_a = render(pad(cell_a), pal)
    label_h = 40
    gap = 16
    canvas = Image.new("RGBA",
                        (img_b.width + img_a.width + gap, img_b.height + label_h),
                        (24, 16, 28, 255))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/press_start_2p.ttf"), 14)
    draw.text((img_b.width // 2, 20), f"AVANT  {fid}/{anim}#{frame}",
              fill=(244, 198, 62, 255), font=font, anchor="mm")
    draw.text((img_b.width + gap + img_a.width // 2, 20),
              f"APRÈS  {fid}/{anim}#{frame}",
              fill=(100, 220, 120, 255), font=font, anchor="mm")
    canvas.paste(img_b, (0, label_h))
    canvas.paste(img_a, (img_b.width + gap, label_h))
    out = os.path.join(ROOT, "tests", "out", "qa", f"focus_{fid}_{anim}{frame}.png")
    canvas.save(out)
    print(out)


if __name__ == "__main__":
    main()
