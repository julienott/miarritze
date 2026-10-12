#!/usr/bin/env python3
"""Moteur de rig cut-out pixel art (SPEC-BORROKA §11.3, §11.7).

Le même moteur sert aux mannequins procéduraux (Phase 1–2) et aux pièces
découpées dans les poses RD (Phase 3+). Seule la source des pièces change.

Conventions
- Images INDEXÉES (numpy uint8) : 0 = transparent, 1 = outline (contrat §1).
- Les pièces sont « remplissage seul » : le contour et l'ombrage sont ajoutés
  APRÈS rotation, dans l'espace monde (lumière en haut à gauche).
- Repère écran (y vers le bas). Angle positif = rotation anti-horaire à
  l'écran : un membre pendant (vers le bas) à +90° pointe vers l'avant
  (la droite, le personnage regarde à droite) ; un torse à +90° penche en
  arrière.
- Rotation pixel-propre « RotSprite » : Scale2x ×3 (= ×8), rotation au plus
  proche voisin, réduction par vote majoritaire. Angles quantifiés à 7,5°.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

ANGLE_STEP = 7.5
UP = 8                     # facteur de sur-échantillonnage (Scale2x ×3)
OUTLINE = 1


# ---------------------------------------------------------------- pièces

@dataclass
class Piece:
    """Pièce de rig : image indexée + pivot (articulation) + points d'attache.

    `pivot` et les `attach` sont en pixels dans l'image (coin haut-gauche =
    (0,0), centre du pixel i = i + 0.5). Les `attach` sont exprimés relatifs
    au pivot. `decals` : motifs non tournés posés après rotation (œil…),
    [(pos_rel_pivot, motif ndarray)], motif centré sur la position.
    """
    img: np.ndarray
    pivot: tuple
    attach: dict = field(default_factory=dict)
    decals: list = field(default_factory=list)
    shade: bool = True


@dataclass
class Bone:
    name: str
    parent: str | None
    piece: str
    attach_key: str = ""     # clé dans parent.attach (défaut : nom de l'os)
    rest: float = 0.0        # angle de repos ajouté à la pose (accessoires tenus)
    soft_joint: bool = True  # pas de contour là où l'os recouvre son parent de même couleur


class Rig:
    """Squelette + pièces + ordre de dessin.

    `ramps` : dict index -> (plus_clair, plus_sombre) pour l'ombrage monde
    (None si pas de voisin dans la rampe).
    """

    def __init__(self, bones: list, pieces: dict, draw_order: list, ramps: dict,
                 families: dict | None = None):
        self.bones = {b.name: b for b in bones}
        # index de palette -> famille (rampe) : sert aux articulations douces
        self.families = families or {}
        self.order_fk = [b.name for b in bones]     # parents avant enfants
        self.pieces = pieces
        self.draw_order = draw_order
        self.ramps = ramps
        self._cache8: dict = {}

    # ------------------------------------------------------------ cinématique

    def solve(self, pose: dict, root_pos: tuple) -> dict:
        """Renvoie {os: (pivot_monde (x,y), angle_monde, étirement)}."""
        out = {}
        stretch = pose.get("str", {})
        offs = pose.get("off", {})
        for name in self.order_fk:
            bone = self.bones[name]
            local = float(pose.get(name, 0.0)) + bone.rest
            st = tuple(stretch.get(name, (1.0, 1.0)))
            off = offs.get(name, (0, 0))
            if bone.parent is None:
                rx, ry = pose.get("root", (0, 0))
                pos = (root_pos[0] + rx + off[0], root_pos[1] + ry + off[1])
                out[name] = (pos, local, st)
                continue
            ppos, pang, pst = out[bone.parent]
            ppiece = self.pieces[self.bones[bone.parent].piece]
            ax, ay = ppiece.attach[bone.attach_key or name]
            ax, ay = ax * pst[0], ay * pst[1]
            wx, wy = rotate((ax, ay), pang)
            pos = (ppos[0] + wx + off[0], ppos[1] + wy + off[1])
            out[name] = (pos, pang + local, st)
        return out

    # ------------------------------------------------------------ rendu

    def render(self, pose: dict, canvas_size=(256, 256), root_pos=(128.0, 150.0)) -> np.ndarray:
        canvas = np.zeros((canvas_size[1], canvas_size[0]), np.uint8)
        owner = np.full(canvas.shape, -1, np.int16)
        solved = self.solve(pose, root_pos)
        names = list(self.bones)
        for name in self.draw_order:
            if name not in solved:
                continue
            bone = self.bones[name]
            piece = self.pieces[bone.piece]
            pos, ang, st = solved[name]
            layer, x0, y0 = self.render_piece(bone.piece, piece, ang, pos, st)
            if layer is None:
                continue
            if piece.shade:
                layer = shade_world(layer, self.ramps)
            layer = add_outline(layer)
            for (dpos, motif) in piece.decals:
                dx, dy = rotate((dpos[0] * st[0], dpos[1] * st[1]), ang)
                cx, cy = pos[0] + dx - x0, pos[1] + dy - y0
                paste_motif(layer, motif, cx, cy)
            soft = None
            if bone.soft_joint and bone.parent and self.families:
                soft = (names.index(bone.parent), self._family(layer))
            blit(canvas, layer, x0, y0, owner, names.index(name), soft, self.families)
        sq = pose.get("squash")
        if sq:
            canvas = squash(canvas, sq, root_pos)
        return cleanup(canvas)

    def _family(self, layer: np.ndarray):
        vals = layer[layer > 2]
        if len(vals) == 0:
            return None
        fams = [self.families.get(int(v)) for v in vals]
        fams = [f for f in fams if f is not None]
        return max(set(fams), key=fams.count) if fams else None

    def _img8(self, key: str, piece: Piece) -> np.ndarray:
        if key not in self._cache8:
            self._cache8[key] = scale2x(scale2x(scale2x(piece.img)))
        return self._cache8[key]

    def render_piece(self, key: str, piece: Piece, angle: float, pos: tuple, st: tuple):
        angle = quantize(angle)
        img8 = self._img8(key, piece)
        h, w = piece.img.shape
        px, py = piece.pivot
        corners = [(-px, -py), (w - px, -py), (-px, h - py), (w - px, h - py)]
        pts = [rotate((cx * st[0], cy * st[1]), angle) for cx, cy in corners]
        xs = [pos[0] + p[0] for p in pts]
        ys = [pos[1] + p[1] for p in pts]
        x0, x1 = int(math.floor(min(xs))) - 1, int(math.ceil(max(xs))) + 1
        y0, y1 = int(math.floor(min(ys))) - 1, int(math.ceil(max(ys))) + 1
        W, H = x1 - x0, y1 - y0
        if W <= 0 or H <= 0:
            return None, 0, 0
        # grille ×8 dans le monde, centres des sous-pixels
        gx = (np.arange(W * UP) + 0.5) / UP + x0 - pos[0]
        gy = (np.arange(H * UP) + 0.5) / UP + y0 - pos[1]
        GX, GY = np.meshgrid(gx, gy)
        # rotation inverse vers le repère local de la pièce
        lx, ly = rotate_arr(GX, GY, -angle)
        lx = lx / st[0] + px
        ly = ly / st[1] + py
        sx = np.floor(lx * UP).astype(np.int64)
        sy = np.floor(ly * UP).astype(np.int64)
        valid = (sx >= 0) & (sy >= 0) & (sx < w * UP) & (sy < h * UP)
        big = np.zeros((H * UP, W * UP), np.uint8)
        big[valid] = img8[sy[valid], sx[valid]]
        return vote_down(big, UP), x0, y0


# ---------------------------------------------------------------- géométrie

def quantize(angle: float) -> float:
    return round(angle / ANGLE_STEP) * ANGLE_STEP


def rotate(v: tuple, angle_deg: float) -> tuple:
    """Rotation anti-horaire à l'écran (y vers le bas)."""
    a = math.radians(angle_deg)
    c, s = math.cos(a), math.sin(a)
    x, y = v
    return (x * c + y * s, -x * s + y * c)


def rotate_arr(x, y, angle_deg: float):
    a = math.radians(angle_deg)
    c, s = math.cos(a), math.sin(a)
    return x * c + y * s, -x * s + y * c


# ---------------------------------------------------------------- RotSprite

def scale2x(img: np.ndarray) -> np.ndarray:
    """Scale2x (EPX) sur image indexée."""
    p = np.pad(img, 1, mode="edge")
    E = p[1:-1, 1:-1]
    B = p[:-2, 1:-1]
    H = p[2:, 1:-1]
    D = p[1:-1, :-2]
    F = p[1:-1, 2:]
    e0 = np.where((D == B) & (B != F) & (D != H), D, E)
    e1 = np.where((B == F) & (B != D) & (F != H), F, E)
    e2 = np.where((D == H) & (D != B) & (H != F), D, E)
    e3 = np.where((H == F) & (D != H) & (B != F), F, E)
    out = np.zeros((img.shape[0] * 2, img.shape[1] * 2), img.dtype)
    out[0::2, 0::2] = e0
    out[0::2, 1::2] = e1
    out[1::2, 0::2] = e2
    out[1::2, 1::2] = e3
    return out


def vote_down(big: np.ndarray, k: int) -> np.ndarray:
    """Réduction ×k par vote : opaque si ≥ moitié des sous-pixels opaques,
    couleur = index non nul le plus fréquent."""
    H, W = big.shape[0] // k, big.shape[1] // k
    blocks = big.reshape(H, k, W, k).transpose(0, 2, 1, 3).reshape(H, W, k * k)
    opaque = (blocks > 0).sum(axis=2) * 2 >= k * k
    counts = np.zeros((H, W, 32), np.int32)
    for idx in np.unique(blocks):
        if idx == 0:
            continue
        counts[:, :, idx] = (blocks == idx).sum(axis=2)
    mode = counts.argmax(axis=2).astype(np.uint8)
    return np.where(opaque, mode, 0).astype(np.uint8)


# ---------------------------------------------------------------- finitions

def _neighbours(mask: np.ndarray):
    p = np.pad(mask, 1)
    return p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]


def shade_world(layer: np.ndarray, ramps: dict) -> np.ndarray:
    """Liseré clair en haut/à gauche, ombre en bas/à droite (lumière haut-gauche)."""
    m = layer > 0
    up, down, left, right = _neighbours(m)
    out = layer.copy()
    light = m & (~up | ~left)
    dark = m & (~down | ~right) & ~light
    for idx in np.unique(layer):
        if idx <= 2 or idx not in ramps:
            continue
        lighter, darker = ramps[idx]
        sel = layer == idx
        if lighter is not None:
            out[sel & light] = lighter
        if darker is not None:
            out[sel & dark] = darker
    return out


def add_outline(layer: np.ndarray) -> np.ndarray:
    """Contour 1 px (4-voisinage) autour du remplissage, dans une marge."""
    padded = np.pad(layer, 1)
    m = padded > 0
    up, down, left, right = _neighbours(m)
    ring = ~m & (up | down | left | right)
    padded[ring] = OUTLINE
    return padded


def blit(canvas: np.ndarray, layer: np.ndarray, x0: int, y0: int,
         owner: np.ndarray | None = None, bone_id: int = -1, soft=None,
         families: dict | None = None) -> None:
    # add_outline a ajouté une marge de 1 px
    x0 -= 1
    y0 -= 1
    h, w = layer.shape
    cx0, cy0 = max(x0, 0), max(y0, 0)
    cx1, cy1 = min(x0 + w, canvas.shape[1]), min(y0 + h, canvas.shape[0])
    if cx1 <= cx0 or cy1 <= cy0:
        return
    sub = layer[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
    region = canvas[cy0:cy1, cx0:cx1]
    write = sub > 0
    if soft is not None and owner is not None and soft[1] is not None:
        # Articulation douce : le contour de l'enfant n'est pas dessiné sur
        # les pixels de son parent de même famille de couleur.
        parent_id, fam = soft
        own = owner[cy0:cy1, cx0:cx1]
        fam_lut = np.zeros(256, np.int16) - 1
        for k, v in (families or {}).items():
            fam_lut[k] = v if isinstance(v, int) else hash(v) % 1000
        target = fam if isinstance(fam, int) else hash(fam) % 1000
        same = (own == parent_id) & (fam_lut[region] == target)
        write &= ~((sub == OUTLINE) & same)
    region[write] = sub[write]
    if owner is not None:
        owner[cy0:cy1, cx0:cx1][write] = bone_id


def paste_motif(layer: np.ndarray, motif: np.ndarray, cx: float, cy: float) -> None:
    mh, mw = motif.shape
    # +1 : marge du contour ajoutée par add_outline
    x0 = int(math.floor(cx - mw / 2.0)) + 1
    y0 = int(math.floor(cy - mh / 2.0)) + 1
    for j in range(mh):
        for i in range(mw):
            v = motif[j, i]
            y, x = y0 + j, x0 + i
            if v and 0 <= y < layer.shape[0] and 0 <= x < layer.shape[1] and layer[y, x] > 1:
                layer[y, x] = v


def squash(canvas: np.ndarray, sq: tuple, root_pos: tuple) -> np.ndarray:
    """Étirement/aplatissement global autour du point bas (plus proche voisin)."""
    sx, sy = sq
    H, W = canvas.shape
    ys, xs = np.nonzero(canvas)
    if len(ys) == 0:
        return canvas
    base_y = ys.max() + 0.5
    cx = root_pos[0]
    gy, gx = np.mgrid[0:H, 0:W]
    srcx = np.floor((gx + 0.5 - cx) / sx + cx).astype(int)
    srcy = np.floor((gy + 0.5 - base_y) / sy + base_y).astype(int)
    ok = (srcx >= 0) & (srcy >= 0) & (srcx < W) & (srcy < H)
    out = np.zeros_like(canvas)
    out[ok] = canvas[srcy[ok], srcx[ok]]
    return out


def cleanup(canvas: np.ndarray) -> np.ndarray:
    """Silhouette extérieure en outline + suppression des pixels orphelins."""
    m = canvas > 0
    up, down, left, right = _neighbours(m)
    out = canvas.copy()
    orphan = m & ~(up | down | left | right)
    out[orphan] = 0
    m = out > 0
    up, down, left, right = _neighbours(m)
    edge = m & ~(up & down & left & right)
    out[edge] = OUTLINE
    # contour « solitaire » (outline sans aucun remplissage voisin) : supprimé
    fill = (out > 1)
    fu, fd, fl, fr = _neighbours(fill)
    p = np.pad(fill, 1)
    diag = p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:]
    lonely = (out == OUTLINE) & ~(fu | fd | fl | fr | diag)
    out[lonely] = 0
    return out


# ---------------------------------------------------------------- poses

def interpolate(anim: dict, base_pose: dict, n_frames: int, amp: float = 1.0,
                guard: dict | None = None) -> list:
    """Développe les keyframes d'une animation en `n_frames` poses complètes.

    anim["keys"] : [{"t": frame, "p": {os: angle, "root": [dx,dy], "off": {...},
                     "str": {...}, "squash": [sx,sy]}}]
    Les os non précisés héritent de la clé précédente (puis de base_pose).
    `str` et `squash` (smear frames, impacts) ne s'appliquent QU'À la frame
    de leur clé. Une clé en t = n_frames sert de bouclage.
    `amp` : facteur d'amplitude du perso, appliqué aux écarts à `guard`.
    """
    keys = sorted(anim["keys"], key=lambda k: k["t"])
    full = []
    current = dict(base_pose)
    current.setdefault("root", [0, 0])
    current.setdefault("off", {})
    for k in keys:
        nxt = dict(current)
        for name, val in k["p"].items():
            if name in ("str", "squash"):
                continue
            if name == "off":
                merged = dict(current.get("off", {}))
                merged.update(val)
                nxt["off"] = merged
            else:
                nxt[name] = val
        full.append((k["t"], nxt, k["p"].get("str"), k["p"].get("squash")))
        current = nxt
    frames = []
    for f in range(n_frames):
        prev = full[0]
        nxt = full[-1]
        for item in full:
            if item[0] <= f:
                prev = item
        for item in full:
            if item[0] >= f:
                nxt = item
                break
        t0, p0 = prev[0], prev[1]
        t1, p1 = nxt[0], nxt[1]
        u = 0.0 if t1 == t0 else (f - t0) / float(t1 - t0)
        pose = {}
        for name in set(p0) | set(p1):
            a = p0.get(name, p1.get(name))
            b = p1.get(name, a)
            if name == "root":
                pose[name] = [round(a[0] + (b[0] - a[0]) * u), round(a[1] + (b[1] - a[1]) * u)]
            elif name == "off":
                off = {}
                for bn in set(a) | set(b):
                    va = a.get(bn, [0, 0])
                    vb = b.get(bn, [0, 0])
                    off[bn] = [round(va[0] + (vb[0] - va[0]) * u), round(va[1] + (vb[1] - va[1]) * u)]
                pose[name] = off
            else:
                pose[name] = a + (b - a) * u
        if guard is not None and amp != 1.0:
            for name, val in list(pose.items()):
                if name in ("root", "off"):
                    continue
                g = guard.get(name, 0.0)
                pose[name] = g + (val - g) * amp
        if prev[0] == f and prev[2]:
            pose["str"] = {k: tuple(v) for k, v in prev[2].items()}
        if prev[0] == f and prev[3]:
            pose["squash"] = tuple(prev[3])
        frames.append(pose)
    return frames
