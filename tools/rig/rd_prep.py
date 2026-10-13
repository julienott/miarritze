#!/usr/bin/env python3
"""Prépare une pose RD trop grande (SPEC §10.4 : Mattin ≈ 118 px, boss ≈ 140) :
réduction par vote majoritaire (couleur la plus fréquente de chaque bloc
source, transparent si le bloc est surtout vide), sans interpolation.
Écrit assets/fighters/<id>/rd_pose.png et, si l'idle RD existe, rd_idle.png
(chaque frame réduite de la même façon, dans une cellule de même taille).
Usage : rd_prep.py <id> <facteur> [--idle chemin_planche] [--cell N]"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def mode_down(rgba: np.ndarray, f: float, out_size=None) -> np.ndarray:
    H, W = rgba.shape[:2]
    oh, ow = out_size or (max(1, round(H * f)), max(1, round(W * f)))
    out = np.zeros((oh, ow, 4), np.uint8)
    for y in range(oh):
        y0, y1 = int(y / f), max(int(y / f) + 1, int((y + 1) / f))
        for x in range(ow):
            x0, x1 = int(x / f), max(int(x / f) + 1, int((x + 1) / f))
            blk = rgba[y0:min(y1, H), x0:min(x1, W)].reshape(-1, 4)
            if blk.size == 0:
                continue
            op = blk[blk[:, 3] > 127]
            if len(op) * 2 < len(blk):
                continue
            cols, counts = np.unique(op[:, :3], axis=0, return_counts=True)
            # Le contour l'emporte à égalité : la silhouette reste fermée.
            best = counts.max()
            cands = cols[counts == best]
            dark = cands[np.argmin(cands.sum(1))]
            out[y, x, :3] = dark
            out[y, x, 3] = 255
    return out


def offset_for(img: np.ndarray, cell: int):
    """Translation qui pose la silhouette en bas (4 px de marge), centrée."""
    ys, xs = np.nonzero(img[..., 3] > 127)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return (cell - 4 - (y1 - y0)) - y0, (cell - (x1 - x0)) // 2 - x0


def shift_into(img: np.ndarray, cell: int, dy: int, dx: int) -> np.ndarray:
    canvas = np.zeros((cell, cell, 4), np.uint8)
    H, W = img.shape[:2]
    for y in range(H):
        ty = y + dy
        if 0 <= ty < cell:
            for x in range(W):
                tx = x + dx
                if 0 <= tx < cell and img[y, x, 3] > 127:
                    canvas[ty, tx] = img[y, x]
    return canvas


def main():
    fid, f = sys.argv[1], float(sys.argv[2])
    cell = int(sys.argv[sys.argv.index("--cell") + 1]) if "--cell" in sys.argv else 160
    finals = json.load(open(os.path.join(ROOT, "tools", "rd", "out", "finals.json")))
    src = np.array(Image.open(os.path.join(ROOT, finals[fid])).convert("RGBA"))
    small = mode_down(src, f)
    dy, dx = offset_for(small, cell)
    pose = shift_into(small, cell, dy, dx)
    out_dir = os.path.join(ROOT, "assets", "fighters", fid)
    Image.fromarray(pose, "RGBA").save(os.path.join(out_dir, "rd_pose.png"))
    print("pose", pose.shape, np.nonzero(pose[..., 3])[0].min())
    if "--idle" in sys.argv:
        sheet = np.array(Image.open(sys.argv[sys.argv.index("--idle") + 1]).convert("RGBA"))
        sc = src.shape[0]
        n = (sheet.shape[0] // sc) * (sheet.shape[1] // sc)
        frames = []
        for k in range(n):
            y, x = (k // (sheet.shape[1] // sc)) * sc, (k % (sheet.shape[1] // sc)) * sc
            fr = sheet[y:y + sc, x:x + sc]
            if (fr[..., 3] > 127).sum() < 50:
                continue
            # Même translation que la pose : les groupes de costume se lisent
            # au même endroit (le recalage fin du pied est fait par process_anim).
            frames.append(shift_into(mode_down(fr, f), cell, dy, dx))
        if "--skip" in sys.argv:
            # Frames ratées de l'idle RD (ex. bras qui sautent) : retirées puis
            # remplacées par la répétition des frames voisines (boucle de 8).
            bad = [int(v) for v in sys.argv[sys.argv.index("--skip") + 1].split(",")]
            keep = [fr for i, fr in enumerate(frames) if i not in bad]
            while len(keep) < len(frames):
                keep.insert(len(keep) // 2, keep[len(keep) // 2])
            frames = keep
        out = np.concatenate(frames, axis=1)
        Image.fromarray(out, "RGBA").save(os.path.join(out_dir, "rd_idle.png"))
        print("idle", len(frames), "frames")


if __name__ == "__main__":
    main()
