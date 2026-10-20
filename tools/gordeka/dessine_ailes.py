#!/usr/bin/env python3
"""Petite aile blanche de fantôme, dessinée par code (TEMPORAIRE, 2026-10-20 : en attendant les vraies
animations fantôme des persos qui n'en ont pas ; Julien : « ajoute peut-être des ailes blanches »).

  dessine_ailes.py   → assets/gordeka/communs/aile_fantome.png (+ .json : point d'attache)

Style du jeu : contour bleu marine épais (#1d2230), plumes blanches, ombre gris clair. Une seule aile,
vue de profil, déployée vers l'arrière et le haut ; le jeu la pose dans le dos du perso (deux fois,
l'aile du fond plus petite et grisée) et la fait battre. Dessin 4× plus grand puis réduit (lissage).
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "gordeka", "communs"))
W, H = 160, 128          # taille finale (px)
SS = 4                   # suréchantillonnage
INK = (29, 34, 48, 255)
WHITE = (255, 255, 255, 255)
SHADE = (205, 214, 226, 255)
LINE = (168, 180, 198, 255)
ROOT = (128, 92)         # attache (épaule), en px finaux
STROKE = 5               # contour (px finaux)


def s(p):
    return (p[0] * SS, p[1] * SS)


def bezier(a, c, b, n=40):
    return [((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
             (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]) for t in (i / n for i in range(n + 1))]


def feather(d, cx, cy, length, width, angle, fill):
    """Plume : goutte allongée de centre (cx, cy), orientée selon angle (degrés)."""
    pts = []
    for i in range(48):
        t = i / 48 * 2 * math.pi
        # bout arrondi d'un côté, plus pointu de l'autre
        r = 1.0 - 0.25 * max(0.0, math.cos(t))
        x, y = math.cos(t) * length / 2 * r, math.sin(t) * width / 2
        a = math.radians(angle)
        pts.append(s((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a))))
    d.polygon(pts, fill=fill)


def main():
    os.makedirs(OUT, exist_ok=True)
    mask = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(mask)
    # Corps de l'aile : bord d'attaque arrondi de l'épaule vers la pointe, en haut à gauche.
    top = bezier(ROOT, (112, 18), (22, 14))
    low = bezier((22, 14), (40, 70), ROOT)
    d.polygon([s(p) for p in top + low], fill=255)
    # Plumes du bas : trois rangées qui débordent en festons.
    plumes = [(40, 46, 52, 22, 128), (58, 62, 54, 22, 118), (80, 74, 50, 21, 106), (102, 84, 40, 19, 96)]
    for cx, cy, ln, wd, ang in plumes:
        feather(d, cx, cy, ln, wd, ang, 255)
    feather(d, 30, 26, 40, 22, 145, 255)
    # Contour : masque épaissi.
    grown = mask.filter(ImageFilter.MaxFilter(2 * STROKE * SS + 1))
    img = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    img.paste(Image.new("RGBA", mask.size, INK), (0, 0), grown)
    img.paste(Image.new("RGBA", mask.size, WHITE), (0, 0), mask)
    # Ombre gris clair : le bas de l'aile (sous la courbe du milieu), dans le dessin.
    sh = Image.new("L", mask.size, 0)
    ds = ImageDraw.Draw(sh)
    mid = bezier((10, 40), (60, 48), (140, 110))
    ds.polygon([s(p) for p in mid + [(160, 128), (0, 128)]], fill=255)
    sh = ImageChops.multiply(sh, mask.filter(ImageFilter.MinFilter(2 * SS + 1)))
    img.paste(Image.new("RGBA", mask.size, SHADE), (0, 0), sh)
    # Séparations des plumes, traits fins.
    dl = ImageDraw.Draw(img)
    for a, c, b in [((44, 52), (56, 50), (70, 54)), ((64, 68), (76, 66), (90, 70)), ((86, 80), (96, 78), (108, 82)),
                    ((40, 26), (72, 30), (104, 54))]:
        dl.line([s(p) for p in bezier(a, c, b)], fill=LINE, width=2 * SS, joint="curve")
    img = img.resize((W, H), Image.LANCZOS)
    img.save(os.path.join(OUT, "aile_fantome.png"), optimize=True)
    json.dump({"_doc": "Point d'attache de l'aile (épaule), en px de l'image ; dessine_ailes.py.",
               "attache": list(ROOT), "size": [W, H]},
              open(os.path.join(OUT, "aile_fantome.json"), "w"), indent=1)
    print("aile :", os.path.join(OUT, "aile_fantome.png"))


if __name__ == "__main__":
    main()
