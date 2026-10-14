#!/usr/bin/env python3
"""Portraits indexés depuis les portraits RD 96×96 (SPEC §10.4, §11.5).

Pour chaque perso : détourage (remplissage depuis les bords sur les couleurs
de fond lues en diagonale jusqu'au premier contour), indexation sur la palette
du perso, puis dérivés :
  portrait.png      96×96   (mode L, index de palette)
  portrait_big.png  160×200 (×2 nearest, recadré sur le visage)
  portrait_hud.png  40×40   (réduction ×2 par vote majoritaire)
  portrait_small.png 28×28  (tête, grille de sélection)
  portrait_ko.png   96×96   (yeux en croix, bouche ouverte)
Les positions des yeux et de la bouche sont relevées à la main sur la
planche tests/out/rig/portraits_grid.png (FACES ci-dessous).
Usage : make_rd_portraits.py [id …]
"""
from __future__ import annotations

import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "rig"))
import rd_rig  # noqa: E402
from rig import vote_down  # noqa: E402

OUTLINE_RGB = np.array([58, 38, 52])
# yeux : boîtes (x0, y0, x1, y1) ; bouche : centre ; tête : boîte de recadrage carrée
FACES = {
    "louis": {"src": "tools/rd/cache/0fc7bc58c065dd0d941e1688f7ae9557822cef25_0.png", "protect": (28, 20, 68, 46), "eyes": [(40, 24, 48, 31), (58, 24, 64, 31)], "mouth": (52, 38), "head": (12, 0, 72, 60)},
    "maia": {"src": "assets/fighters/maia/rd_portrait.png", "protect": (40, 20, 76, 56), "eyes": [(48, 36, 57, 42), (66, 36, 70, 42)], "mouth": (60, 51), "head": (28, 6, 84, 62)},
    "patxi": {"protect": (36, 27, 66, 52), "eyes": [(44, 32, 48, 37), (53, 32, 57, 37)], "mouth": (52, 47), "head": (20, 6, 76, 62)},
    "mattin": {"protect": (30, 16, 60, 40), "eyes": [(41, 21, 45, 25), (50, 21, 54, 25)], "mouth": (47, 31), "head": (20, 4, 76, 60)},
    "amaia": {"protect": (36, 24, 66, 52), "eyes": [(42, 34, 47, 40), (56, 34, 60, 40)], "mouth": (52, 46), "head": (22, 8, 78, 64)},
    "txomin": {"flood_ymax": 76, "protect": (30, 28, 70, 64), "eyes": [(35, 33, 52, 40), (56, 33, 66, 40)], "mouth": (54, 57), "head": (16, 6, 72, 62)},
    # Kaio : décor chargé (détourage depuis le haut) ; texte CHIPS aplati
    "kaio": {"flood_ymax": 60, "fills": [(33, 59, 53, 68, "ed6054")], "protect": (34, 14, 80, 44),
             "eyes": [(41, 22, 49, 29)], "mouth": (62, 38), "head": (24, 4, 80, 60)},
    "karramarro": {"protect": (46, 10, 70, 28), "eyes": [(47, 15, 53, 23), (62, 15, 68, 23)], "mouth": (58, 48), "head": (30, 4, 86, 60)},
    "ramuntxo": {"seal": 1, "protect": (36, 40, 64, 64), "eyes": [(46, 44, 51, 50), (54, 45, 59, 50)], "mouth": (52, 57), "head": (22, 10, 78, 66)},
    "itsaso": {"protect": (46, 28, 76, 56), "eyes": [(56, 36, 62, 41), (66, 37, 70, 41)], "mouth": (61, 49), "head": (28, 8, 84, 64)},
    "peio": {"src": "tools/rd/cache/834a7be0c9a517acf2f99be79ba12848e44c1371_0.png", "protect": (34, 26, 76, 66), "eyes": [(42, 40, 51, 49), (64, 40, 72, 49)], "mouth": (58, 58), "head": (22, 10, 78, 66), "big_x0": 16},
    "itsasargi": {"protect": (24, 16, 58, 48), "eyes": [(33, 24, 37, 28), (41, 24, 46, 28)], "mouth": (45, 36), "head": (12, 2, 68, 58)},
    "xabi": {"big_x0": 32, "protect": (24, 22, 58, 52), "eyes": [(34, 32, 40, 40)], "mouth": (44, 50), "head": (12, 2, 68, 58)},
}


def detour(rgba: np.ndarray, flood_ymax: int = 0, keep=None, seal: int = 0) -> np.ndarray:
    """Masque des pixels de fond (connexes au bord, couleurs de fond).
    flood_ymax > 0 : fond chargé (décor) → tout ce qui n'est pas contour,
    connexe aux bords haut/latéraux au-dessus de flood_ymax."""
    rgb = rgba[..., :3].astype(int)
    H, W = rgb.shape[:2]
    if flood_ymax:
        is_bg = np.abs(rgb - OUTLINE_RGB).sum(-1) >= 60
        is_bg &= np.abs(rgb - np.array([24, 16, 28])).sum(-1) >= 40
        bg = np.zeros((H, W), bool)
        q = deque()
        starts = [(0, x) for x in range(W)] + [(y, x) for y in range(flood_ymax) for x in (0, W - 1)]
        for y, x in starts:
            if is_bg[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
        while q:
            y, x = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and not bg[ny, nx] and is_bg[ny, nx]:
                    bg[ny, nx] = True
                    q.append((ny, nx))
        # cadre du décor (lignes sombres au bord de l'image)
        bg[0, :] = True
        bg[:flood_ymax, 0] = True
        bg[:, -1] = True
        for x in (1, W - 2):
            bg[:flood_ymax, x] |= ~is_bg[:flood_ymax, x] & bg[:flood_ymax, x - 1 if x == 1 else x + 1]
        return bg
    seeds = []
    for k in range(min(H, W)):
        c = rgb[k, k]
        if np.abs(c - OUTLINE_RGB).sum() < 60:
            break
        if not any(np.abs(c - s).sum() < 24 for s in seeds):
            seeds.append(c)
    is_bg = np.zeros((H, W), bool)
    for s in seeds:
        is_bg |= np.abs(rgb - s).sum(-1) < 24
    for k in keep or []:
        # fond de la couleur de la peau : visage et mains ne sont jamais du fond
        is_bg[k[1]:k[3], k[0]:k[2]] = False
    bg = np.zeros((H, W), bool)
    q = deque()
    for y in range(H):
        for x in (0, W - 1):
            if is_bg[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for x in range(W):
        for y in (0, H - 1):
            if is_bg[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    flood_ok = is_bg.copy()
    if seal:
        # fond de la couleur de la peau : les trous du contour sont bouchés
        # (contour épaissi de `seal` px) le temps du remplissage
        dark = rgb.sum(-1) < 200
        for _ in range(seal):
            p = np.pad(dark, 1)
            dark = dark | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        flood_ok &= ~dark
        bg &= flood_ok
        q = deque((y, x) for y, x in zip(*np.nonzero(bg)))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and not bg[ny, nx] and flood_ok[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    for _ in range(seal):
        p = np.pad(bg, 1)
        bg = bg | (is_bg & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]))
    return bg


def portrait_index(fid, rgba, prot):
    """Même indexation par groupes que le sprite : une couleur prend le groupe
    qu'elle a le plus souvent dans la pose RD ; le visage reste « fixed »."""
    slots, gmap, _, _ = rd_rig.rd_palette(fid)
    if rd_rig.load_spec(fid).get("palette_slots"):
        # Perso régénéré (build_rd_anims) : mêmes règles de groupe par teinte.
        import build_rd_anims as bra
        bra.FID = fid
        g = np.full(rgba.shape[:2], "fixed", dtype=object)
        for y, x in zip(*np.nonzero(rgba[..., 3] > 127)):
            # visage : couleur la plus proche parmi toutes (dents, yeux blancs)
            g[y, x] = "visage" if prot[y, x] else bra.group_of(rgba[y, x])
        return rd_rig.index_grouped(rgba, g, slots)
    pose = rd_rig.pose_rgba(rd_rig.load_spec(fid))
    votes = {}
    for y, x in zip(*np.nonzero(pose[..., 3] > 127)):
        key = tuple(int(v) for v in pose[y, x, :3])
        votes.setdefault(key, {}).setdefault(gmap[y, x], 0)
        votes[key][gmap[y, x]] += 1
    g = np.full(rgba.shape[:2], "fixed", dtype=object)
    for y, x in zip(*np.nonzero(rgba[..., 3] > 127)):
        v = votes.get(tuple(int(c) for c in rgba[y, x, :3]))
        if v and not prot[y, x]:
            g[y, x] = max(v, key=v.get)
    return rd_rig.index_grouped(rgba, g, slots)


def skin_index(fid) -> int:
    return 4  # contrat : 3–6 = peau, 4 = ton principal


def make(fid):
    src = FACES[fid].get("src")
    if src is None:
        ps = json.load(open(os.path.join(ROOT, "tools", "rd", "out", "portraits.json")))
        p7 = os.path.join(ROOT, "tools", "rd", "out", "p7_assets.json")
        if fid not in ps and os.path.exists(p7):
            ps[fid] = json.load(open(p7))[fid]["portrait"]
        src = ps[fid]
    rgba = np.array(Image.open(os.path.join(ROOT, src)).convert("RGBA"))
    for x0, y0, x1, y1, h in FACES[fid].get("fills", []):
        rgba[y0:y1 + 1, x0:x1 + 1, :3] = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    bg = detour(rgba, FACES[fid].get("flood_ymax", 0), FACES[fid].get("keep"), FACES[fid].get("seal", 0))
    rgba[bg, 3] = 0
    face0 = FACES[fid]
    prot = np.zeros(rgba.shape[:2], bool)
    px0, py0, px1, py1 = face0["protect"]
    prot[py0:py1, px0:px1] = True
    idx = portrait_index(fid, rgba, prot)
    # contour extérieur unifié (le bord du buste en bas de l'image reste ouvert)
    m = idx > 0
    p = np.pad(m, 1, constant_values=False)
    edge = m & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    edge[-1, :] = False
    idx[edge] = 1
    idx = despeckle(idx)
    d = rd_rig.fighter_dir(fid)
    face = FACES[fid]
    Image.fromarray(idx, "L").save(os.path.join(d, "portrait.png"))
    # grand portrait 160×200 : ×2, cadré sur le visage
    big = np.kron(idx, np.ones((2, 2), np.uint8))
    hx0, hy0, hx1, hy1 = face["head"]
    cx = (hx0 + hx1)  # centre ×2
    x0 = int(face.get("big_x0", np.clip(cx - 80, 0, big.shape[1] - 160)))
    crop = big[:, x0:x0 + 160]
    out = np.zeros((200, 160), np.uint8)
    out[8:8 + crop.shape[0], :] = crop[:192]
    Image.fromarray(out, "L").save(os.path.join(d, "portrait_big.png"))
    # tête : 56×56 → 28×28 (vote) ; HUD : 80×80 → 40×40
    head = _square(idx, face["head"], 56)
    Image.fromarray(vote_down(head, 2), "L").save(os.path.join(d, "portrait_small.png"))
    hx = (hx0 + hx1) // 2
    hud = _square(idx, (hx - 40, max(hy0 - 4, 0), hx + 40, max(hy0 - 4, 0) + 80), 80)
    Image.fromarray(vote_down(hud, 2), "L").save(os.path.join(d, "portrait_hud.png"))
    # K.O. : yeux en croix, bouche ouverte
    ko = idx.copy()
    for (x0e, y0e, x1e, y1e) in face["eyes"]:
        # peau autour de l'œil : pixel le plus fréquent juste sous la boîte
        below = idx[min(y1e + 2, 95), x0e:x1e + 1]
        below = below[below > 1]
        skin = int(np.bincount(below).argmax()) if below.size else 1
        ko[y0e:y1e + 1, x0e:x1e + 1] = np.where(ko[y0e:y1e + 1, x0e:x1e + 1] > 0, skin, 0)
        n = max(x1e - x0e, y1e - y0e)
        for t in range(n + 1):
            xa = x0e + round(t * (x1e - x0e) / max(n, 1))
            ya = y0e + round(t * (y1e - y0e) / max(n, 1))
            yb = y1e - round(t * (y1e - y0e) / max(n, 1))
            for (xx, yy) in ((xa, ya), (xa, yb)):
                if 0 <= yy < 96 and 0 <= xx < 96:
                    ko[yy, xx] = 1
    mx, my = face["mouth"]
    ko[my - 2:my + 3, mx - 2:mx + 3] = 1
    # intérieur de la bouche : la couleur fixe la plus sombre hors contour
    fixed_dark = _darkest_fixed(fid)
    ko[my - 1:my + 2, mx - 1:mx + 2] = fixed_dark
    Image.fromarray(ko, "L").save(os.path.join(d, "portrait_ko.png"))
    return idx


def despeckle(idx, max_size=3):
    """Taches parasites : composante de ≤ max_size pixels d'une couleur
    (hors contour) → couleur majoritaire autour."""
    out = idx.copy()
    H, W = idx.shape
    seen = np.zeros((H, W), bool)
    for y in range(H):
        for x in range(W):
            v = idx[y, x]
            if v <= 1 or seen[y, x]:
                continue
            comp, q = [], [(y, x)]
            seen[y, x] = True
            while q:
                cy, cx = q.pop()
                comp.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and not seen[ny, nx] and idx[ny, nx] == v:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            if len(comp) > max_size:
                continue
            ring = []
            for cy, cx in comp:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and idx[ny, nx] not in (0, 1, v):
                            ring.append(idx[ny, nx])
            if len(ring) >= len(comp):
                fill = np.bincount(ring).argmax()
                for cy, cx in comp:
                    out[cy, cx] = fill
    return out


def _darkest_fixed(fid):
    slots, _, _, _ = rd_rig.rd_palette(fid)
    cands = [(sum(c), i + 1) for i, (g, c) in enumerate(slots) if g == "fixed" and i > 0 and sum(c) > 150]
    return min(cands)[1] if cands else 1


def _square(idx, box, size):
    x0, y0, x1, y1 = box
    out = np.zeros((size, size), np.uint8)
    sub = idx[max(y0, 0):max(y0, 0) + size, max(x0, 0):max(x0, 0) + size]
    out[:sub.shape[0], :sub.shape[1]] = sub
    return out


def sheet(ids, scale=4):
    tiles = []
    for fid in ids:
        d = rd_rig.fighter_dir(fid)
        pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))
        row = []
        for name in ("portrait", "portrait_ko", "portrait_big", "portrait_hud", "portrait_small"):
            a = np.array(Image.open(os.path.join(d, name + ".png")))
            for k in (0, 1):
                if k == 1 and name != "portrait":
                    continue
                row.append(Image.fromarray(pal[k][a].astype(np.uint8), "RGBA"))
        tiles.append(row)
    W = max(sum(t.width + 4 for t in row) for row in tiles)
    H = sum(max(t.height for t in row) + 4 for row in tiles)
    img = Image.new("RGBA", (W, H), (90, 96, 120, 255))
    y = 0
    for row in tiles:
        x = 0
        for t in row:
            img.alpha_composite(t, (x, y))
            x += t.width + 4
        y += max(t.height for t in row) + 4
    img = img.resize((img.width * scale // 2, img.height * scale // 2), Image.NEAREST)
    path = os.path.join(ROOT, "tests", "out", "sheets", "portraits_rd.png")
    img.save(path)
    return path


if __name__ == "__main__":
    ids = sys.argv[1:] or list(FACES)
    for fid in ids:
        make(fid)
    print(sheet(ids))
