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


def load_poses(fid: str | None = None, path: str = POSES_PATH,
               guard_override: dict | None = None) -> dict:
    """Poses communes + surcharges du perso (tools/rig/poses/<fid>.json :
    {"named": {...}, "anims": {nom: définition complète}}). Les surcharges
    remplacent l'animation entière ; les poses communes ne sont pas dupliquées."""
    with open(path) as f:
        data = json.load(f)
    if fid:
        over_path = os.path.join(HERE, "poses", f"{fid}.json")
        if os.path.exists(over_path):
            with open(over_path) as f:
                over = json.load(f)
            for name, pose in over.get("named", {}).items():
                data["named"][name] = {**data["named"].get(name, {}), **pose}
            for name, anim in over.get("anims", {}).items():
                data["anims"][name] = anim
    named = data["named"]
    if guard_override:
        # Rig RD : la garde est la pose mesurée sur l'image RD ; les autres
        # poses nommées héritent de cette garde pour les os non précisés.
        named["guard"] = {**named["guard"], **guard_override}
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


def render_all(rig: Rig, amp: float = 1.0, poses: dict | None = None,
               cell_size: int = CELL, foot: tuple = FOOT) -> dict:
    """Renvoie {anim: [cellule uint8 cell×cell, …]} dans l'ordre ANIM_ORDER."""
    poses = poses or load_poses()
    CELL_ = cell_size
    ground_row = foot[1] - 1
    canvas = (cell_size * 2, cell_size * 2)
    root = (float(cell_size), cell_size * 150.0 / 128.0)
    named = poses["named"]
    raw, lifts = {}, {}
    for name in ANIM_ORDER:
        anim = poses["anims"][name]
        exp = expand(anim, named, amp)
        raw[name] = [rig.render(p, canvas, root) for p in exp]
        # « lift » : élévation (px) appliquée APRÈS le recalage au sol (saut
        # de l'uppercut), bornée par la place libre en haut de la cellule.
        lifts[name] = [int(round(float(p.get("lift", 0)))) for p in exp]
    # référence en l'air : centre vertical de la silhouette d'idle frame 0
    # (les saltos tournent autour du centre du corps, pas du bassin)
    idle_top = _lowest(raw["idle"][0]) - ground_row
    idle_mid = _vmid(raw["idle"][0]) - idle_top
    cells = {}
    base_x0 = int(root[0]) - foot[0]
    for name, frames in raw.items():
        out = []
        for fi, img in enumerate(frames):
            if name in AIR_ANIMS:
                top = int(round(_vmid(img) - idle_mid))
            else:
                top = _lowest(img) - ground_row
                rows = np.nonzero(img.any(axis=1))[0]
                room = int(rows.min()) - top if len(rows) else 0
                top += max(0, min(lifts[name][fi], room))
            # bassin à x = 64 ; si le corps déborde (couché…), décalage minimal
            x0 = base_x0
            cols = np.nonzero(img.any(axis=0))[0]
            if len(cols):
                if cols.min() < x0:
                    x0 = int(cols.min())
                if cols.max() >= x0 + CELL_:
                    x0 = int(cols.max()) - CELL_ + 1
            top = max(top, 0)
            cell = img[top:top + CELL_, x0:x0 + CELL_]
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
