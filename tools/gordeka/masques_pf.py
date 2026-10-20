#!/usr/bin/env python3
"""Masques de gameplay du décor calculés par pixelforge (pf_2d__footprint, demande de Julien 2026-10-20 :
« donner à pixelforge la spec pour nous créer des masques d'après des illustrations, dans une queue
comme une autre » ; notre calcul local sur la silhouette ne respectait pas les lignes de fuite).

  masques_pf.py depose [<id> …]     un job par objet intégré (défaut : tous ceux qui n'en ont pas)
  masques_pf.py releve              rapatrie les jobs finis ; rend la main quand il n'y a plus rien en vol

On envoie l'image INTÉGRÉE (assets/gordeka/decor/objets/<id>.png, 2 px par px de jeu) : les masques
reviennent alignés pixel pour pixel sur ce que le jeu affiche.
Sorties : assets/gordeka/decor/masques/<id>/{footprint,occluder,ground_contact}.png + masks.json (lus
par le jeu) ; aperçu de recette tools/gordeka/masques/<id>.png (affiché par /producer).
Suivi : tools/gordeka/taches_masques.json.
"""
import io
import json
import os
import sys
import time
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
sys.path.insert(0, HERE)
import nuit  # noqa: E402

DECOR = os.path.join(ROOT, "assets", "gordeka", "decor")
INDEX = os.path.join(DECOR, "index.json")
SUIVI = os.path.join(HERE, "taches_masques.json")
APERCUS = os.path.join(HERE, "masques")
PX_PAR_PX_JEU = 2          # images intégrées : 128 px par case de 64 px de jeu
PROMPTS = {e["id"]: e for e in json.load(open(os.path.join(HERE, "prompts_decor.json")))["elements"]}


def lire(p, d):
    return json.load(open(p)) if os.path.exists(p) else d


MARGE = 16                 # px transparents ajoutés autour (nos images sont recadrées au ras de l'objet)


def largeur_jeu(el, img):
    """Largeur affichée dans le jeu, comme GkDecor : s = min(largeur emprise / l, hauteur permise / h)."""
    cw, ch = el["taille_cases"]
    s = min(cw * 64 / img.width, (ch + el.get("debord_haut_cases", 0)) * 64 / img.height)
    return round(img.width * s)


def payload(eid, el):
    img = Image.open(os.path.join(DECOR, el["fichiers"][0])).convert("RGBA")
    grand = Image.new("RGBA", (img.width + 2 * MARGE, img.height + 2 * MARGE))
    grand.alpha_composite(img, (MARGE, MARGE))
    p = PROMPTS.get(eid, {})
    hint = p.get("prompt_specifique") or el.get("nom", eid)
    return {"prompt_style": "pf_2d__footprint", "input_image": nuit.ex.b64(grand),
            "game_width_px": round(largeur_jeu(el, img) * grand.width / img.width),
            "footprint_cells": el["taille_cases"],
            "camera": "front34", "hint": hint[:300], "thin_px": 10 * PX_PAR_PX_JEU, "char_height_cells": 1.5,
            "priority": "high", "tag": f"miarritze/masque_{eid}"}


def depose(ids):
    els = lire(INDEX, {})["elements"]
    suivi = lire(SUIVI, {})
    for eid, el in els.items():
        if el.get("type") != "objet" or not el.get("fichiers"):
            continue
        if ids and eid not in ids:
            continue
        if not ids and eid in suivi:
            continue
        suivi[eid] = {"tid": nuit.deposer(payload(eid, el)), "fichier": el["fichiers"][0], "statut": "en_vol"}
        json.dump(suivi, open(SUIVI, "w"), indent=1)
        print("déposé", eid, suivi[eid]["tid"], flush=True)


def releve(une_fois=False):
    while True:
        suivi = lire(SUIVI, {})
        reste = 0
        for eid, s in suivi.items():
            if s["statut"] != "en_vol":
                continue
            r = nuit.tache(s["tid"])
            if r["status"] not in nuit.FINI:
                reste += 1
                continue
            s["statut"] = r["status"]
            if r["status"] == "succeeded":
                d = os.path.join(DECOR, "masques", eid)
                os.makedirs(d, exist_ok=True)
                for f in r["result"]["pixelforge"]["files"]:
                    data = urllib.request.urlopen(f["url"], timeout=120).read()
                    if f["name"].startswith("preview"):
                        os.makedirs(APERCUS, exist_ok=True)
                        open(os.path.join(APERCUS, eid + ".png"), "wb").write(data)
                    elif f["name"].endswith(".png"):     # on retire la marge ajoutée au dépôt
                        im = Image.open(io.BytesIO(data))
                        im.crop((MARGE, MARGE, im.width - MARGE, im.height - MARGE)).save(os.path.join(d, f["name"]))
                    else:
                        open(os.path.join(d, f["name"]), "wb").write(data)
                m = lire(os.path.join(d, "masks.json"), {})
                if m and not m.get("marge_retiree"):      # coordonnées ramenées à l'image intégrée
                    for k in ("front_y", "back_y", "baseline_y"):
                        if isinstance(m.get(k), (int, float)):
                            m[k] -= MARGE
                    if isinstance(m.get("bbox"), list) and len(m["bbox"]) == 4:
                        m["bbox"] = [m["bbox"][0] - MARGE, m["bbox"][1] - MARGE] + m["bbox"][2:]
                    m["polygons"] = [[[x - MARGE, y - MARGE] for x, y in poly] for poly in m.get("polygons", [])]
                    m["size"] = [m["size"][0] - 2 * MARGE, m["size"][1] - 2 * MARGE] if m.get("size") else m.get("size")
                    m["marge_retiree"] = MARGE
                    json.dump(m, open(os.path.join(d, "masks.json"), "w"), indent=1)
                print("reçu", eid, "warnings:", m.get("warnings"), "confiance:", m.get("confidence"), flush=True)
            else:
                print("ÉCHEC", eid, r["status"], str(r.get("error", ""))[:200], flush=True)
            json.dump(suivi, open(SUIVI, "w"), indent=1)
        if not reste or une_fois:
            if not reste:
                print("FINI", flush=True)
            return
        time.sleep(30)


if __name__ == "__main__":
    if sys.argv[1] == "depose":
        depose(sys.argv[2:])
    else:
        releve()
