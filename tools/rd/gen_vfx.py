#!/usr/bin/env python3
"""Effets des coups spéciaux générés par Retro Diffusion (via client.py, plafond).

Usage : gen_vfx.py <id> [effet …]   (sans effet : tous ceux du perso)
Écrit une planche de choix tools/rd/out/<id>/vfx_<effet>.png (4 propositions).
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client  # noqa: E402

STYLE = "pixel art game effect sprite, crisp pixels, kid friendly cartoon, sunny basque coast palette, no text, no blood"
OUTLINED = "thick dark plum outline"

VFX = {
    "louis": {
        "proj_espadrille": (64, 64, f"a single basque espadrille shoe seen from the side, white canvas upper, braided jute rope sole, red laces, {OUTLINED}"),
        "sp_forward": (64, 64, "horizontal red and white speed lines dash trail, motion streak swoosh pointing right, cartoon"),
        "sp_down": (64, 64, "isolated white sea foam splash crescent, a curved arc of foam droplets and bubbles, single effect on empty background, no beach, no sand, no ground, no sky, no scenery"),
        "sp_up": (64, 64, "isolated vertical column of warm golden light rays shooting upward with small white sparkles, energy glow effect, single effect on empty background, no building, no lighthouse, no ground, no scenery"),
        "super": (96, 96, "big round golden victory burst with a red basque lauburu cross symbol in the center, radiating sparkles and stars"),
    },
}


def generate(fid, name):
    w, h, desc = VFX[fid][name]
    payload = {
        "prompt": f"{desc}, {STYLE}", "prompt_style": "rd_fast__default",
        "width": w, "height": h, "num_images": 4, "seed": 21 + len(desc) % 7, "remove_bg": True,
    }
    paths = client.generate(payload, f"{fid}/vfx_{name}")
    out = os.path.join(HERE, "out", fid)
    os.makedirs(out, exist_ok=True)
    s = max(1, 192 // max(w, h))
    sheet = Image.new("RGBA", ((w * s + 8) * 4 + 8, h * s + 16), (120, 170, 210, 255))
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGBA").resize((w * s, h * s), Image.NEAREST)
        sheet.alpha_composite(im, (8 + i * (w * s + 8), 8))
    path = os.path.join(out, f"vfx_{name}.png")
    sheet.save(path)
    return path, paths


if __name__ == "__main__":
    fid = sys.argv[1]
    for name in sys.argv[2:] or list(VFX[fid]):
        path, paths = generate(fid, name)
        print(name, path)
        for p in paths:
            print("   ", p)
