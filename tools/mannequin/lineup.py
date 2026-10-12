#!/usr/bin/env python3
"""Line-up des silhouettes (idle frame 0 de chaque fiche, côte à côte, ×3)
et aperçu rapide d'animations sans reconstruire les feuilles.

Usage : lineup.py [--anims uppercut,punch_2] [--ids louis,maia] [--out chemin.png]
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
for sub in ("rig", "sprites", "mannequin"):
    sys.path.insert(0, os.path.join(HERE, "..", sub))

import animate  # noqa: E402
import make_palettes  # noqa: E402
from mannequin import FICHES, build_rig  # noqa: E402

BG = (64, 150, 210, 255)


def frames_for(fid, anim):
    fiche = FICHES[fid]
    rig = build_rig(fiche)
    poses = animate.load_poses(fid)
    named = poses["named"]
    a = poses["anims"][anim]
    C = fiche.get("cell", 128)
    root = (float(C), C * 150.0 / 128.0)
    imgs = [rig.render(p, (C * 2, C * 2), root) for p in animate.expand(a, named, fiche.get("amp", 1.0))]
    pal = np.array(make_palettes.build(fiche))[0]
    return imgs, pal, a


def colorize(idx, pal, bg=BG):
    rgba = pal[idx].copy()
    rgba[idx == 0] = bg
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def crop_all(imgs):
    m = np.zeros_like(imgs[0], bool)
    for im in imgs:
        m |= im > 0
    ys, xs = np.nonzero(m)
    return xs.min() - 2, ys.min() - 2, xs.max() + 3, ys.max() + 3


def main():
    args = sys.argv[1:]
    ids = list(FICHES)
    anims = None
    out = os.path.join(ROOT, "tests", "out", "sheets", "lineup.png")
    for i, a in enumerate(args):
        if a == "--ids":
            ids = args[i + 1].split(",")
        elif a == "--anims":
            anims = args[i + 1].split(",")
        elif a == "--out":
            out = args[i + 1]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    scale = 3
    if anims is None:
        tiles = []
        for fid in ids:
            imgs, pal, _ = frames_for(fid, "idle")
            im = imgs[0]
            fiche = FICHES[fid]
            C = fiche.get("cell", 128)
            ys = np.nonzero(im.any(axis=1))[0]
            tiles.append((fid, colorize(im, pal), ys.max() - ys.min() + 1))
        # alignement au sol commun : bas des toiles
        crops = []
        for fid, img, h in tiles:
            a = np.array(img)
            mask = ~(np.all(a == np.array(BG), axis=2))
            ys, xs = np.nonzero(mask)
            crops.append((fid, img.crop((xs.min() - 4, ys.min() - 4, xs.max() + 5, ys.max() + 1)), h))
        H = max(c[1].height for c in crops) + 14
        W = sum(c[1].width for c in crops)
        sheet = Image.new("RGBA", (W, H), BG)
        dr = ImageDraw.Draw(sheet)
        x = 0
        for fid, img, h in crops:
            sheet.paste(img, (x, H - img.height))
            dr.text((x + 2, 1), f"{fid} {h}", fill=(255, 255, 255, 255))
            x += img.width
        sheet = sheet.resize((W * scale, H * scale), Image.NEAREST)
        sheet.save(out)
        print(out)
        return
    rows = []
    for fid in ids:
        for anim in anims:
            imgs, pal, a = frames_for(fid, anim)
            x0, y0, x1, y1 = crop_all(imgs)
            row = Image.new("RGBA", ((x1 - x0) * len(imgs), y1 - y0), BG)
            for k, im in enumerate(imgs):
                tile = colorize(im[y0:y1, x0:x1], pal, (52, 58, 78, 255) if k % 2 else BG)
                if a.get("hit_frame") == k:
                    d = ImageDraw.Draw(tile)
                    d.rectangle([0, 0, tile.width - 1, tile.height - 1], outline=(255, 60, 60, 255))
                row.paste(tile, ((x1 - x0) * k, 0))
            rows.append(row)
    W = max(r.width for r in rows)
    H = sum(r.height for r in rows)
    sheet = Image.new("RGBA", (W, H), (30, 30, 40, 255))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet = sheet.resize((W * scale, H * scale), Image.NEAREST)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
