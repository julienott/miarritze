#!/usr/bin/env python3
"""Rig cut-out découpé dans une pose Retro Diffusion (SPEC §11.3 étape 3).

Entrée : assets/fighters/<id>/rig.json écrit à la main en regardant la pose
RD agrandie (tools/rig/rd_view.py) :
  "image"  : pose RD finale (PNG transparent, cellule du perso)
  "bones"  : {os: {"pivot": [x, y], "tip": [x, y], "r": rayon, "kind": "up"|"down",
                   "fill": rayon de reconstruction (zones cachées), "parent": os}}
  "polys"  : {os: [[[x, y], …], …]}  zones forcées (prioritaires sur la géométrie)
  "order"  : ordre de dessin (arrière → avant)
Le builder :
  1. indexe la pose (couleur → index de palette, rôle majoritaire du mannequin) ;
  2. attribue chaque pixel à l'os le plus proche (distance au segment / rayon),
     sauf zones forcées ;
  3. reconstruit les zones cachées par un os placé devant (épaule sous le bras,
     bras arrière derrière le torse…) en prolongeant les couleurs de la pièce ;
  4. retire le contour extérieur de chaque pièce (il est régénéré à 1 px après
     rotation) ;
  5. produit les Piece avec leur orientation RD (`base`) : rendue dans la pose
     d'origine, chaque pièce reproduit la pose RD au pixel près.
Il réécrit dans rig.json les masques polygonaux calculés (« mask ») et les
angles mesurés (« world », « guard »).
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "sprites"))

from rig import Bone, Piece, Rig, rotate  # noqa: E402
sys.path.insert(0, os.path.join(HERE, ".."))
import indices as ix  # noqa: E402

SKELETON = ["pel", "tor", "head", "uaf", "faf", "uab", "fab", "thf", "shf", "thb", "shb"]
PARENT = {"pel": None, "tor": "pel", "head": "tor", "uaf": "tor", "faf": "uaf", "uab": "tor",
          "fab": "uab", "thf": "pel", "shf": "thf", "thb": "pel", "shb": "thb",
          "acc": "tor", "accf": "faf", "accb": "fab"}
ATTACH_KEY = {"faf": "fa", "fab": "fa", "shf": "sh", "shb": "sh", "accf": "hand", "accb": "hand"}
DEFAULT_ORDER = ["uab", "fab", "thb", "shb", "pel", "tor", "thf", "shf", "head", "uaf", "faf"]


def fighter_dir(fid):
    return os.path.join(ROOT, "assets", "fighters", fid)


def load_spec(fid):
    with open(os.path.join(fighter_dir(fid), "rig.json")) as f:
        return json.load(f)


def has_rd_rig(fid):
    path = os.path.join(fighter_dir(fid), "rig.json")
    if not os.path.exists(path):
        return False
    return json.load(open(path)).get("source") == "rd"


# ------------------------------------------------------------------ indexation

# Index jamais modifiés par les costumes (contrat §1) : contour, yeux, peau, cheveux.
FIXED_INDICES = list(range(1, 10))


def index_image(fid, rgba: np.ndarray, protect: np.ndarray | None = None) -> np.ndarray:
    """Couleur RD → index de palette (costume 1). Quand plusieurs index ont la
    même couleur, on prend celui que le mannequin utilise le plus (le rôle
    « réel » : la chemise plutôt que le blanc des yeux). Dans `protect`
    (visage), seuls les index fixes sont permis : les costumes ne recolorent
    jamais les yeux ni les joues."""
    pal = np.array(Image.open(os.path.join(fighter_dir(fid), "palettes.png")).convert("RGBA"))[0, :, :3].astype(int)
    usage = mannequin_usage(fid)
    out = np.zeros(rgba.shape[:2], np.uint8)
    opaque = rgba[..., 3] > 127
    if protect is None:
        protect = np.zeros(out.shape, bool)
    cols = np.unique(rgba[opaque][:, :3], axis=0)
    for c in cols:
        same = opaque & np.all(rgba[..., :3] == c, axis=-1)
        d = ((pal[1:] - c.astype(int)) ** 2).sum(1)
        best = d.min()
        cands = [i + 1 for i in np.nonzero(d <= best + 12)[0]]
        out[same & ~protect] = max(cands, key=lambda i: (usage.get(i, 0), -d[i - 1]))
        if (same & protect).any():
            fixed = min(FIXED_INDICES, key=lambda i: d[i - 1])
            out[same & protect] = fixed
    return out


def protect_mask(spec, shape) -> np.ndarray:
    m = np.zeros(shape, bool)
    for poly in spec.get("protect", []):
        m |= poly_mask(shape, poly)
    return m


# ------------------------------------------------------------------ palette RD
# Indexation par (groupe, couleur) : le groupe d'un pixel dépend de sa couleur
# ET de l'os qui le porte (règles « groups » de rig.json). Tout pixel hors
# groupe (peau, cheveux, yeux, contour, zones protégées) est « fixed » et ne
# change jamais de couleur dans les costumes. Une même couleur RD peut donc
# occuper deux index (mains de Maïa = fixed, planche = board).

def _hex(c):
    return "%02x%02x%02x" % tuple(int(v) for v in c[:3])


def pose_rgba(spec):
    return np.array(Image.open(os.path.join(ROOT, spec["image"])).convert("RGBA"))


def group_map(spec, rgba, label=None, names=None) -> np.ndarray:
    H, W = rgba.shape[:2]
    out = np.full((H, W), "fixed", dtype=object)
    opaque = rgba[..., 3] > 127
    hexes = np.full((H, W), "", dtype=object)
    ys, xs = np.nonzero(opaque)
    for y, x in zip(ys, xs):
        hexes[y, x] = _hex(rgba[y, x])
    for rule in spec.get("groups", []):
        sel = opaque & np.isin(hexes, rule["colors"])
        if "bones" in rule and label is not None:
            ok = np.isin(label, [names.index(b) for b in rule["bones"] if b in names])
            sel &= ok
        out[sel & (out == "fixed")] = rule["group"]
    out[protect_mask(spec, (H, W))] = "fixed"
    out[~opaque] = ""
    return out


def rd_palette(fid, spec=None):
    """Slots (groupe, couleur) de la pose RD, index 1 = contour. Écrit palettes.png."""
    spec = spec or load_spec(fid)
    rgba = pose_rgba(spec)
    opaque = rgba[..., 3] > 127
    names, label = segment(fid, spec, opaque.astype(np.uint8))
    gmap = group_map(spec, rgba, label, names)
    counts = {}
    for y, x in zip(*np.nonzero(opaque)):
        key = (gmap[y, x], tuple(int(v) for v in rgba[y, x, :3]))
        counts[key] = counts.get(key, 0) + 1
    outline = ("fixed", (58, 38, 52))
    keys = sorted(counts, key=lambda k: -counts[k])
    # 31 index au plus : les couleurs les plus rares retombent (index_grouped)
    # sur la couleur la plus proche de leur groupe.
    slots = [outline] + [k for k in keys if k != outline][:30]
    _write_palettes(fid, spec, slots)
    return slots, gmap, label, names


def _lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def _recolor(c, group_cols, ramp_name):
    from palette import RAMPS
    ramp = RAMPS[ramp_name]
    t = np.array(ramp[(len(ramp) - 1) // 2], float)
    mid = np.mean([_lum(g) for g in group_cols]) or 1.0
    r = _lum(c) / mid
    if r <= 1.0:
        out = t * (0.25 + 0.75 * r)
    else:
        out = t + (255.0 - t) * min((r - 1.0) * 1.1, 0.85)
    return tuple(int(v) for v in np.clip(out, 0, 255))


def _write_palettes(fid, spec, slots):
    img = Image.new("RGBA", (32, 4), (0, 0, 0, 0))
    groups = {}
    for g, c in slots:
        groups.setdefault(g, []).append(c)
    for k in range(4):
        targets = spec.get("costumes", {}).get(str(k), {}) if k else {}
        for i, (g, c) in enumerate(slots):
            col = c
            if g != "fixed" and g in targets:
                col = _recolor(c, groups[g], targets[g])
            img.putpixel((i + 1, k), tuple(col) + (255,))
    img.save(os.path.join(fighter_dir(fid), "palettes.png"))


def index_grouped(rgba, gmap, slots) -> np.ndarray:
    """Pixel → index du slot (groupe, couleur) ; repli : couleur la plus proche du groupe."""
    lut = {s: i + 1 for i, s in enumerate(slots)}
    arr = np.array([c for _, c in slots], int)
    out = np.zeros(rgba.shape[:2], np.uint8)
    for y, x in zip(*np.nonzero(rgba[..., 3] > 127)):
        g = gmap[y, x] or "fixed"
        c = tuple(int(v) for v in rgba[y, x, :3])
        i = lut.get((g, c))
        if i is None:
            d = ((arr - np.array(c)) ** 2).sum(1)
            same = [j for j, (gg, _) in enumerate(slots) if gg == g] or list(range(len(slots)))
            i = min(same, key=lambda j: d[j]) + 1
        out[y, x] = i
    return out


def index_frame(fid, rgba) -> np.ndarray:
    """Frame d'une anim RD (même repère que la pose) : groupe repris de la
    pose au même endroit (ou au pixel étiqueté le plus proche)."""
    spec = load_spec(fid)
    slots, gmap, _, _ = rd_palette(fid, spec)
    H, W = rgba.shape[:2]
    pg = np.full((H, W), "fixed", dtype=object)
    h, w = min(H, gmap.shape[0]), min(W, gmap.shape[1])
    pg[:h, :w] = gmap[:h, :w]
    return index_grouped(rgba, _fill_groups(pg), slots)


def _fill_groups(pg):
    """Comble les cases sans groupe par le groupe du voisin le plus proche."""
    out = pg.copy()
    empty = out == ""
    for _ in range(12):
        if not empty.any():
            break
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(np.roll(out, dy, 0), dx, 1)
            take = empty & (src != "")
            out[take] = src[take]
            empty = out == ""
    out[out == ""] = "fixed"
    return out


def mannequin_usage(fid) -> dict:
    """Nombre de pixels par index dans la feuille mannequin (backup si présent)."""
    for name in ("sheet_mannequin.png", "sheet.png"):
        path = os.path.join(fighter_dir(fid), name)
        if os.path.exists(path):
            arr = np.array(Image.open(path))
            vals, counts = np.unique(arr, return_counts=True)
            return {int(v): int(c) for v, c in zip(vals, counts) if v > 0}
    return {}


# ------------------------------------------------------------------ géométrie

def seg_dist(X, Y, a, b):
    ax, ay = a
    bx, by = b
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy or 1e-6
    t = np.clip(((X - ax) * vx + (Y - ay) * vy) / L2, 0.0, 1.0)
    px, py = ax + t * vx, ay + t * vy
    return np.hypot(X - px, Y - py)


def world_angle(b) -> float:
    dx = b["tip"][0] - b["pivot"][0]
    dy = b["tip"][1] - b["pivot"][1]
    if b.get("kind", "down") == "up":
        return math.degrees(math.atan2(-dx, -dy))
    return math.degrees(math.atan2(dx, dy))


def poly_mask(shape, poly):
    from PIL import ImageDraw
    img = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(img).polygon([tuple(p) for p in poly], fill=1, outline=1)
    return np.array(img, bool)


def _neigh(m):
    p = np.pad(m, 1)
    return p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]


def grow_fill(img, own, target):
    """Propage les couleurs (hors contour) de `own` dans `target` (plus proche voisin)."""
    out = img.copy()
    have = own & (img > 1)
    todo = target & ~have
    for _ in range(64):
        if not todo.any():
            break
        new_have = have.copy()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
            src = np.roll(np.roll(have, dy, 0), dx, 1)
            vals = np.roll(np.roll(out, dy, 0), dx, 1)
            take = todo & src & ~new_have
            out[take] = vals[take]
            new_have |= take
        todo &= ~new_have
        have = new_have
    return out, target & have


# ------------------------------------------------------------------ construction

def segment(fid, spec, idx):
    H, W = idx.shape
    Y, X = np.mgrid[0:H, 0:W] + 0.5
    opaque = idx > 0
    bones = spec["bones"]
    names = [n for n in list(SKELETON) + ["acc", "accf", "accb"] if n in bones]
    cost = np.full((len(names), H, W), np.inf)
    for k, n in enumerate(names):
        b = bones[n]
        a, c = b.get("seg", [b["pivot"], b["tip"]])
        cost[k] = seg_dist(X, Y, a, c) / float(b.get("r", 6))
    label = np.where(opaque, np.argmin(cost, axis=0), -1)
    for n, polys in spec.get("polys", {}).items():
        k = names.index(n)
        for poly in polys:
            label[opaque & poly_mask(idx.shape, poly)] = k
    return names, label


def build_pieces(fid, spec=None):
    spec = spec or load_spec(fid)
    rgba = pose_rgba(spec)
    if spec.get("groups"):
        slots, gmap, _, _ = rd_palette(fid, spec)
        idx = index_grouped(rgba, gmap, slots)
    else:
        idx = index_image(fid, rgba, protect_mask(spec, rgba.shape[:2]))
    names, label = segment(fid, spec, idx)
    H, W = idx.shape
    Y, X = np.mgrid[0:H, 0:W] + 0.5
    order = spec.get("order", DEFAULT_ORDER)
    rank = {n: i for i, n in enumerate(order)}
    bones = spec["bones"]
    pieces, masks, worlds, mains = {}, {}, {}, {}
    opaque_all = idx > 0
    for k, n in enumerate(names):
        b = bones[n]
        own = label == k
        img = np.where(own, idx, 0).astype(np.uint8)
        # Zones cachées : dans la capsule de l'os mais prises par un os dessiné DEVANT.
        fill_r = float(b.get("fill", 0))
        if fill_r > 0:
            a, c = b.get("seg", [b["pivot"], b["tip"]])
            caps = seg_dist(X, Y, a, c) <= fill_r
            front = np.zeros_like(own)
            for k2, n2 in enumerate(names):
                if n2 != n and rank.get(n2, 0) > rank.get(n, 0):
                    front |= label == k2
            hidden = caps & front
            # Couleur dominante de la pièce (hors contour) : pas de taches
            # d'ombre propagées dans les zones reconstruites.
            vals, counts = np.unique(img[own & (img > 1)], return_counts=True)
            main = vals[counts.argmax()] if len(vals) else mains.get(PARENT.get(n), 0)
            if main:
                # Membre entièrement caché (bras arrière) : toute sa capsule.
                add = (hidden if len(vals) else caps & opaque_all) & ~own
                img[add] = main
                own = own | add
        # Contour extérieur retiré : add_outline le régénère à 1 px après rotation.
        up, down, left, right = _neigh(own)
        border = own & ~(up & down & left & right)
        img[border & (img == ix.OUTLINE)] = 0
        own = img > 0
        ys, xs = np.nonzero(own)
        if len(ys) == 0:
            continue
        vals2, counts2 = np.unique(img[img > 1], return_counts=True)
        if len(vals2):
            mains[n] = vals2[counts2.argmax()]
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = img[y0:y1, x0:x1].copy()
        px, py = b["pivot"]
        w = world_angle(b) if n in SKELETON or "tip" in b else 0.0
        worlds[n] = w
        pieces[n] = Piece(img=crop, pivot=(px - x0, py - y0), shade=False, base=w)
        masks[n] = own
    # Points d'attache (dans le repère RD de chaque parent).
    for n in pieces:
        parent = PARENT.get(n)
        if parent is None or parent not in pieces:
            continue
        pb, cb = bones[parent], bones[n]
        v = (cb["pivot"][0] - pb["pivot"][0], cb["pivot"][1] - pb["pivot"][1])
        key = ATTACH_KEY.get(n, n)
        pieces[parent].attach[key] = rotate(v, -worlds[parent])
    return pieces, masks, worlds, idx, label, names


def guard_pose(spec, worlds) -> dict:
    """Angles locaux de la pose RD (= garde du perso)."""
    pose = {}
    for n in SKELETON:
        if n not in worlds:
            continue
        parent = PARENT[n]
        pose[n] = round(worlds[n] - (worlds[parent] if parent else 0.0), 1)
    for n in ("acc", "accf", "accb"):
        if n in worlds:
            pose[n] = 0.0
    pose["root"] = [0, 0]
    return pose


# Surcharges communes aux rigs RD : dans les poses RD (vue de profil), le bras
# arrière est très raccourci, presque caché par le torse. Le 2e coup de
# l'auto-combo devient un direct appuyé du bras AVANT, plus lisible.
RD_DEFAULT_ANIMS = {
    "punch_2": {"frames": 4, "fps": 20, "loop": False, "base": "guard", "hit_frame": 2, "keys": [
        {"t": 0, "p": {}},
        {"t": 1, "p": {"uaf": 55, "faf": 70, "tor": -4, "root": [-1, 0]}},
        {"t": 2, "p": {"uaf": 96, "faf": -6, "tor": -22, "head": 14, "thf": 38, "root": [3, 1],
                       "str": {"uaf": [1.0, 1.15], "faf": [1.0, 1.25]}}},
        {"t": 3, "p": {"uaf": 76, "faf": 30, "tor": -12, "root": [1, 0]}},
        {"t": 4, "use": "guard", "p": {"root": [0, 0]}}]},
    # Txapel-cut : accroupi, détente, bras tendu au zénith, corps décollé du sol.
    "uppercut": {"frames": 6, "fps": 16, "loop": False, "base": "crouch", "hit_frame": 3, "hit_dir": "up", "keys": [
        {"t": 0, "p": {"lift": 0}},
        {"t": 1, "p": {"tor": -22, "uaf": 40, "faf": 100, "head": 16, "root": [-1, 2]}},
        {"t": 2, "use": "guard", "p": {"tor": 2, "uaf": 140, "faf": 30, "thf": 30, "shf": -10, "thb": -12, "shb": 0,
                                       "root": [2, 0], "lift": 6, "str": {"uaf": [1.0, 1.15]}}},
        {"t": 3, "use": "guard", "p": {"tor": 10, "head": -12, "uaf": 176, "faf": 0, "uab": -40, "fab": 30,
                                       "thf": 40, "shf": -60, "thb": -6, "shb": 0, "root": [4, 0], "lift": 14,
                                       "str": {"uaf": [1.0, 1.25], "faf": [1.0, 1.3]}, "squash": [0.94, 1.08]}},
        {"t": 4, "use": "guard", "p": {"tor": 8, "head": -10, "uaf": 170, "faf": 8, "uab": -30, "fab": 30,
                                       "thf": 30, "shf": -40, "thb": -4, "shb": 0, "root": [3, 0], "lift": 9}},
        {"t": 5, "use": "guard", "p": {"root": [0, 0], "lift": 0}}]},
}


def pose_overrides(fid) -> dict:
    """Surcharges de poses propres au rig RD : communes (RD_DEFAULT_ANIMS)
    puis tools/rig/poses/<id>_rd.json."""
    out = {"anims": json.loads(json.dumps(RD_DEFAULT_ANIMS)), "named": {}}
    path = os.path.join(HERE, "poses", f"{fid}_rd.json")
    if os.path.exists(path):
        own = json.load(open(path))
        out["anims"].update(own.get("anims", {}))
        out["named"].update(own.get("named", {}))
    return out


def build_rig(fid):
    """Renvoie (Rig, garde mesurée) pour un perso à rig RD."""
    spec = load_spec(fid)
    pieces, masks, worlds, idx, label, names = build_pieces(fid, spec)
    bones = []
    for n in SKELETON + ["acc", "accf", "accb"]:
        if n not in pieces:
            continue
        rest = 0.0
        if n in ("acc", "accf", "accb"):
            rest = worlds[n] - worlds[PARENT[n]]
        lock = worlds[n] if spec["bones"][n].get("lock") else None
        bones.append(Bone(n, PARENT[n], n, ATTACH_KEY.get(n, ""), rest=rest,
                          soft_joint=n not in ("head", "uaf", "uab", "acc", "accf", "accb"),
                          lock_angle=lock))
    families = {}
    for role, (start, cnt) in ix.ROLES.items():
        for i in range(start, start + cnt):
            families[i] = start
    order = [n for n in spec.get("order", DEFAULT_ORDER) if n in pieces]
    rig = Rig(bones, pieces, order, ix.shade_ramps(), families)
    return rig, guard_pose(spec, worlds)


def export_masks(fid):
    """Écrit les masques polygonaux (enveloppe convexe) et les angles mesurés
    dans rig.json, et une planche « pièces éclatées »."""
    spec = load_spec(fid)
    pieces, masks, worlds, idx, label, names = build_pieces(fid, spec)
    for n, m in masks.items():
        ys, xs = np.nonzero(m)
        pts = np.stack([xs, ys], 1)
        spec["bones"][n]["mask"] = [[int(x), int(y)] for x, y in _hull(pts)]
        spec["bones"][n]["world"] = round(worlds[n], 1)
    spec["guard"] = guard_pose(spec, worlds)
    with open(os.path.join(fighter_dir(fid), "rig.json"), "w") as f:
        json.dump(spec, f, indent=1)
    return exploded_sheet(fid, pieces)


def _hull(pts):
    pts = sorted(set(map(tuple, pts.tolist())))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def exploded_sheet(fid, pieces, scale=4):
    pal = np.array(Image.open(os.path.join(fighter_dir(fid), "palettes.png")).convert("RGBA"))[0]
    tiles = []
    for n, p in pieces.items():
        img = Image.fromarray(pal[p.img].astype(np.uint8), "RGBA")
        canvas = Image.new("RGBA", (img.width + 8, img.height + 8), (90, 96, 120, 255))
        canvas.alpha_composite(img, (4, 4))
        cx, cy = int(p.pivot[0]) + 4, int(p.pivot[1]) + 4
        for d in range(-2, 3):
            if 0 <= cx + d < canvas.width:
                canvas.putpixel((cx + d, cy), (255, 0, 255, 255))
            if 0 <= cy + d < canvas.height:
                canvas.putpixel((cx, cy + d), (255, 0, 255, 255))
        tiles.append((n, canvas))
    W = sum(t.width for _, t in tiles) + 4 * len(tiles)
    H = max(t.height for _, t in tiles) + 12
    sheet = Image.new("RGBA", (W, H), (60, 64, 84, 255))
    x = 0
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for n, t in tiles:
        sheet.alpha_composite(t, (x, 12))
        d.text((x + 1, 0), n, fill=(255, 255, 255, 255))
        x += t.width + 4
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    out = os.path.join(ROOT, "tests", "out", "rig")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, f"{fid}_pieces.png")
    sheet.save(path)
    return path


def labels_view(fid, scale=5):
    """Image de contrôle : pose RD colorée par os."""
    spec = load_spec(fid)
    rgba = np.array(Image.open(os.path.join(ROOT, spec["image"])).convert("RGBA"))
    idx = index_image(fid, rgba)
    names, label = segment(fid, spec, idx)
    colors = np.array([(255, 60, 60), (60, 200, 60), (60, 120, 255), (255, 200, 0), (255, 0, 255),
                       (0, 220, 220), (255, 128, 0), (160, 80, 255), (128, 255, 128), (255, 128, 192),
                       (0, 160, 255), (200, 200, 200), (120, 60, 0), (255, 255, 255)], np.uint8)
    out = np.zeros(rgba.shape, np.uint8)
    out[..., 3] = 255
    out[..., :3] = 90
    sel = label >= 0
    base = rgba[..., :3].astype(int)
    tint = colors[label[sel] % len(colors)].astype(int)
    out[sel, :3] = (base[sel] * 0.45 + tint * 0.55).astype(np.uint8)
    img = Image.fromarray(out, "RGBA").resize((rgba.shape[1] * scale, rgba.shape[0] * scale), Image.NEAREST)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for k, n in enumerate(names):
        b = spec["bones"][n]
        P = (b["pivot"][0] * scale, b["pivot"][1] * scale)
        T = (b["tip"][0] * scale, b["tip"][1] * scale)
        d.line([P, T], fill=tuple(int(c) for c in colors[k % len(colors)]) + (255,), width=2)
        d.ellipse([P[0] - 4, P[1] - 4, P[0] + 4, P[1] + 4], outline=(0, 0, 0, 255), fill=(255, 255, 255, 255))
        d.text((P[0] + 6, P[1] - 6), n, fill=(255, 255, 255, 255))
    path = os.path.join(ROOT, "tests", "out", "rig", f"{fid}_labels.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


if __name__ == "__main__":
    for fid in sys.argv[1:]:
        print(labels_view(fid))
        print(export_masks(fid))
