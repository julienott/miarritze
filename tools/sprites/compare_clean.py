#!/usr/bin/env python3
"""Compare la sheet nettoyée à l'originale, image côte à côte zoomée.

Usage : compare_clean.py <id> [--scale 6]
Produit tests/out/qa/<id>_before_after.png — avant à gauche, après à droite,
sur damier rose/blanc avec les trous d'alpha mis en rouge vif.
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


def colorize(idx: np.ndarray, pal_row: np.ndarray) -> np.ndarray:
    rgba = pal_row[idx].astype(np.uint8)
    rgba[idx == 0] = (0, 0, 0, 0)
    return rgba


def flag_holes(rgba: np.ndarray) -> np.ndarray:
    alpha = rgba[..., 3] > 0
    pad = np.pad(alpha, 1, constant_values=False)
    n = (pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1].astype(int)
         + pad[1:-1, :-2].astype(int) + pad[1:-1, 2:].astype(int))
    holes = (~alpha) & (n >= 3)
    out = rgba.copy()
    out[holes] = HOLE
    return out


def checker(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), LIGHT)
    draw = ImageDraw.Draw(img)
    for y in range(0, h, TILE):
        for x in range(0, w, TILE):
            if ((x // TILE) + (y // TILE)) & 1:
                draw.rectangle((x, y, x + TILE - 1, y + TILE - 1), PINK)
    return img


def render(sheet: np.ndarray, pal_row: np.ndarray, scale: int) -> Image.Image:
    rgba = colorize(sheet, pal_row)
    rgba = flag_holes(rgba)
    img = Image.fromarray(rgba, "RGBA")
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    bg = checker(img.width, img.height)
    bg.alpha_composite(img)
    return bg


def main() -> None:
    fid = sys.argv[1]
    scale = 2
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    d = os.path.join(ROOT, "assets", "fighters", fid)
    orig = np.array(Image.open(os.path.join(d, "sheet.orig.png")))
    new = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    img_before = render(orig, pal, scale)
    img_after = render(new, pal, scale)
    label_h = 40
    font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/press_start_2p.ttf"), 16)
    canvas = Image.new("RGBA",
                        (img_before.width + img_after.width + 16, img_before.height + label_h),
                        (24, 16, 28, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((img_before.width // 2, 20), f"AVANT  {fid}", fill=(244, 198, 62, 255), font=font,
              anchor="mm")
    draw.text((img_before.width + 16 + img_after.width // 2, 20), f"APRÈS  {fid}",
              fill=(100, 220, 120, 255), font=font, anchor="mm")
    canvas.paste(img_before, (0, label_h))
    canvas.paste(img_after, (img_before.width + 16, label_h))
    out = os.path.join(ROOT, "tests", "out", "qa", f"{fid}_before_after.png")
    canvas.save(out)
    print(out, canvas.width, "x", canvas.height)


if __name__ == "__main__":
    main()
