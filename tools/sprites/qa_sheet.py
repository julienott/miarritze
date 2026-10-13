#!/usr/bin/env python3
"""Planche QA transparence : la sheet d'un combattant posée sur un damier
magenta / blanc, scale ×2 (nearest), avec les trous d'alpha dans le corps du
sprite surlignés en rouge vif. Utile pour repérer rapidement les
transparences parasites et les traits noirs sur les planches générées.

Usage : qa_sheet.py <id>  (ou `all`)
Écrit dans tests/out/qa/<id>.png
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SCALE = 2
TILE = 8  # taille du damier
PINK = (255, 0, 190, 255)
LIGHT = (240, 240, 240, 255)
HOLE = (255, 32, 32, 255)   # trous d'alpha signalés


def load(fid: str):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    sheet = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))
    with open(os.path.join(d, "anims.json")) as f:
        meta = json.load(f)
    return sheet, pal, meta


def colorize(idx: np.ndarray, pal_row: np.ndarray) -> np.ndarray:
    rgba = pal_row[idx].astype(np.uint8)
    rgba[idx == 0] = (0, 0, 0, 0)
    return rgba


def flag_holes(rgba: np.ndarray) -> np.ndarray:
    """Marque en rouge les pixels transparents entourés d'opaques (trous)."""
    alpha = rgba[..., 3] > 0
    if not alpha.any():
        return rgba
    # Un pixel est un trou s'il est transparent et a au moins 3 voisins opaques
    # sur 4 (haut/bas/gauche/droite). Repère les percements internes sans
    # colorer tout le fond.
    pad = np.pad(alpha, 1, constant_values=False)
    neighbors = (
        pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1].astype(int)
        + pad[1:-1, :-2].astype(int) + pad[1:-1, 2:].astype(int)
    )
    holes = (~alpha) & (neighbors >= 3)
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


def build(fid: str, out_path: str) -> None:
    sheet, pal, meta = load(fid)
    cell = meta["cell"]
    cols = meta.get("cols", sheet.shape[1] // cell)
    pal0 = pal[0]
    # Reconstruit la sheet complète en RGBA avec la palette 0 (costume neutre).
    composed = colorize(sheet, pal0)
    # Trous d'alpha
    composed = flag_holes(composed)
    sh = Image.fromarray(composed, "RGBA")
    # Scale ×2 nearest
    sh = sh.resize((sh.width * SCALE, sh.height * SCALE), Image.NEAREST)
    bg = checker(sh.width, sh.height)
    bg.alpha_composite(sh)
    # Étiquettes de ligne (noms d'animation) à gauche
    label_w = 140
    canvas = Image.new("RGBA", (bg.width + label_w, bg.height), (24, 16, 28, 255))
    canvas.paste(bg, (label_w, 0))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/press_start_2p.ttf"), 14)
    except Exception:
        font = ImageFont.load_default()
    anims_by_row = {}
    for name, a in meta["anims"].items():
        anims_by_row.setdefault(a["row"], []).append(name)
    row_h = cell * SCALE
    for row, names in anims_by_row.items():
        label = ", ".join(names)
        draw.text((6, row * row_h + 8), label, fill=(244, 198, 62, 255), font=font)
        draw.text((6, row * row_h + 28), f"r{row}", fill=(180, 180, 180, 255), font=font)
    # En-tête : rappel que ROSE/BLANC = transparent, ROUGE = trou d'alpha dans le corps
    header = Image.new("RGBA", (canvas.width, 40), (24, 16, 28, 255))
    hd = ImageDraw.Draw(header)
    hd.text((8, 8), f"QA sprites — {fid}", fill=(244, 198, 62, 255), font=font)
    hd.text((canvas.width // 2, 16), "damier rose = transparent  —  rouge vif = trou d'alpha",
            fill=(240, 240, 240, 255), font=font, anchor="mm")
    final = Image.new("RGBA", (canvas.width, canvas.height + 40), (24, 16, 28, 255))
    final.paste(header, (0, 0))
    final.paste(canvas, (0, 40))
    final.save(out_path)
    print(out_path, final.width, "x", final.height)


def main():
    out_dir = os.path.join(ROOT, "tests", "out", "qa")
    os.makedirs(out_dir, exist_ok=True)
    args = sys.argv[1:] or ["all"]
    if args == ["all"]:
        args = [
            "louis", "maia", "patxi", "xabi", "mattin", "amaia",
            "txomin", "kaio", "karramarro", "ramuntxo", "itsaso", "peio",
            "itsasargi", "hondar",
        ]
    for fid in args:
        build(fid, os.path.join(out_dir, f"{fid}.png"))


if __name__ == "__main__":
    main()
