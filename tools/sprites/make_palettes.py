#!/usr/bin/env python3
"""Palettes de costumes (SPEC-BORROKA §5.4, §11.3.6).

Costume 1 (rangée 0) = défaut. Costumes 2–4 : rotation de teinte des rampes
des rôles « vêtements/accessoires » (outfit_a, outfit_b, hat, acc_b, acc_c,
extra), recalée sur la rampe de tools/palette.py de teinte la plus proche,
pour rester dans la palette unique. Jamais `skin` ni `outline`.
Une fiche peut imposer des rampes par costume (ex. Louis : béret vert).
"""
from __future__ import annotations

import colorsys
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import indices as ix  # noqa: E402
from palette import RAMPS  # noqa: E402

SWAP_ROLES = ("outfit_a", "outfit_b", "hat", "acc_b", "acc_c", "extra")
# Rampes « colorées » candidates au recalage (les neutres restent neutres).
CANDIDATES = ("red", "green", "navy", "turquoise", "yellow", "orange", "purple",
              "pink", "sea", "brass")
HUE_STEPS = {1: 0.33, 2: 0.58, 3: 0.80}


def _hsv(rgb):
    return colorsys.rgb_to_hsv(*(c / 255.0 for c in rgb))


def _mid(ramp):
    return ramp[len(ramp) // 2]


def rotate_ramp(name: str, step: float) -> str:
    h, s, v = _hsv(_mid(RAMPS[name]))
    if s < 0.25 or name not in CANDIDATES:      # blanc, pierre, bois, sable : inchangés
        return name
    target = (h + step) % 1.0
    best, best_d = name, 9.0
    for cand in CANDIDATES:
        if cand == name:
            continue
        ch, cs, _ = _hsv(_mid(RAMPS[cand]))
        d = min(abs(ch - target), 1 - abs(ch - target)) + 0.2 * abs(cs - s)
        if d < best_d:
            best, best_d = cand, d
    return best


def costume_roles(fiche: dict, k: int) -> dict:
    roles = dict(fiche["roles"])
    if k == 0:
        return roles
    override = fiche.get("costumes", {}).get(k, {})
    for role in SWAP_ROLES:
        roles[role] = override.get(role, rotate_ramp(roles[role], HUE_STEPS[k]))
    return roles


def build(fiche: dict) -> Image.Image:
    img = Image.new("RGBA", (32, 4))
    for k in range(4):
        roles = costume_roles(fiche, k)
        row = ix.build_row({r: RAMPS[n] for r, n in roles.items()})
        for i, c in enumerate(row):
            img.putpixel((i, k), c)
    return img


def write(fiche: dict, path: str) -> None:
    build(fiche).save(path)
