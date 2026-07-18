#!/usr/bin/env python3
"""Décors pixel art 320x180 — passe qualité « Fez ».

Techniques : rampes multi-tons dithérées (Bayer 8x8), perspective
atmosphérique (les plans lointains tirent vers le ciel), silhouettes
architecturales de Biarritz (Villa Belza, crampottes, passerelle du
Rocher, balustrades), mer ANIMÉE (3 frames par décor : bg_<lieu>_0/1/2).
"""
from PIL import Image
import os, sys, math, random
sys.path.insert(0, os.path.dirname(__file__))
from palette import PALETTE

W, H = 320, 180
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
SCRATCH = "/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad"

BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]


def c(name):
    return PALETTE[name] + (255,)


def mix(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1[:3], c2[:3])) + (255,)


def bayer(x, y):
    return (BAYER8[y % 8][x % 8] + 0.5) / 64.0


def ramp(img, y0, y1, stops, x0=0, x1=None):
    """Rampe verticale multi-tons dithérée entre plusieurs couleurs."""
    x1 = img.width if x1 is None else x1
    n = len(stops) - 1
    h = max(y1 - y0, 1)
    for y in range(max(y0, 0), min(y1, img.height)):
        t = (y - y0) / h * n
        i = min(int(t), n - 1)
        frac = t - i
        for x in range(x0, x1):
            img.putpixel((x, y), stops[i + 1] if frac > bayer(x, y) else stops[i])


def hline(img, x0, x1, y, color):
    if 0 <= y < img.height:
        for x in range(max(x0, 0), min(x1, img.width)):
            img.putpixel((x, y), color)


def put(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def rect(img, x0, y0, x1, y1, color):
    for y in range(max(y0, 0), min(y1, img.height)):
        for x in range(max(x0, 0), min(x1, img.width)):
            img.putpixel((x, y), color)


def speckle(img, x0, y0, x1, y1, color, density, rng):
    for y in range(max(y0, 0), min(y1, img.height)):
        for x in range(max(x0, 0), min(x1, img.width)):
            if rng.random() < density:
                img.putpixel((x, y), color)


def sun(img, cx, cy, r):
    for y in range(cy - r - 2, cy + r + 3):
        for x in range(cx - r - 2, cx + r + 3):
            d = math.hypot(x - cx, y - cy)
            if d < r:
                put(img, x, y, c("white"))
            elif d < r + 2 and bayer(x, y) < 0.5:
                put(img, x, y, mix(c("gold"), c("white"), 0.5))


def cloud2(img, x, y, w, rng):
    """Nuage à deux tons : dessus blanc, dessous ombré."""
    h = max(4, w // 4)
    for yy in range(h):
        for xx in range(w):
            dx = (xx - w / 2) / (w / 2)
            dy = (yy - h / 2) / (h / 2)
            blob = dx * dx + dy * dy * 2.0
            wob = 0.16 * math.sin(xx * 1.7 + x) * (1 - abs(dy))
            if blob + wob < 1.0:
                color = c("white") if yy < h * 0.62 else mix(c("white"), c("grey_blue"), 0.4)
                put(img, x + xx, y + yy, color)


def hill(img, x0, x1, y_top, y_base, color, wobble=0.0, seed=0):
    for x in range(max(x0, 0), min(x1, img.width)):
        t = (x - x0) / max(x1 - x0, 1)
        bump = math.sin(t * math.pi) ** 0.65
        wob = wobble * math.sin(x * 0.55 + seed) if wobble else 0.0
        top = int(y_base - (y_base - y_top) * bump + wob)
        for y in range(top, min(y_base, img.height)):
            put(img, x, y, color)


def rock_mass(img, x0, x1, y_top, y_base, base, light, dark, seed=0):
    """Rocher à facettes : silhouette + arête éclairée + fissures."""
    rng = random.Random(seed)
    tops = {}
    for x in range(max(x0, 0), min(x1, img.width)):
        t = (x - x0) / max(x1 - x0, 1)
        bump = math.sin(t * math.pi) ** 0.55
        # profil irrégulier mais doux : deux sinus lents + bruit léger
        top = int(y_base - (y_base - y_top) * bump
                  + 2.5 * math.sin(x * 0.22 + seed) + 1.5 * math.sin(x * 0.07 + seed * 2))
        tops[x] = top
        for y in range(top, min(y_base, img.height)):
            depth = (y - top) / max(y_base - top, 1)
            color = base
            if x - 1 in tops and tops[x - 1] - top > 3:
                color = light          # vraie falaise éclairée seulement
            elif depth < 0.10 and bayer(x, y) < 0.55:
                color = light
            elif depth > 0.72 and bayer(x, y) < 0.35:
                color = dark
            elif bayer(x * 7 + y * 3, y - x) < 0.045:
                color = dark           # grain minéral épars
            put(img, x, y, color)
    for _ in range(max((x1 - x0) // 22, 1)):
        fx = rng.randrange(x0 + 4, x1 - 4)
        if fx not in tops:
            continue
        fy = tops[fx] + rng.randint(4, 10)
        for k in range(rng.randint(4, 9)):
            put(img, fx + k // 2, fy + k, dark)


def draw_sea(img, y0, y1, phase, stops=None, sparkle_seed=5, calm=False):
    """Mer animée : houle horizontale dithérée + étincelles + écume."""
    stops = stops or [c("sea_deep"), c("sea_mid"), c("sea_turquoise")]
    rng = random.Random(sparkle_seed)
    n = len(stops) - 1
    h = max(y1 - y0, 1)
    for y in range(y0, min(y1, img.height)):
        t = (y - y0) / h * n
        i = min(int(t), n - 1)
        frac = t - i
        shift = int(3 * math.sin(phase + y * 0.35)) if not calm else int(1.5 * math.sin(phase + y * 0.2))
        for x in range(img.width):
            img.putpixel((x, y), stops[i + 1] if frac > bayer(x + shift, y) else stops[i])
    for k in range(90 if not calm else 130):
        sx = rng.randrange(0, W)
        sy = rng.randrange(y0 + 2, max(y1 - 2, y0 + 3))
        tw = math.sin(phase * 2 + k * 1.7)
        if tw > 0.2:
            put(img, sx, sy, c("sea_foam"))
            if tw > 0.75:
                put(img, sx + 1, sy, c("sea_foam"))
    for row in range(3):
        y = y0 + int(h * (0.25 + row * 0.28))
        drift = int(phase * 14) % 24
        x = -drift + row * 7
        while x < W:
            seg = 5 + (row * 3 + x) % 8
            if (x // 16 + row) % 2 == 0:
                for i2 in range(seg):
                    put(img, x + i2, y, c("sea_foam"))
                    if bayer(x + i2, y + 1) < 0.4:
                        put(img, x + i2, y + 1, mix(c("sea_foam"), stops[-1], 0.5))
            x += seg + 11
    return img


def crampotte(img, x, y_base, w, h, rng, timber="red"):
    """Maison de pêcheur basque : façade blanche, toit rouge, poutres, volets."""
    roof_h = max(3, h // 3)
    wall_top = y_base - h + roof_h
    tc = c(timber)
    for yy in range(h - roof_h):
        for xx in range(w):
            shade = xx > w - 3 or yy > h - roof_h - 2
            put(img, x + xx, wall_top + yy, c("cream_shade") if shade and bayer(xx, yy) < 0.5 else c("white"))
    for yy in range(roof_h):
        half = (w // 2 + 1) * (yy + 1) / roof_h
        for xx in range(-1, w + 1):
            if abs(xx - w // 2) <= half:
                color = c("roof") if yy > 0 else c("red_dark")
                if xx - (w // 2 - half) < 2:
                    color = mix(c("roof"), c("white"), 0.25)
                put(img, x + xx, y_base - h + yy, color)
    for yy in range(h - roof_h):
        put(img, x, wall_top + yy, tc)
        put(img, x + w - 1, wall_top + yy, tc)
    beam_y = wall_top + (h - roof_h) // 2
    for xx in range(w):
        put(img, x + xx, beam_y, tc)
    door_x = x + w // 2 - 1
    for yy in range(min(5, h - roof_h - 1)):
        put(img, door_x, y_base - 1 - yy, c("wood_dark"))
        put(img, door_x + 1, y_base - 1 - yy, c("wood"))
    for xx in range(2, w - 3, 5):
        wy = beam_y + 2
        put(img, x + xx, wy, c("sky_night"))
        put(img, x + xx + 1, wy, c("sky_night"))
        put(img, x + xx - 1, wy, tc)
        put(img, x + xx + 2, wy, tc)


def bunting(img, x0, x1, y, phase=0.0):
    """Guirlande de fanions rouge/blanc/vert."""
    cols = [c("red"), c("white"), c("green")]
    x = x0
    i = 0
    while x < x1 - 4:
        sag = int(2 * math.sin((x - x0) / max(x1 - x0, 1) * math.pi))
        yy = y + sag
        put(img, x, yy, c("outline"))
        put(img, x + 1, yy, c("outline"))
        flap = int(math.sin(phase * 3 + i) > 0.3)
        color = cols[i % 3]
        for k in range(3):
            for m in range(3 - k):
                put(img, x + m + (1 if flap and k > 0 else 0), yy + 1 + k, color)
        x += 6
        i += 1


def small_lighthouse(img, x, y_base, h=24):
    for yy in range(h):
        wq = 3 if yy < h * 0.5 else 4
        for xx in range(-wq // 2, wq // 2 + 1):
            color = c("white") if xx < wq // 2 else c("cream_shade")
            put(img, x + xx, y_base - h + yy, color)
    for xx in range(-3, 4):
        put(img, x + xx, y_base - h, c("black"))
        put(img, x + xx, y_base - h + 1, c("black"))
    put(img, x, y_base - h - 1, c("gold"))
    put(img, x, y_base - h - 2, c("gold"))


def villa_belza(img, x, y_base):
    """La Villa Belza : silhouette sombre, tour ronde à toit pointu."""
    rect(img, x, y_base - 16, x + 14, y_base, c("outline"))
    rect(img, x + 2, y_base - 13, x + 4, y_base - 10, c("gold"))
    rect(img, x + 8, y_base - 13, x + 10, y_base - 10, c("gold"))
    rect(img, x + 12, y_base - 22, x + 19, y_base, c("outline"))
    for k in range(6):
        hline(img, x + 12 + k // 2, x + 19 - k // 2, y_base - 22 - k, c("sky_night"))
    put(img, x + 15, y_base - 29, c("sky_night"))


def save_frames(base_fn, name, frames=3):
    """Génère n frames (la mer bouge) et retourne la frame 0 (preview)."""
    first = None
    for f in range(frames):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        base_fn(img, f * (2 * math.pi / frames))
        img.save(os.path.join(OUT, f"{name}_{f}.png"))
        if first is None:
            first = img
    return first


# ================================================================= DÉCORS

def beach(img, phase):
    rng = random.Random(7)
    ramp(img, 0, 92, [c("sky_high"), mix(c("sky_high"), c("sky_low"), 0.5), c("sky_low"), mix(c("sky_low"), c("white"), 0.35)])
    sun(img, 42, 22, 7)
    cloud2(img, 90, 14, 36, rng)
    cloud2(img, 200, 30, 24, rng)
    cloud2(img, 268, 10, 30, rng)
    draw_sea(img, 92, 124, phase)
    hill(img, 220, 336, 74, 94, mix(c("green_dark"), c("sky_low"), 0.45), 1.5, 3)
    hill(img, 248, 340, 68, 96, c("green_dark"), 2.0, 4)
    small_lighthouse(img, 296, 74, 22)
    rect(img, 262, 84, 268, 92, mix(c("white"), c("sky_low"), 0.2))
    rect(img, 272, 86, 280, 93, mix(c("roof"), c("sky_low"), 0.3))
    edge = 124
    for x in range(W):
        wob = int(2.2 * math.sin(phase + x * 0.12))
        for k in range(2):
            put(img, x, edge + wob + k, c("sea_foam"))
        for k in range(2, 5):
            put(img, x, edge + wob + k, mix(c("sand_shade"), c("sea_turquoise"), 0.35))
    ramp(img, 129, 180, [mix(c("sand"), c("sand_shade"), 0.5), c("sand"), c("sand"), mix(c("sand"), c("sand_shade"), 0.3)])
    speckle(img, 0, 134, W, 180, c("sand_shade"), 0.045, rng)
    speckle(img, 0, 150, W, 180, c("sand_dark"), 0.012, rng)
    for k in range(6):
        y = 138 + k * 7
        for x in range(0, W, 2):
            if bayer(x, y) < 0.4:
                put(img, x + int(3 * math.sin(x * 0.05 + k)), y, c("sand_shade"))
    for px_, colr in [(28, "red"), (120, "green"), (208, "orange"), (288, "red")]:
        put(img, px_, 131, c("outline"))
        put(img, px_, 130, c("outline"))
        for dx in range(-3, 4):
            put(img, px_ + dx, 129 - abs(dx) // 2, c(colr) if (dx + 3) % 2 == 0 else c("white"))
    for tx, ty, colr in [(60, 134, "red"), (170, 133, "sea_turquoise"), (250, 135, "gold")]:
        rect(img, tx, ty, tx + 6, ty + 2, c(colr))


def surf(img, phase):
    rng = random.Random(11)
    ramp(img, 0, 88, [c("sky_high"), mix(c("sky_high"), c("sky_dawn"), 0.4), c("sky_dawn"), mix(c("sky_dawn"), c("gold"), 0.4)])
    sun(img, 258, 30, 9)
    cloud2(img, 40, 18, 34, rng)
    cloud2(img, 150, 36, 22, rng)
    draw_sea(img, 88, 180, phase, stops=[mix(c("sea_mid"), c("sky_dawn"), 0.25), c("sea_mid"), c("sea_deep")])
    rock_mass(img, 252, 348, 46, 118, mix(c("earth"), c("sky_dawn"), 0.35), mix(c("sand_shade"), c("sky_dawn"), 0.3), mix(c("wood_dark"), c("sky_dawn"), 0.3), 6)
    rock_mass(img, 274, 352, 58, 132, c("earth"), c("sand_shade"), c("wood_dark"), 7)
    hill(img, 276, 352, 52, 64, c("leaf_dark"), 1.2, 8)
    villa_belza(img, 286, 52)


def fishing(img, phase):
    rng = random.Random(13)
    ramp(img, 0, 80, [mix(c("sky_high"), c("sky_dawn"), 0.2), c("sky_low"), c("sky_dawn")])
    cloud2(img, 60, 12, 30, rng)
    cloud2(img, 210, 22, 26, rng)
    ground_y = 82
    hline(img, 0, W, ground_y - 1, c("rock_light"))
    xs = 2
    while xs < 208:
        wq = rng.randint(13, 19)
        hq = rng.randint(20, 30)
        crampotte(img, xs, ground_y, min(wq, 206 - xs), hq, rng, "red" if rng.random() < 0.72 else "green")
        xs += wq + rng.randint(1, 3)
    draw_sea(img, 82, 180, phase, stops=[mix(c("sea_mid"), c("sky_dawn"), 0.3), c("sea_mid"), c("sea_deep")], calm=True)
    rock_mass(img, 206, 336, 70, 112, c("rock"), c("rock_light"), c("rock_dark"), 9)
    small_lighthouse(img, 294, 80, 16)
    for bx, colr in [(150, "red"), (196, "green"), (240, "white")]:
        by = 116 + int(1.5 * math.sin(phase + bx))
        for k in range(3):
            hline(img, bx + k, bx + 22 - k, by + k, c(colr) if k < 2 else c("outline"))
        hline(img, bx + 2, bx + 20, by - 1, c("white"))
        for k in range(10):
            put(img, bx + 11, by - 2 - k, c("outline"))
        put(img, bx + 12, by - 11, c("red"))
        put(img, bx + 13, by - 11, c("red"))
        for k in range(4):
            off = int(2 * math.sin(phase * 2 + k))
            hline(img, bx + 4 + off, bx + 18 + off, by + 4 + k * 2, mix(c(colr), c("sea_deep"), 0.55))
    deck_y = 148
    for y in range(deck_y, 180):
        for x in range(0, W):
            plank = ((x + (y - deck_y) * 2) // 16) % 2
            base = c("wood") if plank else mix(c("wood"), c("wood_dark"), 0.35)
            if (y - deck_y) % 7 == 6:
                base = c("wood_dark")
            put(img, x, y, base)
    hline(img, 0, W, deck_y, c("cream_shade"))
    hline(img, 0, W, deck_y + 1, c("wood_dark"))
    for px_ in (30, 150, 270):
        rect(img, px_, deck_y - 10, px_ + 4, deck_y, c("wood_dark"))
        rect(img, px_, deck_y - 12, px_ + 4, deck_y - 10, c("outline"))


def rock(img, phase):
    rng = random.Random(17)
    ramp(img, 0, 88, [c("sky_high"), mix(c("sky_high"), c("sky_low"), 0.5), c("sky_low")])
    cloud2(img, 30, 16, 32, rng)
    cloud2(img, 180, 8, 38, rng)
    cloud2(img, 262, 28, 22, rng)
    draw_sea(img, 88, 180, phase, stops=[c("sea_deep"), c("sea_mid"), mix(c("sea_mid"), c("sea_foam"), 0.18)])
    hill(img, -30, 70, 70, 88, mix(c("green_dark"), c("sky_low"), 0.55), 1.0, 2)
    rock_mass(img, 236, 330, 40, 150, c("rock"), c("rock_light"), c("rock_dark"), 21)
    rock_mass(img, 200, 250, 96, 160, c("rock_dark"), c("rock"), c("outline"), 22)
    sx, sy = 282, 34
    for yy in range(12):
        wq = 2 if yy < 3 else 3
        for xx in range(-wq // 2, wq // 2 + 1):
            put(img, sx + xx, sy + yy, c("white"))
    put(img, sx - 2, sy + 4, c("white"))
    put(img, sx + 2, sy + 4, c("white"))
    put(img, sx, sy - 1, c("gold"))
    rect(img, sx - 4, sy + 12, sx + 5, sy + 16, c("rock_light"))
    rect(img, sx - 2, sy + 16, sx + 3, sy + 20, c("rock"))
    deck_y2 = 108
    hline(img, 150, 240, deck_y2, c("white"))
    hline(img, 150, 240, deck_y2 + 1, c("rock_light"))
    for ax in range(150, 240, 22):
        for t in range(22):
            arch_y = deck_y2 + 2 + int(8 * math.sin(t / 21 * math.pi))
            put(img, ax + t, arch_y, c("white"))
    for px_ in range(152, 240, 8):
        put(img, px_, deck_y2 - 1, c("white"))
        put(img, px_, deck_y2 - 2, c("white"))
    for k in range(26):
        ex = 230 + rng.randrange(0, 70)
        ey = 96 + rng.randrange(0, 30)
        if math.sin(phase * 2 + k) > 0.3:
            put(img, ex, ey, c("sea_foam"))


def espadrille(img, phase):
    rng = random.Random(19)
    ramp(img, 0, 98, [c("sky_high"), mix(c("sky_high"), c("sky_low"), 0.5), c("sky_low"), mix(c("sky_low"), c("white"), 0.3)])
    sun(img, 60, 20, 6)
    cloud2(img, 130, 22, 30, rng)
    cloud2(img, 240, 12, 26, rng)
    draw_sea(img, 98, 156, phase, stops=[c("sea_mid"), c("sea_turquoise"), mix(c("sea_turquoise"), c("sea_foam"), 0.25)])
    rock_mass(img, -40, 72, 26, 150, c("rock"), c("rock_light"), c("rock_dark"), 31)
    rock_mass(img, 246, 356, 40, 150, c("rock"), c("rock_light"), c("rock_dark"), 32)
    hill(img, -30, 70, 22, 30, c("leaf_dark"), 1.0, 33)
    xs = 2
    for _ in range(3):
        crampotte(img, xs, 26, 13, 12, rng, "red")
        xs += 15
    for x in range(W):
        top = 150 + int(8 * math.sin(x / W * math.pi)) - 4
        for y in range(top, 180):
            wet = y - top < 3
            base = mix(c("sand_shade"), c("sea_turquoise"), 0.4) if wet else (c("sand") if bayer(x, y) > 0.25 else c("sand_shade"))
            put(img, x, y, base)
    for y in range(140, 180, 4):
        rect(img, 0, y, 46 - (y - 140), y + 4, c("rock_light") if (y // 4) % 2 else c("rock"))
    bunting(img, 6, 314, 8, phase)


def lighthouse_bg():
    tall_h = 1100
    img = Image.new("RGBA", (W, tall_h), (0, 0, 0, 0))
    rng = random.Random(23)
    ramp(img, 0, tall_h, [mix(c("sky_night"), c("sky_high"), 0.5), c("sky_high"), mix(c("sky_high"), c("sky_low"), 0.5), c("sky_low"), c("sky_dawn")])
    for _ in range(40):
        x, y = rng.randrange(0, W), rng.randrange(0, 180)
        put(img, x, y, c("white"))
    for k in range(18):
        y = 240 + int((tall_h - 420) * (k / 18) ** 0.8)
        cloud2(img, rng.randrange(-10, W - 20), y, rng.randint(22, 46), rng)
    for _ in range(8):
        x, y = rng.randrange(20, W - 20), rng.randrange(260, tall_h - 300)
        put(img, x, y, c("outline")); put(img, x + 1, y - 1, c("outline")); put(img, x + 2, y, c("outline"))
        put(img, x + 3, y - 1, c("outline")); put(img, x + 4, y, c("outline"))
    draw_sea(img, tall_h - 130, tall_h - 62, 0.9)
    rect(img, 0, tall_h - 62, W, tall_h, c("leaf_dark"))
    speckle(img, 0, tall_h - 60, W, tall_h, c("leaf"), 0.22, rng)
    for bx in range(6, W, 34):
        for k in range(5):
            hline(img, bx + k, bx + 16 - k, tall_h - 52 - k, c("leaf"))
        rect(img, bx + 7, tall_h - 47, bx + 9, tall_h - 42, c("wood_dark"))
    x_c, half_top, half_base = 160, 24, 34
    for y in range(64, tall_h - 50):
        t = (y - 64) / (tall_h - 114)
        half = int(half_top + (half_base - half_top) * t)
        for x in range(x_c - half, x_c + half):
            u = (x - (x_c - half)) / (2 * half)
            if u < 0.16:
                color = c("white")
            elif u < 0.75:
                color = c("white") if bayer(x, y) > u * 0.6 else c("cream")
            else:
                color = c("cream_shade") if bayer(x, y) > 0.3 else c("cream")
            put(img, x, y, color)
        put(img, x_c - half, y, c("cream_shade"))
        put(img, x_c + half - 1, y, c("outline"))
    for ring_y in range(150, tall_h - 80, 150):
        hline(img, x_c - half_base, x_c + half_base, ring_y, c("cream_shade"))
        hline(img, x_c - half_base, x_c + half_base, ring_y + 1, c("rock_light"))
    for wy in range(130, tall_h - 100, 75):
        rect(img, x_c - 2, wy, x_c + 3, wy + 8, c("black"))
        rect(img, x_c - 2, wy, x_c + 3, wy + 2, c("sky_night"))
    gal_y = 58
    rect(img, x_c - 32, gal_y, x_c + 32, gal_y + 6, c("black"))
    for gx in range(x_c - 30, x_c + 30, 4):
        rect(img, gx, gal_y - 6, gx + 1, gal_y, c("black"))
    rect(img, x_c - 20, gal_y - 26, x_c + 20, gal_y - 6, c("black"))
    rect(img, x_c - 14, gal_y - 22, x_c + 14, gal_y - 10, c("gold"))
    rect(img, x_c - 14, gal_y - 22, x_c + 14, gal_y - 18, mix(c("gold"), c("white"), 0.5))
    for k in range(3):
        hline(img, x_c - 26 + k * 2, x_c - 8, gal_y - 30 + k, c("black"))
    for k in range(40):
        put(img, x_c + 20 + k, gal_y - 16 - k // 5, mix(c("gold"), c("white"), 0.4))
        put(img, x_c + 20 + k, gal_y - 15 - k // 5, c("gold"))
    img.save(os.path.join(OUT, "bg_lighthouse.png"))
    return img


def hub_map(img, phase):
    rng = random.Random(29)

    def coast_x(y):
        return int(158 - 66 * math.sin(y / H * 2.7) + 48 * (y / H))

    draw_sea(img, 0, H, phase, stops=[c("sea_deep"), c("sea_mid"), c("sea_mid")])
    for y in range(H):
        cx = coast_x(y)
        for x in range(max(cx - 2, 0), min(cx + 7, W)):
            put(img, x, y, c("sand") if x > cx else c("sea_foam"))
        for x in range(cx + 7, W):
            put(img, x, y, c("leaf") if bayer(x, y) > 0.2 else mix(c("leaf"), c("leaf_dark"), 0.6))
    for y in range(28, 74):
        cx = coast_x(y)
        rect(img, cx, y, min(cx + 13, W), y + 1, c("sand"))
    for y in range(150, 180):
        cx = coast_x(y)
        rect(img, cx, y, min(cx + 10, W), y + 1, c("sand"))
    for _ in range(150):
        x = rng.randrange(0, W - 6)
        y = rng.randrange(6, H - 8)
        cx = coast_x(y)
        if x > cx + 16 and rng.random() < 0.9:
            wq = rng.randint(3, 5)
            rect(img, x, y + 2, x + wq, y + 4, c("white"))
            for k in range(2):
                hline(img, x - 1 + k, x + wq + 1 - k, y + k, c("roof") if rng.random() < 0.8 else c("rock_light"))
    for y in range(0, H, 2):
        x = coast_x(y) + 24 + int(6 * math.sin(y * 0.08))
        put(img, x, y, c("cream")); put(img, x + 1, y, c("cream"))
    for x in range(80, W, 2):
        y = 118 + int(10 * math.sin(x * 0.03))
        cx = coast_x(y)
        if x > cx + 10:
            put(img, x, y, c("cream")); put(img, x, y + 1, c("cream"))
    for y in range(H):
        cx = coast_x(y)
        if math.sin(phase + y * 0.5) > -0.2:
            put(img, cx - 1, y, c("sea_foam"))
        if math.sin(phase + y * 0.5) > 0.55:
            put(img, cx - 3, y, c("sea_foam"))
    small_lighthouse(img, 268, 34, 26)
    hill(img, 250, 292, 30, 36, c("leaf_dark"), 1.0, 41)
    gp = coast_x(48)
    put(img, gp + 6, 44, c("outline")); put(img, gp + 6, 43, c("outline"))
    for dx in range(-4, 5):
        put(img, gp + 6 + dx, 42 - abs(dx) // 2, c("red") if (dx + 4) % 2 == 0 else c("white"))
    hx, hy = 190, 96
    rect(img, hx, hy, hx + 26, hy + 14, c("brick"))
    for k in range(5):
        hline(img, hx - 1 + k, hx + 27 - k, hy - 5 + k, c("roof"))
    rect(img, hx + 4, hy + 4, hx + 22, hy + 12, c("rock_light"))
    rect(img, hx + 11, hy + 6, hx + 15, hy + 14, c("wood_dark"))
    rock_mass(img, 58, 92, 84, 112, c("rock"), c("rock_light"), c("rock_dark"), 42)
    put(img, 74, 78, c("white")); put(img, 74, 79, c("white")); put(img, 74, 80, c("white"))
    put(img, 73, 79, c("white")); put(img, 75, 79, c("white"))
    hline(img, 90, coast_x(96), 98, c("white"))
    pp = coast_x(84)
    crampotte(img, pp + 6, 86, 12, 10, rng, "red")
    crampotte(img, pp + 20, 88, 11, 9, rng, "green")
    pv = coast_x(126)
    for y in range(120, 134):
        rect(img, pv - 3, y, pv + 8, y + 1, c("sand"))
    villa_belza(img, coast_x(158) + 10, 160)


def menu(img, phase):
    rng = random.Random(31)
    ramp(img, 0, 104, [c("sky_high"), mix(c("sky_high"), c("sky_dawn"), 0.35), c("sky_dawn"), mix(c("sky_dawn"), c("gold"), 0.3)])
    sun(img, 250, 34, 10)
    cloud2(img, 30, 20, 40, rng)
    cloud2(img, 150, 10, 28, rng)
    cloud2(img, 210, 44, 24, rng)
    draw_sea(img, 104, 152, phase, stops=[mix(c("sea_mid"), c("sky_dawn"), 0.2), c("sea_mid"), c("sea_turquoise")])
    hill(img, 196, 340, 58, 106, mix(c("green_dark"), c("sky_dawn"), 0.4), 1.4, 51)
    small_lighthouse(img, 288, 62, 26)
    xs = 0
    while xs < 160:
        wq = rng.randint(14, 20)
        hq = rng.randint(18, 30)
        crampotte(img, xs, 112, wq, hq, rng, "red" if rng.random() < 0.7 else "green")
        xs += wq + rng.randint(1, 3)
    for x in range(W):
        wob = int(2 * math.sin(phase + x * 0.1))
        put(img, x, 152 + wob, c("sea_foam"))
        put(img, x, 153 + wob, mix(c("sand_shade"), c("sea_turquoise"), 0.4))
    ramp(img, 155, 180, [mix(c("sand"), c("sand_shade"), 0.4), c("sand")])
    speckle(img, 0, 158, W, 180, c("sand_shade"), 0.04, rng)
    bunting(img, 4, 316, 4, phase)


def main():
    previews = []
    for fn, name in [(beach, "play_beach_run"), (surf, "play_surf"), (fishing, "play_fishing"),
                     (rock, "play_rock_crossing"), (espadrille, "play_espadrille")]:
        previews.append((name, save_frames(fn, name)))
        print("décor animé :", name)
    tall = lighthouse_bg()
    print("décor : bg_lighthouse")

    sheet = Image.new("RGBA", (W * 2 * 2, H * 2 * ((len(previews) + 1) // 2)), (20, 20, 30, 255))
    for idx, (name, img) in enumerate(previews):
        scaled = img.resize((W * 2, H * 2), Image.NEAREST)
        sheet.alpha_composite(scaled, ((idx % 2) * W * 2, (idx // 2) * H * 2))
    sheet.save(os.path.join(SCRATCH, "bg_preview.png"))
    tall.save(os.path.join(SCRATCH, "bg_lighthouse_preview.png"))


if __name__ == "__main__":
    main()
