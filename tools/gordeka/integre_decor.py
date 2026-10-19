#!/usr/bin/env python3
"""Intègre dans le jeu un élément de décor livré par pixelforge, dès qu'il est prêt.

  integre_decor.py <id> [<n> [<variante>]] [--ajoute] [--source DIR] [--dest DIR] [--sans-capture]

  <id>        élément de tools/gordeka/prompts_decor.json (ex. sol_dalles_quai, caisses_poisson)
  <n>         job de l'élément : tools/rd/out/decor/<id>/<n>/ (défaut : le premier livré)
  <variante>  image retenue dans ce job (défaut : image_00)
  --ajoute    tuile de sol : ajoute l'image comme variante supplémentaire au lieu de remplacer
  --source    racine des livraisons (défaut : tools/rd/out/decor)
  --dest      racine du décor du jeu (défaut : assets/gordeka/decor). Hors projet, la capture passe
              au jeu `--gk-decor-dir=<dest>` (essais sans toucher aux assets).
  --sans-capture   pas de capture de vérification

Traitement :
- objet / decal : recadrage au plus juste (alpha), réduction à 128 px par case d'emprise
  (2× la case de jeu, sans dépasser la hauteur emprise + débord), ombre (<variante>_shadow.png)
  recadrée à part, avec son décalage noté dans l'index ;
- tuile_sol : réduction sans recadrage à 128 px par case (256 px pour 2×2 cases), faite en
  enroulant la tuile (3×3) pour qu'elle reste raccordable ; contrôle des raccords avant/après.
Écrit <dest>/sols|objets/<id>.png (+ <id>_ombre.png), met à jour <dest>/index.json (lu par
src/gordeka/gk_decor.gd ; décrit tous les éléments, `fichiers` pour ceux qui ont une image), importe dans Godot puis capture la zone (`--gk-cam=<zone>`) dans
tests/out/decor/<id>.png, avec une planche de la tuile 2×2 pour les sols.
"""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PROMPTS = os.path.join(HERE, "prompts_decor.json")
SUIVI = os.path.join(HERE, "taches_decor.json")
SOURCE = os.path.join(ROOT, "tools", "rd", "out", "decor")
DEST = os.path.join(ROOT, "assets", "gordeka", "decor")
CAPTURES = os.path.join(ROOT, "tests", "out", "decor")
ZONES = os.path.join(ROOT, "assets", "maps", "port_pecheurs", "zones.json")
PX_CASE = 128          # px par case dans les images intégrées (2× la case de jeu de 64 px)
SEUIL_ALPHA = 8        # en dessous : transparent (recadrage)
SEUIL_RACCORD = 2.5    # écart au raccord / écart moyen entre colonnes voisines au-delà duquel on prévient
CHAMPS = ("nom", "type", "categorie", "caractere", "zones", "taille_cases", "debord_haut_cases", "animation")


def erreur(msg):
    print("ERREUR :", msg, file=sys.stderr)
    sys.exit(2)


def job_par_defaut(dossier):
    jobs = sorted((d for d in os.listdir(dossier) if d.isdigit()), key=int) if os.path.isdir(dossier) else []
    if not jobs:
        erreur(f"aucun job livré dans {dossier}")
    return jobs[0]


def bbox_alpha(img):
    a = np.asarray(img.getchannel("A"))
    ys, xs = np.nonzero(a > SEUIL_ALPHA)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def detoure(img):
    """Objet livré sans transparence (fond blanc) : le blanc presque pur devient transparent."""
    if img.mode == "RGBA" and np.asarray(img.getchannel("A")).min() < 250:
        return img.convert("RGBA")
    print("  attention : pas de transparence, fond blanc retiré au seuil")
    rgba = np.array(img.convert("RGBA"))
    blanc = (rgba[..., :3].min(axis=2) > 245)
    rgba[blanc, 3] = 0
    return Image.fromarray(rgba, "RGBA")


def ombre_rgba(img, taille):
    """Calque d'ombre en RGBA : s'il n'a pas d'alpha, le sombre devient l'opacité d'un noir."""
    if img.size != taille:
        img = img.resize(taille, Image.LANCZOS)
    if img.mode == "RGBA" and np.asarray(img.getchannel("A")).min() < 250:
        return img
    lum = np.asarray(img.convert("L")).astype(np.float32)
    rgba = np.zeros((img.size[1], img.size[0], 4), np.uint8)
    rgba[..., 3] = np.clip(255 - lum, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def ecart_raccord(img):
    """Rapport (bord gauche↔droit, haut↔bas) entre l'écart au raccord et l'écart moyen entre
    lignes voisines : ~1 pour une tuile raccordable."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    voisins_x = np.abs(np.diff(a, axis=1)).mean()
    voisins_y = np.abs(np.diff(a, axis=0)).mean()
    rx = np.abs(a[:, 0] - a[:, -1]).mean() / max(voisins_x, 1e-3)
    ry = np.abs(a[0, :] - a[-1, :]).mean() / max(voisins_y, 1e-3)
    return rx, ry


def reduit_tuile(img, w, h):
    """Réduction sans recadrage qui garde le raccord : on enroule la tuile 3×3 avant de réduire."""
    img = img.convert("RGB")
    W, H = img.size
    grand = Image.new("RGB", (W * 3, H * 3))
    for j in range(3):
        for i in range(3):
            grand.paste(img, (i * W, j * H))
    petit = grand.resize((w * 3, h * 3), Image.LANCZOS)
    return petit.crop((w, h, 2 * w, 2 * h))


def zone_capture(el):
    noms = [z["name"] for z in json.load(open(ZONES))["zones"]]
    for z in el.get("zones", []):
        base = z.split(" (")[0].strip()
        if base in noms:
            return base
    return noms[0]


def godot(*args, timeout=180):
    return subprocess.run(["godot", "--path", ROOT, *args], capture_output=True, text=True, timeout=timeout)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id")
    ap.add_argument("n", nargs="?")
    ap.add_argument("variante", nargs="?", default="image_00")
    ap.add_argument("--ajoute", action="store_true")
    ap.add_argument("--source", default=SOURCE)
    ap.add_argument("--dest", default=DEST)
    ap.add_argument("--sans-capture", action="store_true")
    o = ap.parse_args()
    els = {e["id"]: e for e in json.load(open(PROMPTS))["elements"]}
    if o.id not in els:
        erreur(f"élément inconnu : {o.id}")
    el = els[o.id]
    typ = el["type"]
    if typ in ("tuile_bord", "bande_facade"):
        erreur(f"type {typ} pas encore géré par le jeu (gk_decor.gd)")
    n = o.n if o.n is not None else job_par_defaut(os.path.join(o.source, o.id))
    variante = o.variante.removesuffix(".png")
    src = os.path.join(o.source, o.id, n, variante + ".png")
    if not os.path.exists(src):
        erreur(f"image absente : {src}")
    dest = os.path.abspath(o.dest)
    cw, ch = (int(v) for v in el["taille_cases"])
    debord = int(el.get("debord_haut_cases", 0))
    img = Image.open(src)
    print(f"{o.id} ({typ}) ← {src} {img.size[0]}×{img.size[1]}")
    index_path = os.path.join(dest, "index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {
        "_doc": "Décor en images intégré par tools/gordeka/integre_decor.py, lu par src/gordeka/gk_decor.gd.",
        "carte": "port_pecheurs", "elements": {}}
    ancien = index["elements"].get(o.id, {})
    entree = {k: el[k] for k in CHAMPS if k in el}
    entree["animation"] = el.get("animation") or {}
    tache = ""
    try:
        tache = json.load(open(SUIVI)).get(o.id, [])[int(n)]
    except (OSError, IndexError, ValueError):
        pass
    source = {"job": int(n), "variante": variante, "task": tache,
              "date": datetime.date.today().isoformat()}

    if typ == "tuile_sol":
        os.makedirs(os.path.join(dest, "sols"), exist_ok=True)
        w, h = cw * PX_CASE, ch * PX_CASE
        if abs(img.size[0] / img.size[1] - w / h) > 0.02:
            print(f"  attention : proportions {img.size} ≠ {cw}×{ch} cases, la tuile sera déformée")
        rx, ry = ecart_raccord(img)
        petit = reduit_tuile(img, w, h)
        px, py = ecart_raccord(petit)
        print(f"  raccord source {rx:.2f}/{ry:.2f}, réduite {px:.2f}/{py:.2f} (≈1 : raccordable)")
        if max(px, py) > SEUIL_RACCORD:
            print("  ATTENTION : la tuile ne semble pas raccordable, à regarder sur la planche 2×2")
        fichiers = list(ancien.get("fichiers", [])) if o.ajoute else []
        sources = list(ancien.get("sources", [])) if o.ajoute else []
        nom = f"sols/{o.id}.png" if not fichiers else f"sols/{o.id}_v{len(fichiers) + 1}.png"
        petit.save(os.path.join(dest, nom), optimize=True)
        fichiers.append(nom)
        sources.append(source)
        entree.update({"fichiers": fichiers, "sources": sources})
        # Planche 2×2 de la tuile intégrée : les raccords se voient.
        os.makedirs(CAPTURES, exist_ok=True)
        planche = Image.new("RGB", (w * 2, h * 2))
        for j in range(2):
            for i in range(2):
                planche.paste(petit, (i * w, j * h))
        planche.save(os.path.join(CAPTURES, f"{o.id}_tuile2x2.png"))
    else:
        os.makedirs(os.path.join(dest, "objets"), exist_ok=True)
        img = detoure(img)
        bb = bbox_alpha(img)
        if bb is None:
            erreur("image entièrement transparente")
        crop = img.crop(bb)
        bw, bh = crop.size
        hmax = (ch + (debord if typ == "objet" else 0)) * PX_CASE
        s = min(cw * PX_CASE / bw, hmax / bh)
        taille = (max(1, round(bw * s)), max(1, round(bh * s)))
        crop.resize(taille, Image.LANCZOS).save(os.path.join(dest, "objets", f"{o.id}.png"), optimize=True)
        print(f"  recadré {bb} → {taille[0]}×{taille[1]} px (emprise {cw}×{ch} cases, débord {debord})")
        entree.update({"fichiers": [f"objets/{o.id}.png"], "sources": [source], "ombre": "", "ombre_decalage": [0, 0]})
        ombre_src = os.path.join(o.source, o.id, n, variante + "_shadow.png")
        if os.path.exists(ombre_src) and typ == "objet":
            om = ombre_rgba(Image.open(ombre_src), img.size)
            ob = bbox_alpha(om)
            if ob:
                ot = (max(1, round((ob[2] - ob[0]) * s)), max(1, round((ob[3] - ob[1]) * s)))
                om.crop(ob).resize(ot, Image.LANCZOS).save(os.path.join(dest, "objets", f"{o.id}_ombre.png"), optimize=True)
                entree["ombre"] = f"objets/{o.id}_ombre.png"
                entree["ombre_decalage"] = [round((ob[0] - bb[0]) * s), round((ob[1] - bb[1]) * s)]
                print(f"  ombre {ot[0]}×{ot[1]} px, décalage {entree['ombre_decalage']}")
        if ancien.get("ouvert"):
            entree["ouvert"] = ancien["ouvert"]
    # Tous les éléments sont décrits (sans image pour la plupart) : le jeu choisit, pour un groupe
    # de cases, l'élément à l'emprise la plus proche parmi tous ceux de la zone, pas seulement
    # parmi ceux déjà intégrés (sinon un banc prendrait l'image de la fontaine).
    for eid, e in els.items():
        meta = {k: e[k] for k in CHAMPS if k in e}
        meta["animation"] = e.get("animation") or {}
        index["elements"][eid] = {**index["elements"].get(eid, {}), **meta}
    index["elements"][o.id] = entree
    os.makedirs(dest, exist_ok=True)
    json.dump(index, open(index_path, "w"), ensure_ascii=False, indent=1)
    print(f"  index : {index_path}")

    if o.sans_capture:
        return
    dans_projet = dest.startswith(os.path.join(ROOT, "assets") + os.sep)
    if dans_projet:
        r = godot("--headless", "--import", timeout=600)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            erreur("import Godot en échec")
    os.makedirs(CAPTURES, exist_ok=True)
    shot = os.path.join(CAPTURES, f"{o.id}.png")
    if os.path.exists(shot):
        os.remove(shot)
    zone = zone_capture(el)
    args = ["--", "--scene=gk_game", "--gk-bots-only", f"--gk-cam={zone}", f"--shot={shot}", "--delay=6"]
    if not dans_projet:
        args.append(f"--gk-decor-dir={dest}")
    r = godot(*args)
    if not os.path.exists(shot):
        print(r.stdout[-2000:], r.stderr[-2000:])
        erreur("capture non produite")
    print(f"  capture ({zone}) : {shot}")


if __name__ == "__main__":
    if shutil.which("godot") is None:
        print("attention : godot introuvable dans le PATH (pas d'import ni de capture)")
    main()
