#!/usr/bin/env python3
"""Copie réduite (512 px, fond blanc) des profils candidats et des retouches de chaque perso, de
tools/rd/out/<id>/gk2d/<lot>/ (gitignoré) vers tools/gordeka/candidats/<id>/<lot>/ (versionné), pour
que /producer en ligne les montre : Julien choisit ses variantes à distance (2026-10-20).
Un lot = un dossier contenant params.json. Les animations (pf/, pf_ondule/) ne sont pas copiées.

  sync_candidats.py
"""
import json
import os
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "tools", "rd", "out")
DST = os.path.join(HERE, "candidats")


def main():
    n = 0
    for pid in sorted(os.listdir(SRC)):
        gk = os.path.join(SRC, pid, "gk2d")
        if not os.path.isdir(gk):
            continue
        for lot in sorted(os.listdir(gk)):
            d = os.path.join(gk, lot)
            if not os.path.exists(os.path.join(d, "params.json")):
                continue
            out = os.path.join(DST, pid, lot)
            os.makedirs(out, exist_ok=True)
            shutil.copy(os.path.join(d, "params.json"), out)
            for k in range(8):
                src = next((os.path.join(d, f) for f in (f"image_0{k}_white.png", f"image_0{k}.png")
                            if os.path.exists(os.path.join(d, f))), None)
                if src is None:
                    continue
                im = Image.open(src).convert("RGBA")
                bg = Image.new("RGBA", im.size, "white")
                bg.alpha_composite(im)
                im = bg.convert("RGB")
                im.thumbnail((512, 512), Image.LANCZOS)
                im.save(os.path.join(out, f"image_0{k}.png"), optimize=True)
                n += 1
    print(n, "images")


if __name__ == "__main__":
    main()
