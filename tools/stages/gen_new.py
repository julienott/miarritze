#!/usr/bin/env python3
"""Nouveaux stages sans photo source (SPEC §11.4) : txt2img rd_plus 384×216,
horizon à ~55 %, rien d'important dans les 20 % du bas (le sol y est posé).
Écrit assets/stages/<id>/src.png (puis widen_mirror élargit à 512×216).
Usage : gen_new.py <id> [<id>…]"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "rd"))
import client  # noqa: E402

COMMON = ("wide fighting game stage backdrop, side view, horizon at 55% height, nothing in the bottom 20%, "
          "detailed pixel art video game background, vibrant warm colors, no people in the foreground, "
          "no text, no letters, no signs, no logos")
PROMPTS = {
    "halles": "inside the covered market hall of Biarritz, iron and glass roof, market stalls with fruit, "
              "cheese and hanging bayonne hams, basque linen with red and green stripes, warm light",
    "fronton": "basque pelota fronton court, tall pink stone wall with rounded top, green hills and white "
               "basque houses with red shutters behind, spectators on stone steps on the side, sunny day",
    "stade": "rugby stadium seen from the pitch, red and white stands full of cheering crowd, red and white "
             "flags, white rugby goal posts, green grass, blue sky, generic stadium without any logo",
    "aquarium": "inside a big aquarium hall, huge blue glass tank with fish, rays and seals swimming, "
                "underwater light rays, dark blue room, art deco details",
    "phare_sommet": "night view from the top balcony of the Biarritz lighthouse, starry dark blue sky, "
                    "crescent moon, lit coastal town lights far below, dark ocean, iron railing far away",
}


def gen(sid):
    payload = {"prompt": PROMPTS[sid] + ", " + COMMON, "prompt_style": "rd_plus__default",
               "width": 384, "height": 216, "num_images": 1, "seed": 31}
    paths = client.generate(payload, f"stage/{sid}/src")
    out = os.path.join(ROOT, "assets", "stages", sid)
    os.makedirs(out, exist_ok=True)
    Image.open(paths[0]).convert("RGB").save(os.path.join(out, "src.png"))
    return out


if __name__ == "__main__":
    for sid in sys.argv[1:]:
        print(gen(sid))
