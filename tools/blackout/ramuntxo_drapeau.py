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
CENTRE, TAILLE, ANGLE = (248, 85), (32, 20), 13.5   # sur le bandeau, incliné comme lui
SUR = 8                               # suréchantillonnage du dessin


def drapeau():
    """Dessiné et tourné en ×SUR, puis réduit d'un coup : bords lisses, trait régulier de 2 px comme le
    contour du perso, croix coupées net à l'intérieur du cadre arrondi."""
    w, h = TAILLE[0] * SUR, TAILLE[1] * SUR
    trait, rayon = 2 * SUR, 3 * SUR
    fond = Image.new("RGBA", (w, h), ROUGE + (255,))
    d = ImageDraw.Draw(fond)
    d.line((0, 0, w, h), fill=VERT, width=int(SUR * 2.4))
    d.line((0, h, w, 0), fill=VERT, width=int(SUR * 2.4))
    d.line((w // 2, 0, w // 2, h), fill=BLANC, width=int(SUR * 2.2))
    d.line((0, h // 2, w, h // 2), fill=BLANC, width=int(SUR * 2.2))
    masque = Image.new("L", (w, h), 0)
    ImageDraw.Draw(masque).rounded_rectangle((0, 0, w - 1, h - 1), radius=rayon, fill=255)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im.paste(fond, (0, 0), masque)
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w - 1, h - 1), radius=rayon, outline=CONTOUR + (255,), width=trait)
    im = im.rotate(ANGLE, resample=Image.BICUBIC, expand=True)
    return im.resize((im.width // SUR, im.height // SUR), Image.LANCZOS)


def main():
    im = Image.open(SRC).convert("RGBA")
    ImageDraw.Draw(im).rectangle(ECUSSON, fill=BLANC_TABLIER)
    f = drapeau()
    im.alpha_composite(f, (CENTRE[0] - f.width // 2, CENTRE[1] - f.height // 2))
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    im.save(DST)


if __name__ == "__main__":
    main()
