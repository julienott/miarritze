#!/usr/bin/env python3
"""Post-traitement d'une animation RD (SPEC §11.3 étape 4).

Découpe la planche (grille de frames), indexe chaque frame sur la palette
du perso (même règle de rôle que le rig RD), recale le pied (rangée opaque la
plus basse → pied du contrat ; horizontal : centre de masse des 20 rangées du
bas aligné sur celui de la frame de référence), unifie le contour (bord de
silhouette → index 1), supprime les pixels orphelins, puis vérifie les
invariants (variation de hauteur < 8 %, dérive de couleur).

Usage : process_anim.py <id> <planche.png> [--frames N] [--cell C]
Écrit tests/out/rig/<id>_idle_rd.png (comparaison ×4) et affiche le verdict.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "rig"))

import rd_rig  # noqa: E402
from rig import cleanup  # noqa: E402

MAX_HEIGHT_VAR = 0.08
MAX_COLOR_DRIFT = 0.04     # part des pixels loin de toute couleur de palette


def split(sheet: np.ndarray, cell: int, n: int) -> list:
    cols = sheet.shape[1] // cell
    frames = []
    for k in range(n):
        y, x = (k // cols) * cell, (k % cols) * cell
        frames.append(sheet[y:y + cell, x:x + cell])
    return frames


def color_drift(fid, rgba) -> float:
    pal = np.array(Image.open(os.path.join(rd_rig.fighter_dir(fid), "palettes.png")).convert("RGBA"))[0, 1:, :3].astype(int)
    m = rgba[..., 3] > 127
    px = rgba[m][:, :3].astype(int)
    if len(px) == 0:
        return 0.0
    d = ((px[:, None, :] - pal[None, :, :]) ** 2).sum(-1).min(1)
    return float((d > 300).mean())


def process(fid, path, n=8, cell=None, foot=None):
    meta = json.load(open(os.path.join(rd_rig.fighter_dir(fid), "anims.json")))
    cell = cell or meta["cell"]
    foot = foot or tuple(meta["foot"])
    src = np.array(Image.open(path).convert("RGBA"))
    src_cell = src.shape[0] // 2 if src.shape[1] == src.shape[0] * 2 else cell
    raw = split(src, src_cell, n)
    drift = max(color_drift(fid, f) for f in raw)
    spec = rd_rig.load_spec(fid) if rd_rig.has_rd_rig(fid) else {}
    if spec.get("groups"):
        idx_frames = [rd_rig.index_frame(fid, f) for f in raw]
    else:
        idx_frames = [rd_rig.index_image(fid, f, rd_rig.protect_mask(spec, f.shape[:2])) for f in raw]
    out, heights = [], []
    ref_cx = None
    for f in idx_frames:
        ys, xs = np.nonzero(f)
        if len(ys) == 0:
            out.append(np.zeros((cell, cell), np.uint8))
            continue
        bottom = ys.max()
        low = f[max(0, bottom - 19):bottom + 1]
        ly, lx = np.nonzero(low)
        cx = lx.mean()
        if ref_cx is None:
            ref_cx = cx
        heights.append(bottom - ys.min() + 1)
        dx = int(round(foot[0] - ref_cx))
        dy = (foot[1] - 1) - bottom
        canvas = np.zeros((cell, cell), np.uint8)
        h, w = f.shape
        for y in range(h):
            ty = y + dy
            if not 0 <= ty < cell:
                continue
            row = f[y]
            xs_ = np.arange(w) + dx
            ok = (xs_ >= 0) & (xs_ < cell)
            canvas[ty, xs_[ok]] = np.where(row[ok] > 0, row[ok], canvas[ty, xs_[ok]])
        out.append(cleanup(canvas))
    var = (max(heights) - min(heights)) / max(heights) if heights else 1.0
    ok = var < MAX_HEIGHT_VAR and drift < MAX_COLOR_DRIFT
    return out, var, drift, ok


def compare_sheet(fid, rd_frames, rig_frames, scale=4):
    pal = np.array(Image.open(os.path.join(rd_rig.fighter_dir(fid), "palettes.png")).convert("RGBA"))[0]
    c = rd_frames[0].shape[0]
    n = max(len(rd_frames), len(rig_frames))
    sheet = Image.new("RGBA", (n * c, 2 * c), (90, 96, 120, 255))
    for row, frames in enumerate((rig_frames, rd_frames)):
        for i, f in enumerate(frames):
            sheet.alpha_composite(Image.fromarray(pal[f].astype(np.uint8), "RGBA"), (i * c, row * c))
    sheet = sheet.resize((sheet.width * scale // 2, sheet.height * scale // 2), Image.NEAREST)
    path = os.path.join(ROOT, "tests", "out", "rig", f"{fid}_idle_rd.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    return path


if __name__ == "__main__":
    fid, path = sys.argv[1], sys.argv[2]
    frames, var, drift, ok = process(fid, path)
    print(f"{fid}: variation de hauteur {var:.1%}, dérive couleur {drift:.1%} → {'OK' if ok else 'REFUSÉ'}")
