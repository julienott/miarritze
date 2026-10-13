#!/usr/bin/env python3
"""Élargissement gratuit d'un décor en 512×216 (SPEC §11.4, repli) :
source 384×216 (src.png) ou ancien décor 320×180 animé (×1,2 nearest),
bords de 64 px prolongés en miroir. Écrit far_0..2.png.
Usage : widen_mirror.py <stage_id> [bg_name]   (sans bg_name : assets/stages/<id>/src.png)"""
import os, sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def widen(center):
    frame = Image.new("RGB", (512, 216))
    frame.paste(center, (64, 0))
    frame.paste(center.crop((0, 0, 64, 216)).transpose(Image.FLIP_LEFT_RIGHT), (0, 0))
    frame.paste(center.crop((320, 0, 384, 216)).transpose(Image.FLIP_LEFT_RIGHT), (448, 0))
    return frame


def main(sid, bg=None):
    out = os.path.join(ROOT, "assets", "stages", sid)
    os.makedirs(out, exist_ok=True)
    for i in range(3):
        if bg:
            name = f"{bg}_{i}.png" if os.path.exists(os.path.join(ROOT, "assets", "sprites", f"{bg}_{i}.png")) else f"{bg}.png"
            center = Image.open(os.path.join(ROOT, "assets", "sprites", name)).convert("RGB").resize((384, 216), Image.NEAREST)
        else:
            center = Image.open(os.path.join(out, "src.png")).convert("RGB")
        widen(center).save(os.path.join(out, f"far_{i}.png"))
    print(sid)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
