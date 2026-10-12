#!/usr/bin/env python3
"""Élargit un ancien décor i2i 320×180 (3 frames d'eau) en calque lointain
512×216 (SPEC §11.4) : ×1,2 nearest → 384×216, puis outpainting RD de 64 px
de chaque côté (un seul appel, sur la frame 0). Les frames 1 et 2 gardent
les côtés générés et leur propre centre animé.
Usage : widen.py <stage_id> <bg_name> "<prompt>"  [--dry]"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "rd"))
import client  # noqa: E402


def scaled(bg, i):
    img = Image.open(os.path.join(ROOT, "assets", "sprites", f"{bg}_{i}.png")).convert("RGB")
    return img.resize((384, 216), Image.NEAREST)


def main(stage, bg, prompt, dry=False):
    base = scaled(bg, 0)
    text = prompt + ", pixel art, seamless continuation of the scene, no people, no text"
    # Fenêtre de génération RD : 256 px → un appel par côté (192 + 64).
    left_in = base.crop((0, 0, 192, 216))
    right_in = base.crop((192, 0, 384, 216))
    pl = {"input_image": client.b64_png(left_in), "expand_left": 64, "prompt": text}
    pr = {"input_image": client.b64_png(right_in), "expand_right": 64, "prompt": text}
    if dry:
        print(client._http("POST", "/edit/tools/outpainting/estimate", pl))
        return
    mode0 = MODES.get(stage, ("rd", "rd"))
    left = Image.open(client.edit_tool("outpainting", pl, f"stage/{stage}/widen_l")[0]).convert("RGB") \
        if mode0[0] == "rd" else Image.new("RGB", (256, 216))
    right = Image.open(client.edit_tool("outpainting", pr, f"stage/{stage}/widen_r")[0]).convert("RGB") \
        if mode0[1] == "rd" else Image.new("RGB", (256, 216))
    left = left.resize((256, 216), Image.NEAREST) if left.size != (256, 216) else left
    right = right.resize((256, 216), Image.NEAREST) if right.size != (256, 216) else right
    out = os.path.join(ROOT, "assets", "stages", stage)
    os.makedirs(out, exist_ok=True)
    mode = MODES.get(stage, ("rd", "rd"))
    for i in range(3):
        center = scaled(bg, i)
        frame = Image.new("RGB", (512, 216))
        frame.paste(center, (64, 0))
        _side(frame, left, center, "left", mode[0])
        _side(frame, right, center, "right", mode[1])
        frame.save(os.path.join(out, f"far_{i}.png"))
    print(out)


# Côté par côté : "rd" (outpainting + raccord tramé) ou "mirror" (gratuit).
MODES = {"grande_plage": ("rd", "mirror"), "cote_basques": ("mirror", "rd"), "port_pecheurs": ("mirror", "mirror")}
BLEND = 12


def _side(frame, gen, center, side, mode):
    if mode == "mirror":
        strip = center.crop((0, 0, 64, 216)) if side == "left" else center.crop((320, 0, 384, 216))
        frame.paste(strip.transpose(Image.FLIP_LEFT_RIGHT), (0, 0) if side == "left" else (448, 0))
        return
    if side == "left":
        frame.paste(gen.crop((0, 0, 64, 216)), (0, 0))
        cols = range(64, 64 + BLEND)
        src = lambda x: x          # même colonne dans la fenêtre générée
    else:
        frame.paste(gen.crop((192, 0, 256, 216)), (448, 0))
        cols = range(448 - BLEND, 448)
        src = lambda x: x - 256
    # Raccord tramé : la part générée décroît en s'éloignant du bord.
    for k, x in enumerate(cols):
        w = (BLEND - k) / (BLEND + 1) if side == "left" else (k + 1) / (BLEND + 1)
        for y in range(216):
            if ((x * 7 + y * 13) % 17) / 17.0 < w:
                frame.putpixel((x, y), gen.getpixel((src(x), y)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], "--dry" in sys.argv)
