#!/usr/bin/env python3
"""Intègre les décors Retro Diffusion dans assets/sprites en ré-animant l'eau.

Pour chaque image : frame 0 = originale ; frames 1 et 2 ajoutent/déplacent
des étincelles d'écume sur les pixels « eau » (teinte bleu-turquoise),
pour garder la mer vivante avec PixelBg (3 frames).
"""
from PIL import Image
import os, sys

SCRATCH = "/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad/rd"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")

FOAM = (222, 244, 240, 255)

# les fichiers i2i_* viennent des photos réelles (tools/rd_i2i.py)
MAP = {
    "i2i_beach": "bg_beach",
    "i2i_surf": "bg_surf",
    "i2i_fishing": "bg_fishing",
    "i2i_rock": "bg_rock",
    "i2i_espadrille": "bg_espadrille",
    "i2i_hub": "bg_hub",
    "i2i_menu": "bg_menu",
}

# miroir horizontal (composition de jeu : le Rocher à droite = destination)
FLIP = {"i2i_rock"}


def is_water(pixel) -> bool:
    r, g, b = pixel[:3]
    return b > 90 and b > r + 18 and g > r and (g + b) > 200


def hash01(x: int, y: int, salt: int) -> float:
    h = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) % 10000) / 10000.0


def main():
    for src_name, dst_name in MAP.items():
        src_path = os.path.join(SCRATCH, f"{src_name}.png")
        base = Image.open(src_path).convert("RGBA")
        if base.size != (320, 180):
            base = base.resize((320, 180), Image.NEAREST)
        if src_name in FLIP:
            base = base.transpose(Image.FLIP_LEFT_RIGHT)
        pixels = base.load()
        # hors carte du hub, on n'anime que la moitié basse (le ciel des
        # autres décors partage des teintes avec la mer)
        y_min = 0 if src_name == "i2i_hub" else int(base.height * 0.45)
        water = [(x, y) for y in range(y_min, base.height) for x in range(base.width)
                 if is_water(pixels[x, y])]
        for frame in range(3):
            img = base.copy()
            if frame > 0:
                px = img.load()
                for (x, y) in water:
                    h = hash01(x, y, frame)
                    if h < 0.010:            # étincelle d'écume
                        px[x, y] = FOAM
                    elif h > 0.995:          # creux légèrement assombri
                        r, g, b, a = px[x, y]
                        px[x, y] = (max(r - 18, 0), max(g - 18, 0), max(b - 12, 0), a)
            img.save(os.path.join(OUT, f"{dst_name}_{frame}.png"))
        print(dst_name, ":", len(water), "px d'eau animés")


if __name__ == "__main__":
    main()
