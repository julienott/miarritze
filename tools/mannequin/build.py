#!/usr/bin/env python3
"""Construit les combattants mannequins : sheet.png (L), palettes.png,
anims.json (anims + boîtes), puis les planches contact.

Usage : .venv/bin/python tools/mannequin/build.py louis maia   (sans argument : tous)
"""
from __future__ import annotations

import json
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
for sub in ("rig", "sprites", "mannequin"):
    sys.path.insert(0, os.path.join(HERE, "..", sub))

import animate  # noqa: E402
import contact_sheet  # noqa: E402
import indices as ix  # noqa: E402
import infer_boxes  # noqa: E402
import make_palettes  # noqa: E402
from mannequin import FICHES, build_rig  # noqa: E402
import rd_rig  # noqa: E402


SHEET_W = 2048


def build(fid: str) -> None:
    t0 = time.time()
    fiche = FICHES[fid]
    source = "mannequin"
    if rd_rig.has_rd_rig(fid) and "--mannequin" not in sys.argv:
        # Pièces découpées dans la pose RD (Phase 3) ; mêmes poses, même rendu.
        rig, guard = rd_rig.build_rig(fid)
        poses = animate.load_poses(fid, guard_override=guard)
        rd_over = rd_rig.pose_overrides(fid)
        for name, anim in rd_over.get("anims", {}).items():
            poses["anims"][name] = anim
        for name, pose in rd_over.get("named", {}).items():
            poses["named"][name] = {**poses["named"].get(name, {}), **pose}
        source = "rd"
    else:
        rig = build_rig(fiche)
        poses = animate.load_poses(fid)
    C = fiche.get("cell", animate.CELL)
    foot = tuple(fiche.get("foot", animate.FOOT))
    if source == "rd":
        # Les poses RD sont plus grandes (≈ 115 px) : cellule 160, pied en (80, 152).
        C = int(rd_rig.load_spec(fid).get("cell", C))
        foot = (C // 2, C - 8) if C != animate.CELL else animate.FOOT
    cells = animate.render_all(rig, fiche.get("amp", 1.0), poses, C, foot)
    meta = animate.anim_meta(poses)
    infer_boxes.set_foot(foot)
    box_cells = cells
    if source == "rd":
        idle_spec = rd_rig.load_spec(fid).get("idle", {})
        if idle_spec.get("source") == "rd":
            # Idle RD post-traité (respiration organique) ; les boîtes restent
            # inférées sur l'idle du rig (référence alignée sur les poses).
            import process_anim
            frames, var, drift, ok = process_anim.process(fid, os.path.join(ROOT, idle_spec["rd_image"]),
                                                          cell=C, foot=foot)
            if ok:
                box_cells = dict(cells)
                cells = dict(cells)
                cells["idle"] = frames
                meta["idle"]["frames"] = len(frames)
                print(f"  {fid}/idle : RD ({var:.1%} de variation)")
    out = os.path.join(ROOT, "assets", "fighters", fid)
    os.makedirs(out, exist_ok=True)
    # Grille compacte (≤ 2048 px de large, hauteur ≤ 4096) : les frames
    # sont rangées à la suite, `first` = index de la 1re frame de l'anim.
    cols = SHEET_W // C
    total = sum(len(f) for f in cells.values())
    rows = (total + cols - 1) // cols
    sheet = np.zeros((rows * C, cols * C), np.uint8)
    index = 0
    for name in animate.ANIM_ORDER:
        meta[name]["first"] = index
        for c in cells[name]:
            y, x = (index // cols) * C, (index % cols) * C
            sheet[y:y + C, x:x + C] = c
            index += 1
    Image.fromarray(sheet, "L").save(os.path.join(out, "sheet.png"), optimize=True)
    make_palettes.write(fiche, os.path.join(out, "palettes.png"))
    data = {
        "id": fid, "cell": C, "cols": cols, "foot": list(foot),
        "palette_roles": ix.palette_roles(),
        "source": source,
        "anims": meta,
        "boxes": infer_boxes.infer(box_cells, meta),
    }
    with open(os.path.join(out, "anims.json"), "w") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    _check(fid, cells)
    pages = contact_sheet.main(fid)
    print(f"{fid}: {sum(len(v) for v in cells.values())} frames en {time.time() - t0:.1f} s")
    for p in pages:
        print("  ", p)


def _check(fid: str, cells: dict) -> None:
    """Invariants : hauteur stable en idle/walk (< 8 %), pied au sol."""
    for name in ("idle", "walk"):
        hs = []
        for c in cells[name]:
            ys = np.nonzero(c.any(axis=1))[0]
            hs.append(ys.max() - ys.min() + 1)
        var = (max(hs) - min(hs)) / max(hs)
        flag = "OK" if var < 0.08 else "À REVOIR"
        print(f"  {fid}/{name} hauteurs {min(hs)}–{max(hs)} ({var:.1%}) {flag}")


if __name__ == "__main__":
    ids = [a for a in sys.argv[1:] if not a.startswith("--")] or list(FICHES)
    for fid in ids:
        build(fid)
