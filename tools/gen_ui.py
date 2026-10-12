#!/usr/bin/env python3
"""Interface « bois de bateau et laiton » (SPEC-BORROKA §10.1, §10.3, §10.5, §3.1).

Tout est procédural ou en grilles ASCII, avec les seules couleurs de
tools/palette.py. Contour brun-prune, lumière en haut à gauche.

Sorties (assets/ui/) :
  logo_0..2.png         logo « MIARRITZE / BORROKA » animé (lauburu qui tourne, écume)
  frame_wood.png        panneau planche peinte + rivets laiton (9-patch)
  button_normal/hover/pressed/disabled.png  (9-patch)
  frame_portrait.png, frame_parchment.png, frame_lifebar.png  (9-patch)
  ninepatch.json        marges 9-patch (gauche, haut, droite, bas)
  banner_0..7.png       bannières de carte de joueur 64×24
  icon_*.png            icônes 16×16
Planches ×4 : tests/out/ui/*.png
Usage : python3 tools/gen_ui.py
"""
import json
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from palette import PALETTE, RAMPS  # noqa: E402
import gen_font  # noqa: E402

UI = os.path.join(ROOT, "assets", "ui")
OUT = os.path.join(ROOT, "tests", "out", "ui")
O = PALETTE["outline"]
T = (0, 0, 0, 0)


def rgba(c):
    return tuple(c) + (255,) if len(c) == 3 else tuple(c)


def from_grid(rows, ink):
    """Grille ASCII → image ; ink : caractère → couleur (None = transparent)."""
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y, r in enumerate(rows):
        assert len(r) == w, f"rangée {y} de longueur {len(r)} ≠ {w}"
        for x, ch in enumerate(r):
            c = ink.get(ch)
            if c is not None:
                px[x, y] = rgba(c)
    return img


def outline_mask(mask):
    """Anneau extérieur de 1 px (8-voisinage) autour d'un masque booléen."""
    h, w = len(mask), len(mask[0])
    ring = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy][xx]:
                        ring[y][x] = True
    return ring


def pad_mask(mask, p):
    h, w = len(mask), len(mask[0])
    out = [[False] * (w + 2 * p) for _ in range(h + 2 * p)]
    for y in range(h):
        for x in range(w):
            out[y + p][x + p] = mask[y][x]
    return out


# ============================================================== logo

def lauburu_mask(size, angle_deg):
    """Lauburu (croix basque) : 4 têtes en virgule, construit en
    sur-échantillonnage ×4 puis seuillé ; `angle_deg` le fait tourner."""
    ss = 4
    R = size * ss / 2.0
    c = size * ss / 2.0
    big = [[False] * (size * ss) for _ in range(size * ss)]
    a0 = math.radians(angle_deg)
    for py in range(size * ss):
        for px in range(size * ss):
            x, y = px + 0.5 - c, py + 0.5 - c
            hit = False
            for k in range(4):
                a = a0 + k * math.pi / 2
                u = x * math.cos(a) + y * math.sin(a)          # le long du bras
                v = -x * math.sin(a) + y * math.cos(a)         # perpendiculaire
                if u < 0:
                    continue
                inside = False
                if v >= 0 and (u - R / 2) ** 2 + v ** 2 <= (R / 2) ** 2:
                    inside = True
                if v < 0 and (u - 3 * R / 4) ** 2 + v ** 2 <= (R / 4) ** 2:
                    inside = True
                if v >= 0 and (u - R / 4) ** 2 + v ** 2 < (R / 5.2) ** 2:
                    inside = False
                if inside:
                    hit = True
                    break
            big[py][px] = hit
    m = [[False] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            n = sum(big[y * ss + j][x * ss + i] for j in range(ss) for i in range(ss))
            m[y][x] = n >= ss * ss // 2
    return m


def paint_lettering(img, mask, ox, oy, ramp, gold=True):
    """Lettrage : remplissage dégradé (clair en haut), liseré or, contour prune."""
    px = img.load()
    h, w = len(mask), len(mask[0])
    ys = [y for y in range(h) if any(mask[y])]
    top, bot = (min(ys), max(ys)) if ys else (0, 1)
    ring1 = outline_mask(mask)
    ring2 = outline_mask([[mask[y][x] or ring1[y][x] for x in range(w)] for y in range(h)])
    for y in range(h):
        t = (y - top) / max(bot - top, 1)
        for x in range(w):
            X, Y = ox + x, oy + y
            if not (0 <= X < img.width and 0 <= Y < img.height):
                continue
            if mask[y][x]:
                # lumière en haut à gauche : reflet clair sur le bord supérieur
                lit = y > 0 and not mask[y - 1][x]
                col = ramp[0] if (t < 0.3 or lit) else (ramp[1] if t < 0.75 else ramp[2])
                px[X, Y] = rgba(col)
            elif ring1[y][x]:
                px[X, Y] = rgba(RAMPS["yellow"][1] if gold else O)
            elif ring2[y][x] and gold:
                px[X, Y] = rgba(O)


def logo_frame(k):
    red = RAMPS["red"]
    scale = 2
    spacing = 3                       # assez pour que les liserés or ne se touchent pas
    top = gen_font.text_mask("MIARRITZE", scale=scale, spacing=spacing)
    parts = []
    for ch in "BORROKA":              # le premier « O » devient un lauburu
        parts.append("lau" if ch == "O" and "lau" not in parts else ch)
    lau_size = 26
    widths = [lau_size if p == "lau" else gen_font.glyph_mask(p)[0] * scale for p in parts]
    gap = spacing * scale // 2 + 2
    bot_w = sum(widths) + gap * (len(parts) - 1)
    W = max(len(top[0]), bot_w) + 10
    body_top1 = 2                     # haut du corps des lettres, ligne 1
    body_top2 = 30                    # ligne 2
    body_h = 12 * scale
    H = body_top2 + body_h + 12
    img = Image.new("RGBA", (W, H), T)
    cell_off = gen_font.TOP * scale + 2      # rangées vides (accents) + marge du contour
    tm = pad_mask(top, 2)
    paint_lettering(img, tm, (W - len(tm[0])) // 2, body_top1 - cell_off, red)
    x = (W - bot_w) // 2
    for p, w in zip(parts, widths):
        if p == "lau":
            m = pad_mask(lauburu_mask(lau_size, k * 30), 2)
            paint_lettering(img, m, x - 2, body_top2 + (body_h - lau_size) // 2 - 2, red)
        else:
            m = pad_mask(gen_font.text_mask(p, scale=scale), 2)
            paint_lettering(img, m, x - 2, body_top2 - cell_off, red)
        x += w + gap
    # vague d'écume sous le lettrage (3 phases), qui lèche le bas des lettres
    px = img.load()
    base = body_top2 + body_h + 4
    sea = RAMPS["turquoise"]
    foam = RAMPS["foam"]
    for xx in range(6, W - 6):
        phase = (xx + k * 4) / 9.0
        crest = base + round(math.sin(phase * math.pi) * 1.6)
        for yy in range(crest, H - 2):
            if px[xx, yy][3] > 0 and yy < base:
                continue
            depth = yy - crest
            col = foam[0] if depth == 0 else (foam[1] if depth == 1 else (sea[0] if depth < 4 else sea[1]))
            px[xx, yy] = rgba(col)
        if px[xx, crest - 1][3] == 0:
            px[xx, crest - 1] = rgba(O)
        px[xx, H - 2] = rgba(O)
        if (xx * 7 + k * 5) % 23 == 0 and px[xx, crest - 2][3] == 0:
            px[xx, crest - 2] = rgba(foam[0])
    for yy in range(base - 2, H - 1):
        for xx in (5, W - 6):
            if px[xx + (1 if xx == 5 else -1), yy][3] > 0:
                px[xx, yy] = rgba(O)
    return img


# ============================================================== 9-patch

def wood_panel(w, h, ramp_name="wood", rivets=True, light=True):
    """Planches horizontales peintes, joints sombres, cadre et rivets laiton."""
    wood = RAMPS[ramp_name]
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y in range(h):
        for x in range(w):
            if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                px[x, y] = rgba(O)
                continue
            plank = (y - 1) // 6
            row_in = (y - 1) % 6
            col = wood[1]
            if row_in == 0 and light:
                col = wood[0]                                       # arête éclairée
            elif row_in == 5:
                col = wood[3] if len(wood) > 3 else wood[2]         # joint
            elif (x * 5 + plank * 11) % 13 == 0 and row_in in (2, 3):
                col = wood[2]                                       # veinure
            px[x, y] = rgba(col)
    # biseau : bord haut-gauche clair, bas-droit sombre
    for x in range(1, w - 1):
        px[x, 1] = rgba(wood[0])
        px[x, h - 2] = rgba(wood[2])
    for y in range(1, h - 1):
        px[1, y] = rgba(wood[0])
        px[w - 2, y] = rgba(wood[2])
    if rivets:
        brass = RAMPS["brass"]
        for (rx, ry) in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
            px[rx, ry] = rgba(brass[0])
            px[rx + 1, ry] = rgba(brass[1])
            px[rx, ry + 1] = rgba(brass[1])
            px[rx + 1, ry + 1] = rgba(brass[2])
    return img


def button(state):
    """Bouton 9-patch 24×16 : planche + liseré laiton ; état normal / hover / pressed / disabled."""
    w, h = 24, 16
    if state == "hover":
        body, edge = RAMPS["red"], RAMPS["brass"]
    elif state == "pressed":
        body, edge = RAMPS["red"][1:] + [RAMPS["red"][-1]], RAMPS["brass"]
    elif state == "disabled":
        body, edge = RAMPS["stone"], RAMPS["stone"]
    else:
        body, edge = RAMPS["wood"], RAMPS["brass"]
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    sink = 1 if state == "pressed" else 0
    for y in range(h):
        for x in range(w):
            corner = (x in (0, w - 1)) and (y in (0, h - 1))
            if corner:
                continue
            if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                px[x, y] = rgba(O)
            elif x == 1 or y == 1 or x == w - 2 or y == h - 2:
                px[x, y] = rgba(edge[1] if (y > 1 + sink or x == 1) else edge[0])
            else:
                t = (y - 2) / (h - 5)
                if state != "pressed" and y == 2:
                    col = body[0]
                elif t > 0.75 and state != "pressed":
                    col = body[2]
                else:
                    col = body[1]
                px[x, y] = rgba(col)
    if state != "pressed":
        for x in range(2, w - 2):           # ombre portée (épaisseur du bouton)
            px[x, h - 2] = rgba(edge[2])
    return img


def portrait_frame():
    """Cadre de portrait 20×20 (9-patch) : laiton riveté autour d'un fond bleu nuit."""
    w = h = 20
    brass = RAMPS["brass"]
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d == 0:
                px[x, y] = rgba(O)
            elif d == 1:
                px[x, y] = rgba(brass[0] if (y == 1 or x == 1) else brass[1])
            elif d == 2:
                px[x, y] = rgba(brass[2])
            elif d == 3:
                px[x, y] = rgba(O)
            else:
                px[x, y] = rgba(RAMPS["night"][1])
    for (rx, ry) in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)):
        px[rx, ry] = rgba(RAMPS["linen"][0])
    return img


def parchment_frame():
    """Cadre parchemin 24×24 (9-patch), bords déchirés légers et filet bois."""
    w = h = 24
    lin = RAMPS["linen"]
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d == 0:
                if (x + y) % 5 != 0:
                    px[x, y] = rgba(O)
            elif d == 1:
                px[x, y] = rgba(RAMPS["wood"][2])
            elif d == 2:
                px[x, y] = rgba(lin[2])
            else:
                px[x, y] = rgba(lin[2] if (x * 5 + y * 3) % 29 == 0 else lin[1])
    return img


def lifebar_frame():
    """Cadre de barre de vie en planche 32×12 (9-patch) ; l'intérieur est transparent."""
    w, h = 32, 12
    wood = RAMPS["wood"]
    brass = RAMPS["brass"]
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d == 0:
                px[x, y] = rgba(O)
            elif d == 1:
                px[x, y] = rgba(wood[0] if y < h // 2 else wood[2])
            elif d == 2:
                px[x, y] = rgba(O)
    for (rx, ry) in ((2, h // 2), (w - 3, h // 2)):
        px[rx, ry] = rgba(brass[0])
    return img


NINEPATCH = {
    "frame_wood.png": [5, 5, 5, 5],
    "button_normal.png": [4, 4, 4, 5],
    "button_hover.png": [4, 4, 4, 5],
    "button_pressed.png": [4, 4, 4, 4],
    "button_disabled.png": [4, 4, 4, 5],
    "frame_portrait.png": [5, 5, 5, 5],
    "frame_parchment.png": [5, 5, 5, 5],
    "frame_lifebar.png": [4, 3, 4, 3],
}


# ============================================================== bannières 64×24

def banner(k):
    w, h = 64, 24
    img = Image.new("RGBA", (w, h), T)
    px = img.load()
    red, green, linen = RAMPS["red"], RAMPS["green"], RAMPS["linen"]

    def fill(c):
        for y in range(h):
            for x in range(w):
                px[x, y] = rgba(c)

    def blit_mask(m, ox, oy, col, ring=True):
        mm = pad_mask(m, 1)
        r = outline_mask(mm)
        for y in range(len(mm)):
            for x in range(len(mm[0])):
                X, Y = ox + x - 1, oy + y - 1
                if 0 <= X < w and 0 <= Y < h:
                    if mm[y][x]:
                        px[X, Y] = rgba(col)
                    elif ring and r[y][x]:
                        px[X, Y] = rgba(O)

    if k == 0:      # lauburu sur fond vert
        fill(green[1])
        for x in range(w):
            for y in (2, h - 3):
                px[x, y] = rgba(green[0])
        blit_mask(lauburu_mask(18, 0), 23, 3, red[1])
        for cx in (9, 55):
            blit_mask(lauburu_mask(14, 45), cx - 7, 5, linen[0])
    elif k == 1:    # makhilas croisés sur rouge
        fill(red[1])
        for t in range(-10, 11):
            for s in (-1, 1):
                x0 = 32 + t * s
                y0 = 12 + t
                for d in (0, 1):
                    if 0 <= x0 + d < w and 0 <= y0 < h:
                        px[x0 + d, y0] = rgba(RAMPS["wood"][1] if d == 0 else RAMPS["wood"][2])
        for (x, y) in ((21, 1), (42, 1), (21, 22), (42, 22)):
            for dx in (0, 1):
                for dy in (0, 1):
                    if 0 <= y + dy < h:
                        px[x + dx, y + dy] = rgba(RAMPS["brass"][1])
        for x in range(w):
            px[x, 0] = rgba(red[2])
            px[x, h - 1] = rgba(red[2])
    elif k == 2:    # vagues
        sea, foam = RAMPS["sea"], RAMPS["foam"]
        for y in range(h):
            for x in range(w):
                band = (y + round(math.sin(x / 5.0) * 2)) // 6
                px[x, y] = rgba([sea[0], sea[1], RAMPS["turquoise"][1], sea[2]][band % 4])
                if (y + round(math.sin(x / 5.0) * 2)) % 6 == 0:
                    px[x, y] = rgba(foam[0])
    elif k == 3:    # « ikurriña » stylisée (inspirée, non officielle)
        fill(red[1])
        for y in range(h):
            for x in range(w):
                # croix blanche droite, sautoir vert décalé et plus fin
                if abs(x - 32) <= 1 or abs(y - 12) <= 1:
                    px[x, y] = rgba(linen[0])
                elif abs((x - 32) - (y - 12) * 2.6) <= 1.5 or abs((x - 32) + (y - 12) * 2.6) <= 1.5:
                    px[x, y] = rgba(green[1])
        for y in range(h):
            for x in range(w):
                if (x // 8 + y // 8) % 2 == 0 and px[x, y] == rgba(red[1]):
                    px[x, y] = rgba(red[0])       # damier discret : pas le drapeau exact
    elif k == 4:    # rayures du linge basque
        cols = [linen[0]] * 5 + [red[1], red[1], linen[0], green[1], linen[0], red[1], red[1]] + [linen[0]] * 5
        for y in range(h):
            for x in range(w):
                px[x, y] = rgba(cols[(y * len(cols)) // h])
                if (x + y) % 9 == 0 and cols[(y * len(cols)) // h] == linen[0]:
                    px[x, y] = rgba(linen[1])
    elif k == 5:    # txapela
        fill(RAMPS["navy"][1])
        beret = [
            "..........###.......",
            "......##########....",
            "...################.",
            "..##################",
            ".###################",
            "####################",
            ".##################.",
            "...##############...",
        ]
        m = [[c == "#" for c in r] for r in beret]
        blit_mask(m, 22, 7, red[1])
        for y in range(9, 11):
            for x in range(25, 38):
                px[x, y] = rgba(red[0])
    elif k == 6:    # pelote + chistera
        fill(linen[1])
        for x in range(w):
            for y in range(h - 5, h):
                px[x, y] = rgba(RAMPS["pink"][1] if y > h - 4 else O)
        chis = [
            "..######......",
            ".##########...",
            "##....######..",
            "#.......#####.",
            ".........#####",
            "..........####",
            "...........###",
            "............##",
        ]
        for y, r in enumerate(chis):
            for x, c in enumerate(r):
                if c == "#":
                    px[14 + x, 6 + y] = rgba(RAMPS["sand"][1] if (x + y) % 2 else RAMPS["sand"][2])
        ball = [[(x - 3.5) ** 2 + (y - 3.5) ** 2 <= 12 for x in range(8)] for y in range(8)]
        blit_mask(ball, 40, 5, linen[0])
    else:           # phare la nuit
        fill(RAMPS["night"][1])
        for (sx, sy) in ((6, 3), (14, 8), (50, 4), (58, 10), (44, 15), (9, 17)):
            px[sx, sy] = rgba(linen[0])
        for y in range(4, h):
            half = 2 + (y - 4) // 6
            for x in range(32 - half, 32 + half + 1):
                stripe = ((y - 4) // 4) % 2
                px[x, y] = rgba(linen[0] if stripe == 0 else red[1])
        for x in range(30, 35):
            px[x, 3] = rgba(RAMPS["yellow"][0])
            px[x, 2] = rgba(O)
        for x in range(0, 30):            # faisceau
            yy = 3 + (30 - x) // 6
            for dy in range(-1 - (30 - x) // 10, 2 + (30 - x) // 10):
                if 0 <= yy + dy < h and px[x, yy + dy] == rgba(RAMPS["night"][1]):
                    px[x, yy + dy] = rgba(RAMPS["night"][0])
    # cadre commun
    for x in range(w):
        px[x, 0] = rgba(O)
        px[x, h - 1] = rgba(O)
    for y in range(h):
        px[0, y] = rgba(O)
        px[w - 1, y] = rgba(O)
    return img


# ============================================================== icônes 16×16

INK = {
    ".": None, "O": O,
    "R": RAMPS["red"][1], "r": RAMPS["red"][2], "L": RAMPS["red"][0],
    "S": RAMPS["skin_a"][1], "s": RAMPS["skin_a"][2],
    "W": RAMPS["linen"][0], "w": RAMPS["linen"][2],
    "Y": RAMPS["yellow"][1], "y": RAMPS["yellow"][2], "Z": RAMPS["yellow"][0],
    "B": RAMPS["navy"][0], "b": RAMPS["navy"][1],
    "G": RAMPS["green"][1], "g": RAMPS["green"][2],
    "T": RAMPS["sand"][1], "t": RAMPS["sand"][2],
    "M": RAMPS["steel"][1], "m": RAMPS["steel"][2],
    "K": RAMPS["ink"][0],
}

ICONS = {
    "punch": [
        "................",
        "................",
        "....OOOOOOO.....",
        "...OSSOSSOSO....",
        "..OSSSOSSOSSO...",
        "..OSSSOSSOSSSO..",
        "..OSSSSSSSSSSO..",
        "..OsSSSSSSSSSO..",
        "..OOOOOOSSSSSO..",
        "..OSSSSOsSSSO...",
        "..OsSSSSSsSSO...",
        "...OsssssssO....",
        "....OOOOOOO.....",
        "....ORRRRRO.....",
        "....OOOOOOO.....",
        "................",
    ],
    "espadrille": [
        "................",
        "................",
        "................",
        "......OOOOO.....",
        "....OOWWWWWO....",
        "...OWWWRRWWWO...",
        "..OWWWRRRRWWWO..",
        ".OWWWWWWWWWWWWO.",
        ".OwWWWWWWWWWWwO.",
        ".OOOOOOOOOOOOOO.",
        ".OTtTtTtTtTtTtO.",
        ".OtTtTtTtTtTtTO.",
        "..OOOOOOOOOOOO..",
        "................",
        "................",
        "................",
    ],
    "shield": [
        "................",
        "..OOOOOOOOOOOO..",
        "..OBBBBBBBBBBO..",
        "..OBWWWWWWWWbO..",
        "..OBWBBBBBBWbO..",
        "..OBWBBBBBBWbO..",
        "..OBWBBBBBBWbO..",
        "..OBWBBBBBBWbO..",
        "...OBWBBBBWbO...",
        "...OBWBBBBWbO...",
        "....OBWBBWbO....",
        ".....OBWWbO.....",
        "......ObbO......",
        ".......OO.......",
        "................",
        "................",
    ],
    "txapela": [
        "................",
        "................",
        "................",
        "........O.......",
        ".......ORO......",
        "....OOOORROOO...",
        "..OOLLLLRRRRROO.",
        ".OLLLRRRRRRRRRRO",
        "ORRRRRRRRRRRRRRO",
        "ORRRRRRRRRRRRRrO",
        ".OrRRRRRRRRRRrO.",
        "..OOrrrrrrrrOO..",
        "....OOOOOOOO....",
        "................",
        "................",
        "................",
    ],
    "lock": [
        "................",
        "................",
        ".....OOOOOO.....",
        "....OMMMMMMO....",
        "...OMO....OMO...",
        "...OMO....OMO...",
        "...OMO....OmO...",
        "..OOOOOOOOOOOO..",
        "..OZYYYYYYYYyO..",
        "..OYYYYOOYYYyO..",
        "..OYYYYOOYYYyO..",
        "..OYYYYYOYYYyO..",
        "..OYYYYYYYYYyO..",
        "..OyyyyyyyyyyO..",
        "..OOOOOOOOOOOO..",
        "................",
    ],
    "star": [
        "................",
        ".......OO.......",
        ".......OO.......",
        "......OZYO......",
        "......OZYO......",
        "OOOOOOOZYOOOOOO.",
        ".OZZZZZZYYYYYO..",
        "..OZZZYYYYYyO...",
        "...OZYYYYYyO....",
        "...OZYYYYYyO....",
        "..OZYYYOOYYyO...",
        "..OZYYO..OYyO...",
        ".OZYOO....OOyO..",
        ".OOO........OO..",
        "................",
        "................",
    ],
    "buoy": [
        "................",
        ".....OOOOOO.....",
        "...OOWWRRWWOO...",
        "..OWWWRRRRWWWO..",
        "..OWRROOOORRWO..",
        ".ORRRO....ORRRO.",
        ".OWWWO....OWWWO.",
        ".OWWWO....OWWWO.",
        ".ORRRO....ORRRO.",
        "..OWRROOOORRwO..",
        "..OwWWRRRRWwwO..",
        "...OOwwrrwwOO...",
        ".....OOOOOO.....",
        "................",
        "................",
        "................",
    ],
    "gamepad": [
        "................",
        "................",
        "................",
        "...OOOOOOOOOO...",
        "..OBBBBBBBBBBO..",
        ".OBBOBBBBBBRBBO.",
        ".OBOOOBBBBRBGBO.",
        ".OBBOBBBBBBYBBO.",
        ".OBBBBBBBBBBBBO.",
        ".ObBBBBOOBBBBbO.",
        ".ObbBBO..OBBbbO.",
        "..OOOO....OOOO..",
        "................",
        "................",
        "................",
        "................",
    ],
    "speaker": [
        "................",
        "................",
        ".......OO.......",
        "......OMO...O...",
        ".....OMMO....O..",
        ".OOOOMMMO..O..O.",
        ".OMMMMMMO...O.O.",
        ".OMMMMMMO...O.O.",
        ".OMMMMMMO...O.O.",
        ".OmmmmMMO..O..O.",
        ".OOOOmMMO....O..",
        ".....OmMO...O...",
        "......OmO.......",
        ".......OO.......",
        "................",
        "................",
    ],
}


def icon_lauburu():
    img = Image.new("RGBA", (16, 16), T)
    px = img.load()
    m = pad_mask(lauburu_mask(12, 0), 2)
    r = outline_mask(m)
    for y in range(16):
        for x in range(16):
            if m[y][x]:
                px[x, y] = rgba(RAMPS["yellow"][1] if (x + y) > 12 else RAMPS["yellow"][0])
            elif r[y][x]:
                px[x, y] = rgba(O)
    return img


# ============================================================== planches

def sheet(images, path, scale=4, cols=None, bg=(64, 70, 96, 255), gap=4):
    cols = cols or len(images)
    rows = (len(images) + cols - 1) // cols
    cw = max(i.width for i in images)
    ch = max(i.height for i in images)
    img = Image.new("RGBA", (cols * (cw + gap) + gap, rows * (ch + gap) + gap), bg)
    for k, im in enumerate(images):
        img.alpha_composite(im, (gap + (k % cols) * (cw + gap), gap + (k // cols) * (ch + gap)))
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(path)
    return path


def stretch9(img, margins, w, h):
    """Aperçu d'un 9-patch en mode « tile » (axis_stretch = TILE), pour vérifier les marges."""
    l, t, r, b = margins
    out = Image.new("RGBA", (w, h), T)
    sw, sh = img.width, img.height
    xs = [(0, l, 0, l), (l, sw - r, l, w - r), (sw - r, sw, w - r, w)]
    ys = [(0, t, 0, t), (t, sh - b, t, h - b), (sh - b, sh, h - b, h)]
    for (sx0, sx1, dx0, dx1) in xs:
        for (sy0, sy1, dy0, dy1) in ys:
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            part = img.crop((sx0, sy0, sx1, sy1))
            for ty in range(dy0, dy1, part.height):
                for tx in range(dx0, dx1, part.width):
                    piece = part.crop((0, 0, min(part.width, dx1 - tx), min(part.height, dy1 - ty)))
                    out.alpha_composite(piece, (tx, ty))
    return out


def main():
    os.makedirs(UI, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    logos = [logo_frame(k) for k in range(3)]
    for k, im in enumerate(logos):
        im.save(os.path.join(UI, f"logo_{k}.png"))
    frames = {
        "frame_wood.png": wood_panel(24, 24),
        "button_normal.png": button("normal"),
        "button_hover.png": button("hover"),
        "button_pressed.png": button("pressed"),
        "button_disabled.png": button("disabled"),
        "frame_portrait.png": portrait_frame(),
        "frame_parchment.png": parchment_frame(),
        "frame_lifebar.png": lifebar_frame(),
    }
    for name, im in frames.items():
        im.save(os.path.join(UI, name))
    with open(os.path.join(UI, "ninepatch.json"), "w") as f:
        json.dump({"_doc": "marges 9-patch [gauche, haut, droite, bas] en px (StyleBoxTexture texture_margin_*)",
                   **NINEPATCH}, f, indent=1)
    banners = [banner(k) for k in range(8)]
    for k, im in enumerate(banners):
        im.save(os.path.join(UI, f"banner_{k}.png"))
    icons = {name: from_grid(rows, INK) for name, rows in ICONS.items()}
    icons["lauburu"] = icon_lauburu()
    for name, im in icons.items():
        assert im.size == (16, 16), name
        im.save(os.path.join(UI, f"icon_{name}.png"))
    # planches
    sheet(logos, os.path.join(OUT, "logo.png"), scale=3, cols=1)
    stretched = [stretch9(im, NINEPATCH[n], 96 if "lifebar" not in n else 120,
                          40 if "button" in n else (14 if "lifebar" in n else 48)) for n, im in frames.items()]
    sheet(list(frames.values()), os.path.join(OUT, "frames_native.png"), scale=4)
    sheet(stretched, os.path.join(OUT, "frames_stretched.png"), scale=4, cols=2)
    sheet(banners, os.path.join(OUT, "banners.png"), scale=4, cols=4)
    sheet(list(icons.values()), os.path.join(OUT, "icons.png"), scale=4)
    print("UI écrite :", len(frames), "cadres,", len(banners), "bannières,", len(icons), "icônes, logo",
          logos[0].size)


if __name__ == "__main__":
    main()
