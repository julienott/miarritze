#!/usr/bin/env python3
"""Carte des différences : la sheet rendue en gris + les pixels CHANGÉS par
le nettoyage colorés en cyan vif. On voit où ça a agi, sans deviner.

Usage : diff_map.py <id>
Sortie : tests/out/qa/diff_<id>.png
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SCALE = 2
CYAN = np.array([0, 220, 255, 255], dtype=np.uint8)
BG = np.array([24, 16, 28, 255], dtype=np.uint8)
GREY = np.array([160, 160, 160, 255], dtype=np.uint8)


def main() -> None:
    fid = sys.argv[1]
    d = os.path.join(ROOT, "assets", "fighters", fid)
    orig = np.array(Image.open(os.path.join(d, "sheet.orig.png")))
    new = np.array(Image.open(os.path.join(d, "sheet.png")))
    changed = orig != new
    rgba = np.where((new > 0)[..., None], GREY, BG)
    rgba[changed] = CYAN
    img = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    out = os.path.join(ROOT, "tests", "out", "qa", f"diff_{fid}.png")
    img.save(out)
    print(out, "- changed", int(changed.sum()), "pixels")


if __name__ == "__main__":
    main()
