#!/usr/bin/env python3
"""Mannequins procéduraux (SPEC-BORROKA §11.7).

Chaque combattant placeholder = des capsules épaisses (remplissage seul ;
contour et ombrage sont ajoutés par le rig, après rotation), colorées selon
sa fiche (§5.1) + un attribut distinctif (béret, planche…). Le rig est le
même que pour les sprites RD : seule la source des pièces change.

Ajouter un personnage = ajouter une entrée dans FICHES.
"""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "rig"))
sys.path.insert(0, os.path.join(HERE, "..", "sprites"))

from rig import Bone, Piece, Rig  # noqa: E402
import indices as ix  # noqa: E402

# --------------------------------------------------------------- fiches
# roles : rôle de palette -> rampe de tools/palette.py
# parts : quelle zone du corps prend quel rôle
# features : coiffure, couvre-chef, accessoire
FICHES = {
    "louis": {
        "name": "Louis",
        "roles": {"skin": "skin_a", "hair": "blond", "outfit_a": "linen", "outfit_b": "navy",
                  "hat": "red", "acc_b": "wood", "acc_c": "sand", "extra": "red"},
        "parts": {"shirt": "outfit_a", "sleeve": "outfit_a", "forearm": "skin",
                  "pants": "outfit_b", "shin": "outfit_b", "feet": "acc_c", "belt": "hat"},
        "hair": "short", "hat": "beret", "acc": None,
        "costumes": {1: {"hat": "green", "outfit_b": "navy", "extra": "green"}, 2: {"outfit_b": "red", "hat": "navy"},
                     3: {"outfit_b": "green", "hat": "yellow"}},
        "amp": 1.0, "scale": 1.0,
    },
    "maia": {
        "name": "Maïa",
        "roles": {"skin": "skin_b", "hair": "hair", "outfit_a": "turquoise", "outfit_b": "navy",
                  "hat": "red", "acc_b": "yellow", "acc_c": "sand", "extra": "orange"},
        "parts": {"shirt": "outfit_a", "sleeve": "outfit_a", "forearm": "outfit_a",
                  "pants": "outfit_a", "shin": "outfit_a", "feet": "skin", "belt": None,
                  "stripe": "outfit_b"},
        "hair": "long_wet", "hat": None, "acc": "surfboard",
        "costumes": {1: {"outfit_a": "pink", "outfit_b": "red"}},
        "amp": 1.08, "scale": 1.0,
    },
}

# Proportions de base (px), ~100 px de haut debout.
PROPS = {
    "pelvis_rx": 11.5, "pelvis_ry": 7.5,
    "torso_len": 15.0, "torso_r": 12.0,
    "head_r": 13.5,
    "uarm_len": 13.0, "uarm_r": 5.2,
    "farm_len": 10.0, "farm_r": 4.6, "fist_r": 5.6,
    "thigh_len": 16.0, "thigh_r": 7.2,
    "shin_len": 14.0, "shin_r": 6.2, "foot_r": 3.8,
}


# --------------------------------------------------------------- dessin

class Canvas:
    """Toile locale dont l'origine (0,0) est le pivot de la pièce."""

    def __init__(self, size: int = 128):
        self.size = size
        self.o = size / 2.0
        self.img = np.zeros((size, size), np.uint8)
        c = (np.arange(size) + 0.5) - self.o
        self.X, self.Y = np.meshgrid(c, c)

    def capsule(self, p0, p1, r, idx, where=None):
        ax, ay = p0
        bx, by = p1
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy or 1e-9
        t = np.clip(((self.X - ax) * dx + (self.Y - ay) * dy) / L2, 0.0, 1.0)
        px, py = ax + t * dx, ay + t * dy
        m = (self.X - px) ** 2 + (self.Y - py) ** 2 <= r * r
        self._set(m, idx, where)
        return m

    def ellipse(self, c, rx, ry, idx, where=None):
        m = ((self.X - c[0]) / rx) ** 2 + ((self.Y - c[1]) / ry) ** 2 <= 1.0
        self._set(m, idx, where)
        return m

    def rect(self, x0, y0, x1, y1, idx, where=None):
        m = (self.X >= x0) & (self.X < x1) & (self.Y >= y0) & (self.Y < y1)
        self._set(m, idx, where)
        return m

    def recolor(self, mask, idx):
        """Recolore la zone `mask` uniquement là où la pièce est déjà opaque."""
        self.img[mask & (self.img > 0)] = idx

    def _set(self, m, idx, where):
        if where is not None:
            m = m & where
        self.img[m] = idx

    def piece(self, attach=None, decals=None, shade=True) -> Piece:
        ys, xs = np.nonzero(self.img)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        img = self.img[y0:y1, x0:x1].copy()
        return Piece(img=img, pivot=(self.o - x0, self.o - y0),
                     attach=attach or {}, decals=decals or [], shade=shade)


def _role_idx(fiche, part, back):
    role = fiche["parts"].get(part)
    return ix.base(role, back) if role else None


# --------------------------------------------------------------- pièces

def build_pieces(fiche: dict) -> dict:
    s = fiche.get("scale", 1.0)
    P = {k: v * s for k, v in PROPS.items()}
    pieces = {}
    skin = ix.base("skin")
    eye = np.array([[ix.EYE, ix.OUTLINE], [ix.EYE, ix.OUTLINE]], np.uint8)

    # bassin : pivot = hanches
    c = Canvas()
    c.ellipse((0, 0), P["pelvis_rx"], P["pelvis_ry"], _role_idx(fiche, "pants", False))
    if fiche["parts"].get("belt"):
        c.recolor(c.Y < -3.0, ix.base(fiche["parts"]["belt"]))
    pieces["pelvis"] = c.piece(attach={"tor": (0, -2), "thf": (2, 2), "thb": (-2, 2)})

    # torse : pivot = taille, monte vers le haut
    tl, tr = P["torso_len"], P["torso_r"]
    c = Canvas()
    body = c.capsule((0, -4), (1.5, -4 - tl), tr, _role_idx(fiche, "shirt", False))
    c.ellipse((1.5, -4 - tl + 1), tr + 1.0, tr * 0.75, _role_idx(fiche, "shirt", False))  # épaules
    if fiche["parts"].get("belt"):
        c.recolor((c.Y > -7) & (c.Y < -2), ix.base(fiche["parts"]["belt"]))
    if fiche["parts"].get("stripe"):
        c.recolor((c.X > -8.5) & (c.X < -6) & (c.Y < -5), ix.base(fiche["parts"]["stripe"]))
    top = -4 - tl - tr
    pieces["torso"] = c.piece(attach={
        "head": (1.5, top + 3.0), "uaf": (4.0, top + 7.5), "uab": (-2.0, top + 7.5),
        "acc": (-12.0, -13.0)})

    # tête : pivot = base du cou
    hr = P["head_r"]
    hc = (1.5, -3.0 - hr)
    c = Canvas()
    c.capsule((0, 1), (0.5, -4), 3.5, skin)                       # cou
    head = c.ellipse(hc, hr, hr * 0.96, skin)
    c.ellipse((hc[0] + hr - 0.5, hc[1] + 2.0), 2.2, 2.0, skin)    # nez
    hair = ix.base("hair")
    if fiche["hair"] == "short":
        c.recolor(head & ((c.Y < hc[1] - 4.0) | ((c.X < hc[0] - 4.0) & (c.Y < hc[1] + 5.0))), hair)
        c.ellipse((hc[0] + 6.0, hc[1] - 7.5), 4.5, 2.5, hair)       # mèche
    elif fiche["hair"] == "long_wet":
        c.capsule((hc[0] - 6.0, hc[1] - 2.0), (hc[0] - 9.0, hc[1] + 15.0), 4.6, hair)
        c.recolor(head & ((c.Y < hc[1] - 3.0) | (c.X < hc[0] - 3.5)), hair)
        c.capsule((hc[0] + 2.0, hc[1] - hr + 1.5), (hc[0] + 9.0, hc[1] - 5.0), 2.2, hair)  # mèche mouillée
    if fiche["hat"] == "beret":
        hat = ix.base("hat")
        c.ellipse((hc[0] - 1.5, hc[1] - hr + 1.0), hr + 1.5, 4.2, hat)
        c.capsule((hc[0] - 1.0, hc[1] - hr - 3.0), (hc[0] - 0.5, hc[1] - hr - 5.0), 1.3, hat)
    pieces["head"] = c.piece(decals=[((hc[0] + 6.0, hc[1] - 0.5), eye)])

    for side, back in (("f", False), ("b", True)):
        # bras supérieur : pivot = épaule, pend vers le bas
        c = Canvas()
        ul, ur = P["uarm_len"], P["uarm_r"]
        c.capsule((0, 0), (0, ul), ur, _role_idx(fiche, "sleeve", back))
        if fiche["parts"]["sleeve"] != fiche["parts"]["forearm"]:
            c.recolor(c.Y > ul * 0.6, ix.base(fiche["parts"]["forearm"], back))
        pieces["uarm_" + side] = c.piece(attach={"fa": (0, ul)})
        # avant-bras + poing : pivot = coude
        c = Canvas()
        fl = P["farm_len"]
        c.capsule((0, 0), (0, fl), P["farm_r"], _role_idx(fiche, "forearm", back))
        c.ellipse((0.3, fl + 2.0), P["fist_r"], P["fist_r"], ix.base("skin", back))
        pieces["farm_" + side] = c.piece()
        # cuisse : pivot = hanche
        c = Canvas()
        th = P["thigh_len"]
        c.capsule((0, 0), (0, th), P["thigh_r"], _role_idx(fiche, "pants", back))
        pieces["thigh_" + side] = c.piece(attach={"sh": (0, th)})
        # jambe + pied : pivot = genou
        c = Canvas()
        sl = P["shin_len"]
        c.capsule((0, 0), (0, sl), P["shin_r"], _role_idx(fiche, "shin", back))
        c.capsule((-1.5, sl + 3.0), (7.5, sl + 3.4), P["foot_r"], _role_idx(fiche, "feet", back))
        pieces["shin_" + side] = c.piece()

    if fiche.get("acc") == "surfboard":
        c = Canvas()
        board = c.ellipse((0, 0), 8.0, 28.0, ix.base("acc_b"))
        c.recolor(board & (np.abs(c.X - 0.5) < 1.2), ix.base("hat"))     # bande centrale
        c.recolor(board & (c.Y < -22), ix.base("acc_b", True))            # nez de la planche
        pieces["acc"] = c.piece()
    return pieces


def build_rig(fiche: dict) -> Rig:
    pieces = build_pieces(fiche)
    bones = [
        Bone("pel", None, "pelvis"),
        Bone("tor", "pel", "torso"),
        Bone("head", "tor", "head"),
        Bone("uaf", "tor", "uarm_f"), Bone("faf", "uaf", "farm_f", "fa"),
        Bone("uab", "tor", "uarm_b"), Bone("fab", "uab", "farm_b", "fa"),
        Bone("thf", "pel", "thigh_f"), Bone("shf", "thf", "shin_f", "sh"),
        Bone("thb", "pel", "thigh_b"), Bone("shb", "thb", "shin_b", "sh"),
    ]
    order = ["uab", "fab", "thb", "shb", "pel", "tor", "thf", "shf", "head", "uaf", "faf"]
    if "acc" in pieces:
        bones.append(Bone("acc", "tor", "acc"))
        order = ["acc"] + order
    return Rig(bones, pieces, order, ix.shade_ramps())
