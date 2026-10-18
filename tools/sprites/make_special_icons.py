#!/usr/bin/env python3
"""Icône du bouton « spécial » de la manette virtuelle, propre à chaque perso :
l'objet de son coup spécial (projectile déjà dessiné), tenu dans 20×20 px
(agrandi ×2 s'il est tout petit, jamais réduit en dessous de ×1 sauf trop
grand). Amaia n'a pas de projectile : sa makila est dessinée ici.
→ assets/ui/special/<id>.png + planche ×4 tests/out/special_icons.png
Usage : make_special_icons.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "special")
MAX = 20
MAX_X2 = 24          # un petit objet (pelote) agrandi ×2 peut aller jusque-là
OUTLINE = (58, 38, 52, 255)

# perso -> projectile (assets/vfx/<id>/proj_<nom>.png), ou None = dessiné ici
SOURCES = {
    "louis": "espadrille", "maia": "rouleau", "itsaso": "perle", "kaio": "fiente",
    "karramarro": "bulles", "mattin": "pierre", "patxi": "sardines", "peio": "ballon",
    "ramuntxo": "gateau", "txomin": "palme", "itsasargi": "faisceau",
    "amaia": None, "xabi": None,
}


def makila() -> Image.Image:
    """Bâton de marche basque en diagonale : fût brun, pommeau et virole argentés."""
    im = Image.new("RGBA", (18, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([(3, 15), (14, 4)], fill=OUTLINE, width=4)
    d.line([(3, 15), (14, 4)], fill=(150, 96, 52, 255), width=2)
    d.line([(4, 13), (13, 4)], fill=(196, 132, 74, 255), width=1)
    d.ellipse([11, 1, 17, 7], fill=OUTLINE)
    d.ellipse([12, 2, 16, 6], fill=(206, 214, 222, 255))   # argent : lisible sur le bouton doré
    d.point((13, 3), fill=(255, 255, 255, 255))
    d.rectangle([1, 15, 4, 17], fill=OUTLINE)
    d.rectangle([2, 15, 3, 16], fill=(206, 214, 222, 255))
    return im


def pelote() -> Image.Image:
    """Pelote basque : balle de cuir blanc, deux coutures en arc (le projectile
    du jeu porte une traînée de vitesse qui grossit mal)."""
    im = Image.new("RGBA", (17, 17), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, 16, 16], fill=OUTLINE)
    d.ellipse([1, 1, 15, 15], fill=(236, 230, 214, 255))
    d.ellipse([3, 2, 9, 7], fill=(255, 252, 244, 255))
    d.pieslice([9, 10, 15, 15], 0, 360, fill=(206, 196, 178, 255))
    d.arc([-6, 3, 7, 14], -60, 60, fill=(196, 62, 52, 255))
    d.arc([9, 2, 22, 13], 120, 240, fill=(196, 62, 52, 255))
    return im


def fit(im: Image.Image) -> Image.Image:
    im = im.crop(im.getbbox())
    if max(im.size) * 2 <= MAX_X2:
        im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
    elif max(im.size) > MAX + 4:
        # Trop grand (faisceau) : on garde le cœur plutôt que de réduire.
        w, h = min(im.width, MAX), min(im.height, MAX)
        x, y = (im.width - w) // 2, (im.height - h) // 2
        im = im.crop((x, y, x + w, y + h))
    elif max(im.size) > MAX:
        k = MAX / max(im.size)
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.NEAREST)
    return im


def outline(im: Image.Image) -> Image.Image:
    """Contour sombre de 1 px autour de l'objet : lisible sur le bouton doré."""
    pad = Image.new("RGBA", (im.width + 2, im.height + 2), (0, 0, 0, 0))
    pad.alpha_composite(im, (1, 1))
    a = pad.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    ring = Image.new("RGBA", pad.size, (0, 0, 0, 0))
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = Image.new("L", pad.size, 0)
        sh.paste(a, (dx, dy))
        ring.paste(OUTLINE, mask=sh)
    ring.alpha_composite(pad)
    return ring


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for fid, proj in SOURCES.items():
        if proj is None:
            im = {"amaia": makila, "xabi": pelote}[fid]()
        else:
            im = Image.open(os.path.join(ROOT, "assets", "vfx", fid, f"proj_{proj}.png")).convert("RGBA")
        icon = outline(fit(im))
        icon.save(os.path.join(OUT, f"{fid}.png"))
        made.append((fid, icon))
    # Planche ×4 sur la couleur du bouton spécial.
    k, cw = 4, 32 * 4
    sheet = Image.new("RGBA", (cw * len(made), cw + 14), (40, 30, 46, 255))
    d = ImageDraw.Draw(sheet)
    for i, (fid, icon) in enumerate(made):
        disc = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        ImageDraw.Draw(disc).ellipse([1, 1, 30, 30], fill=(244, 198, 62, 255), outline=OUTLINE)
        disc.alpha_composite(icon, ((32 - icon.width) // 2, (32 - icon.height) // 2))
        sheet.alpha_composite(disc.resize((cw, cw), Image.NEAREST), (i * cw, 14))
        d.text((i * cw + 4, 2), fid, fill="white")
    os.makedirs(os.path.join(ROOT, "tests", "out"), exist_ok=True)
    p = os.path.join(ROOT, "tests", "out", "special_icons.png")
    sheet.save(p)
    print(p)


if __name__ == "__main__":
    main()
