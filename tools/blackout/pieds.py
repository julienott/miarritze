#!/usr/bin/env python3
"""Pieds qui glissent : mesure et correction des planches d'animation 2D des persos (Julien, recette
du 2026-10-20 : « il glisse sur ses pieds »). Les PNG ne sont jamais réécrits : la correction va dans
le <anim>.json, appliquée par src/blackout/bk_perso.gd.

  pieds.py [<id>…] [--anim a,b] [--ecrire] [--rapport <dossier>] [--planches <dossier>]

Sans --ecrire : mesure seulement (rapport). import_perso.py appelle corriger_perso() après chaque import.

Méthode, image par image (case 256×256, alpha) :
- sol de l'anim = le bas de la silhouette le plus fréquent ; une image dont le bas est à moins de
  V_TOL px du sol a les pieds au sol (sinon : saut, pieds en l'air, on ne la force pas au sol) ;
- pieds = taches de pixels opaques dans la bande basse (BANDE_K de la hauteur ; jupe, robe, animal :
  ce sont simplement les pixels les plus bas) ; une tache qui descend jusqu'au bas de l'image est
  « posée » ;
- glissement = déplacement d'une tache posée appariée d'une image à la suivante (même pied resté au
  sol). Un pied qui se lève puis se repose ailleurs n'est pas apparié : un vrai pas n'est pas corrigé.
Sur place : le pied posé devrait être immobile → `frame_offsets` [[dx, dy], …] (px de case) qui
annulent la dérive cumulée (lissée, refermée sur la boucle) et recalent au sol les images pieds au sol.
Déplacement (walk, run_scared, ghost_move) : le pied posé recule à vitesse constante (tapis roulant)
→ `stride_px` = recul du pied posé sur toute la planche (px de case) : le jeu règle la cadence sur la
vitesse réelle (cadence = vitesse / stride) ; `frame_offsets` corrige en plus les à-coups autour de
cette vitesse constante.
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_json  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PERSOS = os.path.join(ROOT, "assets", "blackout", "persos")

MOUVEMENT = ("walk", "run_scared", "ghost_move")
ALPHA_MIN = 128      # pixel opaque
BANDE_K = 0.12       # bande des pieds : part de la hauteur du perso, depuis le bas
CONTACT_PX = 4       # une tache est posée si elle descend à moins de CONTACT_PX du bas de l'image
V_TOL = 8            # au-delà (px au-dessus du sol), l'image est en l'air : pas de recalage vertical
GAP_PX = 5           # deux colonnes séparées par plus de GAP_PX vides = deux taches
APPARIE_PX = 22      # déplacement max d'un même pied posé d'une image à la suivante (sur place)
APPARIE_MOUV_PX = 32 # idem en déplacement (le pied posé recule vite)
LISSAGE = 3          # fenêtre de lissage des décalages (images)
# Échelle et vitesses du jeu, pour le rapport (bk_perso.gd, data/blackout/rules.json).
ECHELLE = 88.0 / 199.0
CYCLE_S = {"walk": 0.85, "run_scared": 0.6, "ghost_move": 1.0}
RATE_MAX = 3.0       # accélération maximale d'une planche de déplacement (× son fps), comme bk_perso.gd


def _vitesses() -> dict:
    r = json.load(open(os.path.join(ROOT, "data", "blackout", "rules.json")))
    t = float(r["tile_px"])
    return {"walk": r["speed_hider"] * t, "run_scared": r["speed_hider"] * t, "ghost_move": r["speed_ghost"] * t}


def _taches(a: np.ndarray, bas: int, bande: int) -> list:
    """Taches de pieds d'une case (alpha booléen) : [(x0, x1, cx, posée)]."""
    zone = a[max(0, bas - bande):bas + 1]
    cols = np.where(zone.any(axis=0))[0]
    out = []
    if cols.size == 0:
        return out
    debut = prev = int(cols[0])
    for c in list(cols[1:]) + [None]:
        if c is not None and c - prev <= GAP_PX:
            prev = int(c)
            continue
        x0, x1 = debut, prev
        sous = a[:, x0:x1 + 1]
        ys = np.where(sous.any(axis=1))[0]
        b = int(ys.max())
        posee = b >= bas - CONTACT_PX
        # Centre du contact : les pixels les plus bas de la tache (talon à orteils).
        ligne = a[max(0, b - CONTACT_PX):b + 1, x0:x1 + 1]
        xs = np.where(ligne.any(axis=0))[0]
        cx = x0 + (float(xs.min()) + float(xs.max())) / 2.0
        out.append((x0, x1, cx, posee))
        if c is not None:
            debut = prev = int(c)
    return out


def _mesures(png: str, meta: dict) -> dict:
    """Bas de la silhouette, hauteur et taches de pieds de chaque image."""
    img = np.array(Image.open(png).convert("RGBA"))
    cw, ch = meta.get("cell", [256, 256])
    n = int(meta.get("frames", img.shape[1] // cw))
    alphas, bas, haut = [], [], []
    for f in range(n):
        a = img[:ch, f * cw:(f + 1) * cw, 3] >= ALPHA_MIN
        alphas.append(a)
        ys = np.where(a.any(axis=1))[0]
        bas.append(int(ys.max()) if ys.size else -1)
        haut.append(int(ys.min()) if ys.size else -1)
    vals = [b for b in bas if b >= 0]
    if not vals:
        return {}
    # Sol : le bas le plus fréquent parmi les images les plus basses (les sauts remontent le bas).
    sol = int(np.percentile(vals, 75))
    h = float(np.median([b - t for b, t in zip(bas, haut) if b >= 0]))
    bande = max(8, int(h * BANDE_K))
    taches = [_taches(alphas[f], bas[f], bande) if bas[f] >= 0 else [] for f in range(n)]
    return {"n": n, "bas": bas, "sol": sol, "h": h, "taches": taches}


def _apparier(avant: list, apres: list, seuil: float = APPARIE_PX) -> list:
    """Paires (tache avant, tache après) du même pied posé : plus proches l'une de l'autre dans les
    deux sens, assez près et de largeur comparable (deux pieds confondus de profil ne comptent pas)."""
    out = []
    for t in apres:
        if not avant:
            break
        m = min(avant, key=lambda u: abs(u[2] - t[2]))
        m2 = min(apres, key=lambda u: abs(u[2] - m[2]))
        w1, w2 = t[1] - t[0] + 1, m[1] - m[0] + 1
        if m2 is t and abs(m[2] - t[2]) <= seuil and max(w1, w2) <= 1.6 * min(w1, w2):
            out.append((m, t))
    return out


def _centre_pose(taches: list):
    xs = [t[2] for t in taches if t[3]]
    return float(np.mean(xs)) if xs else None


def pieds_ref(pid: str):
    """Position de référence des pieds du perso : le centre des pieds posés de son idle (px de case)."""
    base = os.path.join(PERSOS, pid, "idle")
    if not (os.path.exists(base + ".png") and os.path.exists(base + ".json")):
        return None
    m = _mesures(base + ".png", json.load(open(base + ".json")))
    xs = [c for c in (_centre_pose(t) for t in m.get("taches", [])) if c is not None]
    return float(np.median(xs)) if xs else None


def analyser(png: str, meta: dict, anim: str, ref_x=None) -> dict:
    m = _mesures(png, meta)
    if not m:
        return {}
    n, bas, sol, taches = m["n"], m["bas"], m["sol"], m["taches"]
    boucle = bool(meta.get("loop", False))
    mouvement = anim in MOUVEMENT
    r = {"frames": n, "loop": boucle, "fps": float(meta.get("fps", 24.0)), "sol": sol, "hauteur": round(m["h"], 1), "mouvement": mouvement,
         "_bas": bas, "_taches": taches}
    if mouvement:
        return _analyser_mouvement(r, anim)
    au_sol = [b >= 0 and abs(b - sol) <= V_TOL for b in bas]
    r["_au_sol"] = au_sol
    dy = [float(sol - b) if au_sol[f] else 0.0 for f, b in enumerate(bas)]
    # Glissement d'une image à la suivante : déplacement moyen des pieds posés appariés.
    glisse = {}
    for f in (range(n) if boucle else range(1, n)):
        p = (f - 1) % n
        if au_sol[f] and au_sol[p]:
            prs = _apparier([t for t in taches[p] if t[3]], [t for t in taches[f] if t[3]])
            if prs:
                glisse[f] = float(np.mean([t[2] - u[2] for u, t in prs]))
    cum = [0.0] * n
    for f in range(1, n):
        cum[f] = cum[f - 1] + glisse.get(f, 0.0)
    if boucle:      # le retour de la dernière image à la première referme la dérive
        reste = cum[n - 1] + glisse.get(0, 0.0)
        cum = [c - reste * f / n for f, c in enumerate(cum)]
    dx = [-c for c in cum]
    k = LISSAGE // 2
    if k > 0:
        dx = [float(np.mean([dx[(f + j) % n if boucle else min(max(f + j, 0), n - 1)] for j in range(-k, k + 1)]))
              for f in range(n)]
    # Placement : les pieds posés sur la référence du perso (ses pieds dans l'idle), pour que l'anim
    # parte et finisse sous l'acteur comme l'idle ; en boucle, en moyenne.
    cs = [(f, _centre_pose(taches[f])) for f in range(n) if au_sol[f]]
    cs = [(f, c) for f, c in cs if c is not None]
    if cs:
        cible = ref_x if ref_x is not None else cs[0][1]
        if boucle:
            dx = [d + cible - float(np.mean([c + dx[f] for f, c in cs])) for d in dx]
        else:
            f0, c0 = cs[0]
            f1, c1 = cs[-1]
            e0 = cible - (c0 + dx[f0])
            e1 = cible - (c1 + dx[f1])
            # Début et fin sur la référence ; l'écart entre les deux se répartit le long de l'anim.
            dx = [d + e0 + (e1 - e0) * min(max((f - f0) / max(f1 - f0, 1), 0.0), 1.0) for f, d in enumerate(dx)]
    # Résidu du glissement après correction (px de case par image, pieds posés appariés).
    apres = [abs(g + dx[f] - dx[(f - 1) % n]) for f, g in glisse.items()]
    avant = [abs(g) for g in glisse.values()]
    r.update({
        "derive_x": round(max(cum) - min(cum), 1),
        "derive_y": round(max(dy) - min(dy), 1) if any(au_sol) else 0.0,
        "glisse_moy": round(float(np.mean(avant)), 2) if avant else 0.0,
        "glisse_moy_apres": round(float(np.mean(apres)), 2) if apres else 0.0,
        "glisse_max": round(float(max(avant)), 1) if avant else 0.0,
        "pieds_x": round(float(np.mean([c for _, c in cs])), 1) if cs else None,
        "ref_x": round(ref_x, 1) if ref_x is not None else None,
        "frame_offsets": [[round(a * 2) / 2, round(b * 2) / 2] for a, b in zip(dx, dy)],
    })
    return r


def _analyser_mouvement(r: dict, anim: str) -> dict:
    """Déplacement : vitesse moyenne du pied posé (images figées comprises), d'où la distance
    parcourue par le sol pendant une planche (stride_px) pour que le pied posé n'y glisse pas."""
    n, bas, sol, taches = r["frames"], r["_bas"], r["sol"], r["_taches"]
    # Pied posé = tache qui touche le sol de l'anim (pas le bas de l'image : en l'air, rien n'est posé).
    poses = [[t for t in taches[f] if bas[f] >= 0 and t[3] and bas[f] >= sol - CONTACT_PX] for f in range(n)]
    r["_au_sol"] = [bool(p) for p in poses]
    dxs = []
    for f in range(n) if r["loop"] else range(1, n):
        for u, t in _apparier(poses[(f - 1) % n], poses[f], APPARIE_MOUV_PX):
            dxs.append(t[2] - u[2])
    # Un pied posé qui avance (> +4 px) : talon qui se pose ou mauvais appariement, écarté.
    ok = [d for d in dxs if d <= 4.0]
    v = float(np.mean(ok)) if len(ok) >= 4 else 0.0
    stride = max(0.0, -v * n)
    vit = _vitesses()[anim] / ECHELLE                    # px de case par seconde
    fps = float(r.get("fps", 24.0))
    sol_avant = vit * CYCLE_S[anim]                     # avance du sol pendant une planche, réglage CYCLE_S
    cadence = vit / stride if stride > 0 else None      # planches par seconde pour un pied immobile
    borne = RATE_MAX * fps / n                          # cadence maximale admise par bk_perso.gd
    cad_jeu = min(cadence, borne) if cadence else 1.0 / CYCLE_S[anim]
    r.update({
        "appuis": len(ok), "v_pied": round(v, 2), "stride_px": round(stride, 1),
        "derive_x": 0.0, "derive_y": 0.0,
        "glisse_moy": round(abs(sol_avant - stride) / n, 2) if stride else 0.0,          # patinage avant
        "glisse_moy_apres": round(abs(vit / cad_jeu - stride) / n, 2) if stride else 0.0,  # patinage après
        "glisse_max": 0.0, "pieds_x": None, "ref_x": None, "frame_offsets": [[0.0, 0.0]] * n,
        "cadence": round(cadence, 2) if cadence else None, "cadence_jeu": round(cad_jeu, 2),
    })
    return r


def _offsets_utiles(r: dict) -> bool:
    return any(abs(a) >= 0.5 or abs(b) >= 0.5 for a, b in r["frame_offsets"])


def ecrire(chemin: str, r: dict) -> bool:
    """Ajoute frame_offsets (et stride_px) au .json de l'anim ; le reste du fichier est conservé."""
    brut = open(chemin).read()
    j = json.loads(brut)
    avant = json.dumps(j, sort_keys=True)
    j.pop("frame_offsets", None)
    j.pop("stride_px", None)
    if _offsets_utiles(r):
        j["frame_offsets"] = r["frame_offsets"]
    if r.get("stride_px", 0) > 0:
        j["stride_px"] = r["stride_px"]
    # Format commun des .json d'anim (anim_json.py : une paire par ligne, tables d'entrée compactes).
    texte = anim_json.formater(j)
    if texte == brut or (json.dumps(j, sort_keys=True) == avant and "frame_offsets" not in j):
        return False
    with open(chemin, "w") as fh:
        fh.write(texte)
    return True


ANCRE_TETE = ("hunter_reveal",)


def offsets_tete(planche: str, n: int) -> list:
    """dx par image pour garder le centre de la tête à sa place de la première image (lissé sur 3)."""
    im = np.array(Image.open(planche).convert("RGBA"))
    xs = []
    for k in range(n):
        a = im[:, k * 256:(k + 1) * 256, 3] > 40
        ys = np.nonzero(a.any(1))[0]
        if not len(ys):
            xs.append(None)
            continue
        top, h = ys.min(), ys.max() - ys.min()
        cols = np.nonzero(a[top:top + max(1, int(h * 0.22))].any(0))[0]
        xs.append((cols.min() + cols.max()) / 2.0)
    ref = next((x for x in xs if x is not None), 128.0)
    xs = [ref if x is None else x for x in xs]
    lis = [sum(xs[max(0, i - 1):i + 2]) / len(xs[max(0, i - 1):i + 2]) for i in range(n)]
    return [[round((ref - x) * 2) / 2, 0.0] for x in lis]


def _post(pid: str) -> dict:
    try:
        p = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts_anims.json")))
        return dict(p.get("persos", {}).get(pid, {}).get("post", {}) or {})
    except (OSError, ValueError):
        return {}


def corriger_perso(pid: str, anims=None, ecrit: bool = True) -> dict:
    """Point d'entrée d'import_perso.py : mesure les anims d'un perso et écrit leur correction dans
    leurs .json. Toutes les anims d'un perso sont recalées sur ses pieds dans l'idle : un nouvel idle
    recale donc tout le perso (on repasse tout, c'est rapide)."""
    d = os.path.join(PERSOS, pid)
    ref = pieds_ref(pid)
    res = {}
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        anim = fn[:-5]
        if not fn.endswith(".json") or (anims and anim not in anims):
            continue
        if not os.path.exists(os.path.join(d, anim + ".png")):
            continue
        r = analyser(os.path.join(d, anim + ".png"), json.load(open(os.path.join(d, fn))), anim, ref)
        if not r:
            continue
        # Exception déclarée par données (prompts_anims.json, persos.<id>.post.pieds_fixes) : planche
        # déjà centrée où la mesure des pieds se trompe (ex. bras tendu pris pour un pied) → pas de recalage.
        if anim in (_post(pid).get("pieds_fixes") or []):
            r["frame_offsets"] = [[0.0, 0.0]] * len(r["frame_offsets"])
        # Gestes où le bras se tend loin devant (apparition du chasseur) : pixelforge recentre la planche
        # sur la boîte englobante, le corps saute alors en arrière d'un coup (~40 px). On cale sur la TÊTE,
        # qui ne bouge pas dans ce geste (Julien 2026-10-20 : « l'animation défile »).
        if anim in ANCRE_TETE or anim in (_post(pid).get("ancre_tete") or []):
            r["frame_offsets"] = offsets_tete(os.path.join(d, anim + ".png"), len(r["frame_offsets"]))
        res[f"{pid}/{anim}"] = r
        if ecrit:
            ecrire(os.path.join(d, fn), r)
    return res


def planche(png: str, r: dict, sortie: str, corrige: bool) -> None:
    """Planche de contrôle : toutes les images, pieds posés marqués d'un point rouge, ligne de sol
    (vert) et verticale de référence des pieds (magenta) ; `corrige` applique frame_offsets.
    Plus un GIF animé de la même chose (24 i/s)."""
    img = Image.open(png).convert("RGBA")
    n, sol = r["frames"], r["sol"]
    cols = 8
    lignes = (n + cols - 1) // cols
    cs = 256
    out = Image.new("RGB", (cols * cs, lignes * cs), (236, 236, 228))
    gif = []
    ref = r.get("ref_x") or r.get("pieds_x") or 128.0
    for f in range(n):
        cell = img.crop((f * cs, 0, (f + 1) * cs, cs))
        dx, dy = r["frame_offsets"][f] if corrige else (0.0, 0.0)
        fond = Image.new("RGBA", (cs, cs), (236, 236, 228, 255))
        fond.alpha_composite(cell, (int(round(dx)), int(round(dy))))
        d = ImageDraw.Draw(fond)
        d.line([(0, sol), (cs, sol)], fill=(40, 140, 60), width=1)
        d.line([(ref, sol - 60), (ref, sol + 10)], fill=(200, 60, 200), width=1)
        for t in r["_taches"][f]:
            if t[3] and r["_au_sol"][f]:
                x, y = t[2] + dx, r["_bas"][f] + dy
                d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(230, 30, 30))
        d.text((4, 4), f"{f}{'  corrigé' if corrige else ''}", fill=(0, 0, 0))
        out.paste(fond.convert("RGB"), ((f % cols) * cs, (f // cols) * cs))
        gif.append(fond.convert("RGB"))
    out.save(sortie + ".png")
    gif[0].save(sortie + ".gif", save_all=True, append_images=gif[1:], duration=42, loop=0)


def comparaison(png: str, r: dict, sortie: str, pas: int = 2) -> None:
    """Avant (haut) / après (bas), une image sur `pas`, réduit de moitié : contrôle rapide."""
    planche(png, r, sortie + "_tmp_a", False)
    planche(png, r, sortie + "_tmp_b", True)
    a, b = Image.open(sortie + "_tmp_a.png"), Image.open(sortie + "_tmp_b.png")
    idx = list(range(0, r["frames"], pas))
    out = Image.new("RGB", (len(idx) * 128, 256), (255, 255, 255))
    for k, f in enumerate(idx):
        box = ((f % 8) * 256, (f // 8) * 256, (f % 8) * 256 + 256, (f // 8) * 256 + 256)
        out.paste(a.crop(box).resize((128, 128)), (k * 128, 0))
        out.paste(b.crop(box).resize((128, 128)), (k * 128, 128))
    out.save(sortie + ".png")
    for t in ("_tmp_a", "_tmp_b"):
        for ext in (".png", ".gif"):
            os.remove(sortie + t + ext)


def main() -> None:
    args = sys.argv[1:]
    def opt(nom: str):
        if nom in args:
            i = args.index(nom)
            v = args[i + 1]
            del args[i:i + 2]
            return v
        return None
    ecrit = "--ecrire" in args
    if ecrit:
        args.remove("--ecrire")
    rapport = opt("--rapport")
    planches = opt("--planches")
    anims = opt("--anim")
    ids = args or sorted(d for d in os.listdir(PERSOS) if os.path.isdir(os.path.join(PERSOS, d)))
    res = {}
    for pid in ids:
        res.update(corriger_perso(pid, anims.split(",") if anims else None, ecrit))
    if planches:
        os.makedirs(planches, exist_ok=True)
        for k, r in res.items():
            pid, anim = k.split("/")
            png = os.path.join(PERSOS, pid, anim + ".png")
            planche(png, r, os.path.join(planches, f"{pid}_{anim}_avant"), False)
            if not r["mouvement"]:
                planche(png, r, os.path.join(planches, f"{pid}_{anim}_apres"), True)
                comparaison(png, r, os.path.join(planches, f"{pid}_{anim}_avant_apres"))
    sp = {k: r for k, r in res.items() if not r["mouvement"]}
    mv = {k: r for k, r in res.items() if r["mouvement"]}
    lignes = ["SUR PLACE (px de case ; dérive = course cumulée du pied posé ; glisse = px/image)",
              f"{'perso/anim':28} {'dériveX':>8} {'dériveY':>8} {'glisse':>7} {'après':>6} {'max':>6} "
              f"{'pieds_x':>7} {'réf':>6}"]
    for k, r in sorted(sp.items(), key=lambda kv: -kv[1]["derive_x"]):
        lignes.append(f"{k:28} {r['derive_x']:8.1f} {r['derive_y']:8.1f} {r['glisse_moy']:7.2f} "
                      f"{r['glisse_moy_apres']:6.2f} {r['glisse_max']:6.1f} {r['pieds_x'] or 0:7.1f} "
                      f"{r['ref_x'] or 0:6.1f}")
    lignes += ["", "DÉPLACEMENT (stride = recul du pied posé par planche, px de case ; patine = écart "
               "pied/sol par image (px de case) avant (CYCLE_S) et après (stride, cadence bornée) ; cadences en planches/s à vitesse pleine)",
               f"{'perso/anim':28} {'appuis':>6} {'v_pied':>7} {'stride':>7} {'patine':>7} {'après':>6} {'cad.idéale':>10} {'avant':>6} {'après':>6}"]
    for k, r in sorted(mv.items(), key=lambda kv: -kv[1]["glisse_moy"]):
        anim = k.split("/")[1]
        lignes.append(f"{k:28} {r['appuis']:6d} {r['v_pied']:7.2f} {r['stride_px']:7.1f} "
                      f"{r['glisse_moy']:7.2f} {r['glisse_moy_apres']:6.2f} {r['cadence'] or 0:10.2f} "
                      f"{1.0 / CYCLE_S[anim]:6.2f} {r['cadence_jeu']:6.2f}")
    texte = "\n".join(lignes)
    print(texte)
    if rapport:
        os.makedirs(rapport, exist_ok=True)
        open(os.path.join(rapport, "rapport.txt"), "w").write(texte + "\n")
        propre = {k: {kk: vv for kk, vv in r.items() if not kk.startswith("_")} for k, r in res.items()}
        json.dump(propre, open(os.path.join(rapport, "rapport.json"), "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
