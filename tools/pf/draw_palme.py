#!/usr/bin/env python3
"""Palme de plongée de Txomin (projectile « Lancer de palmes »), dessinée à la
main en pixel art : chausson bleu foncé à gauche, voilure bleue qui s'évase
vers la droite, nervures claires, contour sombre. → assets/vfx/txomin/proj_palme.png
"""
import os

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
W, H = 28, 16
OUT = (36, 30, 46, 255)
FOOT = (30, 70, 140, 255)
FOOT_HI = (60, 110, 190, 255)
BLADE = (52, 140, 220, 255)
BLADE_HI = (130, 200, 245, 255)
RIB = (200, 236, 255, 255)


def inside(x, y):
    """Silhouette : chausson (x < 9, demi-hauteur 3) puis voilure qui s'élargit."""
    cy = H / 2 - 0.5
    half = 3.0 if x < 9 else 3.0 + (x - 9) * 0.3
    if x >= W - 3 and abs(y - cy) < 1.5:
        return False       # encoche au bout de la voilure
    return abs(y - cy) <= half and 1 <= x < W - 1


def main():
    im = Image.new("RGBA", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            if inside(x, y):
                px[x, y] = FOOT if x < 9 else BLADE
    # reflets et nervures
    for x in range(2, 8):
        px[x, int(H / 2) - 2] = FOOT_HI
    for x in range(10, W - 2):
        cy = H / 2 - 0.5
        half = 3.0 + (x - 9) * 0.3
        px[x, int(cy - half) + 1] = BLADE_HI
        if x % 1 == 0 and x > 11:
            px[x, int(cy - half / 2)] = RIB
            px[x, int(cy + half / 2) + 1] = RIB
    # contour
    a = im.copy().load()
    for y in range(H):
        for x in range(W):
            if a[x, y][3] == 0 and any(0 <= x + dx < W and 0 <= y + dy < H and a[x + dx, y + dy][3]
                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = OUT
    # ouverture du chausson
    px[1, int(H / 2) - 1] = OUT
    px[1, int(H / 2)] = OUT
    d = os.path.join(ROOT, "assets", "vfx", "txomin")
    im.save(os.path.join(d, "proj_palme.png"))
    print(os.path.join(d, "proj_palme.png"))


if __name__ == "__main__":
    main()
