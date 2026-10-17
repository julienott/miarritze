#!/usr/bin/env python3
"""Anime légèrement le plan lointain d'un décor (ciel, mer, personnes), dans
l'esprit de l'accueil : N images en boucle lente (PixelBg / calque « frames »).

Part de assets/stages/<id>/far_0.png (512×216, issu de photo_stage.py) et
réécrit far_0..N-1.png ; build_stage.py en tire far_v_* et stage.json.
Effets, réglés par décor dans ANIM :
  ciel      : les pixels de ciel/nuages d'une bande glissent de 0→1→2→1 px
              (va-et-vient, la boucle ne saute jamais) ; ce qui n'est pas du
              ciel (falaise, villa, phare) reste fixe par-dessus ;
  mer       : rangées d'eau décalées de ±1 px en vagues + étincelles d'écume ;
  personnes : petites taches (3–40 px) qui ne sont pas de la couleur du sol
              dans une zone (plage, tribune) : elles bougent de 1 px, chacune
              à son rythme (marcheurs, baigneurs) ;
  fixe      : boîtes jamais animées (villa, phare : murs blancs pris pour des nuages) ;
  foule     : spectateurs d'une tribune : colonnes de 3 px qui sautent de
              1 px à tour de rôle.
Usage : animate_far.py <id> [<id> …] [--images 4]
"""
import colorsys
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FOAM = (236, 248, 246)
SWAY = [0, 1, 2, 1]          # décalage du ciel par image (va-et-vient)


def hsv(a):
    f = a[..., :3].astype(float) / 255
    mx, mn = f.max(-1), f.min(-1)
    v = mx
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    h = np.zeros_like(mx)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return h, s, v


def water_mask(a, y0, y1):
    h, s, v = hsv(a)
    m = (h >= 165) & (h <= 215) & (s > 0.18) & (v > 0.3)
    m[:y0] = False
    m[y1:] = False
    return m


def sky_mask(a, y1):
    h, s, v = hsv(a)
    # ciel bleu, nuages blancs/gris clairs, ciel de tempête gris
    m = ((h >= 180) & (h <= 235) & (v > 0.45)) | ((s < 0.2) & (v > 0.55))
    m[y1:] = False
    return m


def hash01(x, y, salt):
    h = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) % 10000) / 10000.0


def comps(m):
    sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
    from despeck_sheet import comps as c
    return c(m)


def animate(base, cfg, n):
    a = np.array(base.convert("RGB"))
    H, W = a.shape[:2]
    frames = [a.copy() for _ in range(n)]
    if "ciel" in cfg:
        y1 = cfg["ciel"]
        sky = sky_mask(a, y1)
        for i, fr in enumerate(frames):
            d = SWAY[i % len(SWAY)]
            if not d:
                continue
            src = np.roll(a, d, axis=1)
            ok = sky & np.roll(sky, d, axis=1)
            fr[ok] = src[ok]
    if "mer" in cfg:
        y0, y1 = cfg["mer"]
        wat = water_mask(a, y0, y1)
        ys = np.nonzero(wat.any(1))[0]
        for i, fr in enumerate(frames):
            for y in ys:
                d = round(np.sin((y * 0.7) + i * np.pi / 2))
                if d:
                    row = np.roll(a[y], d, axis=0)
                    ok = wat[y] & np.roll(wat[y], d, axis=0)
                    fr[y][ok] = row[ok]
            if i:
                for y, x in zip(*np.nonzero(wat)):
                    if hash01(int(x), int(y), i) < 0.012:
                        fr[y, x] = FOAM
    for box in cfg.get("personnes", []):
        x0, y0, x1, y1 = box
        zone = a[y0:y1, x0:x1].astype(int)
        # couleur du sol de la zone = la plus fréquente
        cols, cnt = np.unique(zone.reshape(-1, 3) // 12, axis=0, return_counts=True)
        ground = cols[cnt.argmax()]
        other = np.abs(zone // 12 - ground).sum(-1) > 3
        for k, pts in enumerate(comps(other)):
            if not 3 <= len(pts) <= cfg.get("personnes_max", 40):
                continue
            ys_, xs_ = zip(*pts)
            ys_, xs_ = np.array(ys_) + y0, np.array(xs_) + x0
            fill = a[min(ys_.max() + 1, H - 1), xs_.min()]
            for i, fr in enumerate(frames):
                dx = [0, 1, 1, 0][(i + k) % 4] * (1 if k % 2 else -1)
                if not dx:
                    continue
                fr[ys_, xs_] = fill
                fr[ys_, np.clip(xs_ + dx, 0, W - 1)] = a[ys_, xs_]
    for box in cfg.get("foule", []):
        x0, y0, x1, y1 = box
        for i, fr in enumerate(frames):
            for cx in range(x0, x1, 3):
                if (cx // 3 + i) % 4 == 0:      # un quart des colonnes saute
                    fr[y0:y1 - 1, cx:cx + 3] = a[y0 + 1:y1, cx:cx + 3]
    for box in cfg.get("fixe", []):           # bâtiments clairs pris pour du ciel (villa, phare)
        x0, y0, x1, y1 = box
        for fr in frames:
            fr[y0:y1, x0:x1] = a[y0:y1, x0:x1]
    return [Image.fromarray(f) for f in frames]


# Réglages par décor (ordonnées dans le calque 512×216 ; le sol cache y ≥ 176).
ANIM = {
    "cote_basques": {"ciel": 64, "mer": (64, 176), "personnes": [(200, 118, 512, 176)], "fixe": [(322, 4, 390, 92)]},
    "rocher_vierge": {"ciel": 92, "mer": (94, 200), "personnes": [(300, 112, 512, 142)]},
    "fronton": {"ciel": 56},
    "stade": {"ciel": 36, "foule": [(86, 74, 440, 108)]},
}


def main(sid, n):
    d = os.path.join(ROOT, "assets", "stages", sid)
    base = Image.open(os.path.join(d, "far_0.png"))
    for i, fr in enumerate(animate(base, ANIM[sid], n)):
        fr.save(os.path.join(d, f"far_{i}.png"))
    for j in range(n, 8):
        p = os.path.join(d, f"far_{j}.png")
        if os.path.exists(p):
            os.remove(p)
    return d


if __name__ == "__main__":
    n = int(sys.argv[sys.argv.index("--images") + 1]) if "--images" in sys.argv else 4
    for sid in [a for a in sys.argv[1:] if not a.startswith("--") and not a.isdigit()]:
        print(main(sid, n))
