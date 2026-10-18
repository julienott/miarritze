"""Masque de l'accessoire (os acc, accf, accb : chistera, makila, rame, poêle…)
image par image, pour les persos animés par le rig découpé (source « rd »).

Le rig est rendu deux fois avec les mêmes poses que tools/mannequin/build.py :
avec et sans les pièces d'accessoire ; les pixels qui diffèrent sont ceux de
l'accessoire visible (contour compris). redraw.py les recolle tels quels sur
le rendu guidé, qui déforme ou fend les accessoires (chistera de Xabi).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
for sub in ("rig", "sprites", "mannequin", ""):
    sys.path.insert(0, os.path.join(HERE, "..", sub))

import animate  # noqa: E402
import rd_rig  # noqa: E402

ACC = ("acc", "accf", "accb")


def masks(fid):
    """{anim: [masque booléen (cell, cell)]} ; {} si le perso n'a pas de rig RD ou d'accessoire."""
    full, bare = renders(fid)
    if not full:
        return {}
    return {a: [np.asarray(f) != np.asarray(b) for f, b in zip(full[a], bare[a])] for a in full}


def renders(fid):
    """(rendu complet, rendu sans accessoire) {anim: [image]} du rig ; ({}, {}) sans rig ou
    sans accessoire. Le rendu sans accessoire sert de contrôle quand l'accessoire est
    retiré du perso (bouée de Txomin remplacée par des palmes, from_rig.py --sans-acc)."""
    if not rd_rig.has_rd_rig(fid):
        return {}, {}
    rig, guard = rd_rig.build_rig(fid)
    keys = [k for k in rig.draw_order if k.split(":")[0] in ACC or k in ACC]
    if not keys:
        return {}, {}
    poses = animate.load_poses(fid, guard_override=guard)
    over = rd_rig.pose_overrides(fid)
    for name, anim in over.get("anims", {}).items():
        poses["anims"][name] = anim
    for name, pose in over.get("named", {}).items():
        poses["named"][name] = {**poses["named"].get(name, {}), **pose}
    from mannequin import FICHES
    amp = FICHES[fid].get("amp", 1.0)
    C = int(rd_rig.load_spec(fid).get("cell", animate.CELL))
    foot = (C // 2, C - 8) if C != animate.CELL else animate.FOOT
    full = animate.render_all(rig, amp, poses, C, foot)
    order = rig.draw_order
    rig.draw_order = [k for k in order if k not in keys]
    rig._cache8 = {}
    bare = animate.render_all(rig, amp, poses, C, foot)
    rig.draw_order = order
    return full, bare
