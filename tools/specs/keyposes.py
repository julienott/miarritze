#!/usr/bin/env python3
"""Planche de poses clés d'un combattant, gratuite (aucun appel RD) : pour
chaque animation du jeu, le mannequin du perso au départ, à l'impact et à
la fin, à côté de l'intention écrite dans sa fiche. C'est la planche que
Julien valide AVANT de générer quoi que ce soit.

Usage : keyposes.py <id>   → tests/out/keyposes/<id>_<n>.png
"""
from __future__ import annotations

import json
import os
import sys
import textwrap

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
for sub in ("rig", "sprites", "mannequin"):
    sys.path.insert(0, os.path.join(ROOT, "tools", sub))
sys.path.insert(0, HERE)
import animate  # noqa: E402
import spec as fiche  # noqa: E402
from mannequin import FICHES, build_rig  # noqa: E402

FONT = os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf")
SKY = (214, 236, 246, 255)
ROWS_PER_PAGE = 10


def render(fid):
    f = FICHES[fid]
    rig = build_rig(f)
    cells = animate.render_all(rig, f.get("amp", 1.0), animate.load_poses(fid),
                               f.get("cell", animate.CELL), tuple(f.get("foot", animate.FOOT)))
    pal = np.array(Image.open(os.path.join(ROOT, "assets", "fighters", fid,
                                           "palettes.png")).convert("RGBA"))[0]
    mpal_path = os.path.join(ROOT, "assets", "fighters", fid, "palettes_mannequin.png")
    if os.path.exists(mpal_path):
        pal = np.array(Image.open(mpal_path).convert("RGBA"))[0]
    return cells, pal


def colorize(idx, pal):
    # Mannequin en aplats lisibles : silhouette sombre, détails gardés par
    # luminance (la palette RD du perso ne correspond pas aux index du mannequin).
    g = np.where(idx == 0, 0, 90 + (idx.astype(int) * 37) % 140).astype(np.uint8)
    rgba = np.zeros(idx.shape + (4,), np.uint8)
    rgba[..., 0] = g // 2 + 40
    rgba[..., 1] = g // 2 + 30
    rgba[..., 2] = g // 2 + 60
    rgba[..., 3] = np.where(idx > 0, 255, 0)
    rgba[idx == 1] = (40, 26, 36, 255)
    bg = np.zeros_like(rgba)
    bg[...] = SKY
    out = Image.fromarray(bg, "RGBA")
    out.alpha_composite(Image.fromarray(rgba, "RGBA"))
    return out


def main():
    fid = sys.argv[1]
    s = fiche.load(fid)
    meta = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "anims.json")))["anims"]
    cells, pal = render(fid)
    mv = s.get("mouvements", {})
    rep = s.get("reprises", {}) or {}
    sp = s.get("speciaux", {}) or {}
    big = ImageFont.truetype(FONT, 14)
    small = ImageFont.truetype(FONT, 10)
    rows = []
    for anim in fiche.GAME_ANIMS:
        frames = cells.get(anim, [])
        if not frames:
            continue
        hit = meta.get(anim, {}).get("hit_frame", len(frames) // 2)
        picks = [0, min(hit, len(frames) - 1), len(frames) - 1]
        c = frames[0].shape[0]
        S = 2
        row = Image.new("RGBA", (3 * c * S + 20 + 900, c * S + 10), (24, 16, 28, 255))
        for i, k in enumerate(picks):
            row.paste(colorize(frames[k], pal).resize((c * S, c * S), Image.NEAREST), (i * (c * S + 5), 5))
        d = ImageDraw.Draw(row)
        x = 3 * (c * S + 5) + 15
        label = {0: "départ", 1: "impact", 2: "fin"}
        for i in range(3):
            d.text((i * (c * S + 5) + 6, 10), label[i], font=small, fill=(40, 26, 36, 255))
        d.text((x, 12), anim, font=big, fill=(244, 198, 62, 255))
        m = mv.get(anim)
        r = rep.get(anim)
        lines = []
        if anim in sp:
            e = sp[anim]
            lines.append(f"« {e.get('nom', '')} »")
            for k in ("intention", "effet", "projectile"):
                if e.get(k):
                    lines.append(f"{k} : {e[k] if isinstance(e[k], str) else e[k].get('description', '')}")
        if m:
            if m.get("intention"):
                lines.append(m["intention"])
            lines.append(f"RD {m['mode']}, {m['images']} images, départ {m.get('depart', 'neutre')}")
            lines.append("consigne : " + m["geste"])
        elif r:
            lines.append(f"reprise de « {r['depuis']} » ({r.get('images', 'tout')})")
        elif anim in ("jump_up", "fall") and "jump" in mv:
            lines.append("découpé dans « jump »")
        else:
            lines.append("⚠ aucune source dans la fiche")
        y = 40
        for line in lines:
            for w in textwrap.wrap(line, 70):
                d.text((x, y), w, font=small, fill=(230, 230, 230, 255))
                y += 16
        rows.append(row)
    out_dir = os.path.join(ROOT, "tests", "out", "keyposes")
    os.makedirs(out_dir, exist_ok=True)
    for p in range(0, len(rows), ROWS_PER_PAGE):
        part = rows[p:p + ROWS_PER_PAGE]
        W = Image.new("RGBA", (part[0].width, sum(r.height + 4 for r in part)), (60, 50, 70, 255))
        y = 0
        for r in part:
            W.paste(r, (0, y))
            y += r.height + 4
        path = os.path.join(out_dir, f"{fid}_{p // ROWS_PER_PAGE + 1}.png")
        W.save(path)
        print(path)


if __name__ == "__main__":
    main()
