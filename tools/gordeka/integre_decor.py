#!/usr/bin/env python3
"""Intègre dans le jeu un élément de décor livré par pixelforge, dès qu'il est prêt.

  integre_decor.py <id> [<n> [<variante>]] [--ajoute] [--source DIR] [--dest DIR] [--sans-capture]
  integre_decor.py <id> [<n> [<variante>]] --etat ouvert [--fichier PNG] [--source DIR] [--dest DIR]

  <id>        élément de tools/gordeka/prompts_decor.json (ex. sol_dalles_quai, caisses_poisson)
  <n>         job de l'élément : tools/rd/out/decor/<id>/<n>/ (défaut : le premier livré)
  <variante>  image retenue dans ce job (défaut : image_00)
  --ajoute    tuile de sol : ajoute l'image comme variante supplémentaire au lieu de remplacer
  --source    racine des livraisons (défaut : tools/rd/out/decor)
  --dest      racine du décor du jeu (défaut : assets/gordeka/decor). Hors projet, la capture passe
              au jeu `--gk-decor-dir=<dest>` (essais sans toucher aux assets).
  --sans-capture   pas de capture de vérification
  --etat ouvert    image de l'état ouvert d'une cachette déjà intégrée (retouche pf_hd__edit de
              l'image fermée) : écrit <dest>/objets/<id>_ouvert.png et met à jour `ouvert` et
              `ouvert_decalage` dans l'index, sans toucher à l'image fermée ni au reste de l'entrée
  --fichier   image source donnée directement (au lieu de <source>/<id>/<n>/<variante>.png)

Traitement :
- objet / decal : recadrage au plus juste (alpha), réduction à 128 px par case d'emprise
  (2× la case de jeu, sans dépasser la hauteur emprise + débord), ombre (<variante>_shadow.png)
  recadrée à part, avec son décalage noté dans l'index ;
- état ouvert : même échelle que l'image fermée. Si l'image fermée d'origine (job et variante de
  `sources`) a la même taille que l'image ouverte (retouche de la même image), le recadrage se
  fait sur l'union des deux contenus et le décalage est exact ; sinon l'image ouverte est mise à la
  largeur de la fermée, bas et centre alignés. Le jeu la fond par-dessus la fermée (GkDecor) ;
- tuile_sol : réduction sans recadrage à 128 px par case (256 px pour 2×2 cases), faite en
  enroulant la tuile (3×3) pour qu'elle reste raccordable ; contrôle des raccords avant/après.
Écrit <dest>/sols|objets/<id>.png (+ <id>_ombre.png), met à jour <dest>/index.json (lu par
src/gordeka/gk_decor.gd ; décrit tous les éléments, `fichiers` pour ceux qui ont une image), importe dans Godot puis capture la zone (`--gk-cam=<zone>`) dans
tests/out/decor/<id>.png (<id>_ouvert.png pendant une entrée pour l'état ouvert), avec une planche de la tuile 2×2 pour les sols.
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
CHAMPS_OUVERT = ("ouvert", "ouvert_decalage", "sources_ouvert")
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


SEUIL_BORD = 0.05      # part d'un bord de l'image générée occupée par l'objet au-delà de laquelle on prévient


def bords_coupes(src):
    """Bords de l'image générée (<variante>_raw.png, fond blanc) que l'objet touche : il y est coupé
    par le cadre de la génération (toit de maison_crampotte, lanterne de tour_phare, 2026-10-20) et le
    recadrage ne peut pas le rendre ; à régénérer avec de la marge."""
    raw = src.removesuffix(".png") + "_raw.png"
    if not os.path.exists(raw):
        return []
    a = np.asarray(Image.open(raw).convert("RGB")).min(axis=2) < 235
    bords = {"haut": a[0], "bas": a[-1], "gauche": a[:, 0], "droite": a[:, -1]}
    return [nom for nom, ligne in bords.items() if ligne.mean() > SEUIL_BORD]


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
    ap.add_argument("--etat", choices=["ferme", "ouvert"], default="ferme")
    ap.add_argument("--fichier")
    o = ap.parse_args()
    els = {e["id"]: e for e in json.load(open(PROMPTS))["elements"]}
    if o.id not in els:
        erreur(f"élément inconnu : {o.id}")
    el = els[o.id]
    typ = el["type"]
    if typ in ("tuile_bord", "bande_facade"):
        erreur(f"type {typ} pas encore géré par le jeu (gk_decor.gd)")
    if o.fichier:
        n, variante, src = o.n or "0", os.path.basename(o.fichier).removesuffix(".png"), o.fichier
    else:
        n = o.n if o.n is not None else job_par_defaut(os.path.join(o.source, o.id))
        variante = o.variante.removesuffix(".png")
        src = os.path.join(o.source, o.id, n, variante + ".png")
    if not os.path.exists(src):
        erreur(f"image absente : {src}")
    dest = os.path.abspath(o.dest)
    cw, ch = (int(v) for v in el["taille_cases"])
    debord = float(el.get("debord_haut_cases", 0))   # négatif permis : objet plus bas qu'une case (bitte)
    img = Image.open(src)
    print(f"{o.id} ({typ}) ← {src} {img.size[0]}×{img.size[1]}")
    if typ == "objet":
        coupes = bords_coupes(src)
        if coupes:
            print(f"  ATTENTION : l'objet touche le cadre de l'image générée ({', '.join(coupes)}) : il y est "
                  "sans doute coupé (toit tronqué…) ; à régénérer avec de la marge, à regarder sur la capture")
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
    source = {"job": int(n) if str(n).isdigit() else n, "variante": variante, "task": tache,
              "date": datetime.date.today().isoformat()}
    if o.fichier:
        source["fichier"] = os.path.abspath(o.fichier)

    if o.etat == "ouvert":
        integre_ouvert(o, el, img, ancien, source, dest)
        index["elements"][o.id] = ancien
        json.dump(index, open(index_path, "w"), ensure_ascii=False, indent=1)
        print(f"  index : {index_path}")
        capture(o, el, dest)
        return

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
        for k in CHAMPS_OUVERT:
            if k in ancien:
                entree[k] = ancien[k]
        if "ouvert" in ancien:
            print("  attention : image fermée changée, vérifier le calage de l'état ouvert (--etat ouvert à refaire ?)")
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
    capture(o, el, dest)


def integre_ouvert(o, el, img, entree, source, dest):
    """État ouvert d'une cachette : même échelle que l'image fermée intégrée, calage noté dans
    `ouvert_decalage` (px de l'image intégrée, depuis le coin haut gauche de la fermée)."""
    if el["type"] != "objet":
        erreur("--etat ouvert : seulement pour un objet (cachette)")
    if not entree.get("fichiers"):
        erreur(f"--etat ouvert : {o.id} n'a pas encore d'image fermée intégrée")
    ferme = Image.open(os.path.join(dest, entree["fichiers"][0]))
    img = detoure(img)
    bb = bbox_alpha(img)
    if bb is None:
        erreur("image entièrement transparente")
    # Image fermée d'origine (même toile si l'ouverte en est une retouche) : calage exact.
    orig = None
    for s0 in entree.get("sources", [])[:1]:
        p = os.path.join(o.source, o.id, str(s0.get("job", "")), str(s0.get("variante", "")) + ".png")
        if os.path.exists(p):
            orig = detoure(Image.open(p))
    if orig is not None and orig.size == img.size and bbox_alpha(orig):
        fb = bbox_alpha(orig)
        s = ferme.size[0] / (fb[2] - fb[0])
        dx, dy = bb[0] - fb[0], bb[1] - fb[1]
        print(f"  calé sur l'image fermée d'origine ({orig.size[0]}×{orig.size[1]})")
    else:
        # Pas la même toile : largeur de la fermée, bas et centre alignés.
        s = ferme.size[0] / (bb[2] - bb[0])
        dx, dy = 0, ferme.size[1] / s - (bb[3] - bb[1])
        print("  attention : image fermée d'origine introuvable ou d'une autre taille, calage par la largeur et le bas")
    crop = img.crop(bb)
    taille = (max(1, round(crop.size[0] * s)), max(1, round(crop.size[1] * s)))
    os.makedirs(os.path.join(dest, "objets"), exist_ok=True)
    nom = f"objets/{o.id}_ouvert.png"
    crop.resize(taille, Image.LANCZOS).save(os.path.join(dest, nom), optimize=True)
    entree["ouvert"] = nom
    entree["ouvert_decalage"] = [round(dx * s), round(dy * s)]
    entree["sources_ouvert"] = [source]
    print(f"  ouvert {taille[0]}×{taille[1]} px, décalage {entree['ouvert_decalage']} (fermée {ferme.size[0]}×{ferme.size[1]})")


def capture(o, el, dest):
    if o.sans_capture:
        return
    dans_projet = dest.startswith(os.path.join(ROOT, "assets") + os.sep)
    if dans_projet:
        r = godot("--headless", "--import", timeout=600)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            erreur("import Godot en échec")
    os.makedirs(CAPTURES, exist_ok=True)
    ouvert = o.etat == "ouvert"
    shot = os.path.join(CAPTURES, f"{o.id}_ouvert.png" if ouvert else f"{o.id}.png")
    if os.path.exists(shot):
        os.remove(shot)
    zone = zone_capture(el)
    args = ["--", "--scene=gk_game", "--gk-bots-only", f"--gk-cam={zone}", f"--shot={shot}", "--delay=6"]
    if ouvert:
        # Capture pendant une entrée : la cachette est ouverte (gk_game, --gk-qa-cachette).
        args += [f"--gk-qa-cachette={zone}", "--gk-rules=phase_draw:60"]
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
