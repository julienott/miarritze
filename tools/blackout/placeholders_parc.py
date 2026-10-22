#!/usr/bin/env python3
"""Placeholders du décor du Parc Mazon, dessinés par le code (formes et couleurs simples, contour bleu
marine épais, vue 3/4 de face comme le reste du décor), en attendant les images du backlog.

Appelé par tools/blackout/make_parc_mazon.py (catalogue CAT) ; écrit dans assets/maps/parc_mazon/decor/ :
- sols/<id>.png : tuiles raccordables de 2 × 2 cases (256 px) ;
- objets/<id>.png : 128 px par case d'emprise, hauteur = emprise + débord (même échelle que les images
  intégrées par integre_decor.py) ;
- masques/<id>/masks.json + occluder.png (format de tools/blackout/masques_pf.py, lus par BkDecor) pour
  les objets qui cachent la vue ou qu'on doit contourner au plus juste : emprise au sol (`polygons`,
  base de l'objet), ligne de tri (`back_y`), partie qui masque un perso derrière (`occluder.png`).
  Les objets bas sans masques prennent la forme calculée par le jeu sur la silhouette.
N'écrit un fichier que s'il a changé (pas de réimport inutile).
"""
import io
import json
import math
import os
import random

from PIL import Image, ImageDraw

PX = 128                   # px par case dans l'image
SS = 2                     # sur-échantillonnage (bords lissés)
NAVY = (29, 34, 48, 255)
OUT_W = 6                  # épaisseur du contour (px de l'image)
ORANGE = (240, 138, 46, 255)
ORANGE_D = (196, 98, 26, 255)
WHITE = (255, 255, 255, 255)


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def dark(c, k=0.75):
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), c[3])


class Pen:
    """Dessin en coordonnées de l'image finale, sur une toile SS fois plus grande."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def _b(self, box):
        return [v * SS for v in box]

    @staticmethod
    def _f(fill):
        # Un remplissage transparent effacerait les pixels (PIL ne compose pas) : contour seul.
        return None if fill is not None and len(fill) == 4 and fill[3] == 0 else fill

    def rect(self, box, fill, r=8, outline=True, width=OUT_W):
        self.d.rounded_rectangle(self._b(box), radius=r * SS, fill=self._f(fill),
                                 outline=NAVY if outline else None, width=width * SS if outline else 0)

    def ell(self, box, fill, outline=True, width=OUT_W):
        self.d.ellipse(self._b(box), fill=self._f(fill), outline=NAVY if outline else None, width=width * SS if outline else 0)

    def poly(self, pts, fill, outline=True, width=OUT_W):
        p = [(x * SS, y * SS) for (x, y) in pts]
        self.d.polygon(p, fill=fill)
        if outline:
            self.d.line(p + [p[0]], fill=NAVY, width=width * SS, joint="curve")

    def line(self, pts, fill=NAVY, width=OUT_W):
        self.d.line([(x * SS, y * SS) for (x, y) in pts], fill=fill, width=width * SS, joint="curve")

    def dot(self, x, y, r, fill):
        self.d.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=fill)

    def image(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)


# ------------------------------------------------------------------------------------------- objets
# Chaque dessin reçoit (p: Pen, w, h, deb, el) en cases et rend l'emprise au sol (polygone, px de l'image)
# ou None (forme calculée par le jeu).

def _foot_rect(W_, H_, h, mx=0.08, top=0.15, bot=0.03):
    """Emprise : bande du bas sur les cases de l'objet (marges en part de case)."""
    y0 = H_ - h * PX + top * PX
    return [(mx * PX, y0), (W_ - mx * PX, y0), (W_ - mx * PX, H_ - bot * PX), (mx * PX, H_ - bot * PX)]


def _ellipse_pts(cx, cy, rx, ry, n=20):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _feuilles(p, cx, cy, r, base, rng, n=6):
    """Couronne en grappe de cercles : ombre, masse, reflets."""
    blobs = [(cx + r * 0.55 * math.cos(a), cy + r * 0.45 * math.sin(a)) for a in
             [rng.uniform(0, 2 * math.pi) for _ in range(n)]]
    for (x, y) in blobs:
        rr = r * rng.uniform(0.45, 0.6)
        p.ell([x - rr, y - rr, x + rr, y + rr], base)
    p.ell([cx - r * 0.62, cy - r * 0.58, cx + r * 0.62, cy + r * 0.5], base)
    # Recouvre les contours intérieurs : grosse masse sans contour, puis taches claires.
    for (x, y) in blobs:
        rr = r * rng.uniform(0.38, 0.5)
        p.ell([x - rr, y - rr, x + rr, y + rr], base, outline=False)
    p.ell([cx - r * 0.55, cy - r * 0.5, cx + r * 0.55, cy + r * 0.45], base, outline=False)
    hl = (min(255, base[0] + 40), min(255, base[1] + 45), min(255, base[2] + 30), 255)
    for _ in range(4):
        x = cx + rng.uniform(-0.5, 0.2) * r
        y = cy + rng.uniform(-0.55, 0.0) * r
        rr = r * rng.uniform(0.12, 0.2)
        p.ell([x - rr, y - rr * 0.8, x + rr, y + rr * 0.8], hl, outline=False)
    sh = dark(base, 0.72)
    p.d.chord([(cx - r * 0.7) * SS, (cy - r * 0.1) * SS, (cx + r * 0.7) * SS, (cy + r * 0.62) * SS], 20, 160, fill=sh)


def d_arbre(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    cx = W_ / 2
    # Tronc et racines.
    p.ell([cx - 70, H_ - 46, cx + 70, H_ - 8], rgba("8a6a48"))
    p.rect([cx - 34, H_ - 230, cx + 34, H_ - 22], rgba("cfc29a"), r=14)
    for (x, y, rr) in ((cx - 14, H_ - 160, 12), (cx + 12, H_ - 110, 14), (cx - 8, H_ - 60, 10)):
        p.ell([x - rr, y - rr * 0.7, x + rr, y + rr * 0.7], rgba("9aa07a"), outline=False)
    _feuilles(p, cx, (H_ - 150) * 0.5, W_ * 0.62, rgba("4f9a45"), rng, 7)
    return _ellipse_pts(cx, H_ - 34, 82, 30)


def d_buisson(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    _feuilles(p, W_ / 2, H_ - 78, 60, rgba("4b8f3f"), rng, 5)
    for _ in range(3):
        x, y = rng.uniform(30, W_ - 30), rng.uniform(H_ - 130, H_ - 50)
        p.dot(x, y, 5, WHITE)
    return _ellipse_pts(W_ / 2, H_ - 40, 56, 34)


def d_bosquet(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([W_ / 2 - 18, H_ - 300, W_ / 2 + 18, H_ - 150], rgba("a07850"), r=8)
    _feuilles(p, W_ / 2, H_ - 330, 110, rgba("3f8a4a"), rng, 6)
    _feuilles(p, W_ * 0.3, H_ - 110, 85, rgba("4b9b42"), rng, 5)
    _feuilles(p, W_ * 0.7, H_ - 105, 85, rgba("458f3c"), rng, 5)
    for _ in range(5):
        x, y = rng.uniform(40, W_ - 40), rng.uniform(H_ - 150, H_ - 40)
        p.dot(x, y, 9, rgba("e58fc2"))
        p.dot(x + 6, y - 4, 6, rgba("f4b8da"))
    return [(14, H_ - 2 * PX + 50), (W_ - 14, H_ - 2 * PX + 50), (W_ - 10, H_ - 6), (10, H_ - 6)]


def d_massif(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    for i in range(4):
        _feuilles(p, 60 + i * (W_ - 120) / 3, H_ - 80, 66, rgba("4f9744"), rng, 4)
    for _ in range(10):
        x, y = rng.uniform(30, W_ - 30), rng.uniform(H_ - 140, H_ - 40)
        p.dot(x, y, 11, rng.choice([rgba("e58fc2"), rgba("8fb6f0"), rgba("b48fe0")]))
    return [(12, H_ - 100), (W_ - 12, H_ - 100), (W_ - 12, H_ - 8), (12, H_ - 8)]


def d_fronton(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    top = 120
    mid = W_ / 2
    # Mur : chapeau arrondi au centre, épaules de part et d'autre.
    pts = [(16, H_ - 30), (16, top + 120)]
    for i in range(21):
        a = math.pi * i / 20
        pts.append((mid - 340 * math.cos(a), top + 120 - 110 * math.sin(a)))
    pts += [(W_ - 16, top + 120), (W_ - 16, H_ - 30)]
    p.poly(pts, rgba("f0c9b4"))
    p.rect([16, H_ - 70, W_ - 16, H_ - 10], rgba("c79a86"), r=6)             # socle
    p.rect([16, H_ - 190, W_ - 16, H_ - 168], rgba("c8302c"), r=4)           # ligne rouge
    p.line([(16, top + 126), (mid - 340, top + 126)], rgba("2f6b43"), 14)
    p.line([(mid + 340, top + 126), (W_ - 16, top + 126)], rgba("2f6b43"), 14)
    for x in range(120, W_ - 100, 180):
        p.line([(x, top + 170), (x, H_ - 200)], rgba("e2b7a1"), 6)
    # Drapeau basque au sommet.
    p.line([(mid, top + 12), (mid, top - 110)], NAVY, 8)
    p.rect([mid, top - 110, mid + 120, top - 40], rgba("d8302c"), r=4)
    p.line([(mid, top - 110), (mid + 120, top - 40)], rgba("2f8a4a"), 12)
    p.line([(mid, top - 40), (mid + 120, top - 110)], rgba("2f8a4a"), 12)
    p.line([(mid + 60, top - 110), (mid + 60, top - 40)], WHITE, 10)
    p.line([(mid, top - 75), (mid + 120, top - 75)], WHITE, 10)
    return [(16, H_ - 92), (W_ - 16, H_ - 92), (W_ - 16, H_ - 8), (16, H_ - 8)]


def d_maison(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    roof_h = (deb + 0.6) * PX
    wall_top = roof_h - 20
    p.rect([14, wall_top, W_ - 14, H_ - 8], rgba("f6f2ea"), r=6)
    # Colombages rouges.
    for x in (14 + 30, W_ / 2, W_ - 44):
        p.line([(x, wall_top + 10), (x, H_ - 20)], rgba("a8231f"), 10)
    p.line([(20, wall_top + (H_ - wall_top) * 0.45), (W_ - 20, wall_top + (H_ - wall_top) * 0.45)], rgba("a8231f"), 10)
    # Porte, fenêtres et volets.
    dw = min(80, W_ * 0.2)
    p.rect([W_ / 2 - dw / 2, H_ - 150, W_ / 2 + dw / 2, H_ - 10], rgba("b3261e"), r=10)
    for x in (W_ * 0.22, W_ * 0.78):
        p.rect([x - 34, wall_top + 40, x + 34, wall_top + 100], rgba("8fc4e8"), r=4)
        p.rect([x - 58, wall_top + 40, x - 34, wall_top + 100], rgba("c22c24"), r=3)
        p.rect([x + 34, wall_top + 40, x + 58, wall_top + 100], rgba("c22c24"), r=3)
    # Toit de tuiles rouges à deux pentes inégales.
    ridge = W_ * 0.42
    p.poly([(4, roof_h), (ridge, 16), (W_ - 4, roof_h - 6), (W_ - 4, roof_h + 16), (4, roof_h + 16)], rgba("d0533a"))
    for k in range(1, 4):
        y = 16 + (roof_h - 16) * k / 4
        p.line([(4 + (ridge - 4) * (1 - k / 4), y), (W_ - 4 - (W_ - 4 - ridge) * (1 - k / 4), y)], rgba("a83a28"), 5)
    return _foot_rect(W_, H_, h, 0.06, 0.2, 0.04)


def d_kiosque(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    cx = W_ / 2
    base_top = H_ - 5 * PX + 60
    # Base octogonale (dessus clair, face avant en pierre).
    oct_top = [(cx - 200, base_top + 40), (cx - 110, base_top), (cx + 110, base_top), (cx + 200, base_top + 40),
               (cx + 260, base_top + 210), (cx + 200, H_ - 150), (cx - 200, H_ - 150), (cx - 260, base_top + 210)]
    front = [(cx - 260, base_top + 210), (cx - 200, H_ - 150), (cx + 200, H_ - 150), (cx + 260, base_top + 210),
             (cx + 260, base_top + 330), (cx + 200, H_ - 20), (cx - 200, H_ - 20), (cx - 260, base_top + 330)]
    p.poly(front, rgba("d9c9a8"))
    p.poly(oct_top, rgba("efe6cf"))
    for x in (cx - 120, cx, cx + 120):
        p.rect([x - 40, H_ - 110, x + 40, H_ - 60], rgba("c8b48c"), r=4)
    # Colonnes et toit.
    for x in (cx - 220, cx - 110, cx, cx + 110, cx + 220):
        p.rect([x - 9, 250, x + 9, base_top + 170], rgba("2f6b43"), r=4)
    p.poly([(cx, 20), (cx + 300, 250), (cx - 300, 250)], rgba("e8e4dc"))
    for k in range(-2, 3):
        p.poly([(cx, 20), (cx + k * 120 + 60, 250), (cx + k * 120, 250)], rgba("d8302c"), outline=False)
    p.line([(cx, 20), (cx + 300, 250), (cx - 300, 250), (cx, 20)], NAVY, OUT_W)
    p.rect([cx - 310, 244, cx + 310, 272], rgba("2f6b43"), r=6)
    p.line([(cx, 20), (cx, -10)], NAVY, 6)
    for i in range(12):
        x = cx - 280 + i * 51
        p.poly([(x, 276), (x + 40, 276), (x + 20, 306)], rgba("d8302c") if i % 2 else rgba("2f8a4a"), outline=False)
    return [(cx - 255, H_ - 330), (cx - 190, H_ - 390), (cx + 190, H_ - 390), (cx + 255, H_ - 330),
            (cx + 255, H_ - 110), (cx + 195, H_ - 20), (cx - 195, H_ - 20), (cx - 255, H_ - 110)]


def d_buvette(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    top = deb * PX - 10
    p.rect([20, top + 60, W_ - 20, H_ - 8], rgba("e7c48d"), r=8)
    p.rect([60, top + 130, W_ - 60, top + 200], rgba("3b2a1e"), r=6)           # guichet
    p.rect([40, top + 200, W_ - 40, top + 228], rgba("b3743c"), r=4)            # comptoir
    # Store rayé.
    for i in range(8):
        x0 = 10 + i * (W_ - 20) / 8
        p.poly([(x0, top + 40), (x0 + (W_ - 20) / 8, top + 40), (x0 + (W_ - 20) / 8, top + 110), (x0, top + 110)],
               rgba("d8302c") if i % 2 == 0 else WHITE, outline=False)
    p.rect([10, top + 40, W_ - 10, top + 110], (0, 0, 0, 0), r=6)
    # Cornet de glace géant sur le toit.
    cx = W_ / 2
    p.poly([(cx - 50, top + 30), (cx + 50, top + 30), (cx, top + 170)], rgba("e0a85a"))
    p.ell([cx - 70, top - 110, cx + 70, top + 40], rgba("f6b3c8"))
    p.ell([cx - 30, top - 150, cx + 30, top - 90], rgba("d8302c"))
    return _foot_rect(W_, H_, h, 0.08, 0.25, 0.04)


def d_cabane(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    roof = deb * PX
    p.rect([20, roof - 10, W_ - 20, H_ - 8], rgba("3f8a5a"), r=6)
    for x in range(40, W_ - 30, 34):
        p.line([(x, roof + 6), (x, H_ - 16)], rgba("2f6f48"), 5)
    p.rect([W_ * 0.55, H_ - 170, W_ * 0.55 + 80, H_ - 10], rgba("8a5a34"), r=8)
    p.rect([50, roof + 40, 130, roof + 100], rgba("bfe2f0"), r=4)
    p.poly([(6, roof + 10), (W_ * 0.5, 20), (W_ - 6, roof - 10), (W_ - 6, roof + 20), (6, roof + 30)], rgba("6b4e3a"))
    p.line([(W_ - 40, H_ - 12), (W_ - 10, H_ - 170)], rgba("c79a5a"), 8)       # râteau
    return _foot_rect(W_, H_, h, 0.07, 0.25, 0.04)


def d_serre(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    roof = deb * PX + 30
    glass = (190, 232, 240, 150)
    p.rect([16, roof, W_ - 16, H_ - 10], glass, r=6)
    for _ in range(9):
        x = rng.uniform(50, W_ - 50)
        p.ell([x - 26, H_ - 110, x + 26, H_ - 50], rgba("4f9a45"), outline=False)
        p.dot(x + 8, H_ - 90, 9, rgba("d8302c"))
    p.poly([(16, roof), (W_ / 2, 20), (W_ - 16, roof)], glass)
    for x in range(16, W_, 104):
        p.line([(x, roof), (x, H_ - 10)], WHITE, 8)
        p.line([(x, roof), (W_ / 2, 20)], WHITE, 6)
    p.line([(16, roof), (W_ - 16, roof)], WHITE, 8)
    p.rect([16, roof, W_ - 16, H_ - 10], (0, 0, 0, 0), r=6)
    return _foot_rect(W_, H_, h, 0.05, 0.6, 0.04)


def d_chateau(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    body_top = deb * PX + 30
    p.rect([90, body_top, W_ - 90, H_ - 10], rgba("c98f55"), r=8)
    for y in range(int(body_top) + 30, H_ - 20, 34):
        p.line([(96, y), (W_ - 96, y)], rgba("a87240"), 5)
    # Mur d'escalade.
    for _ in range(8):
        x, y = rng.uniform(130, W_ - 130), rng.uniform(body_top + 40, H_ - 120)
        p.ell([x - 10, y - 8, x + 10, y + 8], rng.choice([rgba("e84d4d"), rgba("4da3e8"), rgba("f2c12e"), rgba("6fd06f")]))
    for x0 in (10, W_ - 150):
        p.rect([x0, body_top - 120, x0 + 140, H_ - 10], rgba("d9a066"), r=8)
        p.rect([x0 + 40, body_top - 60, x0 + 100, body_top], rgba("3b2a1e"), r=20)
        p.poly([(x0 - 10, body_top - 116), (x0 + 70, body_top - 300), (x0 + 150, body_top - 116)], rgba("d8302c"))
        p.line([(x0 + 70, body_top - 300), (x0 + 70, body_top - 380)], NAVY, 6)
        p.poly([(x0 + 70, body_top - 380), (x0 + 140, body_top - 355), (x0 + 70, body_top - 330)], rgba("f2c12e"))
    p.line([(150, body_top + 10), (W_ / 2, body_top + 40), (W_ - 150, body_top + 10)], rgba("8a5a34"), 10)
    return _foot_rect(W_, H_, h, 0.03, 0.35, 0.03)


def d_toboggan(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    tx = 30
    p.rect([tx, 150, tx + 200, H_ - 10], rgba("c98f55"), r=8)
    for y in range(190, H_ - 20, 40):
        p.line([(tx + 20, y), (tx + 70, y)], rgba("7a5030"), 6)
    p.line([(tx + 20, 170), (tx + 20, H_ - 12)], rgba("7a5030"), 6)
    p.line([(tx + 70, 170), (tx + 70, H_ - 12)], rgba("7a5030"), 6)
    p.poly([(tx - 16, 160), (tx + 100, 40), (tx + 216, 160)], rgba("2f8a4a"))
    # Toboggan jaune qui descend vers la droite.
    p.poly([(tx + 190, 190), (tx + 240, 190), (W_ - 20, H_ - 60), (W_ - 20, H_ - 12), (W_ - 90, H_ - 12)], rgba("f2c12e"))
    p.line([(tx + 205, 200), (W_ - 60, H_ - 40)], rgba("e0a020"), 8)
    return [(tx + 4, H_ - 150), (tx + 196, H_ - 150), (W_ - 30, H_ - 70), (W_ - 30, H_ - 8), (tx + 4, H_ - 8)]


def d_gradins(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    for k in range(3):
        y0 = 8 + k * 38
        p.rect([10, y0, W_ - 10, y0 + 46], rgba("d6d3cc") if k % 2 == 0 else rgba("c4c1ba"), r=8)
        for x in range(60, W_ - 40, 120):
            p.rect([x, y0 + 10, x + 50, y0 + 22], rgba("d8302c"), r=4, outline=False)
    return None


def d_toile(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    cx, top = W_ / 2, 30
    base = [(20, H_ - 70), (W_ * 0.3, H_ - 14), (W_ * 0.7, H_ - 14), (W_ - 20, H_ - 70), (W_ * 0.7, H_ - 3 * PX + 60), (W_ * 0.3, H_ - 3 * PX + 60)]
    for (x, y) in base:
        p.line([(cx, top + 20), (x, y)], rgba("3f6fd0"), 8)
    for k in (0.35, 0.6, 0.85):
        ring = [(cx + (x - cx) * k, top + 20 + (y - top - 20) * k) for (x, y) in base]
        p.line(ring + [ring[0]], rgba("5f8fe8"), 6)
    p.line([(cx, top), (cx, H_ - 40)], rgba("9aa3b0"), 14)
    p.ell([cx - 22, top - 12, cx + 22, top + 22], rgba("d8302c"))
    return None


def d_plateforme(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([30, 170, W_ - 30, 250], rgba("c98f55"), r=6)
    for x in (44, W_ - 54):
        p.rect([x, 240, x + 20, H_ - 10], rgba("8a5a34"), r=4)
    p.rect([W_ / 2 - 12, 20, W_ / 2 + 12, H_ - 10], rgba("8a5a34"), r=4)
    for y in range(280, H_ - 30, 40):
        p.line([(W_ - 120, y), (W_ - 60, y)], rgba("7a5030"), 6)
    p.line([(W_ / 2, 40), (W_ + 10, 60)], rgba("6b7280"), 6)
    return [(24, H_ - 190), (W_ - 24, H_ - 190), (W_ - 24, H_ - 8), (24, H_ - 8)]


def d_cable(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.line([(0, H_ / 2), (W_, H_ / 2)], rgba("6b7280"), 8)
    cx = W_ * 0.4
    p.ell([cx - 20, H_ / 2 - 20, cx + 20, H_ / 2 + 20], rgba("9aa3b0"))
    p.ell([cx - 34, H_ / 2 + 4, cx + 34, H_ / 2 + 44], rgba("3a3f4a"))
    return None


def d_balancoires(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    top = 40
    for x in (40, W_ - 40):
        p.line([(x, top), (x - 30, H_ - 14)], rgba("8a5a34"), 16)
        p.line([(x, top), (x + 30, H_ - 14)], rgba("8a5a34"), 16)
    p.rect([20, top - 14, W_ - 20, top + 14], rgba("a8703c"), r=6)
    for (x, c) in ((W_ * 0.35, rgba("d8302c")), (W_ * 0.65, rgba("3f6fd0"))):
        p.line([(x - 26, top + 10), (x - 26, H_ - 90)], rgba("6b7280"), 5)
        p.line([(x + 26, top + 10), (x + 26, H_ - 90)], rgba("6b7280"), 5)
        p.rect([x - 40, H_ - 100, x + 40, H_ - 74], c, r=8)
    return None


def d_tourniquet(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    cx, cy = W_ / 2, H_ / 2 + 20
    p.ell([12, cy - 70, W_ - 12, cy + 100], rgba("b8bec8"))
    p.ell([12, cy - 90, W_ - 12, cy + 70], rgba("f2c12e"))
    for k in range(6):
        a0 = k * math.pi / 3
        if k % 2:
            pts = [(cx, cy - 10)] + [(cx + 110 * math.cos(a0 + t * math.pi / 3 / 6), cy - 10 + 74 * math.sin(a0 + t * math.pi / 3 / 6)) for t in range(7)]
            p.poly(pts, rgba("d8302c"), outline=False)
    p.ell([12, cy - 90, W_ - 12, cy + 70], (0, 0, 0, 0))
    for a in (0.3, 2.4, 4.4):
        x, y = cx + 70 * math.cos(a), cy - 10 + 46 * math.sin(a)
        p.line([(x, y), (x, y - 50)], rgba("6b7280"), 8)
    p.ell([cx - 30, cy - 70, cx + 30, cy - 40], rgba("3f6fd0"))
    return None


def d_petit_toboggan(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.ell([30, 50, 200, H_ - 20], rgba("9fb0c8"))                                # l'éléphant
    p.ell([150, 70, 210, 130], rgba("8a9ab8"))
    p.dot(130, 100, 8, NAVY)
    p.poly([(200, 110), (240, 110), (W_ - 16, H_ - 40), (W_ - 16, H_ - 10), (W_ - 70, H_ - 10)], rgba("6fd06f"))
    for y in range(110, H_ - 20, 34):
        p.line([(40, y), (90, y)], rgba("5a6a88"), 6)
    return [(28, H_ - 120), (W_ * 0.62, H_ - 120), (W_ - 24, H_ - 40), (W_ - 24, H_ - 6), (28, H_ - 6)]


def d_ressort(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.ell([24, H_ - 30, W_ - 24, H_ - 6], rgba("8a8f99"))
    for k in range(4):
        y = H_ - 34 - k * 12
        p.ell([46, y - 8, W_ - 46, y + 6], (0, 0, 0, 0), width=5)
    p.poly([(14, 30), (W_ - 14, 30), (W_ - 30, 70), (30, 70)], rgba("3f8ad8"))
    p.rect([28, 18, W_ - 28, 34], rgba("d8302c"), r=4)
    p.dot(W_ / 2, 46, 6, WHITE)
    return None


def d_table(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([20, 8, W_ - 20, 30], rgba("a8703c"), r=6)
    p.rect([10, 34, W_ - 10, 86], WHITE, r=6)
    for x in range(10, W_ - 10, 28):
        for y in (34, 60):
            if (x // 28 + y // 26) % 2 == 0:
                p.d.rectangle([x * SS, y * SS, min(x + 28, W_ - 10) * SS, (y + 26) * SS], fill=rgba("d8302c"))
    p.rect([10, 34, W_ - 10, 86], (0, 0, 0, 0), r=6)
    p.rect([20, 92, W_ - 20, 116], rgba("a8703c"), r=6)
    p.rect([W_ / 2 - 30, 44, W_ / 2 + 30, 76], rgba("c99a5a"), r=8)
    return None


def d_fleurs(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([8, 26, W_ - 8, H_ - 8], rgba("b9b2a3"), r=40)
    p.rect([22, 36, W_ - 22, H_ - 22], rgba("6f5038"), r=30, outline=False)
    for _ in range(14):
        x, y = rng.uniform(40, W_ - 40), rng.uniform(44, H_ - 34)
        c = rng.choice([rgba("e58fc2"), rgba("8fb6f0"), rgba("b48fe0")])
        p.ell([x - 18, y - 15, x + 18, y + 15], c, width=3)
    return None


def d_potager(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([8, 14, W_ - 8, H_ - 8], rgba("a8703c"), r=8)
    p.rect([22, 26, W_ - 22, H_ - 34], rgba("6f5038"), r=6, outline=False)
    for i, x in enumerate(range(44, W_ - 30, 46)):
        if i % 3 == 2:
            p.ell([x - 12, 40, x + 12, 70], rgba("4f9a45"), width=3)
            p.dot(x, 76, 8, rgba("d8302c"))
        else:
            p.ell([x - 20, 36, x + 20, 76], rgba("7fcf5a"), width=3)
    return None


def d_souche(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([26, 40, W_ - 26, H_ - 12], rgba("8a5a34"), r=12)
    p.ell([26, 22, W_ - 26, 64], rgba("e2c08a"))
    p.ell([46, 32, W_ - 46, 54], (0, 0, 0, 0), width=3)
    p.ell([W_ - 40, H_ - 40, W_ - 14, H_ - 18], rgba("d8302c"))
    return None


def d_portillon(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([10, 10, W_ - 10, H_ - 10], rgba("cfc8b8"), r=10)
    for y in range(40, H_ - 20, 40):
        for x in range(30 + (y // 40 % 2) * 20, W_ - 30, 44):
            p.rect([x - 16, y - 12, x + 16, y + 12], rgba("bdb5a3"), r=6, outline=False)
    for x0 in (10, W_ - 52):
        p.rect([x0, 0, x0 + 42, 70], rgba("b9b2a3"), r=6)
    # Battants ouverts vers l'intérieur.
    p.poly([(52, 20), (110, 90), (110, 150), (52, 70)], rgba("2f6b43"))
    p.poly([(W_ - 52, 20), (W_ - 110, 90), (W_ - 110, 150), (W_ - 52, 70)], rgba("2f6b43"))
    p.rect([W_ / 2 - 50, H_ - 70, W_ / 2 + 50, H_ - 30], rgba("6fe08a"), r=10)
    p.line([(W_ / 2 - 20, H_ - 50), (W_ / 2 + 20, H_ - 50)], NAVY, 6)
    p.line([(W_ / 2 + 6, H_ - 62), (W_ / 2 + 20, H_ - 50), (W_ / 2 + 6, H_ - 38)], NAVY, 6)
    return None


# --- cachettes (accent orange)
def d_maisonnette(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([14, 110, W_ - 14, H_ - 8], rgba("fff2c8"), r=10)
    p.poly([(4, 120), (W_ / 2, 30), (W_ - 4, 120)], rgba("d8302c"))
    p.ell([W_ / 2 - 30, H_ - 100, W_ / 2 + 30, H_ - 10], ORANGE)
    p.rect([W_ / 2 - 30, H_ - 60, W_ / 2 + 30, H_ - 10], ORANGE, r=4)
    p.dot(W_ / 2 + 16, H_ - 40, 5, NAVY)
    return _foot_rect(W_, H_, h, 0.1, 0.35, 0.03)


def d_tunnel(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([10, 30, W_ - 10, H_ - 14], ORANGE_D, r=40)
    p.ell([14, 20, W_ - 14, H_ - 10], ORANGE)
    p.ell([36, 42, W_ - 36, H_ - 30], rgba("3a2416"))
    p.ell([24, 26, 50, 44], (255, 220, 170, 255), outline=False)
    return _foot_rect(W_, H_, h, 0.1, 0.4, 0.03)


def d_porte_basse(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([8, 10, W_ - 8, H_ - 8], rgba("c98f55"), r=10)
    p.rect([28, 30, W_ - 28, H_ - 8], ORANGE, r=36)
    for x in range(40, W_ - 30, 16):
        p.line([(x, 46), (x, H_ - 14)], ORANGE_D, 4)
    return _foot_rect(W_, H_, h, 0.08, 0.4, 0.03)


def d_buisson_creux(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    _feuilles(p, W_ / 2, H_ - 96, 66, rgba("3f8a3c"), rng, 5)
    p.ell([W_ / 2 - 30, H_ - 80, W_ / 2 + 30, H_ - 20], rgba("1e3b1c"))
    for _ in range(6):
        p.dot(rng.uniform(26, W_ - 26), rng.uniform(H_ - 170, H_ - 90), 7, ORANGE)
    return _ellipse_pts(W_ / 2, H_ - 44, 56, 36)


def d_tronc_creux(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([18, 90, W_ - 18, H_ - 8], rgba("9a6a40"), r=20)
    p.ell([18, 70, W_ - 18, 120], rgba("e2c08a"))
    p.ell([42, 80, W_ - 42, 108], rgba("6a4426"), width=3)
    p.ell([W_ / 2 - 30, H_ - 90, W_ / 2 + 30, H_ - 14], rgba("2a1a10"))
    p.ell([W_ - 44, 150, W_ - 6, 176], ORANGE)
    return _foot_rect(W_, H_, h, 0.1, 0.35, 0.03)


def d_tipi(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.poly([(W_ / 2, 30), (W_ - 8, H_ - 10), (8, H_ - 10)], rgba("a87a4c"))
    for x in (W_ / 2 - 40, W_ / 2 - 15, W_ / 2 + 15, W_ / 2 + 40):
        p.line([(W_ / 2 + (x - W_ / 2) * 0.1, 10), (x * 1.0 + (x - W_ / 2) * 0.6, H_ - 12)], rgba("6f4a2a"), 6)
    p.line([(W_ / 2 - 30, 90), (W_ / 2 + 30, 90)], ORANGE, 8)
    p.poly([(W_ / 2, H_ - 110), (W_ / 2 + 30, H_ - 10), (W_ / 2 - 30, H_ - 10)], rgba("2a1a10"))
    return _foot_rect(W_, H_, h, 0.12, 0.4, 0.03)


def d_niche(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([8, 40, W_ - 8, H_ - 8], rgba("3f8a3c"), r=14)
    for _ in range(14):
        p.dot(rng.uniform(20, W_ - 20), rng.uniform(52, H_ - 20), 7, rgba("4f9a45"))
    p.rect([30, H_ - 110, W_ - 30, H_ - 8], rgba("1e3b1c"), r=30)
    p.rect([W_ - 40, H_ - 140, W_ - 16, H_ - 106], ORANGE, r=6)
    return _foot_rect(W_, H_, h, 0.06, 0.3, 0.03)


def d_trappe(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([10, 20, W_ - 10, H_ - 10], rgba("2f6b43"), r=8)
    for k in range(-3, 5):
        p.line([(10 + k * 24, H_ - 12), (10 + k * 24 + 80, 22)], rgba("4f8f63"), 5)
    p.rect([10, 20, W_ - 10, H_ - 10], (0, 0, 0, 0), r=8)
    p.rect([W_ / 2 - 14, H_ / 2, W_ / 2 + 14, H_ / 2 + 20], ORANGE, r=4)
    return _foot_rect(W_, H_, h, 0.08, 0.4, 0.03)


def d_malle(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([10, 46, W_ - 10, H_ - 10], rgba("b3261e"), r=8)
    p.rect([6, 30, W_ - 6, 64], rgba("c8302c"), r=14)
    for x in (10, W_ - 30):
        p.rect([x, 46, x + 20, H_ - 10], ORANGE, r=4)
    p.dot(40, 24, 13, rgba("f2ead8"))
    p.dot(70, 20, 13, rgba("f2ead8"))
    p.ell([84, 6, 120, 34], rgba("c9a060"))
    return _foot_rect(W_, H_, h, 0.1, 0.5, 0.03)


def d_roseaux(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.ell([16, H_ - 50, W_ - 16, H_ - 8], rgba("4f8f3f"))
    for i in range(9):
        x = 22 + i * (W_ - 44) / 8
        top = rng.uniform(30, 90)
        p.line([(x, H_ - 20), (x + rng.uniform(-8, 8), top)], rgba("5f9f3f"), 7)
        if i % 2 == 0:
            p.rect([x - 7, top - 8, x + 7, top + 30], rgba("8a5a34"), r=7)
    p.poly([(W_ - 40, 120), (W_ - 10, 112), (W_ - 40, 128)], ORANGE)
    return _ellipse_pts(W_ / 2, H_ - 34, 54, 26)


def d_caisse(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([12, 40, W_ - 12, H_ - 10], rgba("a8703c"), r=6)
    for y in range(58, H_ - 20, 18):
        p.line([(16, y), (W_ - 16, y)], rgba("7a5030"), 4)
    p.rect([6, 24, W_ - 6, 50], ORANGE, r=8)
    p.dot(40, 20, 8, rgba("6fae3f"))
    return _foot_rect(W_, H_, h, 0.1, 0.5, 0.03)


def d_coffre(p, w, h, deb, el, rng):
    W_, H_ = p.w, p.h
    p.rect([10, 44, W_ - 10, H_ - 10], rgba("f2f4f6"), r=10)
    p.rect([6, 26, W_ - 6, 56], ORANGE, r=10)
    p.poly([(W_ / 2 - 14, 74), (W_ / 2 + 14, 74), (W_ / 2, 108)], rgba("e0a85a"))
    p.ell([W_ / 2 - 18, 56, W_ / 2 + 18, 82], rgba("f6b3c8"))
    return _foot_rect(W_, H_, h, 0.1, 0.5, 0.03)


DESSINS = {k[2:]: v for k, v in globals().items() if k.startswith("d_")}


# ------------------------------------------------------------------------------------------- sols
def _tore(p, x, y, fn):
    for ox in (-p.w, 0, p.w):
        for oy in (-p.h, 0, p.h):
            fn(x + ox, y + oy)


def sol(eid, rng):
    p = Pen(2 * PX, 2 * PX)
    S = 2 * PX

    def fond(c):
        p.d.rectangle([0, 0, S * SS, S * SS], fill=c)

    if eid == "pm_sol_gravier":
        fond(rgba("ddd2b8"))
        for _ in range(260):
            x, y, r = rng.uniform(0, S), rng.uniform(0, S), rng.uniform(2, 4.5)
            c = rng.choice([rgba("cbbf9f"), rgba("e8dfc9"), rgba("c4b89a"), rgba("d5ccb6")])
            _tore(p, x, y, lambda a, b: p.dot(a, b, r, c))
    elif eid == "pm_sol_pelouse":
        fond(rgba("8cc46a"))
        for _ in range(120):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            c = rng.choice([rgba("7ab35a"), rgba("9dd27a")])
            _tore(p, x, y, lambda a, b: p.line([(a - 5, b + 4), (a, b - 6), (a + 5, b + 4)], c, 3))
        for _ in range(5):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            _tore(p, x, y, lambda a, b: (p.dot(a, b, 5, WHITE), p.dot(a, b, 2, rgba("f2c12e"))))
    elif eid == "pm_sol_souple":
        fond(rgba("bd6a55"))
        for i in range(4):
            for j in range(4):
                c = rgba("8fa89a") if (i * 7 + j * 3) % 7 == 0 else rgba("c87660")
                p.rect([i * 64 + 3, j * 64 + 3, i * 64 + 61, j * 64 + 61], c, r=10, outline=False)
    elif eid == "pm_sol_cancha":
        fond(rgba("c9cbc8"))
        for k in (0, 128):
            p.line([(k + 1, 0), (k + 1, S)], rgba("b3b5b2"), 3)
            p.line([(0, k + 1), (S, k + 1)], rgba("b3b5b2"), 3)
        for _ in range(6):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            _tore(p, x, y, lambda a, b: p.ell([a - 22, b - 12, a + 22, b + 12], rgba("d3d5d2"), outline=False))
    elif eid == "pm_sol_terre":
        fond(rgba("9c7652"))
        for _ in range(60):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            _tore(p, x, y, lambda a, b: p.dot(a, b, 3, rgba("8a6646")))
        for (x, y) in ((60, 60), (190, 140), (80, 200)):
            p.ell([x - 28, y - 18, x + 28, y + 18], rgba("c9bfa8"), width=3)
    elif eid == "pm_sol_terrasse":
        fond(rgba("d2a066"))
        for y in range(0, S, 32):
            p.line([(0, y + 1), (S, y + 1)], rgba("b0804a"), 3)
            off = (y // 32 % 2) * 64
            for x in range(off, S + 64, 128):
                p.line([(x, y), (x, y + 32)], rgba("b0804a"), 3)
    elif eid == "pm_sable":
        fond(rgba("ecd59a"))
        for _ in range(40):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            _tore(p, x, y, lambda a, b: p.line([(a - 10, b), (a, b - 3), (a + 10, b)], rgba("dcc283"), 3))
        for _ in range(4):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            _tore(p, x, y, lambda a, b: p.dot(a, b, 4, rgba("f6ead0")))
    elif eid == "pm_pont":
        fond(rgba("a8763f"))
        for y in range(0, S, 32):
            p.line([(0, y + 1), (S, y + 1)], rgba("7a5030"), 4)
        for x in (12, S - 12):
            for y in range(16, S, 32):
                p.dot(x, y, 3, rgba("5a3a20"))
    elif eid == "pm_canopee":
        fond(rgba("2f6b35"))
        for _ in range(26):
            x, y, r = rng.uniform(0, S), rng.uniform(0, S), rng.uniform(26, 44)
            c = rng.choice([rgba("3f8040"), rgba("37763a"), rgba("4a8c45")])
            _tore(p, x, y, lambda a, b: p.ell([a - r, b - r, a + r, b + r], c, outline=False))
        for _ in range(16):
            x, y, r = rng.uniform(0, S), rng.uniform(0, S), rng.uniform(8, 14)
            _tore(p, x, y, lambda a, b: p.ell([a - r, b - r, a + r, b + r], rgba("5a9c50"), outline=False))
    elif eid == "pm_haie":
        fond(rgba("3d7d3a"))
        for _ in range(180):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            c = rng.choice([rgba("4a8d44"), rgba("356f33"), rgba("55994d")])
            _tore(p, x, y, lambda a, b: p.dot(a, b, 6, c))
    elif eid == "pm_cloture":
        fond(rgba("2f6b35"))
        for i in range(4):
            for j in range(4):
                p.rect([i * 64 + 6, j * 64 + 6, i * 64 + 58, j * 64 + 58], rgba("b9b2a3"), r=12, outline=False)
                p.dot(i * 64 + 32, j * 64 + 32, 9, rgba("2f4a3a"))
    return p.image()


# ------------------------------------------------------------------------------------------- écriture
def _png_bytes(im):
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return b.getvalue()


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and open(path, "rb").read() == data:
        return False
    with open(path, "wb") as fh:
        fh.write(data)
    return True


def _area(poly):
    a = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        a += x0 * y1 - x1 * y0
    return abs(a) / 2


def dessine_tout(cat, dest):
    n = 0
    for eid, el in cat.items():
        if el.get("reprise"):
            continue
        rng = random.Random(eid)
        if el.get("type") == "tuile_sol":
            n += _write(os.path.join(dest, "sols", eid + ".png"), _png_bytes(sol(eid, rng)))
            continue
        w, h = el["taille"]
        deb = el.get("deb", 0)
        p = Pen(w * PX, int((h + deb) * PX))
        foot = DESSINS[el["dessin"]](p, w, h, deb, el, rng)
        im = p.image()
        n += _write(os.path.join(dest, "objets", eid + ".png"), _png_bytes(im))
        if not el.get("masques") or not foot:
            continue
        alpha = im.getchannel("A")
        sil = sum(1 for a in alpha.getdata() if a >= 128)
        # Emprise ramenée sous 2/3 de la silhouette (le jeu refuse au-delà de decor_masques_pf_part_max) :
        # on la tasse vers l'avant (le bas), la partie haute reste ce qui masque.
        fy = max(y for (_, y) in foot)
        while _area(foot) / max(sil, 1) > 0.64:
            foot = [(x, fy - (fy - y) * 0.92) for (x, y) in foot]
        foot = [(round(x), round(y)) for (x, y) in foot]
        occ = Image.new("RGBA", im.size, (0, 0, 0, 0))
        occ.putalpha(alpha.point(lambda a: 255 if a >= 128 else 0))
        part = _area(foot) / max(sil, 1)
        warnings = []
        if part > 0.68:
            warnings.append(f"emprise = {part:.0%} de la silhouette (plafond du jeu : decor_masques_pf_part_max)")
        back_y = min(y for (_, y) in foot)
        front_y = max(y for (_, y) in foot)
        bloque = el.get("bloque_vue")
        m = {"size": [im.width, im.height], "polygons": [[list(q) for q in foot]], "back_y": back_y,
             "front_y": front_y, "baseline_y": (back_y + front_y) // 2,
             "blocks_view": True if bloque is None else bool(bloque), "camera": "front34", "confidence": 1.0,
             "source": "placeholder (tools/blackout/placeholders_parc.py)", "warnings": warnings}
        md = os.path.join(dest, "masques", eid)
        n += _write(os.path.join(md, "masks.json"), json.dumps(m, ensure_ascii=False, indent=1).encode())
        n += _write(os.path.join(md, "occluder.png"), _png_bytes(occ))
        if warnings:
            print("  ", eid, warnings[0])
    print(f"placeholders : {n} fichiers écrits dans {dest}")
