#!/usr/bin/env python3
"""Sets placeholders (temporaires) des PNJ, animaux et boss qui n'ont pas encore leur rendu pixelforge
(demande de Julien, 23/10 ; GDD-BLACKOUT.md §3.8, §5, §8.1, §8.3, §8.4).

Même format que le moteur B de pixelforge, pour que le jeu les charge sans rien changer (BkPerso) :
  assets/blackout/<famille>/<id>/px32/<élément>_sheet.png   bande horizontale d'images
  assets/blackout/<famille>/<id>/px32/animations.json       images, cadence, boucle par élément
  assets/blackout/<famille>/<id>/px32/set.json              canevas, ligne des pieds, "placeholder": true
Familles : pnj (humains de data/blackout/pnj.json), animaux (même fichier), boss (rules.json → boss).
Rendu : silhouette pixel art simple aux couleurs de la description, contour sombre, 2 à 4 images.
Humain et Intxixu : 32 px dans une case de 64 (pieds à 60) ; boss : 64 px dans une case de 128 (pieds à 120).

Un dossier qui contient déjà un vrai set (set.json sans "placeholder") n'est JAMAIS touché. Quand le vrai
rendu arrive, tools/blackout/integre_persos_v2.py (DEST=pnj, animaux ou boss) remplace tout le dossier px32.

  .venv/bin/python tools/blackout/placeholders_sets.py            tous les manquants
  .venv/bin/python tools/blackout/placeholders_sets.py chat …     seulement ceux-là
  .venv/bin/python tools/blackout/placeholders_sets.py --planche /chemin/planche.png   + planche de contrôle
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "assets", "blackout")
PNJ = json.load(open(os.path.join(ROOT, "data", "blackout", "pnj.json"), encoding="utf-8"))
RULES = json.load(open(os.path.join(ROOT, "data", "blackout", "rules.json"), encoding="utf-8"))

CONTOUR = (20, 16, 28)
CONTOUR_CLAIR = (120, 112, 140)     # contour d'un corps très sombre (chat noir, combinaison)
NOIR = (26, 24, 34)
OEIL = (18, 14, 22)

# ------------------------------------------------------------------ apparences (d'après pnj.json §8.4)
# haut, bas, peau, cheveux, chaussures ; options : robe (vêtement long), short, long (cheveux), petit
# (enfant), motif (rayures|carreaux|fleurs, couleur), chapeau (beret|casquette|couronne|chignon, couleur),
# foulard, ceinture, tablier, bottes, sac (dos), casque, tient (objet en main), dos (objet porté derrière),
# tete_geante (mascotte), ballon, velo.
PEAU = (232, 180, 138)
PEAU2 = (196, 138, 98)
H = {
    "festayre": dict(haut="#f4f1ea", bas="#f4f1ea", cheveux="#3a2618", foulard="#d82020", ceinture="#d82020"),
    "txistulari": dict(haut="#f4f1ea", bas="#f4f1ea", cheveux="#3a2618", chapeau=("beret", "#d02828"),
                       tient="flute"),
    "amona": dict(haut="#24222c", bas="#24222c", robe=True, cheveux="#c4c4cc", chapeau=("chignon", "#c4c4cc"),
                  tient="eventail"),
    "marin": dict(haut="#f4f1ea", motif=("rayures", "#2a4a9a"), bas="#2a3a5a", cheveux="#5a3a20",
                  bottes="#f2c12e", chapeau=("beret", "#1e2a4a")),
    "surfeuse": dict(haut="#1c1c24", bas="#1c1c24", cheveux="#f2e2a0", long=True, peau=PEAU2, dos="planche"),
    "serveur": dict(haut="#f4f1ea", bas="#1c1c24", cheveux="#2a1a10", tablier="#1c1c24", tient="plateau"),
    "sardine": dict(haut="#2a5aa8", bas="#f4f1ea", tete_geante=("sardine", "#b8c8d8")),
    "errege": dict(haut="#b02838", bas="#f4f1ea", tete_geante=("roi", "#e8b48a")),
    "ballon": dict(haut="#f2d020", bas="#2a3a6a", robe=True, petit=True, cheveux="#7a4a20", ballon="#e02828"),
    "trompettiste": dict(haut="#f4f1ea", bas="#f4f1ea", cheveux="#2a1a10", foulard="#d82020", tient="trompette"),
    "glacier": dict(haut="#f4f1ea", motif=("rayures", "#f08ab0"), bas="#f4f1ea", tablier="#f08ab0",
                    chapeau=("casquette", "#f08ab0"), cheveux="#5a3a20"),
    "supporter": dict(haut="#c82828", bas="#2a3a5a", cheveux="#3a2618", foulard="#f4f1ea", maquillage="#d82020"),
    "touriste": dict(haut="#2aa0d8", motif=("fleurs", "#f2d020"), bas="#d8c090", short=True, cheveux="#c89a50",
                     tient="appareil"),
    "jogger": dict(haut="#3ac040", bas="#3ac040", cheveux="#2a1a10", casque="#1c1c24"),
    "ado": dict(haut="#7a3ab0", bas="#2a2a3a", cheveux="#2a1a10", casque="#1c1c24", peau=PEAU2),
    "lecteur": dict(haut="#c8b088", bas="#4a4a52", robe=True, cheveux="#c4c4cc", chapeau=("beret", "#1c1c24"),
                    tient="journal"),
    "promeneuse": dict(haut="#f0c020", bas="#2a2a3a", robe=True, cheveux="#7a3a20", long=True),
    "cycliste": dict(haut="#2a6ad0", bas="#1c1c24", short=True, cheveux="#5a3a20", velo="#d82828"),
    "musicienne": dict(haut="#3a5a8a", bas="#2a2a3a", cheveux="#5a3a20", long=True, tient="guitare"),
    "amoureux": dict(haut="#f4f1ea", bas="#2a2a3a", cheveux="#2a1a10", tient="rose"),
    "policier": dict(haut="#1e2a5a", bas="#1e2a5a", cheveux="#2a1a10", chapeau=("casquette", "#1e2a5a")),
    "pecheuse": dict(haut="#f0d020", bas="#2a3a2a", robe=True, cheveux="#7a4a20", bottes="#2a8a3a", tient="seau"),
    "passant_jean": dict(haut="#3a6ad0", bas="#2a3a6a", cheveux="#3a2618"),
    "passante_robe": dict(haut="#3aa050", bas="#3aa050", robe=True, cheveux="#c89a50", long=True),
    "papy_gilet": dict(haut="#7a5030", bas="#808088", cheveux="#c4c4cc"),
    "mamie_cabas": dict(haut="#b8a0d8", bas="#5a5a66", robe=True, cheveux="#c4c4cc", chapeau=("chignon", "#c4c4cc"),
                        tient="cabas"),
    "femme_tailleur": dict(haut="#1e2a5a", bas="#f0f0f0", cheveux="#2a1a10", long=True),
    "homme_costume": dict(haut="#6a6a74", bas="#6a6a74", cheveux="#2a1a10", cravate="#c82828"),
    "etudiante": dict(haut="#f0d030", bas="#2a3a6a", cheveux="#7a3a20", long=True, sac="#3a3a5a"),
    "etudiant": dict(haut="#c83030", bas="#2a3a6a", cheveux="#2a1a10", sac="#3a3a5a", peau=PEAU2),
    "maman": dict(haut="#f4f1ea", bas="#2a4a8a", cheveux="#5a3a20", long=True),
    "papa": dict(haut="#b83030", motif=("carreaux", "#5a1a1a"), bas="#8a8a50", cheveux="#3a2618"),
    "enfant_fille": dict(haut="#f080b0", bas="#3a5a9a", short=True, petit=True, cheveux="#c89a50", long=True),
    "enfant_garcon": dict(haut="#f08020", bas="#3a5a9a", short=True, petit=True, cheveux="#5a3a20"),
    "femme_pull": dict(haut="#2a9a9a", bas="#1c1c24", cheveux="#2a1a10", long=True),
    "homme_polo": dict(haut="#f4f1ea", bas="#d8c090", short=True, cheveux="#7a4a20"),
    "jeune_casquette": dict(haut="#8a8a92", bas="#2a2a3a", cheveux="#2a1a10", chapeau=("casquette", "#1c1c24"),
                            peau=PEAU2),
    "femme_imper": dict(haut="#c8b088", bas="#4a4a52", robe=True, cheveux="#c89a50", long=True),
    "homme_doudoune": dict(haut="#2a5a3a", bas="#2a2a3a", cheveux="#3a2618", large=True),
    "femme_short": dict(haut="#f4f1ea", motif=("rayures", "#1e2a5a"), bas="#4a6aa0", short=True,
                        cheveux="#7a3a20", long=True),
    "homme_chemise": dict(haut="#9ac8f0", bas="#4a4a5a", cheveux="#5a3a20"),
    "ado_skate": dict(haut="#f4f1ea", bas="#2a3a6a", cheveux="#c89a50", tient="skate"),
}

# Animaux (§8.4) : forme, couleurs, activité (élément) ; fuite = run.
A = {
    "chat": dict(forme="quadrupede", corps="#1c1a24", clair="#3a3644", yeux="#f2d020", L=10, haut=6,
                 oreilles="pointues", queue="haute", activite="dormir"),
    "chien": dict(forme="quadrupede", corps="#a0602a", clair="#f4f1ea", yeux=OEIL, L=12, haut=8,
                  oreilles="tombantes", queue="haute", activite="renifler"),
    "goeland": dict(forme="oiseau", corps="#f4f1ea", ailes="#9aa0aa", bec="#f2c12e", L=9, activite="picorer"),
    "pigeon": dict(forme="oiseau", corps="#8a8e9a", ailes="#6a6e7a", bec="#3a3a44", cou="#3aa070", L=7,
                   activite="picorer"),
}

# Boss (§5.2, §8.3) : humanoïdes au gabarit ×2 (64 px), Intxixuk à 32 px, deux créatures.
B = {
    "basajaun": dict(forme="humain", s=2, haut="#6a4424", bas="#5a3a1c", peau="#8a6a4a", cheveux="#5a3a1c",
                     large=True, barbe="#4a8a3a", tient="baton", pouvoirs=("#6ad04a", "#8a5a2a")),
    "tartalo": dict(forme="humain", s=2, haut="#7a5a3a", bas="#5a4030", peau="#c89060", cheveux="#3a2618",
                    large=True, cyclope=True, tient="massue", pouvoirs=("#e83030", "#a07a50")),
    "intxixu_1": dict(forme="humain", s=1, haut="#7a6040", bas="#5a4a30", peau="#8a8e96", petit=True,
                      bosse=True, touffe="#4aa040", yeux_jaunes=True, tient="fronde", pouvoirs=("#c8c0b0", "#9a9aa0")),
    "intxixu_2": dict(forme="humain", s=1, haut="#6a5038", bas="#4a3a28", peau="#8a8e96", petit=True,
                      bosse=True, touffe="#e0802a", yeux_jaunes=True, tient="sac_cailloux",
                      pouvoirs=("#c8c0b0", "#9a9aa0")),
    "intxixu_3": dict(forme="humain", s=1, haut="#7a6040", bas="#5a4a30", peau="#8a8e96", petit=True,
                      bosse=True, touffe="#9a4ac8", yeux_jaunes=True, collier="#f0ead8",
                      pouvoirs=("#c8c0b0", "#9a9aa0")),
    "zezengorri": dict(forme="quadrupede", s=2, corps="#d0201c", clair="#8a1010", yeux="#f2e040", L=26, haut=18,
                       cornes="#f0e8d0", flammes="#ff9a20", oreilles="", queue="basse", pouvoirs=("#ff8a20", "#e0d070")),
    "herensuge": dict(forme="serpent", s=2, corps="#a8782a", clair="#e8c83a", ailes="#c89a2a",
                      pouvoirs=("#ff7a1a", "#e8d870")),
}
BOSS_ELEMENTS = ["profile", "portrait", "idle", "run", "etourdi", "cri", "pouvoir_1", "pouvoir_2"]


def rgb(c) -> tuple:
    if isinstance(c, tuple):
        return c
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def sombre(c, k: float = 0.7) -> tuple:
    return tuple(int(v * k) for v in rgb(c))


class Toile:
    """Image d'une case ; coordonnées en unités (×s pixels) depuis le pied : x vers la droite, y vers le haut négatif."""

    def __init__(self, case: int, s: int, cx: int | None = None):
        self.a = np.zeros((case, case, 4), np.uint8)
        self.case, self.s = case, s
        self.cx = case // 2 if cx is None else cx
        self.fy = case * 60 // 64
        self.dx = 0

    def r(self, x, y, w, h, c) -> None:
        if c is None or w <= 0 or h <= 0:
            return
        s = self.s
        x0, y0 = self.cx + (x + self.dx) * s, self.fy + y * s
        x0, x1 = max(0, x0), min(self.case, x0 + w * s)
        y0, y1 = max(0, y0), min(self.case, y0 + h * s)
        if x1 > x0 and y1 > y0:
            self.a[y0:y1, x0:x1, :3] = rgb(c)
            self.a[y0:y1, x0:x1, 3] = 255

    def p(self, x, y, c) -> None:
        self.r(x, y, 1, 1, c)

    def ell(self, xc, yc, rx, ry, c) -> None:
        """Ellipse pleine (unités, centre éventuellement demi-entier)."""
        for yy in range(int(np.floor(yc - ry)), int(np.ceil(yc + ry)) + 1):
            for xx in range(int(np.floor(xc - rx)), int(np.ceil(xc + rx)) + 1):
                if ((xx + 0.5 - xc) / max(rx, 0.5)) ** 2 + ((yy + 0.5 - yc) / max(ry, 0.5)) ** 2 <= 1.0:
                    self.p(xx, yy, c)

    def pix(self, X, Y, c) -> None:
        """Un pixel réel (effets, ficelles) sans contour."""
        if 0 <= X < self.case and 0 <= Y < self.case:
            self.a[Y, X, :3] = rgb(c)
            self.a[Y, X, 3] = 255

    def ligne(self, X0, Y0, X1, Y1, c) -> None:
        n = max(abs(X1 - X0), abs(Y1 - Y0), 1)
        for i in range(n + 1):
            self.pix(round(X0 + (X1 - X0) * i / n), round(Y0 + (Y1 - Y0) * i / n), c)

    def u(self, x, y) -> tuple:
        """Unités → pixel réel (coin haut-gauche)."""
        return self.cx + (x + self.dx) * self.s, self.fy + y * self.s

    def contour(self, couleur=CONTOUR) -> None:
        al = self.a[:, :, 3] > 0
        v = np.zeros_like(al)
        v[1:, :] |= al[:-1, :]
        v[:-1, :] |= al[1:, :]
        v[:, 1:] |= al[:, :-1]
        v[:, :-1] |= al[:, 1:]
        bord = v & ~al
        self.a[bord, :3] = couleur
        self.a[bord, 3] = 255


# ------------------------------------------------------------------ humains

def objet(t: Toile, nom: str, hx: int, hy: int, sp: dict) -> None:
    """Objet tenu, la main en (hx, hy) (unités)."""
    if nom == "flute":
        t.r(hx - 1, hy - 1, 8, 1, "#4a3020")
    elif nom == "trompette":
        t.r(hx, hy - 1, 5, 2, "#f2c12e")
        t.r(hx + 5, hy - 2, 2, 4, "#ffd84a")
    elif nom == "eventail":
        t.ell(hx + 2, hy - 2, 2.5, 2, "#d82020")
    elif nom == "plateau":
        t.r(hx - 2, hy - 1, 8, 1, "#9aa0aa")
        for k in (0, 3):
            t.r(hx - 1 + k, hy - 3, 1, 2, "#f2b84a")
    elif nom == "appareil":
        t.r(hx, hy - 2, 3, 2, NOIR)
        t.p(hx + 1, hy - 3, "#9aa0aa")
    elif nom == "guitare":
        t.ell(hx - 2, hy + 1, 2.5, 2, "#b07030")
        t.r(hx, hy - 1, 6, 1, "#5a3a20")
    elif nom == "rose":
        t.r(hx, hy - 3, 1, 3, "#2a8a3a")
        t.r(hx - 1, hy - 5, 2, 2, "#e02040")
    elif nom == "seau":
        t.r(hx - 1, hy + 1, 3, 3, "#8a9aa8")
    elif nom == "cabas":
        t.r(hx - 1, hy + 1, 4, 4, "#8a5a3a")
    elif nom == "skate":
        t.r(hx - 4, hy, 9, 1, "#c84a2a")
        t.p(hx - 3, hy + 1, NOIR)
        t.p(hx + 3, hy + 1, NOIR)
    elif nom == "journal":
        t.r(hx - 1, hy - 7, 4, 8, "#e8e4d8")
        t.r(hx, hy - 6, 2, 1, "#8a8a92")
        t.r(hx, hy - 4, 2, 1, "#8a8a92")
    elif nom == "telephone":
        t.r(hx, hy - 1, 1, 2, NOIR)
    elif nom == "verre":
        t.r(hx, hy - 2, 2, 2, "#f2b84a")
    elif nom == "baton":
        t.r(hx, hy - 12, 2, 18, "#6a4a2a")
        t.r(hx - 1, hy - 13, 4, 2, "#4a8a3a")
    elif nom == "massue":
        t.r(hx, hy - 2, 2, 6, "#8a6a40")
        t.r(hx - 1, hy - 8, 4, 7, "#6a4a2a")
    elif nom == "fronde":
        t.r(hx, hy - 2, 1, 3, "#6a4a2a")
        t.p(hx + 1, hy - 3, "#6a4a2a")
    elif nom == "sac_cailloux":
        t.r(hx - 1, hy + 1, 3, 3, "#8a6a40")


def humain(t: Toile, sp: dict, pose: dict) -> None:
    """Silhouette humaine de profil vers la droite. pose : dy, jambes (dx arrière, dx avant) ou 'assis',
    bras ('bas', 'avant', 'haut', 'tete', 'bouche', 'croise', 'panique'), tete_dy, tient (objet d'activité),
    laisse (promener), bouche (cri)."""
    petit = sp.get("petit")
    lj, lt, lh = (6, 7, 8) if petit else (10, 10, 8)
    peau = sp.get("peau", PEAU)
    haut, bas = sp["haut"], sp["bas"]
    larg = 10 if sp.get("large") else 8
    x0 = -larg // 2
    dy = pose.get("dy", 0)
    assis = pose.get("jambes") == "assis"
    if assis:
        dy += 4
    tbas = -lj + dy                      # bas du torse
    ttop = tbas - lt                     # haut du torse
    htop = ttop - lh + pose.get("tete_dy", 0)
    if sp.get("bosse"):
        htop += 2
    # Objets portés derrière (planche de surf, sac à dos) et vélo.
    if sp.get("dos") == "planche":
        t.r(x0 - 3, -24, 3, 23, "#f4f1ea")
        t.r(x0 - 2, -22, 1, 19, "#2aa0d8")
    if sp.get("velo"):
        c = sp["velo"]
        for wx in (-7, 7):
            t.ell(wx + 0.5, -2.5, 3, 3, NOIR)
            t.ell(wx + 0.5, -2.5, 1.5, 1.5, "#3a3a44")
        t.r(-7, -4, 15, 1, c)
        t.r(5, -7, 1, 4, c)
    if sp.get("sac"):
        t.r(x0 - 2, ttop + 1, 3, 7, sp["sac"])
    # Jambes.
    if assis:
        t.r(x0 + 1, tbas - 2, 8, 2, bas)
        t.r(x0 + 7, tbas, 2, 3, bas)
        t.r(x0 + 7, tbas + 3, 3, 1, sp.get("chaussures", NOIR))
        t.r(x0 - 1, tbas, 9, 2, "#6a4a2a")          # banc
        t.r(x0, tbas + 2, 1, -(tbas + 2), "#6a4a2a")
    else:
        jd = pose.get("jambes", (0, 0))
        for k, (jx, jdx) in enumerate(((-3, jd[0]), (1, jd[1]))):
            col = sombre(bas, 0.8) if k == 0 else bas
            for yy in range(-lj + dy, 0):
                frac = (yy + lj - dy) / max(lj, 1)
                xx = jx + round(jdx * frac)
                court = sp.get("short") and frac > 0.45
                t.r(xx, yy, 2, 1, sombre(peau, 0.85 if k == 0 else 1) if court else col)
            botte = sp.get("bottes")
            t.r(jx + jdx, -3 if botte else -1, 3, 3 if botte else 1, botte or sp.get("chaussures", NOIR))
    # Bras arrière levé (panique, cri).
    bras = pose.get("bras", "bas")
    if bras in ("panique", "cri"):
        t.r(x0 + 1, ttop - 6, 2, 7, sombre(haut, 0.8))
        t.r(x0 + 1, ttop - 7, 2, 1, peau)
    # Torse (robe ou manteau long : jusqu'aux mollets, un peu évasé).
    t.r(x0, ttop, larg, lt, haut)
    if sp.get("bosse"):
        t.r(x0 - 1, ttop + 1, 2, 4, haut)
    if sp.get("robe") and not assis:
        t.r(x0, tbas, larg, lj - 3, haut)
        t.r(x0 - 1, tbas + lj // 2, larg + 2, lj - 3 - lj // 2, haut)
    motif = sp.get("motif")
    if motif:
        m, mc = motif
        for yy in range(ttop, tbas + (lj - 3 if sp.get("robe") else 0)):
            for xx in range(x0, x0 + larg):
                if (m == "rayures" and (yy - ttop) % 2 == 1) or (m == "carreaux" and (xx + yy) % 2 == 0) or \
                        (m == "fleurs" and (xx * 3 + yy * 5) % 7 == 0):
                    t.p(xx, yy, mc)
    if sp.get("ceinture"):
        t.r(x0, tbas - 2, larg, 2, sp["ceinture"])
    if sp.get("tablier"):
        t.r(x0 + larg // 2, tbas - 4, larg // 2 + 1, lj - 2, sp["tablier"])
    if sp.get("cravate"):
        t.r(x0 + larg - 3, ttop + 1, 1, 5, sp["cravate"])
    if sp.get("collier"):
        t.r(x0 + 1, ttop, larg - 1, 1, sp["collier"])
    # Tête.
    tg = sp.get("tete_geante")
    if tg:
        forme, c = tg
        if forme == "sardine":
            t.ell(0.5, htop - 1, 8, 6, c)
            t.r(-10, htop - 4, 3, 6, sombre(c, 0.8))       # nageoire de queue
            t.r(2, htop, 5, 1, "#d82050")                  # sourire
            t.r(4, htop - 4, 2, 2, "#f4f1ea")
            t.p(5, htop - 4, OEIL)
        else:
            t.ell(0.5, htop - 1, 7, 6, c)
            t.r(-5, htop - 9, 11, 3, "#f2c12e")            # couronne
            for k in (-5, -1, 3):
                t.r(k, htop - 11, 2, 2, "#f2c12e")
            t.r(0, htop + 2, 6, 2, "#5a3a20")              # barbe
            t.r(4, htop - 3, 1, 2, OEIL)
    else:
        t.r(-3, htop, 7, lh, peau)
        ch = sp.get("cheveux")
        if ch:
            t.r(-3, htop - 1, 7, 2, ch)
            t.r(-3, htop, 2, lh - 3 + (5 if sp.get("long") else 0), ch)
        t.r(2, htop + 3, 1, 2 if not sp.get("yeux_jaunes") else 1, "#f2e040" if sp.get("yeux_jaunes") else OEIL)
        if sp.get("cyclope"):
            t.r(0, htop + 1, 4, 4, "#f4f1ea")
            t.r(2, htop + 2, 2, 2, OEIL)
        if sp.get("maquillage"):
            t.r(1, htop + 5, 3, 1, sp["maquillage"])
        if sp.get("barbe"):
            t.r(0, htop + 5, 5, 5, sp["barbe"])
            t.r(1, htop + 10, 3, 2, sp["barbe"])
        if pose.get("bouche"):
            t.r(3, htop + 5, 2, 2, "#5a1020")
        if sp.get("touffe"):
            t.r(-2, htop - 2, 5, 2, sp["touffe"])
            t.p(0, htop - 3, sp["touffe"])
        ch_ = sp.get("chapeau")
        if ch_:
            forme, c = ch_
            if forme == "beret":
                t.r(-4, htop - 2, 8, 2, c)
                t.p(0, htop - 3, c)
            elif forme == "casquette":
                t.r(-3, htop - 2, 7, 2, c)
                t.r(4, htop - 1, 3, 1, c)
            elif forme == "chignon":
                t.r(-5, htop - 1, 3, 3, c)
        if sp.get("casque"):
            t.r(-3, htop - 2, 7, 1, sp["casque"])
            t.r(-1, htop + 2, 3, 3, sp["casque"])
    if sp.get("foulard"):
        t.r(x0, ttop, larg, 2, sp["foulard"])
        t.r(x0 + larg - 2, ttop + 2, 2, 2, sp["foulard"])
    # Bras avant et main.
    sx = x0 + larg // 2 - 1          # épaule
    main = None
    if bras == "bas":
        t.r(sx, ttop + 1, 2, lt - 3, haut)
        main = (sx, ttop + lt - 2)
    elif bras == "avant":
        t.r(sx, ttop + 2, 5, 2, haut)
        main = (sx + 5, ttop + 2)
    elif bras in ("haut", "panique", "cri"):
        t.r(sx, ttop - 6, 2, 7, haut)
        main = (sx, ttop - 7)
    elif bras in ("tete", "bouche"):
        t.r(sx + 1, ttop - 2, 2, 4, haut)
        main = (sx + 2, htop + (3 if bras == "tete" else 5))
    elif bras == "croise":
        t.r(x0 + 1, ttop + 4, larg - 1, 2, haut)
        main = (x0 + larg, ttop + 4)
    elif bras == "frappe":
        t.r(sx, ttop + 1, 6, 2, haut)
        main = (sx + 6, ttop + 3)
    if main:
        t.r(main[0], main[1], 2 if bras != "avant" else 1, 1 if bras != "avant" else 2, peau)
        nom = pose.get("tient", sp.get("tient") if bras != "panique" else None)
        if nom:
            objet(t, nom, main[0], main[1], sp)
    if sp.get("ballon"):
        bx, by = t.u(sx + 1, ttop + lt - 2)
        tx, ty = t.u(sx + 6, htop - 8)
        t.ligne(bx, by, tx, ty + 3, "#f4f1ea")
        t.ell(sx + 6.5, htop - 10, 3, 3.5, sp["ballon"])
    if pose.get("laisse"):
        mx, my = t.u(*(main or (sx, ttop + lt - 2)))
        t.ligne(mx, my, t.cx + 14 * t.s, t.fy - 4 * t.s, "#d82020")
        chien(t, 14 + pose.get("chien_dx", 0))


def chien(t: Toile, x: int) -> None:
    t.r(x, -4, 6, 3, "#a0602a")
    t.r(x + 5, -6, 3, 3, "#a0602a")
    t.p(x + 7, -5, OEIL)
    t.r(x + 1, -1, 1, 1, "#a0602a")
    t.r(x + 4, -1, 1, 1, "#a0602a")


ACT_POSES = {
    "parler": [dict(bras="avant"), dict(bras="haut"), dict(bras="avant"), dict(bras="bas")],
    "telephone": [dict(bras="tete", tient="telephone"), dict(bras="tete", tient="telephone", tete_dy=1)],
    "danser": [dict(bras="haut", jambes=(-1, 1)), dict(bras="avant", dy=-1, jambes=(1, -1)),
               dict(bras="haut", jambes=(1, -1)), dict(bras="avant", dy=-1, jambes=(-1, 1))],
    "musique": [dict(bras="bas", casque=True), dict(bras="bas", casque=True, tete_dy=1)],
    "journal": [dict(bras="avant", tient="journal"), dict(bras="avant", tient="journal", tete_dy=1)],
    "boire": [dict(bras="bas", tient="verre"), dict(bras="avant", tient="verre"), dict(bras="bouche", tient="verre"),
              dict(bras="avant", tient="verre")],
    "assis": [dict(jambes="assis", bras="bas"), dict(jambes="assis", bras="bas", tete_dy=1)],
    "attendre": [dict(bras="croise"), dict(bras="croise", tete_dy=1)],
    "promener": [dict(jambes=(-2, 2), laisse=True, bras="avant"), dict(jambes=(0, 0), dy=-1, laisse=True,
                 bras="avant", chien_dx=1), dict(jambes=(2, -2), laisse=True, bras="avant"),
                 dict(jambes=(0, 0), dy=-1, laisse=True, bras="avant", chien_dx=1)],
    "jouer": [dict(bras="avant"), dict(bras="avant", dy=-1), dict(bras="avant"), dict(bras="avant", tete_dy=1)],
}
MARCHE = [dict(jambes=(-2, 2)), dict(jambes=(0, 0), dy=-1), dict(jambes=(2, -2)), dict(jambes=(0, 0), dy=-1)]
FUITE = [dict(bras="panique", jambes=(-3, 3)), dict(bras="panique", jambes=(0, 0), dy=-2),
         dict(bras="panique", jambes=(3, -3)), dict(bras="panique", jambes=(0, 0), dy=-2)]
SURSAUT = [dict(bras="bas"), dict(bras="panique", dy=-3, recul=-2, jambes=(-1, 1)), dict(bras="haut", recul=-2)]


def poses_humain(sp: dict, activites: list) -> dict:
    """Éléments d'un PNJ humain (§8.4) : [poses], fps, boucle."""
    def act(nom: str) -> list:
        ps = [dict(p) for p in ACT_POSES[nom]]
        if nom == "jouer":
            for p in ps:
                p["tient"] = sp.get("tient") or "flute"
        return ps
    els = {"profile": ([{}], 1, False), "idle": ([{}, dict(tete_dy=1)], 3, True), "run": (FUITE, 12, True),
           "marcher": (MARCHE, 8, True), "sursaut": (SURSAUT, 8, False)}
    for a in activites:
        els[a] = (act(a), 6 if a in ("danser", "parler", "boire", "promener", "jouer") else 3, True)
    return els


def dessine_humain(t: Toile, sp: dict, pose: dict) -> None:
    t.dx = pose.get("recul", 0)
    sp2 = dict(sp)
    if pose.get("casque"):
        sp2["casque"] = sp.get("casque", "#1c1c24")
    humain(t, sp2, pose)
    t.dx = 0


# ------------------------------------------------------------------ animaux et créatures

def quadrupede(t: Toile, sp: dict, pose: dict) -> None:
    """Quadrupède de profil vers la droite. pose : pattes (décalage), dy, tete_dy, dort, cri, tourne."""
    L, h = sp["L"], sp["haut"]
    c, clair = sp["corps"], sp["clair"]
    dy = pose.get("dy", 0)
    if pose.get("dort"):
        t.ell(0, -2 + dy, L / 2 + 1, 2.5 + pose.get("souffle", 0) * 0.5, c)
        t.r(L // 2 - 1, -4, 3, 3, c)
        t.p(L // 2 + 1, -3, sombre(c, 0.6))
        t.r(-L // 2 - 2, -2, 3, 1, c)
        return
    pl = max(2, h // 3)               # hauteur des pattes
    corps_bas = -pl + dy
    corps_h = h - pl - 2
    pd = pose.get("pattes", 0)
    for k, px in enumerate((-L // 2 + 1, -L // 2 + 3, L // 2 - 3, L // 2 - 1)):
        d = pd if k % 2 == 0 else -pd
        col = sombre(c, 0.8) if k in (1, 3) else c
        t.r(px + d, corps_bas, max(1, L // 10), pl - dy, col)
    t.ell(0, corps_bas - corps_h / 2, L / 2, corps_h / 2, c)
    if clair != c:
        t.ell(0, corps_bas - 1, L / 2 - 1, 1.2, clair)
    q = sp.get("queue")
    if q == "haute":
        t.r(-L // 2 - 1, corps_bas - corps_h - 2 + (pose.get("queue_dy", 0)), 1, 4, c)
    else:
        t.r(-L // 2 - 1, corps_bas - corps_h + 1, 1, corps_h, c)
    # Tête : devant le corps, plus basse si elle renifle, levée si elle crie.
    hy = corps_bas - corps_h - 1 + pose.get("tete_dy", 0)
    ht = max(3, h // 2)
    hx = L // 2 - 1
    t.r(hx, hy - ht // 2, ht, ht, c)
    t.r(hx + ht, hy - ht // 2 + ht // 2, max(1, ht // 2), ht - ht // 2, c)    # museau
    o = sp.get("oreilles")
    if o == "pointues":
        t.p(hx, hy - ht // 2 - 1, c)
        t.p(hx + 2, hy - ht // 2 - 1, c)
    elif o == "tombantes":
        t.r(hx, hy - ht // 2, 2, ht, sombre(c, 0.7))
    t.p(hx + ht - 1, hy - ht // 2 + 1, sp["yeux"])
    if sp.get("cornes"):
        t.r(hx + 1, hy - ht // 2 - 2, 2, 2, sp["cornes"])
        t.r(hx + 2, hy - ht // 2 - 3, 2, 1, sp["cornes"])
        for k, fx in enumerate((hx, hx + 3, hx + 4)):
            if (k + pose.get("f", 0)) % 2 == 0:
                t.p(fx, hy - ht // 2 - 4, sp["flammes"])
    if pose.get("cri"):
        t.r(hx + ht, hy + ht // 2 - 1, 2, 1, "#5a1020")


def oiseau(t: Toile, sp: dict, pose: dict) -> None:
    L = sp["L"]
    c = sp["corps"]
    vol = pose.get("vol")
    dy = pose.get("dy", 0)
    base = -2 + dy
    if not vol:
        t.r(0, -2, 1, 2, "#e0a040")
        t.r(2, -2, 1, 2, "#e0a040")
    t.ell(0, base - 2.5, L / 2, 2.5, c)
    t.r(-L // 2 - 1, base - 3, 2, 2, sp["ailes"])                     # queue
    t.r(-L // 2 + 1, base - 4, L - 3, 2, sp["ailes"])                 # aile repliée
    if vol:
        if pose.get("aile_haute"):
            t.r(-2, base - 9, 3, 5, sp["ailes"])
        else:
            t.r(-2, base - 2, 3, 4, sp["ailes"])
    hy = base - 6 + pose.get("tete_dy", 0)
    hx = L // 2 - 2
    t.r(hx, hy, 3, 3, c)
    if sp.get("cou"):
        t.r(hx, hy + 2, 2, 2, sp["cou"])
    t.r(hx + 3, hy + 1, 2, 1, sp["bec"])
    t.p(hx + 1, hy + 1, OEIL)


def serpent(t: Toile, sp: dict, pose: dict) -> None:
    """Herensuge : corps ondulant, ailes, trois têtes au bout de trois cous (unités ×s)."""
    f = pose.get("f", 0)
    c, clair = sp["corps"], sp["clair"]
    dy = pose.get("dy", 0)
    ondule = pose.get("ondule", 1)
    # Ailes derrière le corps.
    ah = -24 if pose.get("aile_haute", f % 2 == 0) else -20
    t.r(-6, ah + dy, 10, 3, sp["ailes"])
    t.r(-4, ah + 3 + dy, 6, 6, sombre(sp["ailes"], 0.8))
    for i in range(-24, 10):
        yy = -5 + dy + round(2 * ondule * np.sin((i + f * 3) / 3.0))
        t.r(i, yy, 1, 5 - (1 if i < -18 else 0), c)
        t.p(i, yy + 4, clair)
    # Trois cous et trois têtes.
    for k, (lx, hy) in enumerate(((10, -16), (12, -22), (8, -26))):
        tdy = pose.get("tetes", [0, 0, 0])[k] + dy
        for j in range(abs(hy) - 5):
            t.r(6 + k + round(j * (lx - 6 - k) / (abs(hy) - 5)), -6 - j + dy, 2, 1, c)
        t.r(lx, hy + tdy, 5, 3, c)
        t.r(lx + 5, hy + 1 + tdy, 2, 2, c)
        t.p(lx + 3, hy + tdy, "#f2e040")
        if pose.get("cri"):
            t.r(lx + 5, hy + 3 + tdy, 2, 1, "#5a1020")


# ------------------------------------------------------------------ effets de boss (pixels réels)

def etoiles(t: Toile, f: int, haut_y: int) -> None:
    for k in range(3):
        ang = (f / 4 + k / 3) * 2 * np.pi
        X = t.cx + round(np.cos(ang) * 6 * t.s)
        Y = haut_y - 3 * t.s + round(np.sin(ang) * 2 * t.s)
        for ddx, ddy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            t.pix(X + ddx, Y + ddy, "#f2e040")


def particules(t: Toile, f: int, X: int, Y: int, c, sol: bool = False) -> None:
    r = (3 + 3 * f) * t.s
    for k in range(8):
        ang = k / 8 * 2 * np.pi
        px, py = X + round(np.cos(ang) * r), Y + round(np.sin(ang) * r * (0.35 if sol else 1))
        for ddx in range(t.s):
            for ddy in range(t.s):
                t.pix(px + ddx, py + ddy, c)


def cri_traits(t: Toile, f: int, X: int, Y: int) -> None:
    for k in (-1, 0, 1):
        for j in range(2 + f):
            t.pix(X + (3 + j) * t.s // 2 + j, Y + k * (2 + j), "#f4f1ea")


def haut_sprite(a: np.ndarray) -> int:
    ys = np.where(a[:, :, 3] > 0)[0]
    return int(ys.min()) if len(ys) else 0


# ------------------------------------------------------------------ fabrication des sets

def frames_pnj(pid: str) -> dict:
    sp = H[pid]
    els = poses_humain(sp, PNJ["humains"][pid]["activites"])
    out = {}
    for el, (poses, fps, boucle) in els.items():
        ims = []
        for p in poses:
            t = Toile(64, 1)
            dessine_humain(t, sp, p)
            t.contour()
            ims.append(t.a)
        out[el] = (ims, fps, boucle)
    return out


def frames_animal(aid: str) -> dict:
    sp = A[aid]
    act = sp["activite"]
    if sp["forme"] == "quadrupede":
        dessin = quadrupede
        els = {"profile": [{}], "idle": [{}, dict(queue_dy=1)],
               "marcher": [dict(pattes=1), dict(dy=-1), dict(pattes=-1), dict(dy=-1)],
               "run": [dict(pattes=2), dict(dy=-1, pattes=0), dict(pattes=-2), dict(dy=-1)]}
        els[act] = [dict(dort=True), dict(dort=True, souffle=1)] if act == "dormir" else \
            [dict(tete_dy=3), dict(tete_dy=4)]
    else:
        dessin = oiseau
        els = {"profile": [{}], "idle": [{}, dict(tete_dy=1)],
               "marcher": [dict(), dict(dy=-1)],
               "run": [dict(vol=True, dy=-3, aile_haute=True), dict(vol=True, dy=-5), dict(vol=True, dy=-7,
                       aile_haute=True), dict(vol=True, dy=-8)]}
        els[act] = [dict(tete_dy=0), dict(tete_dy=3), dict(tete_dy=4), dict(tete_dy=1)]
    fps = {"profile": 1, "idle": 3, "marcher": 6, "run": 10, act: 3 if act == "dormir" else 5}
    out = {}
    for el, poses in els.items():
        ims = []
        for p in poses:
            t = Toile(64, 1)
            dessin(t, sp, p)
            t.contour(CONTOUR_CLAIR if sum(rgb(sp["corps"])) < 150 else CONTOUR)
            ims.append(t.a)
        out[el] = (ims, fps[el], el != "profile")
    return out


def frames_boss(bid: str) -> dict:
    sp = B[bid]
    s = sp["s"]
    case = 64 * s
    forme = sp["forme"]
    c1, c2 = sp["pouvoirs"]

    def rendu(pose: dict, effet=None) -> np.ndarray:
        t = Toile(case, s)
        if forme == "humain":
            humain(t, sp, pose)
        elif forme == "quadrupede":
            quadrupede(t, sp, pose)
        else:
            serpent(t, sp, pose)
        t.contour()
        if effet:
            effet(t)
        return t.a

    if forme == "humain":
        idle = [dict(), dict(tete_dy=1, dy=0)]
        run = [dict(jambes=(-3, 3)), dict(jambes=(0, 0), dy=-1), dict(jambes=(3, -3)), dict(jambes=(0, 0), dy=-1)]
        cri = [dict(bras="bas"), dict(bras="cri", bouche=True), dict(bras="cri", bouche=True, dy=-1)]
        p1 = [dict(bras="avant"), dict(bras="avant"), dict(bras="avant"), dict(bras="avant")]
        p2 = [dict(bras="haut"), dict(bras="haut", dy=-1), dict(bras="frappe"), dict(bras="frappe")]
    elif forme == "quadrupede":
        idle = [dict(f=0), dict(f=1, dy=0, tete_dy=1)]
        run = [dict(pattes=2, f=0), dict(dy=-1, f=1), dict(pattes=-2, f=0), dict(dy=-1, f=1)]
        cri = [dict(f=0), dict(tete_dy=-2, cri=True, f=1), dict(tete_dy=-2, cri=True, f=0)]
        p1 = [dict(pattes=1, f=k % 2) for k in range(4)]
        p2 = [dict(tete_dy=2, f=k % 2) for k in range(4)]
    else:
        idle = [dict(f=0, tetes=[0, 1, 0]), dict(f=1, tetes=[1, 0, 1])]
        run = [dict(f=k, ondule=1.5) for k in range(4)]
        cri = [dict(f=0), dict(f=1, cri=True, tetes=[-1, -1, -1]), dict(f=2, cri=True, tetes=[-2, -2, -2])]
        p1 = [dict(f=k, cri=True) for k in range(4)]
        p2 = [dict(f=k, cri=True, tetes=[1, 1, 1]) for k in range(4)]

    out = {}
    prof = rendu({})
    out["profile"] = ([prof], 1, False)
    out["idle"] = ([rendu(p) for p in idle], 3, True)
    out["run"] = ([rendu(p) for p in run], 8, True)
    sommet = haut_sprite(prof)
    out["etourdi"] = ([rendu(dict(idle[k % 2]), lambda t, k=k: etoiles(t, k, sommet)) for k in range(4)], 6, True)
    devant = (case // 2 + 10 * s, case * 60 // 64 - 18 * s)
    out["cri"] = ([rendu(p, (lambda t, k=k: cri_traits(t, k, devant[0], sommet + 6 * s)) if k else None)
                   for k, p in enumerate(cri)], 6, False)
    out["pouvoir_1"] = ([rendu(p, lambda t, k=k: particules(t, k, devant[0], devant[1], c1)) for k, p in
                         enumerate(p1)], 8, False)
    sol = (case // 2 + 8 * s, case * 60 // 64)
    out["pouvoir_2"] = ([rendu(p, (lambda t, k=k: particules(t, k - 1, sol[0], sol[1], c2, True)) if k >= 2 else
                         None) for k, p in enumerate(p2)], 8, False)
    if bid.startswith("intxixu"):
        return out           # pas de portrait pour les lutins (taches_boss_essai.json)
    # Portrait : la tête du profil, agrandie ×2 dans la case.
    al = prof[:, :, 3] > 0
    xs = np.where(al.any(0))[0]
    cxh = int((xs.min() + xs.max()) // 2) if forme != "humain" else case // 2
    cyh = sommet + case // 8
    if forme == "serpent":
        cxh = int(xs.max()) - case // 8
    x0 = int(np.clip(cxh - case // 4, 0, case // 2))
    y0 = int(np.clip(cyh - case // 4, 0, case // 2))
    crop = Image.fromarray(prof[y0:y0 + case // 2, x0:x0 + case // 2])
    out["portrait"] = ([np.array(crop.resize((case, case), Image.NEAREST))], 1, False)
    return out


def ecrit(famille: str, eid: str, frames: dict, taille: str, ordre: list | None = None) -> str:
    dossier = os.path.join(ASSETS, famille, eid, "px32")
    if os.path.exists(os.path.join(dossier, "set.json")):
        if not json.load(open(os.path.join(dossier, "set.json"))).get("placeholder"):
            return "vrai set pixelforge : pas touché"
    shutil.rmtree(dossier, ignore_errors=True)
    os.makedirs(dossier)
    case = frames["profile"][0][0].shape[0]
    feet = case * 60 // 64
    elements, anims, couleurs = {}, {}, set()
    for el in (ordre or list(frames)):
        if el not in frames:
            continue
        ims, fps, boucle = frames[el]
        Image.fromarray(np.concatenate(ims, axis=1), "RGBA").save(os.path.join(dossier, f"{el}_sheet.png"))
        elements[el] = {"frames": len(ims), "fps": fps, "loop": boucle, "anchor": "feet", "size": [case, case]}
        anims[el] = {"fps": fps, "loop": boucle, "count": len(ims),
                     "caption": f"{el} · {len(ims)} image(s) · {fps} i/s{' · boucle' if boucle else ''} · placeholder"}
        for im in ims:
            px = im[im[:, :, 3] > 0][:, :3]
            couleurs.update("#%02x%02x%02x" % tuple(int(v) for v in c) for c in px)
    prof = frames["profile"][0][0]
    s = {"placeholder": True, "source": "tools/blackout/placeholders_sets.py", "size": taille,
         "height": feet - haut_sprite(prof), "canvas": [case, case], "feet_y": feet,
         "palette": sorted(couleurs), "elements": elements}
    json.dump(s, open(os.path.join(dossier, "set.json"), "w"), ensure_ascii=False, indent=1)
    json.dump(anims, open(os.path.join(dossier, "animations.json"), "w"), ensure_ascii=False, indent=1)
    return f"placeholder ({', '.join(elements)})"


def planche(chemin: str, ids: list) -> None:
    """Planche de contrôle : chaque set, toutes ses images, sur fond nuit, ×2."""
    lignes = []
    for fam, eid in ids:
        d = os.path.join(ASSETS, fam, eid, "px32")
        sj = json.load(open(os.path.join(d, "set.json")))
        ims = [Image.open(os.path.join(d, f"{el}_sheet.png")) for el in sj["elements"]]
        lignes.append(ims)
    W = max(sum(i.width + 4 for i in l) for l in lignes)
    Ht = sum(max(i.height for i in l) + 4 for l in lignes)
    out = Image.new("RGBA", (W, Ht), (40, 44, 70, 255))
    y = 0
    for l in lignes:
        x = 0
        for i in l:
            out.alpha_composite(i, (x, y))
            x += i.width + 4
        y += max(i.height for i in l) + 4
    out.resize((W * 2, Ht * 2), Image.NEAREST).save(chemin)


def main() -> None:
    args = sys.argv[1:]
    chemin_planche = None
    if "--planche" in args:
        chemin_planche = args[args.index("--planche") + 1]
        args = [a for a in args if a not in ("--planche", chemin_planche)]
    voulus = set(args)
    cibles = [("pnj", k) for k in PNJ["humains"]] + [("animaux", k) for k in PNJ["animaux"]] + \
        [("boss", k) for k in RULES.get("boss", [])]
    faits = []
    for fam, eid in cibles:
        if voulus and eid not in voulus:
            continue
        if fam == "pnj":
            if eid not in H:
                print(eid, ": pas d'apparence dans placeholders_sets.py (à ajouter)")
                continue
            dossier = os.path.join(ASSETS, "pnj", eid, "px32", "set.json")
            if os.path.exists(dossier) and not json.load(open(dossier)).get("placeholder"):
                print(eid, ": vrai set pixelforge : pas touché")
                continue
            acts = PNJ["humains"][eid]["activites"]
            txt = ecrit(fam, eid, frames_pnj(eid), "normal", ["profile", "idle", "run", "marcher", "sursaut"] + acts)
        elif fam == "animaux":
            txt = ecrit(fam, eid, frames_animal(eid), "normal")
        else:
            txt = ecrit(fam, eid, frames_boss(eid), "boss" if B[eid]["s"] == 2 else "normal", BOSS_ELEMENTS)
        print(f"{fam}/{eid} :", txt)
        if txt.startswith("placeholder"):
            faits.append((fam, eid))
    if chemin_planche and faits:
        planche(chemin_planche, faits)
        print("planche :", chemin_planche)


if __name__ == "__main__":
    main()
