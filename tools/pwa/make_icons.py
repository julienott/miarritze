#!/usr/bin/env python3
"""Icônes PWA de Miarritze Borroka.

Compose une icône carrée à partir de icon_txapela.png (béret basque) sur
fond rouge brand, avec « MB » en Press Start 2P. Décline en 192, 512, 180
(apple-touch-icon), 512 maskable (avec safe area 10 %) et 32 (favicon).

Usage : make_icons.py
Sortie : web/pwa/icon-<size>.png
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "web", "pwa")
TXAPELA = os.path.join(ROOT, "assets", "ui", "icon_txapela.png")
FONT_TTF = os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf")

BG = (206, 52, 52, 255)        # rouge brand
GOLD = (244, 198, 62, 255)
LINEN = (247, 241, 227, 255)
OUTLINE = (58, 38, 52, 255)


def compose(size: int, maskable: bool = False) -> Image.Image:
    """Icône carrée size×size. En mode maskable on garde une safe area de 10 %."""
    img = Image.new("RGBA", (size, size), BG)
    draw = ImageDraw.Draw(img)
    # Bordure extérieure (hors zone maskable) : juste un contour sombre.
    pad = int(size * 0.1) if maskable else max(size // 32, 2)
    draw.rectangle((pad, pad, size - 1 - pad, size - 1 - pad), outline=OUTLINE,
                   width=max(size // 64, 2))
    # Txapela agrandi (nearest) et centré-haut.
    txapela = Image.open(TXAPELA).convert("RGBA")
    tx_target = int(size * 0.52)
    scale = max(tx_target // txapela.width, 1)
    txapela = txapela.resize((txapela.width * scale, txapela.height * scale), Image.NEAREST)
    tx_x = (size - txapela.width) // 2
    tx_y = int(size * 0.14)
    img.alpha_composite(txapela, (tx_x, tx_y))
    # « MB » en bas, pixel-net. On passe par anchor="mm" (centre géométrique
    # du glyphe) — Press Start 2P a des avances latérales trompeuses, textbbox
    # décentre d'un bon paquet de pixels sans ça.
    font_size = int(size * 0.34)
    font = ImageFont.truetype(FONT_TTF, font_size)
    text = "MB"
    cx = size // 2
    cy = size - int(size * 0.18) - font_size // 2
    shadow = max(size // 128, 1)
    draw.text((cx + shadow, cy + shadow), text, font=font, fill=OUTLINE, anchor="mm")
    draw.text((cx, cy), text, font=font, fill=LINEN, anchor="mm")
    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for sz in (32, 180, 192, 512):
        compose(sz).save(os.path.join(OUT, f"icon-{sz}.png"))
        print(f"icon-{sz}.png")
    compose(512, maskable=True).save(os.path.join(OUT, "icon-maskable-512.png"))
    print("icon-maskable-512.png")


if __name__ == "__main__":
    main()
