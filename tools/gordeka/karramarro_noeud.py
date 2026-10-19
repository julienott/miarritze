#!/usr/bin/env python3
"""Karramarro (2026-10-20, Julien : « le foulard du 2 a un nœud bizarre ») : pixelforge ne corrige pas le
nœud par retouche. On repart du foulard n° 2 (tools/rd/out/karramarro/gk2d/foulard/image_00.png), on
efface le pendant et on dessine un petit nœud rond propre avec deux pointes, au trait du perso.

  karramarro_noeud.py   → assets/gordeka/persos/karramarro/modele.png
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "tools", "rd", "out", "karramarro", "gk2d", "foulard", "image_00.png")
DST = os.path.join(ROOT, "assets", "gordeka", "persos", "karramarro", "modele.png")

ZONE = (318, 336, 380, 424)          # zone nettoyée autour de l'ancien nœud (px de l'image 512)
NOEUD = (337, 349)                   # coin du foulard, où l'on pose le nouveau nœud
CONTOUR, BLANC, OMBRE = (0, 12, 64, 255), (255, 255, 255, 255), (196, 210, 230, 255)
SUR = 8


def hors_tissu(x, y):
    """Sous le bord bas-droit du foulard ou à droite de son bord droit (relevés sur l'image)."""
    bas = 373.0 - 0.9 * (x - 308.0)
    droit = 352.0 - 0.55 * (y - 320.0)
    return y > bas + 5.0 or x > droit + 5.0


SANS_NOEUD = True                    # Julien : nœud bizarre ; une pointe de bandana propre se lit mieux


def main():
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    x0, y0, x1, y1 = ZONE
    for y in range(y0, y1):
        for x in range(x0, x1):
            if hors_tissu(x, y):
                px[x, y] = (0, 0, 0, 0)       # l'ancien pendant et sa boucle disparaissent
    if SANS_NOEUD:
        # Raccord du coin : un court trait entre la fin du bord droit et celle du bord bas.
        k = Image.new("RGBA", ((x1 - x0) * SUR, (y1 - y0) * SUR), (0, 0, 0, 0))
        ImageDraw.Draw(k).line([((329 - x0) * SUR, (354 - y0) * SUR), ((343 - x0) * SUR, (339 - y0) * SUR)],
                               fill=CONTOUR, width=int(4.6 * SUR))
        im.alpha_composite(k.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
        im.save(DST)
        return
    # Nœud rond et deux pointes, dessinés en ×SUR puis réduits (trait du perso, ~4,5 px).
    c = 44
    t = Image.new("RGBA", (c * SUR, c * SUR), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    m, s = c * SUR // 2, SUR
    tr = int(4.2 * s)
    for pts in (((m - 4 * s, m + 2 * s), (m - 7 * s, m + 19 * s), (m + 3 * s, m + 8 * s)),
                ((m + 4 * s, m + 2 * s), (m + 12 * s, m + 17 * s), (m - 1 * s, m + 9 * s))):
        d.polygon(pts, fill=BLANC)
        d.line(list(pts) + [pts[0]], fill=CONTOUR, width=tr, joint="curve")
    r = 8 * s
    d.ellipse((m - r, m - r, m + r, m + r), fill=BLANC, outline=CONTOUR, width=tr)
    d.arc((m - r + tr, m - r + tr, m + r - tr, m + r - tr), 30, 150, fill=OMBRE, width=int(1.8 * s))
    t = t.resize((c, c), Image.LANCZOS)
    im.alpha_composite(t, (NOEUD[0] - c // 2, NOEUD[1] - c // 2))
    im.save(DST)


if __name__ == "__main__":
    main()
