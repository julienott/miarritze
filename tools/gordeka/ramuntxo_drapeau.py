#!/usr/bin/env python3
"""Ramuntxo (2026-10-20, demande de Julien) : la retouche pixelforge a mis l'ikurriña sur le tablier au
lieu de la toque. On repart de la retouche n° 1 (tools/rd/out/ramuntxo/gk2d/retouche/image_00.png),
on efface l'écusson du tablier et on colle un petit drapeau basque propre sur le bandeau de la toque.

  ramuntxo_drapeau.py   → assets/gordeka/persos/ramuntxo/modele.png
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "tools", "rd", "out", "ramuntxo", "gk2d", "retouche", "image_00.png")
DST = os.path.join(ROOT, "assets", "gordeka", "persos", "ramuntxo", "modele.png")

ECUSSON = (244, 338, 309, 407)        # boîte de l'écusson sur le tablier (px de l'image 512)
BLANC_TABLIER = (255, 255, 255, 255)
CONTOUR = (0, 12, 64)                 # bleu marine du trait
ROUGE, VERT, BLANC = (213, 43, 30), (0, 155, 72), (255, 255, 255)
CENTRE, TAILLE, ANGLE = (248, 94), (32, 20), 13.5   # sur le bandeau, incliné comme lui
SUR = 8                               # suréchantillonnage du dessin


def drapeau():
    w, h = TAILLE[0] * SUR, TAILLE[1] * SUR
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    t = SUR * 1.6                      # épaisseur des croix
    d.rectangle((0, 0, w - 1, h - 1), fill=ROUGE)
    d.line((0, 0, w, h), fill=VERT, width=int(t * 1.2))
    d.line((0, h, w, 0), fill=VERT, width=int(t * 1.2))
    d.line((w // 2, 0, w // 2, h), fill=BLANC, width=int(t))
    d.line((0, h // 2, w, h // 2), fill=BLANC, width=int(t))
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=SUR, outline=CONTOUR, width=int(SUR * 1.3))
    im = im.resize(TAILLE, Image.LANCZOS)
    return im.rotate(ANGLE, resample=Image.BICUBIC, expand=True)


def main():
    im = Image.open(SRC).convert("RGBA")
    ImageDraw.Draw(im).rectangle(ECUSSON, fill=BLANC_TABLIER)
    f = drapeau()
    im.alpha_composite(f, (CENTRE[0] - f.width // 2, CENTRE[1] - f.height // 2))
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    im.save(DST)


if __name__ == "__main__":
    main()
