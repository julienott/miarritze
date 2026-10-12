#!/usr/bin/env python3
"""Mannequins procéduraux (SPEC-BORROKA §11.7).

Chaque combattant placeholder = des capsules épaisses (remplissage seul ;
contour et ombrage sont ajoutés par le rig, après rotation), colorées selon
sa fiche (§5.1), avec ses attributs distinctifs (béret, planche, chistera,
pinces, bec…). Le rig est le même que pour les sprites RD : seule la source
des pièces change.

Ajouter un personnage = ajouter une entrée dans FICHES.
Rôles de palette : nom de rampe de tools/palette.py, ou liste « rampe:i »
pour composer une rampe avec des couleurs de la palette unique.
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

# Carnations (rampes composées dans la palette unique).
SKIN_LIGHT = "skin_a"
SKIN_TAN = ["skin_a:1", "skin_a:2", "skin_b:1", "skin_a:3"]
SKIN_MID = "skin_b"
SKIN_DARK = ["skin_b:1", "skin_b:2", "hair:0", "hair:1"]
SKIN_RUDDY = ["skin_a:0", "skin_a:1", "pink:0", "skin_a:2"]
WATER = ["foam:1", "turquoise:0", "turquoise:1", "turquoise:2"]
TEAL_DEEP = ["turquoise:1", "turquoise:2", "sea:2"]
BLACKISH = ["night:1", "night:2", "ink:0"]

_BASE_PARTS = {"shirt": "outfit_a", "sleeve": "outfit_a", "forearm": "skin",
               "pants": "outfit_b", "shin": "outfit_b", "feet": "acc_c", "belt": None}


def _fiche(**kw):
    parts = dict(_BASE_PARTS)
    parts.update(kw.pop("parts", {}))
    kw["parts"] = parts
    kw.setdefault("hair", "short")
    kw.setdefault("hat", None)
    kw.setdefault("face", [])
    kw.setdefault("hands", "fist")
    kw.setdefault("feet_style", "shoe")
    kw.setdefault("torso_style", None)
    kw.setdefault("pelvis_style", None)
    kw.setdefault("acc_back", None)
    kw.setdefault("acc_front", None)
    kw.setdefault("acc_hand_b", None)
    kw.setdefault("body", {})
    kw.setdefault("amp", 1.0)
    kw.setdefault("scale", 1.0)
    kw.setdefault("costumes", {})
    return kw


# --------------------------------------------------------------- fiches
FICHES = {
    "louis": _fiche(
        name="Louis",
        roles={"skin": SKIN_LIGHT, "hair": "blond", "outfit_a": "linen", "outfit_b": "navy",
               "hat": "red", "acc_b": "wood", "acc_c": "sand", "extra": "red"},
        parts={"belt": "hat"}, hat="beret",
        costumes={1: {"hat": "green", "outfit_b": "navy", "extra": "green"},
                  2: {"outfit_b": "red", "hat": "navy"}, 3: {"outfit_b": "green", "hat": "yellow"}}),
    "maia": _fiche(
        name="Maïa",
        roles={"skin": SKIN_MID, "hair": "hair", "outfit_a": TEAL_DEEP, "outfit_b": "navy",
               "hat": "foam", "acc_b": "yellow", "acc_c": "sand", "extra": "orange"},
        parts={"sleeve": "outfit_a", "forearm": "outfit_a", "pants": "outfit_a", "shin": "outfit_a",
               "feet": "skin", "zip": "hat", "panel": "outfit_b"},
        hair="long_wet", acc_back="surfboard", amp=1.08,
        costumes={1: {"outfit_a": "pink", "outfit_b": "red"}, 2: {"outfit_a": "orange", "outfit_b": "navy"},
                  3: {"outfit_a": "purple", "outfit_b": "yellow"}}),
    "patxi": _fiche(
        name="Patxi",
        roles={"skin": SKIN_RUDDY, "hair": "hair", "outfit_a": "yellow", "outfit_b": "navy",
               "hat": "navy", "acc_b": "wood", "acc_c": BLACKISH, "extra": "steel"},
        parts={"sleeve": "outfit_a", "forearm": "outfit_a", "pants": "outfit_a", "shin": "acc_c",
               "feet": "acc_c"},
        hair="short", hat="beanie", face=["beard"], feet_style="boot", torso_style="coat",
        acc_front="rod", body={"torso_r": 1.08, "pelvis_rx": 1.1},
        costumes={1: {"outfit_a": "red", "hat": "navy"}, 2: {"outfit_a": "green", "hat": "red"},
                  3: {"outfit_a": "orange", "hat": "green"}}),
    "xabi": _fiche(
        cell=160, foot=[80, 152],
        name="Xabi",
        roles={"skin": SKIN_TAN, "hair": "hair", "outfit_a": "linen", "outfit_b": "linen",
               "hat": "red", "acc_b": "sand", "acc_c": "linen", "extra": "red"},
        parts={"belt": "hat", "feet": "acc_c"},
        hair="short", acc_front="chistera", body={"uarm_len": 1.05},
        costumes={1: {"hat": "green", "extra": "green"}, 2: {"hat": "navy", "outfit_b": "navy"},
                  3: {"hat": "yellow", "acc_b": "wood"}}),
    "mattin": _fiche(
        cell=160, foot=[80, 152],
        name="Mattin",
        roles={"skin": SKIN_MID, "hair": "hair", "outfit_a": "linen", "outfit_b": "navy",
               "hat": "red", "acc_b": "stone", "acc_c": BLACKISH, "extra": "red"},
        parts={"stripes": "hat", "forearm": "skin", "sleeve": "skin", "belt": "hat"},
        hair="buzz", face=["mustache"], torso_style="stripes", acc_hand_b="stone",
        scale=1.2, amp=0.9,
        body={"torso_r": 1.32, "torso_len": 1.05, "head_r": 0.88, "uarm_r": 1.45, "farm_r": 1.45,
              "fist_r": 1.3, "thigh_r": 1.35, "shin_r": 1.3, "pelvis_rx": 1.35, "thigh_len": 0.92},
        costumes={1: {"hat": "green"}, 2: {"hat": "navy", "outfit_b": "wood"},
                  3: {"hat": "yellow", "outfit_b": "green"}}),
    "amaia": _fiche(
        name="Amaia",
        roles={"skin": SKIN_LIGHT, "hair": "hair", "outfit_a": "linen", "outfit_b": "red",
               "hat": "green", "acc_b": "wood", "acc_c": "linen", "extra": "brass"},
        parts={"vest": "hat", "pants": "outfit_b", "shin": "acc_c", "skirt": "outfit_b"},
        hair="bun", hat="ribbons", pelvis_style="skirt", torso_style="vest", acc_front="makila",
        body={"torso_r": 0.92, "head_r": 0.97, "thigh_r": 0.9, "shin_r": 0.9}, amp=1.06,
        costumes={1: {"outfit_b": "navy", "hat": "red"}, 2: {"outfit_b": "green", "hat": "red"},
                  3: {"outfit_b": "purple", "hat": "yellow"}}),
    "txomin": _fiche(
        name="Txomin",
        roles={"skin": SKIN_DARK, "hair": "hair", "outfit_a": "yellow", "outfit_b": "red",
               "hat": BLACKISH, "acc_b": "orange", "acc_c": "linen", "extra": "red"},
        parts={"sleeve": "skin", "shin": "skin", "feet": "acc_c"},
        hair="curly", face=["sunglasses", "whistle"], torso_style="tank", acc_back="buoy",
        costumes={1: {"outfit_a": "red", "outfit_b": "yellow"}, 2: {"outfit_a": "turquoise", "outfit_b": "navy"},
                  3: {"outfit_a": "linen", "outfit_b": "green"}}),
    "kaio": _fiche(
        name="Kaio",
        roles={"skin": "linen", "hair": "stone", "outfit_a": "linen", "outfit_b": "linen",
               "hat": "yellow", "acc_b": "orange", "acc_c": "orange", "extra": "red"},
        parts={"sleeve": "hair", "forearm": "hair", "shirt": "outfit_a", "pants": "outfit_a",
               "shin": "acc_c", "feet": "acc_c"},
        hair="gull", face=["beak"], hands="wing", feet_style="bird", torso_style="belly",
        pelvis_style="tail", acc_hand_b="chips", scale=0.86, amp=1.15,
        body={"torso_r": 1.18, "head_r": 0.95, "thigh_r": 0.75, "shin_r": 0.5, "thigh_len": 0.7,
              "shin_len": 1.05, "uarm_r": 1.25, "farm_len": 1.4},
        costumes={1: {"hair": "night", "hat": "orange"}, 2: {"hair": "sand", "acc_c": "pink"},
                  3: {"hair": "purple", "hat": "pink"}}),
    "karramarro": _fiche(
        cell=160, foot=[80, 152],
        name="Karramarro",
        roles={"skin": ["orange:0", "orange:1", "orange:2", "red:2"], "hair": "orange",
               "outfit_a": "orange", "outfit_b": "red", "hat": "linen", "acc_b": "red",
               "acc_c": "red", "extra": "yellow"},
        parts={"shirt": "outfit_a", "sleeve": "outfit_a", "forearm": "outfit_a", "pants": "outfit_b",
               "shin": "outfit_a", "feet": "outfit_b"},
        hair="none", face=["eyestalks", "crab_mouth"], hands="claw", feet_style="crab",
        torso_style="carapace", scale=1.0, amp=0.95,
        body={"torso_r": 1.45, "torso_len": 0.75, "head_r": 0.62, "uarm_r": 1.05, "farm_r": 1.15,
              "thigh_r": 0.85, "shin_r": 0.75, "pelvis_rx": 1.3},
        costumes={1: {"outfit_a": "purple", "outfit_b": "navy", "hair": "purple"},
                  2: {"outfit_a": "sea", "outfit_b": "navy", "hair": "sea"},
                  3: {"outfit_a": "green", "outfit_b": "yellow", "hair": "green"}}),
    "ramuntxo": _fiche(
        name="Ramuntxo",
        roles={"skin": SKIN_RUDDY, "hair": "hair", "outfit_a": "linen", "outfit_b": "navy",
               "hat": "linen", "acc_b": "steel", "acc_c": BLACKISH, "extra": "red"},
        parts={"scarf": "extra", "apron": "hat"},
        hair="short", hat="toque", face=["mustache"], torso_style="chef", pelvis_style="apron",
        acc_front="ladle", body={"torso_r": 1.12, "pelvis_rx": 1.12},
        costumes={1: {"extra": "green", "outfit_b": "red"}, 2: {"extra": "navy", "outfit_b": "green"},
                  3: {"outfit_a": "yellow", "extra": "red"}}),
    "itsaso": _fiche(
        name="Itsaso",
        roles={"skin": WATER, "hair": ["foam:0", "turquoise:0", "turquoise:2"], "outfit_a": "foam", "outfit_b": "turquoise",
               "hat": "sea", "acc_b": "foam", "acc_c": "turquoise", "extra": "sea"},
        parts={"shirt": "outfit_a", "sleeve": "skin", "pants": "skin", "shin": "skin", "feet": "skin",
               "skirt": "outfit_a"},
        hair="wave", pelvis_style="skirt", feet_style="bare", body={"torso_r": 0.9, "thigh_r": 0.88},
        amp=1.08,
        costumes={1: {"outfit_a": "pink", "outfit_b": "pink"}, 2: {"outfit_a": "yellow", "outfit_b": "orange"},
                  3: {"outfit_a": "purple", "outfit_b": "night"}}),
    "peio": _fiche(
        name="Peio",
        roles={"skin": SKIN_DARK, "hair": BLACKISH, "outfit_a": "red", "outfit_b": BLACKISH,
               "hat": "linen", "acc_b": "wood", "acc_c": "linen", "extra": "red"},
        parts={"hoop": "hat", "shin": "acc_c", "feet": "outfit_b"},
        hair="buzz", face=["ears"], torso_style="rugby", acc_hand_b="ball", scale=1.05,
        body={"torso_r": 1.18, "uarm_r": 1.2, "farm_r": 1.15, "thigh_r": 1.15, "head_r": 0.95},
        costumes={1: {"outfit_a": "navy", "hat": "linen"}, 2: {"outfit_a": "green", "hat": "yellow"},
                  3: {"outfit_a": "yellow", "hat": "navy"}}),
    "itsasargi": _fiche(
        name="Itsasargi",
        roles={"skin": SKIN_RUDDY, "hair": "linen", "outfit_a": "navy", "outfit_b": "stone",
               "hat": "navy", "acc_b": "brass", "acc_c": BLACKISH, "extra": "yellow"},
        parts={"sleeve": "outfit_a", "forearm": "outfit_a", "buttons": "acc_b", "shin": "acc_c",
               "feet": "acc_c"},
        hair="short", hat="cap", face=["beard_big"], torso_style="caban", feet_style="boot",
        acc_hand_b="lantern", scale=1.3, cell=160, foot=[80, 152], amp=0.95,
        body={"torso_r": 1.08},
        costumes={1: {"outfit_a": "red", "hat": "red"}, 2: {"outfit_a": "green", "hat": "green"},
                  3: {"outfit_a": "wood", "hat": "wood", "acc_b": "steel"}}),
    "hondar": _fiche(
        name="Hondar",
        roles={k: "sand" for k in ("skin", "hair", "outfit_a", "outfit_b", "hat", "acc_b", "acc_c", "extra")},
        parts={"sleeve": "skin", "forearm": "skin", "shirt": "skin", "pants": "skin", "shin": "skin",
               "feet": "skin"},
        hair="none", feet_style="bare", face=["sand_eye"],
        costumes={k: {r: "sand" for r in ("outfit_a", "outfit_b", "hat", "acc_b", "acc_c", "extra")}
                  for k in (1, 2, 3)}),
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

    def __init__(self, size: int = 160):
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

    def poly(self, pts, idx, where=None):
        """Polygone convexe (sens quelconque)."""
        m = np.ones_like(self.X, bool)
        n = len(pts)
        cx = sum(p[0] for p in pts) / n
        cy = sum(p[1] for p in pts) / n
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            side = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            val = (bx - ax) * (self.Y - ay) - (by - ay) * (self.X - ax)
            m &= (val * side) >= 0
        self._set(m, idx, where)
        return m

    def recolor(self, mask, idx):
        """Recolore la zone `mask` uniquement là où la pièce est déjà opaque."""
        self.img[mask & (self.img > 0)] = idx

    def _set(self, m, idx, where):
        if idx is None:
            return
        if where is not None:
            m = m & where
        self.img[m] = idx

    def piece(self, attach=None, decals=None, shade=True) -> Piece:
        ys, xs = np.nonzero(self.img)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        img = self.img[y0:y1, x0:x1].copy()
        return Piece(img=img, pivot=(self.o - x0, self.o - y0),
                     attach=attach or {}, decals=decals or [], shade=shade)


def _role_idx(fiche, part, back=False):
    role = fiche["parts"].get(part)
    return ix.base(role, back) if role else None


def _light(role, back=False):
    """Ton clair d'un rôle (1er de la rampe)."""
    start, _ = ix.ROLES[role]
    return start + (1 if back else 0)


# --------------------------------------------------------------- pièces

def build_pieces(fiche: dict) -> dict:
    s = fiche.get("scale", 1.0)
    P = {k: v * s * fiche["body"].get(k, 1.0) for k, v in PROPS.items()}
    parts = fiche["parts"]
    pieces = {}
    skin = ix.base("skin")
    eye = np.array([[ix.EYE, ix.OUTLINE], [ix.EYE, ix.OUTLINE]], np.uint8)
    if "sand_eye" in fiche["face"]:
        eye = np.array([[ix.base("skin", True)]], np.uint8)
    pants = _role_idx(fiche, "pants")
    shirt = _role_idx(fiche, "shirt")

    # ---------------- bassin : pivot = hanches
    c = Canvas()
    c.ellipse((0, 0), P["pelvis_rx"], P["pelvis_ry"], pants)
    if parts.get("belt"):
        c.recolor(c.Y < -3.0 * s, ix.base(parts["belt"]))
    style = fiche["pelvis_style"]
    if style == "skirt":
        sk = _role_idx(fiche, "skirt")
        c.poly([(-P["pelvis_rx"] - 1, -2), (P["pelvis_rx"] + 1, -2),
                (P["pelvis_rx"] + 6 * s, 15 * s), (-P["pelvis_rx"] - 6 * s, 15 * s)], sk)
        c.recolor(c.Y > 11 * s, _light(parts["skirt"]))
    elif style == "apron":
        c.poly([(-2, -4), (P["pelvis_rx"] + 1, -4), (P["pelvis_rx"] + 3, 16 * s), (-1, 16 * s)],
               _role_idx(fiche, "apron"))
    elif style == "tail":
        c.poly([(-P["pelvis_rx"] + 2, -4), (-P["pelvis_rx"] - 13 * s, -10 * s),
                (-P["pelvis_rx"] - 12 * s, 2 * s), (-P["pelvis_rx"] + 3, 4)], ix.base("hair"))
        c.recolor(c.X < -P["pelvis_rx"] - 8 * s, ix.base("hair", True))
    if fiche["torso_style"] in ("coat", "caban"):
        c.poly([(-P["pelvis_rx"] - 1, -4), (P["pelvis_rx"] + 2, -4),
                (P["pelvis_rx"] + 3, 9 * s), (-P["pelvis_rx"] - 2, 9 * s)], shirt)
    pieces["pelvis"] = c.piece(attach={"tor": (0, -2), "thf": (2, 2), "thb": (-2, 2)})

    # ---------------- torse : pivot = taille, monte vers le haut
    tl, tr = P["torso_len"], P["torso_r"]
    c = Canvas()
    tstyle = fiche["torso_style"]
    if tstyle == "carapace":
        body = c.ellipse((1.0, -4 - tl * 0.6), tr * 1.05, tr * 1.0, shirt)
        for (sx, sy) in ((-4, -0.9), (5, -1.3), (-1, -1.6)):
            c.ellipse((sx * s, -4 - tl * 0.6 + sy * tr * 0.5), 2.2 * s, 1.8 * s, _light("outfit_a"))
        top = -4 - tl * 0.6 - tr
    else:
        body = c.capsule((0, -4), (1.5, -4 - tl), tr, shirt)
        c.ellipse((1.5, -4 - tl + 1), tr + 1.0, tr * 0.75, shirt)          # épaules
        top = -4 - tl - tr
    ty = (c.Y < -4) & (c.Y > top)
    if parts.get("belt") and tstyle not in ("coat", "caban"):
        c.recolor((c.Y > -7 * s) & (c.Y < -2), ix.base(parts["belt"]))
    if tstyle == "stripes":
        band = (np.floor((c.Y - top) / (3.0 * s)) % 2 == 1)
        c.recolor(band & (c.Y < -6 * s), ix.base(parts["stripes"]))
    elif tstyle == "rugby":
        c.recolor((c.Y > top + tr * 0.9) & (c.Y < top + tr * 0.9 + 4 * s), ix.base(parts["hoop"]))
        c.recolor((c.Y < top + 4 * s) & (np.abs(c.X - 3) < 5 * s), ix.base(parts["hoop"]))   # col
    elif tstyle == "vest":
        c.recolor((np.abs(c.X - 3.0) > 3.2 * s) & ty, ix.base(parts["vest"]))
        c.recolor((c.Y > -9 * s) & (c.Y < -4), ix.base("outfit_b"))                         # ceinture
    elif tstyle == "tank":
        c.recolor((c.Y < top + 6 * s) & (np.abs(c.X - 1.5) > 6 * s), skin)
    elif tstyle == "chef":
        c.recolor((c.Y < top + 5 * s) & (c.Y > top + 1) & (np.abs(c.X - 3) < 7 * s), ix.base(parts["scarf"]))
        for by in (0.35, 0.55, 0.75):
            c.ellipse((5.5 * s, top + by * (tl + 2 * tr)), 1.0, 1.0, ix.base("outfit_a", True))
    elif tstyle == "caban":
        for by in (0.35, 0.5, 0.65, 0.8):
            for bx in (3.5, 8.0):
                c.ellipse((bx * s, top + by * (tl + 2 * tr)), 1.1, 1.1, ix.base(parts["buttons"]))
        c.recolor((c.Y < top + 5 * s) & (c.X > 0), ix.base("outfit_a", True))               # col
    elif tstyle == "coat":
        c.recolor((np.abs(c.X - 6 * s) < 1.0) & ty, ix.base("outfit_a", True))             # boutonnage
    elif tstyle == "belly":
        c.ellipse((4 * s, -4 - tl * 0.45), tr * 0.75, tr * 0.95, _light("outfit_a"), where=body)
    if parts.get("zip"):
        c.recolor((np.abs(c.X - 7.5 * s) < 1.2) & (c.Y < -5), _light(parts["zip"]))
    if parts.get("panel"):
        c.recolor((c.X < -6.5 * s) & (c.Y < -5), ix.base(parts["panel"]))
    pieces["torso"] = c.piece(attach={
        "head": (1.5, top + 3.0), "uaf": (4.0, top + 7.5), "uab": (-2.0, top + 7.5),
        "acc": (-12.0 * s, -13.0 * s)})

    # ---------------- tête : pivot = base du cou
    pieces["head"] = _head(fiche, P, s, eye)

    # ---------------- membres
    for side, back in (("f", False), ("b", True)):
        c = Canvas()
        ul, ur = P["uarm_len"], P["uarm_r"]
        c.capsule((0, 0), (0, ul), ur, _role_idx(fiche, "sleeve", back))
        if parts["sleeve"] != parts["forearm"] and fiche["hands"] != "wing":
            c.recolor(c.Y > ul * 0.6, ix.base(parts["forearm"], back))
        pieces["uarm_" + side] = c.piece(attach={"fa": (0, ul)})
        c = Canvas()
        fl = P["farm_len"]
        fore = _role_idx(fiche, "forearm", back)
        if fiche["hands"] == "wing":
            c.capsule((0, 0), (0, fl), P["farm_r"] * 1.15, fore)
            c.ellipse((0.5, fl + 5 * s), P["farm_r"] * 0.95, 7.5 * s, ix.base("hair", True))
            c.recolor(c.Y > fl + 6 * s, ix.base("outfit_b", True) if back else _light("hair"))
            hand = (0.5, fl + 4)
        elif fiche["hands"] == "claw":
            c.capsule((0, 0), (0, fl), P["farm_r"], fore)
            cr = 7.0 * s
            c.ellipse((0.0, fl + cr * 0.9), cr * 0.95, cr * 1.15, ix.base("outfit_b", back))
            c.ellipse((2.6 * s, fl + cr * 1.5), cr * 0.45, cr * 0.75, 0)          # entaille de la pince
            c.img[(c.X > 1.0) & (c.Y > fl + cr * 1.0) & (c.Y < fl + cr * 2.2) & (np.abs(c.X - 2.4 * s) < 1.4 * s)] = 0
            hand = (0.0, fl + cr)
        else:
            c.capsule((0, 0), (0, fl), P["farm_r"], fore)
            c.ellipse((0.3, fl + 2.0), P["fist_r"], P["fist_r"], ix.base("skin", back))
            hand = (0.3, fl + 2.0)
        pieces["farm_" + side] = c.piece(attach={"hand": hand})
        # cuisse : pivot = hanche
        c = Canvas()
        th = P["thigh_len"]
        c.capsule((0, 0), (0, th), P["thigh_r"], _role_idx(fiche, "pants", back))
        if fiche["pelvis_style"] == "skirt":
            c.recolor(c.Y < 9 * s, _role_idx(fiche, "skirt", back))
        pieces["thigh_" + side] = c.piece(attach={"sh": (0, th)})
        # jambe + pied : pivot = genou
        c = Canvas()
        sl = P["shin_len"]
        shin = _role_idx(fiche, "shin", back)
        feet = _role_idx(fiche, "feet", back)
        fs = fiche["feet_style"]
        if fs == "bird":
            c.capsule((0, 0), (0, sl), P["shin_r"], shin)
            c.poly([(-2 * s, sl + 1), (9 * s, sl + 3), (9 * s, sl + 6 * s), (-2 * s, sl + 5 * s)], feet)
        elif fs == "crab":
            c.capsule((0, 0), (0.5, sl * 0.55), P["shin_r"], shin)
            c.capsule((0.5, sl * 0.55), (3 * s, sl + 4 * s), P["shin_r"] * 0.85, shin)
            c.poly([(1 * s, sl + 2 * s), (6 * s, sl + 4 * s), (3 * s, sl + 6 * s)], feet)
        else:
            c.capsule((0, 0), (0, sl), P["shin_r"], shin)
            if fs == "boot":
                c.recolor(c.Y > sl * 0.45, feet)
            if fiche["parts"]["shin"] == "acc_c" and fs not in ("boot",) and fiche["torso_style"] == "rugby":
                c.recolor((c.Y > sl * 0.3) & (c.Y < sl * 0.45), ix.base("outfit_a", back))  # bas rayés
            fr = P["foot_r"] * (1.15 if fs == "boot" else 1.0)
            c.capsule((-1.5, sl + 3.0), (7.5 * s, sl + 3.4), fr, feet)
        pieces["shin_" + side] = c.piece()

    # ---------------- accessoires
    _accessories(fiche, P, s, pieces)
    return pieces


def _head(fiche, P, s, eye) -> Piece:
    hr = P["head_r"]
    hc = (1.5, -3.0 - hr)
    skin = ix.base("skin")
    hair = ix.base("hair")
    c = Canvas()
    face = fiche["face"]
    c.capsule((0, 1), (0.5, -4), 3.5 * s, skin)                       # cou
    head = c.ellipse(hc, hr, hr * 0.96, skin)
    decals = [((hc[0] + 6.0 * s, hc[1] - 0.5), eye)]
    if "beak" in face:
        c.recolor(head, ix.base("outfit_a"))
        c.ellipse(hc, hr, hr * 0.96, ix.base("outfit_a"))
        c.capsule((hc[0] + hr * 0.6, hc[1] + 2.5 * s), (hc[0] + hr + 9 * s, hc[1] + 3.5 * s), 3.2 * s, ix.base("hat"))
        c.capsule((hc[0] + hr * 0.6, hc[1] + 5.5 * s), (hc[0] + hr + 5 * s, hc[1] + 6.0 * s), 2.0 * s, ix.base("hat", True))
        c.ellipse((hc[0] + hr + 8.5 * s, hc[1] + 5.0 * s), 1.6 * s, 1.6 * s, ix.base("extra"))   # tache rouge
        decals = [((hc[0] + 3.5 * s, hc[1] - 2.0 * s), np.array([[ix.EYE, ix.EYE], [ix.EYE, ix.OUTLINE]], np.uint8))]
    elif "eyestalks" not in face:
        c.ellipse((hc[0] + hr - 0.5, hc[1] + 2.0), 2.2 * s, 2.0 * s, skin)    # nez
    st = fiche["hair"]
    if st == "short":
        c.recolor(head & ((c.Y < hc[1] - 4.0 * s) | ((c.X < hc[0] - 4.0 * s) & (c.Y < hc[1] + 5.0 * s))), hair)
        c.ellipse((hc[0] + 6.0 * s, hc[1] - 7.5 * s), 4.5 * s, 2.5 * s, hair)       # mèche
    elif st == "buzz":
        c.recolor(head & ((c.Y < hc[1] - 6.0 * s) | ((c.X < hc[0] - 6.0 * s) & (c.Y < hc[1] + 2.0 * s))), hair)
    elif st == "curly":
        c.recolor(head & ((c.Y < hc[1] - 3.5 * s) | ((c.X < hc[0] - 4.0 * s) & (c.Y < hc[1] + 4.0 * s))), hair)
        for k in range(5):
            c.ellipse((hc[0] - 9 * s + k * 4.5 * s, hc[1] - hr + 1.5 * s), 3.2 * s, 3.0 * s, hair)
    elif st == "long_wet":
        c.capsule((hc[0] - 6.0, hc[1] - 2.0), (hc[0] - 9.0, hc[1] + 15.0), 4.6, hair)
        c.recolor(head & ((c.Y < hc[1] - 3.0) | (c.X < hc[0] - 3.5)), hair)
        c.capsule((hc[0] + 2.0, hc[1] - hr + 1.5), (hc[0] + 9.0, hc[1] - 5.0), 2.2, hair)
    elif st == "bun":
        c.recolor(head & ((c.Y < hc[1] - 3.5 * s) | (c.X < hc[0] - 3.5 * s)), hair)
        c.ellipse((hc[0] - hr + 1, hc[1] - hr + 3), 5.0 * s, 4.5 * s, hair)
        c.capsule((hc[0] - hr + 1, hc[1] - 2), (hc[0] - hr - 3, hc[1] + 14 * s), 2.6 * s, hair)   # tresse
    elif st == "wave":
        # Chevelure en vague : part du sommet, roule vers l'arrière et retombe
        # en volute d'écume dans le dos.
        c.recolor(head & ((c.Y < hc[1] - 3.0 * s) | (c.X < hc[0] - 3.0 * s)), hair)
        c.ellipse((hc[0] - 4 * s, hc[1] - hr * 0.6), hr * 0.95, hr * 0.55, hair)
        c.capsule((hc[0] - hr * 0.6, hc[1] - 2 * s), (hc[0] - hr - 6 * s, hc[1] + 12 * s), 5.0 * s, hair)
        c.capsule((hc[0] - hr - 6 * s, hc[1] + 12 * s), (hc[0] - hr - 2 * s, hc[1] + 20 * s), 3.6 * s, hair)
        c.ellipse((hc[0] - hr - 9 * s, hc[1] + 8 * s), 3.0 * s, 2.6 * s, ix.base("hair", True))
        c.ellipse((hc[0] + 4 * s, hc[1] - hr * 0.75), 4.0 * s, 2.4 * s, ix.base("hair", True))
    elif st == "gull":
        c.ellipse((hc[0] - 2, hc[1] - hr * 0.55), hr * 0.85, hr * 0.5, hair, where=head)          # calotte grise
    if fiche["hat"] == "beret":
        hat = ix.base("hat")
        c.ellipse((hc[0] - 1.5, hc[1] - hr + 1.0), hr + 1.5, 4.2, hat)
        c.capsule((hc[0] - 1.0, hc[1] - hr - 3.0), (hc[0] - 0.5, hc[1] - hr - 5.0), 1.3, hat)
    elif fiche["hat"] == "beanie":
        hat = ix.base("hat")
        c.ellipse((hc[0] - 0.5, hc[1] - hr * 0.55), hr * 1.05, hr * 0.7, hat, where=(c.Y < hc[1] - 3 * s))
        c.rect(hc[0] - hr - 1, hc[1] - 5 * s, hc[0] + hr + 1, hc[1] - 2 * s, _light("hat"), where=head | (c.Y < 0))
        c.ellipse((hc[0] - 1, hc[1] - hr - 3 * s), 3.2 * s, 2.6 * s, _light("hat"))                 # pompon
    elif fiche["hat"] == "cap":
        hat = ix.base("hat")
        c.ellipse((hc[0] - 1, hc[1] - hr * 0.6), hr * 1.05, hr * 0.55, hat, where=(c.Y < hc[1] - 3.5 * s))
        c.capsule((hc[0] + 2, hc[1] - 4 * s), (hc[0] + hr + 7 * s, hc[1] - 3 * s), 2.0 * s, ix.base("acc_c"))  # visière
        c.ellipse((hc[0] + 4 * s, hc[1] - hr * 0.75), 2.0 * s, 1.8 * s, ix.base("acc_b"))              # insigne
    elif fiche["hat"] == "toque":
        hat = _light("hat")
        c.rect(hc[0] - hr * 0.8, hc[1] - hr - 5 * s, hc[0] + hr * 0.8, hc[1] - hr * 0.55, hat)
        c.ellipse((hc[0], hc[1] - hr - 6 * s), hr * 1.0, 5.5 * s, hat)
        c.rect(hc[0] - hr * 0.85, hc[1] - hr * 0.8, hc[0] + hr * 0.85, hc[1] - hr * 0.45, ix.base("hat", True))
    elif fiche["hat"] == "ribbons":
        c.rect(hc[0] - hr, hc[1] - hr * 0.55, hc[0] + hr * 0.4, hc[1] - hr * 0.3, ix.base("outfit_b"), where=head)
        c.capsule((hc[0] - hr, hc[1] - hr * 0.4), (hc[0] - hr - 6 * s, hc[1] + 10 * s), 1.5 * s, ix.base("hat"))
        c.capsule((hc[0] - hr + 1, hc[1] - hr * 0.4), (hc[0] - hr - 2 * s, hc[1] + 13 * s), 1.5 * s, ix.base("outfit_b"))
    if "beard" in face or "beard_big" in face:
        big = "beard_big" in face
        beard = ix.base("hair") if not big else _light("hair")
        c.ellipse((hc[0] + 3 * s, hc[1] + hr * 0.55), hr * (0.85 if big else 0.7), hr * (0.7 if big else 0.5), beard,
                  where=(c.Y > hc[1] + 2 * s) | ~head)
        c.ellipse((hc[0] + 7 * s, hc[1] + 2.5 * s), 4.0 * s, 1.6 * s, beard)
    if "mustache" in face:
        c.ellipse((hc[0] + hr - 2 * s, hc[1] + 4.0 * s), 4.5 * s, 1.8 * s, ix.base("hair"))
    if "sunglasses" in face:
        decals = []
        c.rect(hc[0] + 1 * s, hc[1] - 3 * s, hc[0] + hr + 1, hc[1] + 1 * s, ix.base("hat"), where=head)
        c.rect(hc[0] - 4 * s, hc[1] - 2 * s, hc[0] + 1 * s, hc[1] - 0.5 * s, ix.base("hat"), where=head)
    if "ears" in face:
        c.ellipse((hc[0] - 2.5 * s, hc[1] + 1.5 * s), 3.6 * s, 4.2 * s, ix.base("skin", True))
        c.ellipse((hc[0] - 2.0 * s, hc[1] + 1.0 * s), 1.5 * s, 1.8 * s, ix.base("skin"))
    if "whistle" in face:
        c.capsule((hc[0] + 2, 0), (hc[0] + 4 * s, 4 * s), 0.8, ix.base("extra"))
    if "eyestalks" in face:
        decals = []
        for k, (dx, h) in enumerate(((2.5, 12), (8.0, 10))):
            c.capsule((hc[0] + dx * s - 2, hc[1] - hr * 0.5), (hc[0] + dx * s, hc[1] - hr - h * s), 1.4 * s,
                      ix.base("hair", k == 0))
            c.ellipse((hc[0] + dx * s, hc[1] - hr - h * s - 1.5 * s), 3.0 * s, 3.0 * s, ix.EYE)
            decals.append(((hc[0] + dx * s + 1.0, hc[1] - hr - h * s - 1.5 * s), np.array([[ix.OUTLINE]], np.uint8)))
    if "crab_mouth" in face:
        c.rect(hc[0] + hr * 0.2, hc[1] + 2 * s, hc[0] + hr * 0.9, hc[1] + 3.2 * s, ix.OUTLINE, where=head)
    return c.piece(decals=decals)


def _accessories(fiche, P, s, pieces) -> None:
    acc = fiche["acc_back"]
    if acc == "surfboard":
        c = Canvas()
        board = c.ellipse((0, 0), 7.5, 24.0, ix.base("acc_b"))
        c.recolor(board & (np.abs(c.X - 0.5) < 1.2), ix.base("hat"))
        c.recolor(board & (c.Y < -19), ix.base("acc_b", True))
        pieces["acc"] = c.piece()
    elif acc == "buoy":
        c = Canvas()
        c.capsule((0, -18 * s), (0, 18 * s), 5.0 * s, ix.base("acc_b"))
        c.recolor(np.abs(c.Y) < 2.0 * s, ix.base("acc_c"))
        pieces["acc"] = c.piece()
    front = fiche["acc_front"]
    c = Canvas()
    if front == "rod":
        c.capsule((0, -4 * s), (0, 27 * s), 1.2 * s, ix.base("acc_b"))
        c.capsule((0, -4 * s), (0, 5 * s), 2.2 * s, ix.base("acc_c"))           # manche
        c.ellipse((2.0 * s, 8 * s), 2.4 * s, 2.4 * s, ix.base("extra"))          # moulinet
        pieces["accf"] = c.piece()
    elif front == "chistera":
        # Gant d'osier courbe : part du poignet, s'allonge et remonte en bec.
        c.capsule((0, -2 * s), (1 * s, 10 * s), 4.0 * s, ix.base("acc_b"))
        c.capsule((1 * s, 10 * s), (-1 * s, 24 * s), 5.0 * s, ix.base("acc_b"))
        c.capsule((-1 * s, 24 * s), (-7 * s, 30 * s), 3.6 * s, ix.base("acc_b"))
        c.img[(c.img > 0) & ((np.floor(c.Y / 2.0 + c.X / 3.0) % 2) == 0)] = ix.base("acc_b", True)   # osier
        c.capsule((2.5 * s, 8 * s), (2.0 * s, 24 * s), 1.8 * s, ix.base("acc_b", True))  # creux du panier
        pieces["accf"] = c.piece()
    elif front == "makila":
        c.capsule((-14 * s, 0), (24 * s, 0), 1.6 * s, ix.base("acc_b"))
        c.ellipse((24 * s, 0), 2.4 * s, 2.4 * s, ix.base("extra"))
        c.ellipse((-14 * s, 0), 2.2 * s, 2.0 * s, ix.base("extra"))
        pieces["accf"] = c.piece()
    elif front == "ladle":
        c.capsule((0, 0), (0, 16 * s), 1.4 * s, ix.base("acc_b"))
        c.ellipse((1.5 * s, 19 * s), 5.0 * s, 3.8 * s, ix.base("acc_b"))
        c.ellipse((1.5 * s, 18 * s), 3.5 * s, 1.8 * s, ix.base("acc_b", True))
        pieces["accf"] = c.piece()
    hb = fiche["acc_hand_b"]
    c = Canvas()
    if hb == "stone":
        c.ellipse((0, -6 * s), 12 * s, 10 * s, ix.base("acc_b"))
        c.ellipse((-3 * s, -4 * s), 2.0 * s, 1.5 * s, ix.base("acc_b", True))
        c.ellipse((4 * s, -9 * s), 1.5 * s, 1.2 * s, ix.base("acc_b", True))
        pieces["accb"] = c.piece()
    elif hb == "ball":
        c.ellipse((0, 0), 8 * s, 5.5 * s, ix.base("acc_b"))
        c.rect(-1.0, -5 * s, 1.0, 5 * s, _light("hat"), where=c.img > 0)
        pieces["accb"] = c.piece()
    elif hb == "lantern":
        c.rect(-4 * s, 2 * s, 4 * s, 14 * s, ix.base("acc_b"))
        c.rect(-2.6 * s, 4 * s, 2.6 * s, 12 * s, _light("extra"))
        c.capsule((0, -1 * s), (0, 3 * s), 1.0 * s, ix.base("acc_b"))
        pieces["accb"] = c.piece()
    elif hb == "chips":
        c.rect(-5 * s, -4 * s, 5 * s, 6 * s, ix.base("extra"))
        c.rect(-3 * s, -1 * s, 3 * s, 2 * s, _light("hat"))
        pieces["accb"] = c.piece()


# Angles de repos des accessoires tenus (relatifs à l'avant-bras).
ACC_REST = {"rod": -20.0, "chistera": -75.0, "makila": 35.0, "ladle": -10.0,
            "stone": -100.0, "ball": 0.0, "lantern": -120.0, "chips": 0.0}


def build_rig(fiche: dict) -> Rig:
    pieces = build_pieces(fiche)
    bones = [
        Bone("pel", None, "pelvis"),
        Bone("tor", "pel", "torso"),
        Bone("head", "tor", "head", soft_joint=False),
        Bone("uaf", "tor", "uarm_f", soft_joint=False), Bone("faf", "uaf", "farm_f", "fa"),
        Bone("uab", "tor", "uarm_b", soft_joint=False), Bone("fab", "uab", "farm_b", "fa"),
        Bone("thf", "pel", "thigh_f"), Bone("shf", "thf", "shin_f", "sh"),
        Bone("thb", "pel", "thigh_b"), Bone("shb", "thb", "shin_b", "sh"),
    ]
    order = ["uab", "fab", "thb", "shb", "pel", "tor", "thf", "shf", "head", "uaf", "faf"]
    if "acc" in pieces:
        bones.append(Bone("acc", "tor", "acc", soft_joint=False))
        order = ["acc"] + order
    if "accb" in pieces:
        bones.append(Bone("accb", "fab", "accb", "hand", rest=ACC_REST.get(fiche["acc_hand_b"], 0.0),
                          soft_joint=False))
        order.insert(order.index("thf"), "accb")
    if "accf" in pieces:
        bones.append(Bone("accf", "faf", "accf", "hand", rest=ACC_REST.get(fiche["acc_front"], 0.0),
                          soft_joint=False))
        order.append("accf")
    families = {}
    for role, (start, n) in ix.ROLES.items():
        for i in range(start, start + n):
            families[i] = start
    # Rôles partagés par plusieurs zones : même famille si même rampe.
    return Rig(bones, pieces, order, ix.shade_ramps(), families)
