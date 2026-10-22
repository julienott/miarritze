"""Décor provisoire de la carte Plage (tools/blackout/make_plage.py) : images simples dessinées ici, dans
le style du jeu (aplats, contour bleu marine épais, vue 3/4 de face : dessus clair, face avant plus sombre,
haut qui dépasse vers le haut), et l'index du décor (assets/maps/plage/decor/index.json) lu par BkDecor.

Chaque objet touche le bas de son image sur toute sa largeur au sol : BkDecor en déduit l'empreinte qui
bloque (passage, vue) et laisse le haut passer devant les persos qui sont derrière (masquage). Les images
communes du port qui conviennent sont reprises telles quelles (res://assets/blackout/decor/…). Les
cachettes ont une image « ouverte » (porte, couvercle ou rideau ouvert sur du noir).

Pillow requis : .venv/bin/python tools/blackout/make_plage.py
"""
import json
import math
import os

from PIL import Image, ImageDraw

PX = 128                      # px d'image par case (le jeu dessine 64 px par case : images × 2)
INK = (29, 34, 48, 255)
LW = 6                        # contour
WHITE = (246, 243, 236, 255)
RED = (205, 48, 52, 255)
RED_D = (150, 30, 38, 255)
GREEN = (36, 120, 78, 255)
GREEN_D = (22, 84, 54, 255)
BLUE = (52, 120, 200, 255)
BLUE_D = (34, 84, 150, 255)
TURQ = (64, 186, 196, 255)
TURQ_D = (38, 132, 150, 255)
ORANGE = (232, 140, 44, 255)
ORANGE_D = (178, 96, 24, 255)
YELLOW = (244, 200, 60, 255)
SAND = (232, 206, 150, 255)
SAND_D = (204, 174, 116, 255)
ROCK = (186, 160, 118, 255)
ROCK_D = (138, 114, 82, 255)
ROCK_T = (208, 186, 146, 255)
CAVE = (86, 100, 128, 255)
CAVE_D = (58, 68, 92, 255)
CAVE_T = (112, 128, 156, 255)
WOOD = (172, 118, 70, 255)
WOOD_D = (124, 80, 44, 255)
WOOD_T = (204, 152, 98, 255)
GREY = (150, 156, 166, 255)
GREY_D = (104, 110, 122, 255)
DARK = (34, 26, 30, 255)
SEAWEED = (76, 140, 70, 255)


def canvas(w, h):
    img = Image.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def box(d, x0, y0, x1, y1, top, front, depth, r=10):
    """Bloc vu en 3/4 : dessus de y0 à y1 - depth, face avant jusqu'à y1 (bas de l'image = sol)."""
    d.rounded_rectangle([x0, y0, x1, y1], r, fill=front, outline=INK, width=LW)
    d.rounded_rectangle([x0, y0, x1, y1 - depth], r, fill=top, outline=INK, width=LW)


def rock(d, x0, y0, x1, y1, top, front, seed=0, weed=True):
    """Rocher arrondi : grosse forme molle, dessus clair, face sombre, algues au pied."""
    w, h = x1 - x0, y1 - y0
    pts = []
    for k in range(18):
        a = math.pi * 2 * k / 18
        j = 0.86 + 0.14 * math.sin(seed * 1.7 + k * 2.3)
        pts.append((x0 + w / 2 + math.cos(a) * w / 2 * j, y0 + h / 2 + math.sin(a) * h / 2 * (j if math.sin(a) < 0 else 1)))
    # Bas plat : le rocher repose sur le sol.
    pts = [(px, min(py, y1 - 2)) for (px, py) in pts]
    d.polygon(pts, fill=front, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=LW, joint="curve")
    tp = [(px, y0 + (py - y0) * 0.62) for (px, py) in pts]
    d.polygon(tp, fill=top)
    d.line(tp + [tp[0]], fill=INK, width=max(3, LW - 2), joint="curve")
    d.arc([x0 + w * 0.25, y0 + h * 0.12, x0 + w * 0.55, y0 + h * 0.35], 200, 300, fill=(255, 255, 255, 160), width=4)
    if weed:
        for k in range(3):
            cx = x0 + w * (0.2 + 0.3 * k)
            d.ellipse([cx - 12, y1 - 16, cx + 12, y1 - 2], fill=SEAWEED, outline=INK, width=3)


def stripes_rect(d, x0, y0, x1, y1, c1, c2, n):
    sw = (x1 - x0) / n
    for k in range(n):
        d.rectangle([x0 + k * sw, y0, x0 + (k + 1) * sw, y1], fill=c1 if k % 2 == 0 else c2)


# ---------------------------------------------------------------- objets

def cabine(w, h, c1, c2, door, roof, opened=False, flat_roof=False):
    img, d = canvas(w * PX, h * PX)
    W_, H_ = img.size
    body_top = int(H_ * (0.42 if not flat_roof else 0.3))
    x0, x1 = 12, W_ - 12
    # Corps rayé (face avant), puis le toit.
    stripes_rect(d, x0, body_top, x1, H_ - 4, c1, c2, 5 if c1 != c2 else 1)
    d.rectangle([x0, body_top, x1, H_ - 4], outline=INK, width=LW)
    dw = (x1 - x0) * 0.36
    dx0 = (W_ - dw) / 2
    if opened:
        d.rectangle([dx0, body_top + 34, dx0 + dw, H_ - 6], fill=DARK, outline=INK, width=LW - 2)
        d.polygon([(dx0, body_top + 34), (dx0 - dw * 0.7, body_top + 46), (dx0 - dw * 0.7, H_ - 2), (dx0, H_ - 6)],
                  fill=door, outline=INK)
    else:
        d.rectangle([dx0, body_top + 34, dx0 + dw, H_ - 6], fill=door, outline=INK, width=LW - 2)
        d.ellipse([dx0 + dw - 16, (body_top + H_) / 2, dx0 + dw - 6, (body_top + H_) / 2 + 10], fill=INK)
    if flat_roof:
        box(d, x0 - 8, body_top - 40, x1 + 8, body_top + 8, WHITE, roof, 18, 6)
    else:
        d.polygon([(x0 - 10, body_top + 6), (W_ / 2, 8), (x1 + 10, body_top + 6)], fill=roof, outline=INK)
        d.line([(x0 - 10, body_top + 6), (W_ / 2, 8), (x1 + 10, body_top + 6), (x0 - 10, body_top + 6)], fill=INK,
               width=LW, joint="curve")
        d.line([(W_ / 2, 14), (W_ / 2, 30)], fill=WHITE, width=5)
    return img


def parasol(c1, c2):
    img, d = canvas(PX, 2.1 * PX)
    W_, H_ = img.size
    d.ellipse([W_ / 2 - 26, H_ - 22, W_ / 2 + 26, H_ - 2], fill=SAND_D, outline=INK, width=4)
    d.rectangle([W_ / 2 - 4, 70, W_ / 2 + 4, H_ - 12], fill=WOOD_D, outline=INK, width=2)
    cx, cy, rx, ry = W_ / 2, 74, W_ / 2 - 4, 54
    for k in range(8):
        a0, a1 = 180 + k * 22.5, 180 + (k + 1) * 22.5
        d.pieslice([cx - rx, cy - ry, cx + rx, cy + ry], a0, a1, fill=c1 if k % 2 == 0 else c2)
    d.chord([cx - rx, cy - ry * 0.35, cx + rx, cy + ry * 0.35], 0, 180, fill=c1)
    d.arc([cx - rx, cy - ry, cx + rx, cy + ry], 180, 360, fill=INK, width=LW)
    d.line([(cx - rx, cy), (cx + rx, cy)], fill=INK, width=LW)
    d.ellipse([cx - 7, cy - ry - 6, cx + 7, cy - ry + 8], fill=WHITE, outline=INK, width=3)
    return img


def transat():
    """Transat vu de 3/4 : toile rayée tendue sur un cadre en bois, dossier relevé à droite."""
    img, d = canvas(2 * PX, 1.2 * PX)
    W_, H_ = img.size
    # Pieds et cadre.
    for x in (30, W_ * 0.55, W_ - 40):
        d.rectangle([x - 4, H_ - 30, x + 4, H_ - 4], fill=WOOD_D, outline=INK, width=2)
    seat = [(16, H_ - 44), (W_ * 0.62, H_ - 44), (W_ * 0.62, H_ - 24), (16, H_ - 24)]
    back = [(W_ * 0.6, H_ - 44), (W_ - 46, 14), (W_ - 12, 14), (W_ * 0.66, H_ - 24)]
    for poly, c in ((seat, GREEN), (back, GREEN)):
        d.polygon(poly, fill=c)
    for k in range(6):
        x0 = 16 + k * (W_ * 0.62 - 16) / 6
        if k % 2:
            d.rectangle([x0, H_ - 44, x0 + (W_ * 0.62 - 16) / 6, H_ - 24], fill=WHITE)
    d.line(seat + [seat[0]], fill=INK, width=LW, joint="curve")
    d.line(back + [back[0]], fill=INK, width=LW, joint="curve")
    d.line([(W_ * 0.7, H_ - 30), (W_ - 30, 26)], fill=WHITE, width=10)
    return img


def douche():
    img, d = canvas(PX, 2.2 * PX)
    W_, H_ = img.size
    box(d, 16, H_ - 40, W_ - 16, H_ - 4, WOOD_T, WOOD_D, 12, 4)
    d.rectangle([W_ / 2 - 7, 30, W_ / 2 + 7, H_ - 30], fill=BLUE, outline=INK, width=4)
    d.rectangle([W_ / 2 - 7, 30, W_ / 2 + 34, 44], fill=BLUE, outline=INK, width=4)
    d.ellipse([W_ / 2 + 22, 38, W_ / 2 + 48, 56], fill=GREY, outline=INK, width=4)
    for k in range(4):
        d.line([(W_ / 2 + 26 + k * 6, 64 + k * 9), (W_ / 2 + 26 + k * 6, 74 + k * 9)], fill=TURQ, width=4)
    return img


def paravent():
    img, d = canvas(2 * PX, 1.5 * PX)
    W_, H_ = img.size
    cols = [YELLOW, ORANGE, BLUE, WHITE]
    top, bot = 26, H_ - 6
    n = 6
    sw = (W_ - 24) / n
    for k in range(n):
        d.rectangle([12 + k * sw, top + (k % 2) * 6, 12 + (k + 1) * sw, bot], fill=cols[k % 4])
    d.rectangle([12, top, W_ - 12, bot], outline=INK, width=LW)
    for k in range(n + 1):
        x = 12 + k * sw
        d.rectangle([x - 5, top - 14, x + 5, bot], fill=WOOD_D, outline=INK, width=3)
    return img


def planches_surf():
    img, d = canvas(PX, 2 * PX)
    W_, H_ = img.size
    cols = [YELLOW, TURQ, (240, 120, 110, 255), WHITE]
    box(d, 6, H_ - 50, W_ - 6, H_ - 4, WOOD_T, WOOD_D, 18, 4)
    for k in range(4):
        x = 14 + k * 26
        d.rounded_rectangle([x, 20 + (k % 2) * 14, x + 24, H_ - 30], 12, fill=cols[k], outline=INK, width=4)
        d.line([(x + 12, 34 + (k % 2) * 14), (x + 12, H_ - 40)], fill=(0, 0, 0, 60), width=2)
    return img


def kiosque():
    img, d = canvas(2 * PX, 3.4 * PX)
    W_, H_ = img.size
    body_top = int(H_ * 0.52)
    box(d, 20, body_top, W_ - 20, H_ - 4, (250, 220, 230, 255), (232, 160, 186, 255), int((H_ - body_top) * 0.7), 18)
    d.rounded_rectangle([60, body_top + 50, W_ - 60, body_top + 100], 10, fill=DARK, outline=INK, width=4)
    d.rectangle([52, body_top + 100, W_ - 52, body_top + 118], fill=WHITE, outline=INK, width=4)
    # Auvent rayé.
    aw_top, aw_bot = body_top - 34, body_top + 26
    n = 8
    sw = (W_ - 20) / n
    for k in range(n):
        d.pieslice([10 + k * sw, aw_bot - 22, 10 + (k + 1) * sw, aw_bot + 22], 0, 180, fill=RED if k % 2 == 0 else WHITE,
                   outline=INK, width=3)
        d.rectangle([10 + k * sw, aw_top, 10 + (k + 1) * sw, aw_bot], fill=RED if k % 2 == 0 else WHITE)
    d.rectangle([10, aw_top, W_ - 10, aw_bot], outline=INK, width=LW)
    # Cornet géant sur le toit (repère).
    cx = W_ / 2
    d.polygon([(cx - 40, aw_top - 50), (cx + 40, aw_top - 50), (cx, aw_top + 6)], fill=WOOD_T, outline=INK)
    d.line([(cx - 40, aw_top - 50), (cx + 40, aw_top - 50), (cx, aw_top + 6), (cx - 40, aw_top - 50)], fill=INK, width=LW)
    d.ellipse([cx - 46, aw_top - 120, cx + 46, aw_top - 36], fill=(250, 200, 220, 255), outline=INK, width=LW)
    d.ellipse([cx - 34, aw_top - 170, cx + 34, aw_top - 100], fill=(250, 246, 230, 255), outline=INK, width=LW)
    d.ellipse([cx - 8, aw_top - 186, cx + 8, aw_top - 168], fill=RED, outline=INK, width=3)
    return img


def chateau_sable():
    img, d = canvas(2 * PX, 2.6 * PX)
    W_, H_ = img.size
    d.ellipse([4, H_ - 90, W_ - 4, H_ - 4], fill=(120, 180, 200, 255), outline=INK, width=LW)
    box(d, 40, H_ - 170, W_ - 40, H_ - 40, SAND, SAND_D, 40, 8)
    for (x, y, r) in ((44, H_ - 170, 26), (W_ - 44, H_ - 170, 26), (W_ / 2, H_ - 210, 32)):
        d.rectangle([x - r, y - 10, x + r, y + 60], fill=SAND_D, outline=INK, width=LW)
        d.ellipse([x - r, y - 24, x + r, y + 4], fill=SAND, outline=INK, width=LW)
    d.line([(W_ / 2, H_ - 236), (W_ / 2, H_ - 290)], fill=WOOD_D, width=5)
    d.polygon([(W_ / 2, H_ - 290), (W_ / 2 + 40, H_ - 280), (W_ / 2, H_ - 268)], fill=RED, outline=INK)
    d.rectangle([W_ / 2 - 16, H_ - 92, W_ / 2 + 16, H_ - 46], fill=DARK, outline=INK, width=4)
    return img


def tente(opened=False):
    img, d = canvas(PX, 1.6 * PX)
    W_, H_ = img.size
    d.pieslice([6, 20, W_ - 6, 2 * H_ - 30], 180, 360, fill=ORANGE, outline=INK, width=LW)
    d.pieslice([30, 30, W_ - 30, 2 * H_ - 40], 180, 360, fill=TURQ)
    d.line([(6, H_ - 5), (W_ - 6, H_ - 5)], fill=INK, width=LW)
    d.pieslice([W_ / 2 - 30, H_ - 70, W_ / 2 + 30, H_ + 50], 180, 360, fill=DARK if opened else TURQ_D, outline=INK, width=4)
    return img


def bouee_poteau():
    img, d = canvas(PX, 2 * PX)
    W_, H_ = img.size
    d.rectangle([W_ / 2 - 8, 40, W_ / 2 + 8, H_ - 6], fill=WOOD, outline=INK, width=4)
    d.ellipse([W_ / 2 - 44, 46, W_ / 2 + 44, 134], fill=RED, outline=INK, width=LW)
    d.ellipse([W_ / 2 - 22, 68, W_ / 2 + 22, 112], fill=(0, 0, 0, 0), outline=INK, width=LW)
    for a in (45, 135, 225, 315):
        x = W_ / 2 + math.cos(math.radians(a)) * 33
        y = 90 + math.sin(math.radians(a)) * 33
        d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=WHITE)
    d.ellipse([W_ / 2 - 30, H_ - 26, W_ / 2 + 30, H_ - 4], fill=SAND_D, outline=INK, width=3)
    return img


def rocher(w, h, top, front, seed, weed=True):
    img, d = canvas(w * PX, h * PX)
    W_, H_ = img.size
    rock(d, 6, 6, W_ - 6, H_ - 2, top, front, seed, weed)
    return img


def rocher_bas(w):
    img, d = canvas(w * PX, PX)
    W_, H_ = img.size
    for k in range(w * 2):
        x = 10 + k * (W_ - 20) / (w * 2)
        rock(d, x, H_ * 0.45 + (k % 2) * 8, x + (W_ - 20) / (w * 2) + 20, H_ - 4, ROCK_T, ROCK_D, k, weed=k % 2 == 0)
    return img


def flaque(w, h):
    img, d = canvas(w * PX, h * PX)
    W_, H_ = img.size
    d.ellipse([4, 8, W_ - 4, H_ - 4], fill=ROCK_D, outline=INK, width=LW)
    d.ellipse([22, 22, W_ - 22, H_ - 20], fill=TURQ, outline=INK, width=4)
    d.arc([40, 32, W_ * 0.5, H_ * 0.6], 200, 290, fill=(255, 255, 255, 200), width=5)
    cx, cy = W_ * 0.62, H_ * 0.55
    star = []
    for k in range(10):
        r = 18 if k % 2 == 0 else 8
        a = math.pi * 2 * k / 10 - math.pi / 2
        star.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(star, fill=ORANGE, outline=INK)
    return img


def creux_rocher(opened=False):
    img, d = canvas(PX, 1.6 * PX)
    W_, H_ = img.size
    rock(d, 4, 6, W_ - 4, H_ - 2, ROCK_T, ROCK_D, 3)
    r = 30 if not opened else 38
    d.ellipse([W_ / 2 - r, H_ - 2 * r - 8, W_ / 2 + r, H_ - 4], fill=DARK, outline=INK, width=4)
    cx, cy = W_ * 0.74, H_ * 0.32
    star = []
    for k in range(10):
        rr = 16 if k % 2 == 0 else 7
        a = math.pi * 2 * k / 10 - math.pi / 2
        star.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(star, fill=ORANGE, outline=INK)
    return img


def tonneau():
    img, d = canvas(PX, 1.4 * PX)
    W_, H_ = img.size
    d.rounded_rectangle([18, 20, W_ - 18, H_ - 4], 30, fill=WOOD, outline=INK, width=LW)
    for y in (0.32, 0.72):
        d.rectangle([20, H_ * y, W_ - 20, H_ * y + 10], fill=GREY_D)
    d.ellipse([22, 10, W_ - 22, 46], fill=WOOD_T, outline=INK, width=LW)
    return img


def lanterne():
    img, d = canvas(PX, 1.5 * PX)
    W_, H_ = img.size
    d.ellipse([W_ / 2 - 46, H_ - 34, W_ / 2 + 46, H_ - 2], fill=(250, 220, 120, 110))
    rock(d, 24, H_ - 50, W_ - 24, H_ - 4, CAVE_T, CAVE_D, 1, weed=False)
    d.rectangle([W_ / 2 - 20, 40, W_ / 2 + 20, H_ - 40], fill=(250, 214, 110, 255), outline=INK, width=4)
    d.ellipse([W_ / 2 - 8, 60, W_ / 2 + 8, 84], fill=(255, 250, 220, 255))
    d.polygon([(W_ / 2 - 26, 42), (W_ / 2 + 26, 42), (W_ / 2, 16)], fill=(190, 150, 60, 255), outline=INK)
    return img


def facade(c_beam, c_shutter, awning, wood=False):
    img, d = canvas(3 * PX, 2.6 * PX)
    W_, H_ = img.size
    wall = (226, 200, 160, 255) if wood else WHITE
    box(d, 6, 30, W_ - 6, H_ - 4, (210, 196, 176, 255), wall, H_ - 70, 4)
    if wood:
        for y in range(70, H_ - 8, 22):
            d.line([(10, y), (W_ - 10, y)], fill=WOOD_D, width=3)
    else:
        for x in (10, W_ / 2 - 6, W_ - 22):
            d.rectangle([x, 50, x + 14, H_ - 6], fill=c_beam)
        d.rectangle([10, 50, W_ - 10, 62], fill=c_beam)
    # Fenêtre et volets.
    wx0, wx1, wy0, wy1 = W_ * 0.3, W_ * 0.7, H_ * 0.42, H_ * 0.78
    d.rectangle([wx0, wy0, wx1, wy1], fill=(150, 190, 210, 255), outline=INK, width=4)
    d.rectangle([wx0 - 34, wy0, wx0, wy1], fill=c_shutter, outline=INK, width=4)
    d.rectangle([wx1, wy0, wx1 + 34, wy1], fill=c_shutter, outline=INK, width=4)
    # Auvent rayé.
    n = 9
    sw = (W_ - 20) / n
    for k in range(n):
        d.rectangle([10 + k * sw, wy0 - 70, 10 + (k + 1) * sw, wy0 - 20], fill=awning if k % 2 == 0 else WHITE)
        d.pieslice([10 + k * sw, wy0 - 40, 10 + (k + 1) * sw, wy0], 0, 180, fill=awning if k % 2 == 0 else WHITE,
                   outline=INK, width=3)
    d.rectangle([10, wy0 - 70, W_ - 10, wy0 - 20], outline=INK, width=LW)
    return img


def jardiniere():
    img, d = canvas(3 * PX, 1.4 * PX)
    W_, H_ = img.size
    box(d, 8, 50, W_ - 8, H_ - 4, (240, 236, 228, 255), WHITE, 34, 8)
    for k in range(9):
        x = 26 + k * (W_ - 52) / 8
        c = (110, 140, 220, 255) if k % 2 else (236, 140, 190, 255)
        d.ellipse([x - 22, 14 + (k % 3) * 6, x + 22, 62 + (k % 3) * 6], fill=c, outline=INK, width=4)
    return img


def sous_terrasse(opened=False):
    img, d = canvas(PX, PX)
    W_, H_ = img.size
    box(d, 2, 4, W_ - 2, H_ - 4, WOOD_T, WOOD_D, H_ - 34, 4)
    for k in range(-4, 8):
        d.line([(k * 22, 34), (k * 22 + 60, H_ - 6)], fill=WOOD, width=5)
    d.rectangle([W_ * 0.25, 44, W_ * 0.75, H_ - 6], fill=DARK, outline=INK, width=4)
    if not opened:
        d.rectangle([W_ * 0.25, 44, W_ * 0.75, H_ - 6], fill=ORANGE, outline=INK, width=4)
        d.line([(W_ / 2, 46), (W_ / 2, H_ - 8)], fill=ORANGE_D, width=4)
    return img


def fourneau():
    img, d = canvas(2 * PX, 1.7 * PX)
    W_, H_ = img.size
    box(d, 8, 60, W_ - 8, H_ - 4, (90, 94, 104, 255), (52, 56, 66, 255), 70, 8)
    d.rectangle([40, H_ - 56, W_ - 40, H_ - 20], fill=(30, 30, 36, 255), outline=INK, width=4)
    for (x, c) in ((60, (210, 120, 70, 255)), (W_ - 60, (190, 110, 60, 255))):
        d.rectangle([x - 32, 30, x + 32, 76], fill=c, outline=INK, width=LW)
        d.ellipse([x - 32, 20, x + 32, 40], fill=(230, 160, 110, 255), outline=INK, width=4)
    return img


def plan_travail():
    img, d = canvas(3 * PX, 1.2 * PX)
    W_, H_ = img.size
    box(d, 8, 26, W_ - 8, H_ - 4, (214, 220, 228, 255), GREY, 40, 6)
    d.rounded_rectangle([40, 34, 130, 70], 6, fill=WOOD_T, outline=INK, width=4)
    for k, c in enumerate((RED, GREEN, YELLOW)):
        d.ellipse([170 + k * 34, 36, 200 + k * 34, 66], fill=c, outline=INK, width=3)
    d.ellipse([290, 30, 350, 72], fill=WOOD, outline=INK, width=4)
    return img


def frigo(opened=False):
    img, d = canvas(PX, 2.1 * PX)
    W_, H_ = img.size
    box(d, 14, 10, W_ - 14, H_ - 4, (200, 236, 232, 255), (150, 210, 206, 255), H_ - 40, 18)
    if opened:
        d.rounded_rectangle([24, 40, W_ - 24, H_ - 12], 8, fill=DARK, outline=INK, width=4)
        d.polygon([(W_ - 24, 40), (W_ + 0, 52), (W_ + 0, H_ - 4), (W_ - 24, H_ - 12)], fill=(150, 210, 206, 255))
    else:
        d.line([(20, H_ * 0.42), (W_ - 20, H_ * 0.42)], fill=INK, width=4)
        d.rounded_rectangle([W_ - 36, 56, W_ - 26, 110], 4, fill=GREY, outline=INK, width=3)
        d.ellipse([34, 70, 54, 90], fill=ORANGE, outline=INK, width=3)
    return img


def poste_secours():
    img, d = canvas(4 * PX, 4.2 * PX)
    W_, H_ = img.size
    # Pilotis, cabane, toit rouge, balcon, mât et drapeau.
    for x in (40, W_ / 2 - 10, W_ - 60):
        d.rectangle([x, H_ * 0.62, x + 20, H_ - 4], fill=WOOD, outline=INK, width=4)
    d.rectangle([20, H_ * 0.62, W_ - 20, H_ * 0.66], fill=WOOD_D, outline=INK, width=4)
    box(d, 30, H_ * 0.3, W_ - 30, H_ * 0.64, (236, 232, 226, 255), WHITE, int(H_ * 0.26), 6)
    d.rectangle([W_ / 2 - 36, H_ * 0.42, W_ / 2 + 36, H_ * 0.5], fill=RED)
    d.rectangle([W_ / 2 - 12, H_ * 0.37, W_ / 2 + 12, H_ * 0.55], fill=RED)
    for x in (70, W_ - 130):
        d.rectangle([x, H_ * 0.4, x + 60, H_ * 0.52], fill=(150, 190, 210, 255), outline=INK, width=4)
    d.polygon([(10, H_ * 0.32), (W_ / 2, H_ * 0.14), (W_ - 10, H_ * 0.32)], fill=RED, outline=INK)
    d.line([(10, H_ * 0.32), (W_ / 2, H_ * 0.14), (W_ - 10, H_ * 0.32), (10, H_ * 0.32)], fill=INK, width=LW)
    d.rectangle([W_ - 46, 10, W_ - 36, H_ * 0.32], fill=WHITE, outline=INK, width=3)
    d.polygon([(W_ - 36, 12), (W_ - 4, 22), (W_ - 36, 40)], fill=(60, 180, 90, 255), outline=INK)
    # Escalier d'accès.
    d.polygon([(W_ - 20, H_ - 4), (W_ - 70, H_ * 0.64), (W_ - 50, H_ * 0.64), (W_ + 0, H_ - 4)], fill=WOOD_T, outline=INK)
    return img


def chaise_surveillance():
    img, d = canvas(PX, 2.6 * PX)
    W_, H_ = img.size
    for x in (24, W_ - 34):
        d.line([(x, H_ - 4), (W_ / 2 - 5, 120)], fill=INK, width=12)
        d.line([(x, H_ - 4), (W_ / 2 - 5, 120)], fill=WHITE, width=6)
    for y in range(140, int(H_) - 10, 30):
        d.line([(34, y), (W_ - 44, y)], fill=WHITE, width=5)
    box(d, 26, 92, W_ - 26, 130, WHITE, (220, 220, 220, 255), 14, 4)
    d.line([(W_ / 2, 92), (W_ / 2, 30)], fill=INK, width=4)
    d.pieslice([10, 6, W_ - 10, 60], 180, 360, fill=RED, outline=INK, width=4)
    return img


def rack_sauvetage():
    img, d = canvas(2 * PX, 1.6 * PX)
    W_, H_ = img.size
    box(d, 10, 60, W_ - 10, H_ - 4, WOOD_T, WOOD_D, 30, 4)
    for k in range(2):
        d.rounded_rectangle([24, 22 + k * 28, W_ - 24, 46 + k * 28], 12, fill=YELLOW, outline=INK, width=4)
    d.rounded_rectangle([W_ / 2 - 50, H_ - 40, W_ / 2 + 50, H_ - 22], 8, fill=RED, outline=INK, width=4)
    return img


def coffre_sauveteur(opened=False):
    img, d = canvas(PX, 1.2 * PX)
    W_, H_ = img.size
    box(d, 8, 26, W_ - 8, H_ - 4, RED, RED_D, 64, 8)
    if opened:
        d.rectangle([14, 30, W_ - 14, 54], fill=DARK)
        d.polygon([(8, 30), (W_ - 8, 30), (W_ - 14, 0), (14, 0)], fill=RED, outline=INK)
    else:
        d.rectangle([W_ / 2 - 6, 34, W_ / 2 + 6, 58], fill=WHITE)
        d.rectangle([W_ / 2 - 18, 40, W_ / 2 + 18, 52], fill=WHITE)
        d.rectangle([W_ / 2 - 8, 70, W_ / 2 + 8, 90], fill=ORANGE, outline=INK, width=3)
    return img


def barque(w, h, hull, hull_d, stripe, extra=None):
    img, d = canvas(w * PX, (h + 0.4) * PX)
    W_, H_ = img.size
    # Coque retournée : fuseau, quille au milieu, bande de couleur.
    d.ellipse([8, 14, W_ - 8, H_ - 2], fill=hull_d, outline=INK, width=LW)
    d.ellipse([8, 14, W_ - 8, H_ - 40], fill=hull, outline=INK, width=LW)
    d.line([(30, (14 + H_ - 40) / 2), (W_ - 30, (14 + H_ - 40) / 2)], fill=hull_d, width=8)
    d.arc([8, 14, W_ - 8, H_ - 2], 20, 160, fill=stripe, width=10)
    if extra == "filet":
        for k in range(6):
            d.line([(W_ * 0.2 + k * 30, 30), (W_ * 0.25 + k * 30, H_ - 30)], fill=(120, 130, 140, 200), width=3)
    else:
        d.line([(W_ * 0.15, H_ - 14), (W_ * 0.45, H_ - 50)], fill=WOOD_D, width=8)
    return img


def bateau_remorque():
    img, d = canvas(4 * PX, 3 * PX)
    W_, H_ = img.size
    d.rectangle([20, H_ - 40, W_ - 20, H_ - 22], fill=WOOD_D, outline=INK, width=4)
    for x in (70, W_ - 90):
        d.ellipse([x - 26, H_ - 52, x + 26, H_ - 2], fill=(50, 50, 56, 255), outline=INK, width=4)
    d.chord([20, H_ * 0.18, W_ - 20, H_ - 34], 0, 180, fill=RED, outline=INK, width=LW)
    d.rectangle([20, H_ * 0.48, W_ - 20, H_ * 0.56], fill=GREEN)
    d.line([(20, (H_ * 0.18 + H_ - 34) / 2), (W_ - 20, (H_ * 0.18 + H_ - 34) / 2)], fill=INK, width=LW)
    d.rectangle([20, (H_ * 0.18 + H_ - 34) / 2 - 22, W_ - 20, (H_ * 0.18 + H_ - 34) / 2], fill=WHITE, outline=INK, width=4)
    box(d, W_ - 170, 26, W_ - 70, (H_ * 0.18 + H_ - 34) / 2 - 18, WHITE, (220, 220, 220, 255), 40, 6)
    return img


def canoe():
    img, d = canvas(3 * PX, 1.3 * PX)
    W_, H_ = img.size
    for k, c in enumerate((YELLOW, ORANGE)):
        y = 14 + k * 40
        d.ellipse([10, y, W_ - 10, y + 60], fill=c, outline=INK, width=LW)
        d.ellipse([W_ / 2 - 40, y + 18, W_ / 2 + 40, y + 42], fill=DARK)
    d.line([(40, H_ - 10), (W_ - 60, 20)], fill=INK, width=8)
    return img


def annexe(opened=False):
    img, d = canvas(PX, 1.2 * PX)
    W_, H_ = img.size
    lift = 16 if opened else 0
    d.ellipse([6, 20, W_ - 6, H_ - 4], fill=DARK if opened else WOOD_D, outline=INK, width=LW)
    d.ellipse([6, 14 - lift, W_ - 6, H_ - 28 - lift], fill=WOOD_T, outline=INK, width=LW)
    d.arc([6, 14 - lift, W_ - 6, H_ - 28 - lift], 20, 160, fill=ORANGE, width=10)
    rock(d, W_ - 44, H_ - 36, W_ - 6, H_ - 2, ROCK_T, ROCK_D, 2, weed=False)
    return img


def lampadaire():
    img, d = canvas(PX, 2.6 * PX)
    W_, H_ = img.size
    d.rectangle([W_ / 2 - 26, H_ - 28, W_ / 2 + 26, H_ - 4], fill=GREEN_D, outline=INK, width=4)
    d.rectangle([W_ / 2 - 7, 60, W_ / 2 + 7, H_ - 26], fill=GREEN, outline=INK, width=4)
    d.ellipse([W_ / 2 - 30, 10, W_ / 2 + 30, 70], fill=(255, 250, 225, 255), outline=INK, width=LW)
    return img


def longue_vue():
    img, d = canvas(PX, 1.8 * PX)
    W_, H_ = img.size
    d.rectangle([W_ / 2 - 24, H_ - 24, W_ / 2 + 24, H_ - 4], fill=GREEN_D, outline=INK, width=4)
    d.rectangle([W_ / 2 - 7, 70, W_ / 2 + 7, H_ - 22], fill=GREEN, outline=INK, width=4)
    d.polygon([(W_ / 2 - 40, 50), (W_ / 2 + 34, 24), (W_ / 2 + 44, 46), (W_ / 2 - 30, 76)], fill=GREEN, outline=INK)
    d.line([(W_ / 2 - 40, 50), (W_ / 2 + 34, 24), (W_ / 2 + 44, 46), (W_ / 2 - 30, 76), (W_ / 2 - 40, 50)], fill=INK, width=LW)
    d.ellipse([W_ / 2 + 30, 22, W_ / 2 + 50, 50], fill=(150, 190, 210, 255), outline=INK, width=3)
    return img


def club_plage():
    img, d = canvas(3 * PX, 3.4 * PX)
    W_, H_ = img.size
    top = int(H_ * 0.36)
    stripes_rect(d, 16, top, W_ - 16, H_ - 4, BLUE, YELLOW, 8)
    d.rectangle([16, top, W_ - 16, H_ - 4], outline=INK, width=LW)
    d.rectangle([W_ / 2 - 40, H_ - 110, W_ / 2 + 40, H_ - 4], fill=DARK, outline=INK, width=4)
    d.polygon([(6, top + 10), (W_ / 2, top - 90), (W_ - 6, top + 10)], fill=YELLOW, outline=INK)
    d.line([(6, top + 10), (W_ / 2, top - 90), (W_ - 6, top + 10), (6, top + 10)], fill=INK, width=LW)
    for k in range(9):
        x = 14 + k * (W_ - 28) / 8
        d.pieslice([x - 16, top - 6, x + 16, top + 26], 0, 180, fill=BLUE if k % 2 else RED, outline=INK, width=3)
    d.line([(W_ / 2, top - 90), (W_ / 2, top - 150)], fill=INK, width=5)
    for k in range(6):
        x0 = W_ / 2 - 110 + k * 36
        y0 = top - 120 + abs(k - 2.5) * 14
        d.polygon([(x0, y0), (x0 + 30, y0), (x0 + 15, y0 + 26)], fill=(RED, YELLOW, GREEN, BLUE, ORANGE, TURQ)[k], outline=INK)
    return img


def pile_transats():
    img, d = canvas(2 * PX, 1.6 * PX)
    W_, H_ = img.size
    for k in range(5):
        x = 20 + k * 40
        d.polygon([(x, H_ - 4), (x + 30, 20 + (k % 2) * 8), (x + 48, 24 + (k % 2) * 8), (x + 22, H_ - 4)],
                  fill=GREEN if k % 2 else WHITE, outline=INK)
        d.line([(x, H_ - 4), (x + 30, 20 + (k % 2) * 8), (x + 48, 24 + (k % 2) * 8), (x + 22, H_ - 4), (x, H_ - 4)], fill=INK, width=4)
    d.line([(14, H_ * 0.55), (W_ - 14, H_ * 0.5)], fill=WOOD_D, width=8)
    d.rectangle([10, H_ - 16, W_ - 10, H_ - 4], fill=WOOD, outline=INK, width=3)
    return img


# ---------------------------------------------------------------- sorties (à plat)

def sortie_escalier(rampe=False):
    img, d = canvas(2 * PX, 2 * PX)
    W_, H_ = img.size
    d.rectangle([4, 4, W_ - 4, H_ - 4], fill=(214, 190, 140, 255), outline=INK, width=4)
    for k in range(5):
        y = 20 + k * 46
        d.line([(10, y), (W_ - 10, y)], fill=(170, 146, 100, 255), width=6)
    # Flèche vers la ville et barrière ouverte.
    d.polygon([(W_ / 2, 24), (W_ / 2 + 50, 90), (W_ / 2 + 20, 90), (W_ / 2 + 20, 170), (W_ / 2 - 20, 170),
               (W_ / 2 - 20, 90), (W_ / 2 - 50, 90)], fill=(255, 255, 255, 170), outline=INK)
    if rampe:
        d.line([(W_ - 18, 10), (W_ - 18, H_ - 10)], fill=WHITE, width=10)
    else:
        d.rectangle([8, 8, 50, 22], fill=GREEN, outline=INK, width=3)
    return img


def sortie_digue():
    img, d = canvas(3 * PX, 2 * PX)
    W_, H_ = img.size
    d.rounded_rectangle([4, 4, W_ - 4, H_ * 0.62], 40, fill=(190, 184, 172, 255), outline=INK, width=LW)
    for k in range(3):
        d.rectangle([W_ / 2 - 30, H_ * 0.62 - 6 + k * 18, W_ / 2 + 30, H_ * 0.62 + 4 + k * 18], fill=GREY_D, outline=INK, width=3)
    d.ellipse([W_ / 2 - 120, H_ * 0.66, W_ / 2 + 120, H_ - 6], fill=RED, outline=INK, width=LW)
    d.ellipse([W_ / 2 - 90, H_ * 0.71, W_ / 2 + 90, H_ - 18], fill=WOOD_T, outline=INK, width=4)
    return img


def sortie_canot():
    img, d = canvas(3 * PX, PX)
    W_, H_ = img.size
    d.rounded_rectangle([10, 10, W_ - 10, H_ - 10], 50, fill=ORANGE, outline=INK, width=LW)
    d.rounded_rectangle([40, 32, W_ - 40, H_ - 32], 30, fill=(60, 60, 70, 255), outline=INK, width=4)
    d.line([(W_ - 60, 20), (W_ - 10, 0)], fill=WOOD_D, width=8)
    return img


# ---------------------------------------------------------------- sols (tuiles 2 × 2 cases, raccords)

def _dots(d, size, n, color, r, seed):
    for k in range(n):
        x = (k * 73 + seed * 31) % size
        y = (k * 151 + seed * 17) % size
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r], fill=color)


def sol_sable(wet=False):
    s = 2 * PX
    img, d = canvas(s, s)
    base = (206, 176, 124, 255) if wet else (236, 214, 164, 255)
    d.rectangle([0, 0, s, s], fill=base)
    for k in range(6):
        y = 20 + k * 42
        pts = [(x, y + 6 * math.sin(2 * math.pi * x / s * 2 + k)) for x in range(0, s + 1, 8)]
        d.line(pts, fill=(196, 164, 112, 255) if wet else (222, 196, 144, 255), width=4)
    _dots(d, s, 10, (250, 240, 220, 255), 3, 1)
    if wet:
        for k in range(3):
            y = 40 + k * 80
            d.line([(0, y), (s, y + 10)], fill=(240, 246, 246, 150), width=3)
    return img


def sol_grotte():
    s = 2 * PX
    img, d = canvas(s, s)
    d.rectangle([0, 0, s, s], fill=(74, 84, 108, 255))
    for (x, y, rx, ry) in ((60, 70, 50, 30), (180, 180, 40, 26), (200, 50, 30, 18)):
        d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=(84, 96, 122, 255))
    d.ellipse([120, 110, 170, 136], fill=(70, 130, 150, 255))
    _dots(d, s, 8, (104, 116, 140, 255), 4, 2)
    return img


def sol_marches():
    s = 2 * PX
    img, d = canvas(s, s)
    d.rectangle([0, 0, s, s], fill=(222, 198, 150, 255))
    for k in range(4):
        y = k * 64
        d.rectangle([0, y + 50, s, y + 64], fill=(176, 150, 104, 255))
        d.line([(0, y + 50), (s, y + 50)], fill=(150, 124, 84, 255), width=3)
    return img


def sol_falaise():
    """Dessus de la falaise : grès ocre foncé à blocs, touffes d'herbe et fleurs (bien distinct du sable)."""
    s = 2 * PX
    img, d = canvas(s, s)
    d.rectangle([0, 0, s, s], fill=(150, 112, 70, 255))
    for (x, y, w, h) in ((0, 0, 120, 70), (128, 10, 128, 60), (20, 84, 100, 80), (130, 90, 126, 70),
                         (0, 178, 90, 78), (100, 176, 156, 80)):
        d.rounded_rectangle([x + 4, y + 4, x + w - 4, y + h - 4], 18, fill=(170, 130, 84, 255))
        d.line([(x + 14, y + 12), (x + w - 20, y + 12)], fill=(192, 156, 106, 255), width=4)
    for (x, y) in ((50, 40), (196, 130), (90, 214), (226, 34)):
        for k in range(3):
            d.ellipse([x - 20 + k * 12, y - 12, x - 4 + k * 12, y + 6], fill=(96, 150, 70, 255))
        d.ellipse([x - 3, y - 6, x + 5, y + 2], fill=(236, 150, 190, 255))
    return img


def sol_falaise_face():
    """Pied de falaise (une case de haut) : face rocheuse à strates, plus sombre en bas, contour en haut et en bas."""
    w, h = 2 * PX, PX
    img, d = canvas(w, h)
    d.rectangle([0, 0, w, h], fill=(128, 90, 56, 255))
    for k in range(3):
        y = 22 + k * 30
        d.rectangle([0, y, w, y + 12], fill=(108, 74, 46, 255))
    for x in (30, 92, 150, 214):
        d.line([(x, 8), (x - 6, h - 24)], fill=(84, 58, 36, 255), width=4)
    d.rectangle([0, h - 22, w, h], fill=(72, 50, 34, 255))
    d.line([(0, 3), (w, 3)], fill=INK, width=6)
    d.line([(0, h - 3), (w, h - 3)], fill=INK, width=6)
    return img


# ---------------------------------------------------------------- index

PROVISOIRES = {
    "cabine_rayee": lambda o=False: cabine(1, 2.3, BLUE, WHITE, (230, 230, 240, 255), BLUE_D),
    "cabine_rayee_rouge": lambda o=False: cabine(1, 2.3, RED, WHITE, (240, 230, 230, 255), RED_D),
    "cachette_cabine": lambda o=False: cabine(1, 2.3, BLUE, WHITE, ORANGE, BLUE_D, opened=o),
    "cabine_blanche": lambda o=False: cabine(1, 2.3, WHITE, WHITE, TURQ, WHITE, flat_roof=True),
    "parasol": lambda o=False: parasol(RED, WHITE),
    "parasol_bleu": lambda o=False: parasol(TURQ, WHITE),
    "transat": lambda o=False: transat(),
    "douche": lambda o=False: douche(),
    "paravent": lambda o=False: paravent(),
    "planches_surf": lambda o=False: planches_surf(),
    "kiosque_glaces": lambda o=False: kiosque(),
    "chateau_sable": lambda o=False: chateau_sable(),
    "cachette_tente": lambda o=False: tente(o),
    "bouee_poteau": lambda o=False: bouee_poteau(),
    "rocher": lambda o=False: rocher(1, 1.4, ROCK_T, ROCK, 1),
    "rocher_large": lambda o=False: rocher(2, 1.6, ROCK_T, ROCK, 2),
    "grand_rocher": lambda o=False: rocher(2, 2.9, ROCK_T, ROCK, 3),
    "rocher_geant": lambda o=False: rocher(3, 3.3, ROCK_T, ROCK, 4),
    "rocher_bas": lambda o=False: rocher_bas(1),
    "rocher_bas_large": lambda o=False: rocher_bas(2),
    "flaque": lambda o=False: flaque(2, 1),
    "flaque_grande": lambda o=False: flaque(3, 2),
    "cachette_creux_rocher": lambda o=False: creux_rocher(o),
    "rocher_grotte": lambda o=False: rocher(1, 1.6, CAVE_T, CAVE, 5, weed=False),
    "rocher_grotte_large": lambda o=False: rocher(2, 1.7, CAVE_T, CAVE, 6, weed=False),
    "tonneau": lambda o=False: tonneau(),
    "lanterne_grotte": lambda o=False: lanterne(),
    "facade_resto_rouge": lambda o=False: facade(RED_D, RED, RED),
    "facade_resto_vert": lambda o=False: facade(GREEN_D, GREEN, GREEN, wood=True),
    "jardiniere": lambda o=False: jardiniere(),
    "cachette_sous_terrasse": lambda o=False: sous_terrasse(o),
    "fourneau": lambda o=False: fourneau(),
    "plan_travail": lambda o=False: plan_travail(),
    "cachette_frigo": lambda o=False: frigo(o),
    "poste_secours": lambda o=False: poste_secours(),
    "chaise_surveillance": lambda o=False: chaise_surveillance(),
    "rack_sauvetage": lambda o=False: rack_sauvetage(),
    "cachette_coffre_sauveteur": lambda o=False: coffre_sauveteur(o),
    "barque_retournee": lambda o=False: barque(3, 2, (240, 236, 228, 255), (200, 196, 188, 255), RED),
    "barque_retournee_verte": lambda o=False: barque(3, 2, GREEN, GREEN_D, WHITE, "filet"),
    "bateau_remorque": lambda o=False: bateau_remorque(),
    "canoe": lambda o=False: canoe(),
    "cachette_annexe": lambda o=False: annexe(o),
    "lampadaire": lambda o=False: lampadaire(),
    "longue_vue": lambda o=False: longue_vue(),
    "club_plage": lambda o=False: club_plage(),
    "pile_transats": lambda o=False: pile_transats(),
    "sortie_escalier": lambda o=False: sortie_escalier(),
    "sortie_rampe": lambda o=False: sortie_escalier(rampe=True),
    "sortie_digue": lambda o=False: sortie_digue(),
    "sortie_canot": lambda o=False: sortie_canot(),
}
def sol_talus():
    s = 2 * PX
    img, d = canvas(s, s)
    d.rectangle([0, 0, s, s], fill=(128, 156, 88, 255))
    for (x, y, r) in ((40, 50, 30), (180, 80, 26), (100, 180, 34), (220, 210, 22)):
        d.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=ROCK_T, outline=ROCK_D, width=4)
    for k in range(14):
        x = (k * 67) % s
        y = (k * 113) % s
        d.line([(x, y + 10), (x + 6, y - 8)], fill=(90, 128, 60, 255), width=4)
        d.line([(x + 8, y + 10), (x + 14, y - 6)], fill=(90, 128, 60, 255), width=4)
    _dots(d, s, 6, (236, 150, 190, 255), 4, 3)
    return img


SOLS = {"talus": sol_talus, "sable": lambda: sol_sable(), "sable_mouille": lambda: sol_sable(True), "sol_grotte": sol_grotte,
        "marches": sol_marches, "falaise": sol_falaise, "falaise_face": sol_falaise_face}
COMMUN = "res://assets/blackout/decor/"


def ecrit(out, elements, floors, zone_names, placed, zone_name):
    """`zone_name(x, y)` : nom de la zone d'une case (« hors zones » sinon)."""
    os.makedirs(os.path.join(out, "provisoires"), exist_ok=True)
    used = {}
    for (el, x, y, w, h) in placed:
        used.setdefault(el, set()).add(zone_name(x, y))
    index = {"_doc": "Décor de la carte Plage de la Côte des Basques (tools/blackout/make_plage.py, plage_decor.py) : "
                     "images provisoires dessinées par le code (provisoires/), images communes du port reprises en res://. "
                     "Lu par BkDecor (assets/maps/<id>/decor/index.json) ; zones.json → « objets » fixe l'élément de "
                     "chaque objet posé. À remplacer élément par élément par les images de pixelforge (kanban : "
                     "« Carte : Plage de la Côte des Basques »).",
             "carte": "plage", "elements": {}}
    for el, e in elements.items():
        if el not in used:
            continue
        entry = {"nom": e["nom"], "type": e.get("type", "objet"), "categorie": e["cat"], "caractere": e["car"],
                 # Posé seulement là où zones.json → « objets » le dit (pas de pose par caractère et par zone :
                 # la mer d'une zone qui a une flaque resterait la mer).
                 "zones": [], "zones_des_poses": sorted(used[el]), "taille_cases": list(e["taille"]),
                 "debord_haut_cases": e["haut"], "animation": {}}
        if e["cat"] == "cachette":
            entry["animation"] = {"methode": "jeu", "description": "tremble quand quelqu'un y entre ou en sort"}
        if "fichier" in e:
            entry["fichiers"] = [COMMUN + e["fichier"]]
            if e.get("ombre"):
                entry["ombre"] = COMMUN + e["ombre"]
            entry["provisoire_png"] = False
        else:
            img = PROVISOIRES[el]()
            rel = f"provisoires/{el}.png"
            img.save(os.path.join(out, rel), optimize=True)
            entry["fichiers"] = [rel]
            entry["provisoire_png"] = True
            if e["cat"] == "cachette":
                op = PROVISOIRES[el](True)
                if op.tobytes() != img.tobytes():
                    rel2 = f"provisoires/{el}_ouvert.png"
                    op.save(os.path.join(out, rel2), optimize=True)
                    entry["ouvert"] = rel2
                    entry["ouvert_decalage"] = [0, 0]
        index["elements"][el] = entry
    for fid, f in floors.items():
        entry = {"nom": f["nom"], "type": "tuile_sol", "categorie": "sol", "caractere": f["car"],
                 "zones": sorted(zone_names) + ["hors zones"] if f["zones"] == ["*"] else f["zones"],
                 "taille_cases": [2, 1] if fid == "falaise_face" else [2, 2], "debord_haut_cases": 0, "animation": {}}
        if "fichier" in f:
            entry["fichiers"] = [COMMUN + f["fichier"]]
        elif "fichier_de" in f:
            entry["fichiers"] = [f"provisoires/{f['fichier_de']}.png"]
        else:
            rel = f"provisoires/{fid}.png"
            SOLS[fid]().save(os.path.join(out, rel), optimize=True)
            entry["fichiers"] = [rel]
        index["elements"][fid] = entry
    with open(os.path.join(out, "index.json"), "w") as fh:
        json.dump(index, fh, ensure_ascii=False, indent=1)
    print(f"décor : {len(index['elements'])} éléments dans {out}")
