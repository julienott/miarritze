#!/usr/bin/env python3
"""Raccord des animations 2D des persos (Julien, 2026-10-20 : « que toutes les animations aient le
temps de jouer, que leurs transitions soient correctes, que le perso soit raccord d'une animation à
l'autre et que l'animation ne le déplace pas »). Mesures sur les planches, telles que le jeu les
dessine (src/gordeka/gk_perso.gd : case recalée de `frame_offsets`, mise à l'échelle `echelle`
autour des pieds `feet_anchor`). Les PNG ne sont jamais réécrits.

  audit_anims.py [<id>…] [--sortie <dossier>] [--brut]

  --brut : mesure sans `echelle` ni `entrees` (l'état « avant » des corrections de ce module).

Quatre volets, par perso et par animation :
 a. durée : durée jouée de chaque animation contre la durée de l'état de jeu qui la déclenche
    (data/gordeka/rules.json, section `anims`) ;
 b. transitions : pour chaque passage d'état possible (TRANSITIONS), dernière image de A (ou chaque
    image d'une boucle interrompue) contre l'image d'entrée de B : 1 − IoU des silhouettes, écart des
    pieds, de hauteur, de couleur moyenne ; avec et sans point d'entrée (`entrees`) ;
 c. raccord : taille (aire de la silhouette), couleurs, pieds au repos, contre l'idle du perso ;
 d. déplacement parasite : course des pieds posés et du centre pendant une animation sur place.

Calculs réutilisés par post_anims.py : `echelle` (taille de l'anim ramenée à celle de l'idle) et
`entrees` (point d'entrée intelligent d'une boucle B depuis chaque image de A, avec son écart).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PERSOS = os.path.join(ROOT, "assets", "gordeka", "persos")
RULES = os.path.join(ROOT, "data", "gordeka", "rules.json")

CASE = 256
ALPHA_MIN = 128
RED = 2                  # masques réduits de moitié pour l'IoU (128×128)
BANDE_PIEDS = 0.06       # bande des pieds : part de la hauteur, depuis le bas de la silhouette
MOUVEMENT = ("walk", "run_scared", "ghost_move")
BOUCLES = ("idle", "walk", "run_scared", "ghost", "ghost_move", "trapped", "search", "victory", "sad")
EMOTES = ("emote_salut", "emote_rire", "emote_danse", "emote_pouce", "emote_chut", "emote_langue")
SOL = ("idle", "walk", "run_scared")
# Passages d'état réellement possibles dans le jeu (gk_game.gd, gk_perso.gd::_state_anim) :
# A -> [B…]. hide_in finit dans la cachette (invisible) ; victory/sad sont des poses de fin.
TRANSITIONS = {
    "idle": ["walk", "run_scared", "hide_in", "trap", "found", "extract", "detect", "search",
             "trapped", "hunter_reveal", "victory", "sad", *EMOTES],
    "walk": ["idle", "run_scared", "hide_in", "trap", "found", "extract", "detect", "search",
             "trapped", "victory", "sad"],
    "run_scared": ["idle", "walk", "hide_in", "trap", "found", "extract", "victory", "sad"],
    "hide_out": ["idle", "walk", "run_scared", "found"],
    "found": ["ghost", "ghost_move"],
    "extract": ["ghost", "ghost_move"],
    "trap": ["idle", "walk", "run_scared"],
    "detect": ["idle", "walk", "search", "trapped"],
    "search": ["idle", "walk", "trapped"],
    "trapped": ["idle", "walk", "search", "detect"],
    "hunter_reveal": ["idle", "walk"],
    "ghost": ["ghost_move", "hide_out"],
    "ghost_move": ["ghost", "hide_out"],
    **{e: ["idle", "walk", "run_scared"] for e in EMOTES},
}


def _num(x):
    return round(float(x), 3)


# ------------------------------------------------------------------ chargement et mesures

def anims_du_perso(pid: str) -> list:
    d = os.path.join(PERSOS, pid)
    if not os.path.isdir(d):
        return []
    return sorted(f[:-5] for f in os.listdir(d)
                  if f.endswith(".json") and os.path.exists(os.path.join(d, f[:-5] + ".png")))


def aligne(case: Image.Image, off, e: float, feet) -> Image.Image:
    """Case telle que le jeu la pose : décalée de `off`, mise à l'échelle `e` autour des pieds."""
    fx, fy = feet
    ox, oy = off
    if abs(e - 1.0) < 1e-6:
        if abs(ox) < 1e-6 and abs(oy) < 1e-6:
            return case
        return case.transform(case.size, Image.AFFINE, (1, 0, -ox, 0, 1, -oy), Image.BILINEAR)
    k = 1.0 / e
    return case.transform(case.size, Image.AFFINE,
                          (k, 0, fx - ox - fx * k, 0, k, fy - oy - fy * k), Image.BILINEAR)


def mesurer(pid: str, anim: str, brut: bool = False, echelle=None, decalage=None) -> dict:
    """Mesures image par image d'une anim, dans le repère du jeu (pieds de la case = pieds de l'acteur)."""
    base = os.path.join(PERSOS, pid, anim)
    meta = json.load(open(base + ".json"))
    img = Image.open(base + ".png").convert("RGBA")
    cw, ch = meta.get("cell", [CASE, CASE])
    n = int(meta.get("frames", img.width // cw))
    offs = meta.get("frame_offsets", [])
    feet = meta.get("feet_anchor", [128, 236])
    e = echelle if echelle is not None else (1.0 if brut else float(meta.get("echelle", 1.0)))
    dec = (0.0, 0.0) if brut or decalage is False else tuple(meta.get("decalage", (0.0, 0.0)))
    fps = float(meta.get("fps", 24.0))
    ms = meta.get("frame_ms", [])
    durees = [float(ms[i]) / 1000.0 if i < len(ms) else 1.0 / fps for i in range(n)]
    imgs, masques, mes = [], [], []
    for f in range(n):
        c = img.crop((f * cw, 0, (f + 1) * cw, ch))
        o = offs[f] if f < len(offs) else (0.0, 0.0)
        c = aligne(c, (o[0] + dec[0], o[1] + dec[1]), e, feet)
        a = np.array(c)
        op = a[:, :, 3] >= ALPHA_MIN
        imgs.append(c)
        masques.append(np.array(c.split()[3].resize((cw // RED, ch // RED), Image.BILINEAR)) >= ALPHA_MIN)
        ys, xs = np.nonzero(op)
        if ys.size == 0:
            mes.append(None)
            continue
        top, bot = int(ys.min()), int(ys.max())
        h = bot - top
        bande = op[max(top, bot - max(3, int(h * BANDE_PIEDS))):bot + 1]
        bx = np.nonzero(bande.any(axis=0))[0]
        rgb = a[:, :, :3][op].astype(float)
        hist, _ = np.histogramdd(rgb // 64, bins=(4, 4, 4), range=((0, 4), (0, 4), (0, 4)))
        mes.append({"top": top, "bas": bot, "h": h, "gauche": int(xs.min()), "droite": int(xs.max()),
                    "aire": int(op.sum()), "cx": float(xs.mean()), "cy": float(ys.mean()),
                    "pieds_x": float((bx.min() + bx.max()) / 2.0), "rgb": rgb.mean(axis=0),
                    "hist": hist.ravel() / max(1.0, hist.sum())})
    return {"pid": pid, "anim": anim, "n": n, "loop": bool(meta.get("loop", False)), "durees": durees,
            "debut": 0 if brut else int(meta.get("debut", 0)), "fin": n if brut else int(meta.get("fin", n)),
            "duree": float(sum(durees)), "echelle": e, "feet": feet, "imgs": imgs, "masques": masques,
            "mes": mes, "meta": meta}


def iou(a: np.ndarray, b: np.ndarray) -> float:
    u = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / u) if u else 1.0


def ecart_images(A: dict, i: int, B: dict, j: int) -> dict:
    """Écart visuel entre l'image i de A et l'image j de B, telles que dessinées."""
    ma, mb = A["mes"][i], B["mes"][j]
    if ma is None or mb is None:
        return {"e": 1.0, "pieds": 0.0, "sol": 0.0, "h": 0.0, "coul": 0.0}
    return {"e": 1.0 - iou(A["masques"][i], B["masques"][j]),
            "pieds": mb["pieds_x"] - ma["pieds_x"], "sol": float(mb["bas"] - ma["bas"]),
            "h": mb["h"] / max(1.0, ma["h"]) - 1.0,
            "coul": float(np.linalg.norm(mb["rgb"] - ma["rgb"]))}


def matrice(A: dict, B: dict) -> np.ndarray:
    """1 − IoU de chaque image de A contre chaque image de B (n_A × n_B)."""
    ma = np.stack([m.ravel() for m in A["masques"]]).astype(np.float32)
    mb = np.stack([m.ravel() for m in B["masques"]]).astype(np.float32)
    inter = ma @ mb.T
    union = ma.sum(1)[:, None] + mb.sum(1)[None, :] - inter
    return 1.0 - inter / np.maximum(union, 1.0)


# ------------------------------------------------------------------ calculs réutilisés

TETE_K = 0.38            # haut de la silhouette comparé pour l'échelle (tête, épaules) : part de la hauteur


def _tete(im: Image.Image, s: float, h_ref: float):
    """Masque du haut de la silhouette (tête, épaules), mis à l'échelle s, calé sur son sommet et
    centré : la tête garde sa forme d'une pose à l'autre bien mieux que le corps entier."""
    a = im.split()[3]
    a = a.resize((max(1, int(a.width * s / RED)), max(1, int(a.height * s / RED))), Image.BILINEAR)
    m = np.array(a) >= ALPHA_MIN
    ys, xs = np.nonzero(m)
    if ys.size == 0:
        return None
    top = ys.min()
    sel = ys < top + int(h_ref * TETE_K / RED)
    ys, xs = ys[sel], xs[sel]
    out = np.zeros((120, 160), bool)
    yy, xx = ys - top + 10, xs - int(np.median(xs)) + 80
    ok = (yy >= 0) & (yy < 120) & (xx >= 0) & (xx < 160)
    out[yy[ok], xx[ok]] = True
    return out


def echelle_brute(pid: str, anim: str, mx: float = 0.25):
    """(s, IoU à s, IoU à 1) : l'échelle s qui fait le mieux coïncider le haut de la silhouette (tête,
    épaules) d'une image de l'anim avec celui d'une image de l'idle."""
    ref = mesurer(pid, "idle", echelle=1.0, decalage=False)
    M = mesurer(pid, anim, echelle=1.0, decalage=False)
    hs = [m["h"] for m in ref["mes"] if m]
    if not hs:
        return 1.0, 0.0, 0.0
    h_ref = float(np.median(hs))
    R = [t for t in (_tete(ref["imgs"][f], 1.0, h_ref) for f in range(0, ref["n"], 4)) if t is not None]
    imgs = [M["imgs"][f] for f in range(0, M["n"], 2)]
    cache = {}
    def score(s):
        s = round(float(s), 2)
        if s not in cache:
            best = 0.0
            for im in imgs:
                t = _tete(im, s, h_ref)
                if t is not None:
                    best = max(best, max(iou(t, r) for r in R))
            cache[s] = best
        return cache[s]
    for s in np.arange(1.0 - mx, 1.0 + mx + 1e-6, 0.02):
        score(s)
    s0 = max(cache, key=lambda s: (cache[s], -abs(s - 1.0)))
    score(s0 - 0.01)
    score(s0 + 0.01)
    sb = max(cache, key=lambda s: (cache[s], -abs(s - 1.0)))
    return sb, cache[sb], score(1.0)


def echelle_conseillee(pid: str, anim: str, post: dict, repli: float = 1.0) -> float:
    """Facteur `echelle` qui ramène l'anim à la taille de l'idle du perso (pixelforge redessine parfois
    le perso plus petit, ex. Amaia dans found et hide_out). On ne corrige que si la coïncidence des
    têtes est franche (IoU ≥ `tete_iou`, défaut 0,85), nettement meilleure qu'à l'échelle 1 (gain ≥
    `tete_gain`, défaut 0,03) et l'écart au-delà de `echelle_tol` (4 %), borné à `echelle_max` (25 %).
    Pas mesurable (aucune tête assez ressemblante : course, vol) : `repli`, l'échelle de sa pose de repos.
    Exception par perso : post.echelle {anim: valeur imposée}."""
    fixe = (post.get("echelle") or {}).get(anim)
    if fixe is not None:
        return float(fixe)
    if anim == "idle" or "idle" not in anims_du_perso(pid):
        return 1.0
    s, i_s, i_1 = echelle_brute(pid, anim, float(post.get("echelle_max", 0.25)))
    if i_s < float(post.get("tete_iou", 0.85)):
        return repli          # pas mesurable (course, vol) : l'échelle de sa pose de repos
    if i_s - i_1 < float(post.get("tete_gain", 0.03)) or abs(s - 1.0) < float(post.get("echelle_tol", 0.04)):
        return 1.0
    return round(float(np.clip(s, 1.0 - float(post.get("echelle_max", 0.25)), 1.0 + float(post.get("echelle_max", 0.25)))), 2)


def decalage_conseille(pid: str, anim: str, post: dict):
    """Déplacement (walk, run_scared, ghost_move) : pieds.py ne les recale pas (le pied posé y recule,
    c'est voulu). On cale toute la planche sur sa pose de repos (idle, ghost pour ghost_move) : sol de la
    planche (bas des images d'appui) sur le sol du repos, et horizontalement là où ses silhouettes
    coïncident le mieux avec celles du repos. Sinon le perso saute de quelques px à chaque arrêt et
    départ. [dx, dy] px de case."""
    fixe = (post.get("decalage") or {}).get(anim)
    if fixe is not None:
        return [float(fixe[0]), float(fixe[1])]
    if anim not in MOUVEMENT:
        return None
    existants = anims_du_perso(pid)
    base = "ghost" if anim == "ghost_move" and "ghost" in existants else "idle"
    if base not in existants:
        return None
    R = mesurer(pid, base, decalage=False)
    M = mesurer(pid, anim, decalage=False)
    r_ok = [(m, R["imgs"][f]) for f, m in enumerate(R["mes"]) if m]
    m_ok = [(m, M["imgs"][f]) for f, m in enumerate(M["mes"]) if m]
    if not r_ok or not m_ok:
        return None
    sol_r = float(np.median([m["bas"] for m, _ in r_ok]))
    sol_m = float(np.percentile([m["bas"] for m, _ in m_ok], 90))     # images d'appui
    dy = round((sol_r - sol_m) * 2) / 2
    # Horizontal : le décalage qui fait le mieux coïncider les silhouettes de la planche avec celles
    # du repos (moyenne, sur les images de la planche, de la meilleure IoU avec une image du repos).
    ry = int(round(dy / RED))
    rm = np.stack([R["masques"][f] for f in range(0, R["n"], 2)]).reshape(-1, (CASE // RED) ** 2).astype(np.float32)
    best = (-1.0, 0)
    for sx in range(-24, 25):
        mm = np.stack([np.roll(np.roll(M["masques"][f], ry, axis=0), sx, axis=1) for f in range(M["n"])])
        mm = mm.reshape(M["n"], -1).astype(np.float32)
        inter = mm @ rm.T
        union = mm.sum(1)[:, None] + rm.sum(1)[None, :] - inter
        sc = float((inter / np.maximum(union, 1.0)).max(axis=1).mean())
        if sc > best[0] + 1e-4 or (abs(sc - best[0]) <= 1e-4 and abs(sx) < abs(best[1])):
            best = (sc, sx)
    dx = float(best[1] * RED)
    return [float(dx), float(dy)] if abs(dx) >= 1 or abs(dy) >= 1 else None


def bornes(pid: str, anim: str, post: dict):
    """Images jouées d'un geste ponctuel [debut, fin[ : sans les images figées du début et de la fin
    (différence moyenne < FIGE avec la voisine : du temps de jeu perdu), ni une dernière image en
    rupture (saut > RUPTURE × la médiane : la planche de pixelforge « saute » parfois à la fin)."""
    M = mesurer(pid, anim)
    if M["loop"] or M["n"] < 6:
        return 0, M["n"]
    arr = [np.asarray(im, dtype=np.float32) for im in M["imgs"]]
    d = [float(np.abs(arr[i + 1] - arr[i]).mean()) for i in range(M["n"] - 1)]
    fige = float(post.get("fige", 0.6))
    med = float(np.median(d))
    fin = M["n"]
    if d[-1] > max(10.0, float(post.get("rupture", 4.0)) * med):
        fin -= 1
    while fin > 2 and d[fin - 2] < fige:
        fin -= 1
    debut = 0
    while debut < fin - 3 and d[debut] < fige:
        debut += 1
    # Jamais plus d'un quart de l'anim retiré : ce sont des réglages fins.
    debut = min(debut, M["n"] // 8)
    fin = max(fin, M["n"] - M["n"] // 8)
    return debut, fin


def entrees(pid: str, anim: str, existants: list, cache: dict) -> dict:
    """Point d'entrée intelligent et écart de chaque transition possible depuis `anim` : pour chaque
    état B qui peut suivre, et chaque image i de `anim`, l'image de B où entrer (boucle : la plus
    proche ; geste ponctuel : sa première image jouée) et l'écart 1 − IoU des deux silhouettes telles
    que dessinées, en centièmes (le jeu en tire la durée du fondu). {B: {"i": […], "e": […]}}"""
    out = {}
    A = cache.setdefault(anim, mesurer(pid, anim))
    for b in TRANSITIONS.get(anim, []):
        if b not in existants or b == anim:
            continue
        B = cache.setdefault(b, mesurer(pid, b))
        m = matrice(A, B)
        if b in BOUCLES:
            j = m.argmin(axis=1)
            out[b] = {"i": [int(x) for x in j], "e": [int(round(100 * m[i, x])) for i, x in enumerate(j)]}
        else:
            d0 = int(B.get("debut", 0))
            out[b] = {"e": [int(round(100 * m[i, d0])) for i in range(A["n"])]}
    return out


# ------------------------------------------------------------------ durées de jeu

def duree_jouee(M: dict, rules: dict, brut: bool) -> dict:
    """Durée effectivement jouée par le jeu contre la fenêtre de l'état qui la montre. `brut` : règles
    d'avant la section `anims` de rules.json (rien d'accéléré, rien de coupé au mouvement)."""
    anim = M["anim"]
    a = {} if brut or not rules.get("anim_durees", 1) else rules.get("anims", {})
    drap = {} if brut else rules
    fps_d = M["durees"]
    utile = float(sum(fps_d[M["debut"]:M["fin"]]))
    dmax = (a.get("duree_max") or {}).get("emote" if anim.startswith("emote_") else anim)
    jouee = min(utile, float(dmax)) if dmax and not M["loop"] else utile
    r = {"duree": _num(M["duree"]), "jouee": _num(jouee), "fenetre": None, "etat": "", "part": None,
         "cycles": None, "glisse_s": 0.0}
    coupe = (a.get("coupe_mouv") or {}).get("emote" if anim.startswith("emote_") else anim)
    if anim == "hide_in":
        dive = min(max(jouee, rules["cachette_dive_min"]), rules["cachette_dive_max"])
        r.update(fenetre=_num(dive), etat="plongée (cachette_dive_min..max)", part=_num(min(1.0, dive / jouee)))
    elif anim == "search":
        cal = (a.get("cale_etat") or {}).get("search")
        if cal:
            r["jouee"] = _num(rules[cal])
        r.update(fenetre=rules["search_time"], etat="fouille (search_time)",
                 part=_num(min(1.0, rules["search_time"] / float(r["jouee"]))))
    elif anim == "trapped":
        r.update(fenetre=rules["trap_duration"], etat="piège (trap_duration)",
                 cycles=_num(rules["trap_duration"] / jouee),
                 glisse_s=0.0 if drap.get("anim_piege_marche") else _num(rules["trap_duration"]))
    elif anim in ("victory", "sad"):
        r.update(fenetre=rules["phase_end"], etat="fin de manche (phase_end)", cycles=_num(rules["phase_end"] / jouee))
    elif anim.startswith("emote_"):
        r.update(fenetre=rules["emote_duration"], etat="bulle (emote_duration)",
                 part=_num(min(1.0, rules["emote_duration"] / jouee)))
    elif anim == "hunter_reveal":
        if drap.get("anim_reveal_avance"):
            r.update(fenetre=_num(jouee), etat="fin de la phase cachée, chasseur figé", part=1.0)
        else:
            r.update(fenetre=0.0, etat="chasseur lâché à l'image 0 : il glisse en marchant", part=1.0,
                     glisse_s=_num(jouee))
    elif anim in ("trap", "detect", "found", "extract", "hide_out"):
        # Le perso peut bouger pendant le geste : il glisse jusqu'à la coupe (ou toute l'anim).
        r.update(etat="jusqu'au premier pas" + (f" (coupé à {coupe:.0%})" if coupe is not None else ""),
                 glisse_s=_num(jouee * (coupe if coupe is not None else 1.0)))
    return r


# ------------------------------------------------------------------ audit

def auditer(pid: str, brut: bool = False, sortie=None) -> dict:
    rules = json.load(open(RULES))
    anims = anims_du_perso(pid)
    res = {"perso": pid, "anims": anims, "duree": {}, "raccord": {}, "deplacement": {}, "transitions": []}
    if not anims:
        return res
    M = {a: mesurer(pid, a, brut) for a in anims}
    ref = M.get("idle")
    # Taille de chaque anim contre l'idle (1/s de echelle_brute), telle que dessinée (× son echelle) ;
    # None : aucune image assez ressemblante pour la mesurer (course, vol).
    taille = {}
    if ref is not None:
        for a in M:
            if a != "idle":
                s_, i_s, _ = echelle_brute(pid, a)
                taille[a] = _num(M[a]["echelle"] / s_) if i_s >= 0.85 else None
    for a, m in M.items():
        res["duree"][a] = duree_jouee(m, rules, brut)
        ok = [x for x in m["mes"] if x is not None]
        # d. déplacement parasite : course horizontale des pieds (images au sol) et du centre.
        if ok:
            sol = max(x["bas"] for x in ok)
            pieds = [x["pieds_x"] for x in ok if x["bas"] >= sol - 6]
            res["deplacement"][a] = {
                "pieds_course": _num(max(pieds) - min(pieds)) if pieds else 0.0,
                "centre_course": _num(max(x["cx"] for x in ok) - min(x["cx"] for x in ok)),
                "sol_course": _num(sol - min(x["bas"] for x in ok)),
                "debut_fin_pieds": _num(ok[-1]["pieds_x"] - ok[0]["pieds_x"]),
            }
        # c. raccord contre l'idle.
        if ref is not None and ok:
            r_ok = [x for x in ref["mes"] if x is not None]
            hist_r = np.mean([x["hist"] for x in r_ok], axis=0)
            hist_a = np.mean([x["hist"] for x in ok], axis=0)
            res["raccord"][a] = {
                "taille": taille.get(a),
                "hauteur_max": _num(max(x["h"] for x in ok) / max(1, max(x["h"] for x in r_ok))),
                "couleur": _num(np.linalg.norm(np.mean([x["rgb"] for x in ok], 0) - np.mean([x["rgb"] for x in r_ok], 0))),
                "histo": _num(0.5 * np.abs(hist_a - hist_r).sum()),
                "pieds_repos": _num(ok[0]["pieds_x"] - float(np.median([x["pieds_x"] for x in r_ok]))),
                "sol_repos": _num(ok[0]["bas"] - float(np.median([x["bas"] for x in r_ok]))),
                "echelle": m["echelle"],
            }
    # b. transitions.
    for a, suivantes in TRANSITIONS.items():
        if a not in M:
            continue
        A = M[a]
        for b in suivantes:
            if b not in M or b == a:
                continue
            B = M[b]
            src = list(range(A["n"])) if A["loop"] else [A["fin"] - 1]
            ent = (A["meta"].get("entrees") or {}).get(b) if not brut else None
            naif = [ecart_images(A, i, B, 0) for i in src]
            if brut:
                malin = naif
            elif ent and "i" in ent:
                malin = [ecart_images(A, i, B, int(ent["i"][i])) for i in src]
            else:
                malin = [ecart_images(A, i, B, B["debut"]) for i in src]
            def agg(L):
                return {"e_moy": _num(np.mean([x["e"] for x in L])), "e_max": _num(max(x["e"] for x in L)),
                        "pieds": _num(max(abs(x["pieds"]) for x in L)), "sol": _num(max(abs(x["sol"]) for x in L)),
                        "h": _num(max(abs(x["h"]) for x in L)), "coul": _num(max(x["coul"] for x in L))}
            pire = int(np.argmax([x["e"] for x in naif]))
            res["transitions"].append({"de": a, "vers": b, "naif": agg(naif), "entree": agg(malin),
                                       "pire_i": src[pire]})
    if sortie:
        _planche_transitions(pid, M, res, sortie)
    return res


def _planche_transitions(pid: str, M: dict, res: dict, sortie: str, k: int = 8) -> None:
    """Planche « dernière image A | première image B » des k pires transitions (naïves), avec à
    droite l'image d'entrée retenue ; repère des pieds de l'acteur en magenta."""
    os.makedirs(sortie, exist_ok=True)
    pires = sorted(res["transitions"], key=lambda t: -t["entree"]["e_max"])[:k]
    S = 160
    out = Image.new("RGB", (S * 3 + 230, S * max(1, len(pires))), (240, 238, 230))
    d = ImageDraw.Draw(out)
    for r, t in enumerate(pires):
        A, B = M[t["de"]], M[t["vers"]]
        i = t["pire_i"]
        ent = (A["meta"].get("entrees") or {}).get(t["vers"])
        j = int(ent["i"][i]) if ent and "i" in ent else B["debut"]
        for c, (im, lab) in enumerate([(A["imgs"][i], f"{t['de']}[{i}]"), (B["imgs"][0], f"{t['vers']}[0]"),
                                       (B["imgs"][j], f"entrée {t['vers']}[{j}]")]):
            fond = Image.new("RGBA", (CASE, CASE), (240, 238, 230, 255))
            fond.alpha_composite(im)
            dd = ImageDraw.Draw(fond)
            fx, fy = A["feet"]
            dd.line([(fx, fy - 30), (fx, fy + 8)], fill=(200, 40, 200), width=2)
            dd.line([(fx - 30, fy), (fx + 30, fy)], fill=(40, 140, 60), width=2)
            out.paste(fond.convert("RGB").resize((S, S)), (c * S, r * S))
            d.text((c * S + 3, r * S + 3), lab, fill=(0, 0, 0))
        n, m = t["naif"], t["entree"]
        d.text((3 * S + 6, r * S + 20),
               f"{t['de']} -> {t['vers']}\nécart {n['e_max']:.2f} -> {m['e_max']:.2f}\n"
               f"pieds {n['pieds']:.0f}px sol {n['sol']:.0f}px\nhaut. {100 * n['h']:.0f}% coul {n['coul']:.0f}",
               fill=(0, 0, 0))
    out.save(os.path.join(sortie, f"{pid}_transitions.png"))


def film(pid: str, a: str, b: str, sortie: str, i=None, rules=None) -> str:
    """Bande « avant / après » d'une transition A -> B telle que le jeu la dessine, une image toutes
    les 1/30 s autour du passage : avant = planches brutes, B à son image 0, sans fondu ; après =
    échelle, calage, point d'entrée et fondu enchaîné (réglages anim_* de rules.json). `i` : image de
    A au moment du passage (défaut : la pire pour l'entrée naïve)."""
    rules = rules or json.load(open(RULES))
    av = {x: mesurer(pid, x, brut=True) for x in (a, b)}
    ap = {x: mesurer(pid, x) for x in (a, b)}
    A0, A1 = av[a], ap[a]
    if i is None:
        src = list(range(A0["n"])) if A0["loop"] else [A0["n"] - 1]
        i = max(src, key=lambda k: ecart_images(A0, k, av[b], 0)["e"])
    ent = (A1["meta"].get("entrees") or {}).get(b, {})
    j = int(ent["i"][i]) if "i" in ent else ap[b]["debut"]
    e = (ent.get("e") or [100] * A1["n"])[i] / 100.0
    lo, hi = rules.get("anim_fondu_ecart_min", 0.12), rules.get("anim_fondu_ecart_plein", 0.45)
    fs = rules.get("anim_fondu_s", 0.11) * min(1.0, max(0.0, (e - lo) / max(hi - lo, 0.01)))
    pas, avant_n, apres_n = 1.0 / 30.0, 3, 9
    S = 128
    out = Image.new("RGB", (S * (avant_n + apres_n), S * 2 + 16), (240, 238, 230))
    d = ImageDraw.Draw(out)
    def case(M, f):
        return M["imgs"][min(max(f, 0), M["n"] - 1)]
    for row, (M, j0, fondu) in enumerate(((av, 0, 0.0), (ap, j, fs))):
        for k in range(-avant_n, apres_n):
            t = k * pas
            fond = Image.new("RGBA", (CASE, CASE), (240, 238, 230, 255))
            if t < 0:
                fond.alpha_composite(case(M[a], i + int(round(t * 24))))
            else:
                fb = j0 + int(t * 24)
                fb = fb % M[b]["n"] if M[b]["loop"] else min(fb, M[b]["n"] - 1)
                fond.alpha_composite(case(M[b], fb))
                if fondu > 0 and t < fondu:
                    q = 1.0 - t / fondu
                    old = case(M[a], i).copy()
                    old.putalpha(old.split()[3].point(lambda v, q=q: int(v * q * q * (3 - 2 * q))))
                    fond.alpha_composite(old)
            dd = ImageDraw.Draw(fond)
            fx, fy = M[a]["feet"]
            dd.line([(fx, fy - 40), (fx, fy + 10)], fill=(200, 40, 200), width=2)
            dd.line([(0, fy), (CASE, fy)], fill=(40, 140, 60), width=1)
            out.paste(fond.convert("RGB").resize((S, S)), ((k + avant_n) * S, 16 + row * S))
    d.text((4, 2), f"{pid} {a}[{i}] -> {b} : avant (B[0], brut)  /  après (entrée {b}[{j}], écart {e:.2f}, "
                   f"fondu {fs:.2f} s) ; 1/30 s par case, passage à la 4e", fill=(0, 0, 0))
    os.makedirs(sortie, exist_ok=True)
    chemin = os.path.join(sortie, f"film_{pid}_{a}_{b}.png")
    out.save(chemin)
    return chemin


def texte(res: dict) -> str:
    pid = res["perso"]
    if not res["anims"]:
        return f"== {pid} : aucune animation"
    L = [f"== {pid} ({len(res['anims'])} anims)"]
    L.append("  a. durée (s) : anim  durée  jouée  fenêtre  part/cycles  glisse (s où le perso glisse en bougeant)")
    for a, r in res["duree"].items():
        if r.get("fenetre") is None and not r.get("glisse_s"):
            continue
        extra = f"part {r['part']:.2f}" if r.get("part") is not None else (f"cycles {r['cycles']:.2f}" if r.get("cycles") else "")
        alerte = "  <-- COUPÉE" if r.get("part") is not None and r["part"] < 0.98 else ""
        if r.get("glisse_s"):
            alerte += f"  glisse {r['glisse_s']:.2f}"
        fen = f"{r['fenetre']:5.2f}" if r.get("fenetre") is not None else "  -  "
        L.append(f"     {a:14} {r['duree']:5.2f} {r['jouee']:5.2f}  {fen}  {extra:12}{alerte}   [{r['etat']}]")
    L.append("  b. pires transitions (1−IoU max ; image de A, entrée de B ; pieds, sol px ; hauteur %)")
    for t in sorted(res["transitions"], key=lambda t: -t["entree"]["e_max"])[:8]:
        n, m = t["naif"], t["entree"]
        L.append(f"     {t['de']:>13} -> {t['vers']:13} image 0 : {n['e_max']:.2f}  entrée : {m['e_max']:.2f} (moy {m['e_moy']:.2f})"
                 f"   pieds {m['pieds']:5.1f} sol {m['sol']:5.1f} haut {100 * m['h']:4.0f}%")
    L.append("  c. raccord contre l'idle (taille : tête mesurée × echelle, ? = pose trop différente ; couleur RGB ; pieds0/sol0 : image 0)")
    for a, r in sorted(res["raccord"].items(), key=lambda kv: -abs((kv[1]["taille"] or 1.0) - 1)):
        if a == "idle":
            continue
        t = f"{r['taille']:.2f}" if r["taille"] is not None else "  ? "
        L.append(f"     {a:14} taille {t} haut.max {r['hauteur_max']:.2f} "
                 f"couleur {r['couleur']:5.1f} histo {r['histo']:.2f} pieds0 {r['pieds_repos']:6.1f} sol0 {r['sol_repos']:5.1f}"
                 f" éch. {r['echelle']}")
    L.append("  d. déplacement (px de case) : course des pieds au sol, du centre ; début->fin des pieds")
    for a, r in sorted(res["deplacement"].items(), key=lambda kv: -kv[1]["pieds_course"]):
        if a in MOUVEMENT:
            continue
        L.append(f"     {a:14} pieds {r['pieds_course']:5.1f} centre {r['centre_course']:5.1f} "
                 f"sol {r['sol_course']:5.1f} début->fin {r['debut_fin_pieds']:6.1f}")
    return "\n".join(L)


def main() -> None:
    args = sys.argv[1:]
    sortie = None
    if "--sortie" in args:
        i = args.index("--sortie")
        sortie = args[i + 1]
        del args[i:i + 2]
    if "--film" in args:          # --film <id> <A> <B> [<image de A>]
        i = args.index("--film")
        pid, a, b = args[i + 1:i + 4]
        k = int(args[i + 4]) if len(args) > i + 4 and args[i + 4].isdigit() else None
        print(film(pid, a, b, sortie or ".", k))
        return
    brut = "--brut" in args
    if brut:
        args.remove("--brut")
    ids = args or sorted(d for d in os.listdir(PERSOS) if os.path.isdir(os.path.join(PERSOS, d)))
    tout = {}
    for pid in ids:
        r = auditer(pid, brut, sortie)
        tout[pid] = r
        print(texte(r), flush=True)
    if sortie:
        os.makedirs(sortie, exist_ok=True)
        open(os.path.join(sortie, "audit.txt"), "w").write("\n\n".join(texte(r) for r in tout.values()) + "\n")
        json.dump(tout, open(os.path.join(sortie, "audit.json"), "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
