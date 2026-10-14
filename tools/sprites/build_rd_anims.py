#!/usr/bin/env python3
"""Assemble la feuille d'un combattant à partir des animations RD
(tools/rd/out/<id>/anims.json, produit par tools/rd/gen_anims.py).

Pour chaque animation du jeu :
  1. images de la planche RD (case 160), alpha binarisé ;
  2. choix d'autant d'images que le jeu en attend (anims.json), l'image
     d'impact des coups calée sur `hit_frame` ;
  3. recalage : pieds au sol pour les mouvements debout, centre fixe pour
     ceux en l'air ; décalage horizontal commun repris de la pose neutre ;
  4. plis rouges sur la peau repeints, bordures contrôlées (check_borders) ;
  5. indexation sur la palette de la pose neutre (les couleurs RD qui
     dérivent retombent sur la plus proche), contour de silhouette unifié ;
  6. hitboxes déduites des images (infer_boxes), feuille + anims.json.
Usage : build_rd_anims.py <id>
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "rig"))
import check_borders as cb  # noqa: E402
import contact_sheet  # noqa: E402
import indices as ix  # noqa: E402
import infer_boxes  # noqa: E402
import rd_rig  # noqa: E402

SRC = 160
CELL = 192
FOOT = (96, 184)
SHEET_W = 1920
OUTLINE = (58, 38, 52)
AIR = {"jump_up", "jump_fwd", "fall", "jump_punch", "jump_kick", "hit_air", "thrown"}

# anim du jeu -> (anim RD source, sélection d'images ou None)
SOURCES = {
    "jump_up": ("jump", slice(1, 5)),
    "fall": ("jump", slice(4, 6)),
    "crouch_idle": ("crouch", "hold"),
    "block": ("block", "hold"),
    "crouch_block": ("crouch_block", "hold"),
    # RD anime mal un perso en l'air : on reprend des images au sol réussies,
    # placées en l'air (jambe tendue du coup de pied, début de chute arrière).
    "jump_kick": ("kick", None),
    "hit_air": ("knockdown", slice(0, 3)),
}
# Reprises propres à un perso (mouvement RD raté, image réussie ailleurs).
SOURCES_BY = {
    "maia": {
        "crouch": ("sp_down", slice(0, 6)),
        "crouch_idle": ("sp_down", "hold"),
        "crouch_block": ("sp_down", "hold"),
        "ko": ("knockdown", "end_hold"),
        "getup": ("knockdown", "reverse"),
    },
}


def frames_of(path):
    im = np.array(Image.open(os.path.join(ROOT, path)).convert("RGBA"))
    out = []
    for y in range(0, im.shape[0], SRC):
        for x in range(0, im.shape[1], SRC):
            f = im[y:y + SRC, x:x + SRC].copy()
            f[f[..., 3] < 128] = 0
            f[f[..., 3] >= 128, 3] = 255
            if f[..., 3].any():
                out.append(f)
    return out


def bbox(f):
    ys, xs = np.nonzero(f[..., 3])
    return xs.min(), ys.min(), xs.max(), ys.max()


def reach(f, direction):
    # Allonge du corps seul (plus grande composante) : les traits de vitesse
    # et miettes que RD dessine devant le poing ne comptent pas.
    comps = _comps(f[..., 3] > 0)
    body = max(comps, key=len)
    f = np.zeros_like(f)
    ys, xs = zip(*body)
    f[list(ys), list(xs), 3] = 255
    x0, y0, x1, y1 = bbox(f)
    if direction == "up":
        return -y0
    if direction == "low":
        mid = y0 + (y1 - y0) * 2 // 5
        low = f[mid:y1 + 1, :, 3] > 0
        return np.nonzero(low.any(0))[0].max()
    return x1


def pick(frames, n, hit=None, direction="fwd"):
    """n images régulièrement espacées ; si `hit`, l'image de plus grande
    allonge tombe à l'index `hit`."""
    last = len(frames) - 1
    if hit is None or n < 2:
        idx = np.round(np.linspace(0, last, n)).astype(int)
        return [frames[i] for i in idx]
    imp = max(range(len(frames)), key=lambda i: reach(frames[i], direction))
    pre = np.round(np.linspace(0, imp, hit + 1)).astype(int) if hit > 0 else np.array([imp])
    post = np.round(np.linspace(imp, last, n - hit)).astype(int)
    idx = list(pre[:-1]) + list(post)
    return [frames[i] for i in idx]


def hold(frames, n):
    """Pose tenue (garde, accroupi) : l'image la plus basse/ramassée, répétée."""
    k = max(range(len(frames)), key=lambda i: bbox(frames[i])[1])
    return [frames[k]] * n


def is_skin(c):
    r, g, b = int(c[0]), int(c[1]), int(c[2])
    return r > 170 and g > 110 and b < 175 and r > g > b and r - b > 40


def fix_red_skin(f):
    out = f.copy()
    rgb = f[..., :3].astype(int)
    op = f[..., 3] > 0
    red = op & (rgb[..., 0] > 1.6 * rgb[..., 1]) & (rgb[..., 0] > 1.6 * rgb[..., 2])
    h, w = op.shape
    for y, x in zip(*np.nonzero(red)):
        y0, y1, x0, x1 = max(0, y - 2), min(h, y + 3), max(0, x - 2), min(w, x + 3)
        blk = f[y0:y1, x0:x1].reshape(-1, 4)
        cand = [c for c in blk if c[3] and not (c[0] > 1.6 * c[1] and c[0] > 1.6 * c[2]) and int(c[:3].astype(int).sum()) > 180]
        if cand and sum(is_skin(c) for c in cand) * 2 > len(cand):
            skins = [tuple(int(v) for v in c[:3]) for c in cand if is_skin(c)]
            out[y, x, :3] = min(skins, key=lambda c: sum(c))
    return out


def _comps(mask):
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        stack, pts = [(sy, sx)], []
        seen[sy, sx] = True
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append(pts)
    return out


def is_pale(c):
    """Blanc/crème (dents, blanc des yeux, chemise) : peu saturé et clair."""
    r, g, b = int(c[0]), int(c[1]), int(c[2])
    return min(r, g, b) > 160 and max(r, g, b) - min(r, g, b) < 60


def fix_light_specks(f, max_size=20):
    """Taches crème posées sur la peau (RD étale la couleur des dents sur le
    menton et les joues) : sur un ciel clair elles se lisent comme des trous.
    Une dent ou un blanc d'œil a un trait sombre juste au-dessus (lèvre,
    paupière) ; une petite tache claire entourée de peau, sans ce trait,
    prend la couleur de peau voisine la plus fréquente."""
    out = f.copy()
    op = f[..., 3] > 0
    pale = op & np.array([[is_pale(c) for c in row] for row in f])
    h, w = op.shape
    dark = op & (f[..., :3].astype(int).sum(-1) < 200)
    for pts in _comps(pale):
        if len(pts) > max_size:
            continue
        ring = set()
        for y, x in pts:
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not pale[ny, nx]:
                    ring.add((ny, nx))
        cols = [f[q] for q in ring if op[q]]
        skins = [tuple(int(v) for v in c[:3]) for c in cols if is_skin(c)]
        if not cols or len(skins) < 0.5 * len(cols):
            continue
        xs = sorted({x for _, x in pts})
        lid = 0
        for x in xs:
            top = min(y for y, xx in pts if xx == x)
            if dark[max(0, top - 2):top, x].any():
                lid += 1
        if lid >= 0.5 * len(xs):
            continue
        fill = max(set(skins), key=skins.count)
        for y, x in pts:
            out[y, x, :3] = fill
    return out


def _hsv(c):
    import colorsys
    h, sat, v = colorsys.rgb_to_hsv(*(int(x) / 255 for x in c[:3]))
    return h * 360, sat, v


# Groupes de couleurs recolorés par les costumes (rig.json « costumes »),
# reconnus par teinte : les couleurs RD varient d'une image à l'autre.
GROUP_RULES = {
    "louis": [
        ("hat", lambda c, h, s, v: c[0] > 120 and c[1] < 90 and c[2] < 90),
        ("pants", lambda c, h, s, v: c[2] > c[0] + 20 and c[2] > c[1] and c[2] > 60),
        ("shirt", lambda c, h, s, v: min(c) > 160 and max(c) - min(c) < 60),
    ],
    "maia": [
        ("suit", lambda c, h, s, v: 165 <= h <= 250 and s > 0.25),
    ],
}
FID = None


def group_of(c):
    c = tuple(int(x) for x in c[:3])
    h, s, v = _hsv(c)
    for g, rule in GROUP_RULES.get(FID, []):
        if rule(c, h, s, v):
            return g
    return "fixed"


def palette_slots(neutral):
    op = neutral[..., 3] > 0
    counts = {}
    for c in neutral[op][:, :3]:
        t = tuple(int(v) for v in c)
        counts[t] = counts.get(t, 0) + 1
    keys = sorted(counts, key=lambda t: -counts[t])
    slots = [("fixed", OUTLINE)] + [(group_of(c), c) for c in keys if c != OUTLINE][:30]
    return slots


def index(f, slots):
    arr = np.array([c for _, c in slots], int)
    groups = [g for g, _ in slots]
    out = np.zeros(f.shape[:2], np.uint8)
    op = f[..., 3] > 0
    for y, x in zip(*np.nonzero(op)):
        c = f[y, x, :3].astype(int)
        g = group_of(c)
        cand = [j for j, gg in enumerate(groups) if gg == g] or list(range(len(slots)))
        d = ((arr[cand] - c) ** 2).sum(1)
        out[y, x] = cand[int(d.argmin())] + 1
    p = np.pad(op, 1)
    edge = op & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    out[edge] = 1
    return out


def final_clean(idx, hole_max=6, island_max=60):
    """Dernière passe sur l'image indexée définitive : morceaux détachés
    (traits de vitesse, miettes) retirés, micro-trous bouchés au contour."""
    op = idx > 0
    comps = sorted(_comps(op), key=len, reverse=True)
    for pts in comps[1:]:
        if len(pts) <= island_max:
            for p in pts:
                idx[p] = 0
    h, w = idx.shape
    for pts in _comps(idx == 0):
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        if len(pts) <= hole_max and min(ys) > 0 and min(xs) > 0 and max(ys) < h - 1 and max(xs) < w - 1:
            for p in pts:
                idx[p] = 1
    return idx


def place(f, dx, air):
    x0, y0, x1, y1 = bbox(f)
    cell = np.zeros((CELL, CELL, 4), np.uint8)
    if air:
        ty = min((FOOT[1] - 63) - (y0 + y1) // 2, (FOOT[1] - 1) - y1)
    else:
        ty = (FOOT[1] - 1) - y1
    sy0, sy1 = max(0, -ty), min(SRC, CELL - ty)
    sx0, sx1 = max(0, -dx), min(SRC, CELL - dx)
    cell[sy0 + ty:sy1 + ty, sx0 + dx:sx1 + dx] = f[sy0:sy1, sx0:sx1]
    return cell


def main():
    global FID
    fid = sys.argv[1]
    FID = fid
    d = rd_rig.fighter_dir(fid)
    reg = json.load(open(os.path.join(ROOT, "tools", "rd", "out", fid, "anims.json")))
    old = json.load(open(os.path.join(d, "anims.json")))
    meta = {k: {kk: vv for kk, vv in v.items() if kk not in ("first", "row")} for k, v in old["anims"].items()}
    neutral = np.array(Image.open(os.path.join(ROOT, "tools", "rd", "out", fid, "neutral_160.png")).convert("RGBA"))
    nx0, _, nx1, ny1 = bbox(neutral)
    low = neutral[ny1 - 19:ny1 + 1, :, 3] > 0
    ref_cx = int(round(np.nonzero(low)[1].mean()))
    dx = FOOT[0] - ref_cx
    slots = palette_slots(neutral)
    spec = rd_rig.load_spec(fid)
    spec["palette_slots"] = [[g, list(c)] for g, c in slots]
    with open(os.path.join(d, "rig.json"), "w") as fh:
        json.dump(spec, fh, indent=1)
    rd_rig._write_palettes(fid, spec, slots)
    cells, report, cleaned = {}, {}, {}
    for name in [n for n in meta]:
        src, sel = SOURCES_BY.get(fid, {}).get(name) or SOURCES.get(name, (name, None))
        if src not in cleaned:
            cleaned[src] = [cb.fix(fix_light_specks(fix_red_skin(f))) for f in frames_of(reg[src])]
        frames = cleaned[src]
        n = meta[name]["frames"]
        if sel == "hold":
            chosen = hold(frames, n)
        elif sel == "reverse":
            chosen = pick(frames[::-1], n)
        elif sel == "end_hold":     # chute puis reste au sol
            k = max(1, n - 3)
            chosen = pick(frames, k) + [frames[-1]] * (n - k)
        elif isinstance(sel, slice):
            chosen = pick(frames[sel], n)
        else:
            chosen = pick(frames, n, meta[name].get("hit_frame"), meta[name].get("hit_dir", "fwd"))
        out = []
        worst = 0
        for f in chosen:
            r = cb.analyse(f)
            worst = max(worst, int(r["slits"].sum() + r["islands"].sum()))
            out.append(final_clean(index(place(f, dx, name in AIR), slots)))
        cells[name] = out
        report[name] = worst
    cols = SHEET_W // CELL
    total = sum(len(v) for v in cells.values())
    sheet = np.zeros((((total + cols - 1) // cols) * CELL, cols * CELL), np.uint8)
    k = 0
    for name in meta:
        meta[name]["first"] = k
        for c in cells[name]:
            sheet[(k // cols) * CELL:(k // cols + 1) * CELL, (k % cols) * CELL:(k % cols + 1) * CELL] = c
            k += 1
    Image.fromarray(sheet, "L").save(os.path.join(d, "sheet.png"), optimize=True)
    infer_boxes.set_foot(FOOT)
    data = {"id": fid, "cell": CELL, "cols": cols, "foot": list(FOOT), "palette_roles": ix.palette_roles(),
            "source": "rd_anim", "anims": meta, "boxes": infer_boxes.infer(cells, meta)}
    with open(os.path.join(d, "anims.json"), "w") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"{fid}: {total} images ; défauts de bord restants (pire image) :",
          {k: v for k, v in report.items() if v})
    for p in contact_sheet.main(fid):
        print("  ", p)


if __name__ == "__main__":
    main()
