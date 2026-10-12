#!/usr/bin/env python3
"""Rendu de toutes les animations d'un rig en cellules 128×128 (contrat §2–3).

Commun aux mannequins et aux rigs découpés dans les sprites RD.
"""
from __future__ import annotations

import json
import os

import numpy as np

from rig import Rig, interpolate

HERE = os.path.dirname(os.path.abspath(__file__))
POSES_PATH = os.path.join(HERE, "poses", "poses.json")

ANIM_ORDER = [
    "intro", "idle", "walk", "run", "crouch", "crouch_idle", "jump_up", "jump_fwd", "fall",
    "block", "crouch_block", "punch_1", "punch_2", "punch_3", "kick", "kick_high",
    "crouch_punch", "sweep", "uppercut", "jump_punch", "jump_kick", "throw", "thrown",
    "hit_high", "hit_low", "hit_air", "knockdown", "getup", "dizzy", "ko", "win",
    "sp_neutral", "sp_forward", "sp_down", "sp_up", "super", "finisher",
]
AIR_ANIMS = {"jump_up", "jump_fwd", "fall", "jump_punch", "jump_kick", "hit_air", "thrown"}

CELL = 128
FOOT = (64, 120)
GROUND_ROW = FOOT[1] - 1          # dernière rangée opaque (le pied touche y = 120)
CANVAS = (256, 256)
ROOT = (128.0, 150.0)             # bassin sur la toile de travail


def load_poses(path: str = POSES_PATH) -> dict:
    with open(path) as f:
        data = json.load(f)
    named = data["named"]
    guard = named["guard"]
    for name, pose in named.items():
        for bone, val in guard.items():
            pose.setdefault(bone, val)
    return data


def expand(anim: dict, named: dict, amp: float) -> list:
    keys = []
    for k in anim["keys"]:
        p = dict(k.get("p", {}))
        if "use" in k:
            merged = {kk: vv for kk, vv in named[k["use"]].items()}
            merged.update(p)
            p = merged
        keys.append({"t": k["t"], "p": p})
    return interpolate({"keys": keys}, named[anim["base"]], anim["frames"], amp, named["guard"])


def render_all(rig: Rig, amp: float = 1.0, poses: dict | None = None) -> dict:
    """Renvoie {anim: [cellule uint8 128×128, …]} dans l'ordre ANIM_ORDER."""
    poses = poses or load_poses()
    named = poses["named"]
    raw = {}
    for name in ANIM_ORDER:
        anim = poses["anims"][name]
        raw[name] = [rig.render(p, CANVAS, ROOT) for p in expand(anim, named, amp)]
    # référence en l'air : centre vertical de la silhouette d'idle frame 0
    # (les saltos tournent autour du centre du corps, pas du bassin)
    idle_top = _lowest(raw["idle"][0]) - GROUND_ROW
    idle_mid = _vmid(raw["idle"][0]) - idle_top
    cells = {}
    base_x0 = int(ROOT[0]) - FOOT[0]
    for name, frames in raw.items():
        out = []
        for img in frames:
            if name in AIR_ANIMS:
                top = int(round(_vmid(img) - idle_mid))
            else:
                top = _lowest(img) - GROUND_ROW
            # bassin à x = 64 ; si le corps déborde (couché…), décalage minimal
            x0 = base_x0
            cols = np.nonzero(img.any(axis=0))[0]
            if len(cols):
                if cols.min() < x0:
                    x0 = int(cols.min())
                if cols.max() >= x0 + CELL:
                    x0 = int(cols.max()) - CELL + 1
            cell = img[top:top + CELL, x0:x0 + CELL]
            lost = int((img > 0).sum() - (cell > 0).sum())
            if lost:
                print(f"  ! {name}: {lost} px hors cellule")
            out.append(cell.copy())
        cells[name] = out
    return cells


def _vmid(img: np.ndarray) -> float:
    rows = np.nonzero(img.any(axis=1))[0]
    return (rows.min() + rows.max()) / 2.0 if len(rows) else 0.0


def _lowest(img: np.ndarray) -> int:
    rows = np.nonzero(img.any(axis=1))[0]
    return int(rows.max()) if len(rows) else 0


def anim_meta(poses: dict | None = None) -> dict:
    poses = poses or load_poses()
    meta = {}
    for row, name in enumerate(ANIM_ORDER):
        a = poses["anims"][name]
        m = {"row": row, "frames": a["frames"], "fps": a["fps"], "loop": a["loop"]}
        if "hit_frame" in a:
            m["hit_frame"] = a["hit_frame"]
            m["hit_dir"] = a.get("hit_dir", "fwd")
        meta[name] = m
    return meta
