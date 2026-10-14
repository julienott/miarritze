#!/usr/bin/env python3
"""Recette d'un combattant livré : contrôles automatiques image par image et
planches à regarder (à lancer après chaque génération, avant d'intégrer).

Contrôles :
- trou    : pixel transparent enfermé dans la silhouette (≤ 6 px ; au-delà,
            c'est en général un vrai vide, vérifié sur la planche) ;
- îlot    : morceau opaque détaché du corps (≤ 60 px) ;
- bord    : la silhouette touche le bord de la case (coupée en jeu) ;
- taille  : hauteur qui saute de plus de 12 % d'une image à la suivante ;
- surface : surface opaque qui chute de plus de 25 % par rapport aux deux
            voisines (membre ou pan du corps disparu le temps d'une image) ;
- tache   : petite tache crème sur la peau sans trait sombre au-dessus
            (pas une dent ni un blanc d'œil) : se lit comme un trou.
Planches (tests/out/qa_fighter/<id>/) : toutes les images ×2 sur fond de
ciel clair, défauts entourés en rouge ; visages ×5 ; rapport texte.
Usage : qa_fighter.py <id>   (code de sortie 1 s'il reste des défauts)
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from build_rd_anims import _comps, is_pale, is_skin  # noqa: E402

SKY = (214, 236, 246, 255)
RED = (230, 40, 40, 255)


def frames(fid):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    m = json.load(open(os.path.join(d, "anims.json")))
    s = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    c, cols = m["cell"], m["cols"]
    out = {}
    for n, a in m["anims"].items():
        out[n] = []
        for i in range(a["frames"]):
            k = a["first"] + i
            out[n].append(s[(k // cols) * c:(k // cols + 1) * c, (k % cols) * c:(k % cols + 1) * c])
    return out, pal


def check(idx, pal):
    op = idx > 0
    issues, marks = [], np.zeros_like(op)
    h, w = op.shape
    for pts in _comps(~op):
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        if min(ys) > 0 and min(xs) > 0 and max(ys) < h - 1 and max(xs) < w - 1 and len(pts) <= 6:
            issues.append(f"trou {len(pts)}px")
            for p in pts:
                marks[p] = True
    comps = sorted(_comps(op), key=len, reverse=True)
    for pts in comps[1:]:
        if len(pts) <= 60:
            issues.append(f"îlot {len(pts)}px")
            for p in pts:
                marks[p] = True
    if op[0].any() or op[-1].any() or op[:, 0].any() or op[:, -1].any():
        issues.append("bord")
    rgba = pal[idx]
    pale = op & np.array([[is_pale(c) for c in row] for row in rgba])
    dark = op & (rgba[..., :3].astype(int).sum(-1) < 200)
    for pts in _comps(pale):
        if len(pts) > 20:
            continue
        ring = {(y + dy, x + dx) for y, x in pts for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= y + dy < h and 0 <= x + dx < w and not pale[y + dy, x + dx]}
        cols = [rgba[p] for p in ring if op[p]]
        if not cols or sum(is_skin(c) for c in cols) < 0.5 * len(cols):
            continue
        xs_ = sorted({x for _, x in pts})
        lid = sum(1 for x in xs_ if dark[max(0, min(y for y, xx in pts if xx == x) - 2):min(y for y, xx in pts if xx == x), x].any())
        if lid < 0.5 * len(xs_):
            issues.append(f"tache {len(pts)}px")
            for p in pts:
                marks[p] = True
    return issues, marks


def main():
    fid = sys.argv[1]
    allf, pal = frames(fid)
    out = os.path.join(ROOT, "tests", "out", "qa_fighter", fid)
    os.makedirs(out, exist_ok=True)
    font = ImageFont.load_default()
    report, total = [], 0
    rows, faces = [], []
    for name, fr in allf.items():
        heights = [int(np.ptp(np.nonzero((f > 0).any(1))[0]) + 1) for f in fr]
        areas = [int((f > 0).sum()) for f in fr]
        row_imgs = []
        for i, f in enumerate(fr):
            issues, marks = check(f, pal)
            if i and abs(heights[i] - heights[i - 1]) > 0.12 * heights[i - 1] and name not in (
                    "knockdown", "getup", "ko", "thrown", "crouch", "jump_up", "jump_fwd"):
                issues.append(f"taille {heights[i - 1]}→{heights[i]}")
            if 0 < i < len(fr) - 1 and areas[i] < 0.75 * min(areas[i - 1], areas[i + 1]):
                issues.append(f"surface −{100 - 100 * areas[i] // min(areas[i - 1], areas[i + 1])}%")
            if issues:
                total += len(issues)
                report.append(f"{name}#{i}: " + ", ".join(issues))
            rgba = pal[f].copy()
            rgba[f == 0] = SKY
            img = Image.fromarray(rgba.astype(np.uint8), "RGBA")
            if marks.any():
                ys, xs = np.nonzero(marks)
                d = ImageDraw.Draw(img)
                d.rectangle([xs.min() - 3, ys.min() - 3, xs.max() + 3, ys.max() + 3], outline=RED)
            if issues:
                ImageDraw.Draw(img).rectangle([0, 0, img.width - 1, img.height - 1], outline=RED)
            row_imgs.append(img)
            ys, xs = np.nonzero(f)
            top = ys.min()
            x1 = xs[ys < top + 60].max()
            face = img.crop((x1 - 44, top, x1 + 6, top + 60))
            faces.append(face.resize((face.width * 4, face.height * 4), Image.NEAREST))
        c = fr[0].shape[0]
        row = Image.new("RGBA", (12 * c, c + 12), (24, 16, 28, 255))
        ImageDraw.Draw(row).text((2, 0), name, fill=(244, 198, 62, 255), font=font)
        for i, img in enumerate(row_imgs[:12]):
            row.paste(img, (i * c, 12))
        rows.append(row)
    for p in range(0, len(rows), 8):
        part = rows[p:p + 8]
        W = Image.new("RGBA", (part[0].width, sum(r.height for r in part)), (24, 16, 28, 255))
        y = 0
        for r in part:
            W.paste(r, (0, y))
            y += r.height
        W.save(os.path.join(out, f"planche_{p // 8 + 1}.png"))
    fw, fh = faces[0].size
    per = 12
    for p in range(0, len(faces), per * 6):
        part = faces[p:p + per * 6]
        W = Image.new("RGBA", (per * fw, ((len(part) + per - 1) // per) * fh), (24, 16, 28, 255))
        for i, f in enumerate(part):
            W.paste(f, ((i % per) * fw, (i // per) * fh))
        W.save(os.path.join(out, f"visages_{p // (per * 6) + 1}.png"))
    with open(os.path.join(out, "rapport.txt"), "w") as fh_:
        fh_.write("\n".join(report) or "aucun défaut détecté")
    print(f"{fid}: {total} défaut(s) sur {sum(len(v) for v in allf.values())} images")
    for line in report[:40]:
        print("  ", line)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
