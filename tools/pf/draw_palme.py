#!/usr/bin/env python3
"""Palmes de sauveteur de Txomin, dessinées à la main en pixel art d'après la
référence de Julien (palmes courtes de bodyboard / sauvetage, rouges à bout
jaune) : vue de dessus, sangle de talon ouverte, chausson visible au milieu,
voilure en trapèze qui s'évase, bout jaune ondulé.

  fin(L, w0, w1)  → une palme couchée (talon à gauche, bout à droite)
  projectile      → assets/vfx/txomin/proj_palme.png (Lancer de palmes)
  ceinture        → tools/rd/out/txomin/palmes_ceinture.png : la paire pendue,
                    sangles en haut, posée sur le bassin par from_mannequin.py
"""
import os

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = (40, 22, 30, 255)
RED = (214, 46, 40, 255)
RED_HI = (240, 96, 80, 255)
RED_LO = (160, 28, 34, 255)
YEL = (250, 206, 48, 255)
YEL_LO = (214, 160, 30, 255)


def fin(L, w0, w1):
    """Palme couchée de longueur L : talon de demi-largeur w0, bout de demi-largeur w1."""
    strap = max(3, L // 6)
    tip = max(3, L // 5)
    H = int(2 * w1) + 4
    im = Image.new("RGBA", (L + 2, H))
    px = im.load()
    cy = H / 2 - 0.5
    body = L - strap

    def half(x):
        return w0 + (w1 - w0) * (x - strap) / max(1, body - 1)

    for x in range(strap, L):
        h = half(x)
        for y in range(H):
            d = y - cy
            if abs(d) > h:
                continue
            if x == L - 1 and (abs(d) < 1.2 or abs(d) > h - 1.2):
                continue                        # bout ondulé : encoche + coins arrondis
            if x >= L - tip:
                px[x, y] = YEL_LO if abs(d) > h - 1.2 else YEL
            elif (x - strap) < body * 0.6 and abs(d) < w0 * 0.85 and \
                    ((x - strap) < body * 0.6 - w0 * 0.85 or
                     (x - strap - (body * 0.6 - w0 * 0.85)) ** 2 + d ** 2 < (w0 * 0.85) ** 2):
                # chausson : poche arrondie, un ton plus sombre, bord éclairé en haut
                px[x, y] = RED_HI if d < -w0 * 0.85 + 1 else RED_LO
            elif abs(d) > h - 1.2:
                px[x, y] = RED_LO                       # rebords de la voilure
            elif d < -h + 1.5:
                px[x, y] = RED_HI
            else:
                px[x, y] = RED
    for y in range(H):                          # mélange rouge/jaune irrégulier
        x = L - tip
        if px[x, y][3] and y % 3 == 1:
            px[x - 1, y] = YEL
    for y in range(int(cy - w0), int(cy + w0) + 2):     # sangle de talon (boucle ouverte)
        px[1, y] = RED_LO
    for x in range(1, strap + 1):
        px[x, int(cy - w0)] = RED_LO
        px[x, int(cy + w0) + 1] = RED_LO
    a = im.copy().load()
    for y in range(H):
        for x in range(im.width):
            if a[x, y][3] == 0 and any(0 <= x + dx < im.width and 0 <= y + dy < H and a[x + dx, y + dy][3]
                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = OUT
    return im.crop(im.getbbox())


def belt_pair():
    """Paire pendue à la ceinture, attachée par les sangles : les deux boucles se
    superposent en un même point d'accroche (en haut au milieu), palmes un peu
    écartées en éventail, pointes en bas. Point d'accroche : GRIP."""
    f = fin(28, 4.0, 10.0).rotate(-90, expand=True)      # sangle en haut
    W, H = 48, f.height + 8
    out = Image.new("RGBA", (W, H))
    for ang in (-14, 12):                                 # palme du fond puis de devant
        c = Image.new("RGBA", (W, H))
        c.alpha_composite(f, (W // 2 - f.width // 2, 2))
        out.alpha_composite(c.rotate(ang, Image.NEAREST, center=(W // 2, 3)))
    return out.crop(out.getbbox())


def main():
    d = os.path.join(ROOT, "assets", "vfx", "txomin")
    fin(18, 3.0, 8.0).save(os.path.join(d, "proj_palme.png"))
    p = os.path.join(ROOT, "tools", "rd", "out", "txomin", "palmes_ceinture.png")
    belt_pair().save(p)
    print(os.path.join(d, "proj_palme.png"), p)


if __name__ == "__main__":
    main()
