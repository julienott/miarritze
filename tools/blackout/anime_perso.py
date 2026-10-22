#!/usr/bin/env python3
"""Anime un perso de Blackout chez pixelforge (pf_2d__animate), un perso à la fois, à partir des
prompts soignés de tools/blackout/prompts_anims.json (Julien, 2026-10-20) : mouvement exagéré par les
réglages du mannequin (`mouvement`), accessoires décrits animation par animation, objets tenus
verrouillés (`hold`), masque de tenue par un mot simple.

  anime_perso.py depose <id> <profil.png> <fantome.png> [<anim> …]   (par défaut : toutes celles prêtes)
  anime_perso.py suivant <id>          attend la prochaine animation finie, rapatrie son GIF, rend la main
  anime_perso.py payload <id> <anim>   affiche le payload sans rien envoyer

Suivi : tools/blackout/taches_<id>.json (relu par import_perso.py). GIF de relecture :
tools/rd/out/<id>/gk2d/anims/<anim>.gif. Les paramètres sont recopiés dans GDD-BLACKOUT.md
"""
import json
import os
import re
import sys
import time
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402
import extras_pf as ex  # noqa: E402

PROMPTS = json.load(open(os.path.join(HERE, "prompts_anims.json")))
FINI = ("succeeded", "failed", "canceled", "expired")
FANTOMES = ("ghost", "ghost_move")
AILES = " and small white feathered angel wings on the back"


def payload(pid, anim):
    """Payload pf_2d__animate d'une animation (sans l'image d'entrée)."""
    a, p = PROMPTS["animations"][anim], PROMPTS["persos"][pid]
    mvt = {k: v for k, v in a["mouvement"].items() if k != "a_venir"}
    # Réglages propres au perso (ex. une mouette n'a pas de bras à lever : ses ailes en tiennent lieu).
    mvt.update(p.get("mouvement_tous", {}))              # ex. arms "wings" pour une mouette
    mvt.update(p.get("mouvement", {}).get(anim, {}))
    mvt = {k: v for k, v in mvt.items() if v is not None}
    action = p.get("actions", {}).get(anim, a["action"])
    for motif, mot in p.get("lexique", {}).items():      # corps non humain, féminin : on décrit ce qu'il a
        action = re.sub(motif, mot, action)
    morceaux = [PROMPTS["regles_communes"], action]
    if p.get("allure") and anim in ("walk", "run_scared", "idle", "victory"):
        morceaux.append("Way of moving: " + p["allure"] + ".")
    for acc in p.get("accessoires", []):
        geste = acc.get("par_animation", {}).get(anim, acc["defaut"])
        morceaux.append(f"The {acc['objet']}: {geste}.")
    desc = p["description"] + (AILES if anim in FANTOMES else "")
    texte = " ".join(morceaux)
    pl = {"prompt_style": "pf_2d__animate", **mvt, "description": desc, "action": texte,
          "expression": a["expression"], "loop": bool(a["boucle"]), "priority": "normal",
          "tag": f"miarritze/gk2d_{pid}"}
    if p.get("tenue"):
        pl["tenue"] = p["tenue"]
    if p.get("hold") and anim not in p.get("hold_sauf", []):
        pl["hold"] = p["hold"]
    return pl


def pretes():
    return [k for k, v in PROMPTS["animations"].items() if "a_venir" not in v["mouvement"] and not v.get("en_pause")]


def depose(pid, profil, fantome, anims):
    chemin = os.path.join(HERE, f"taches_{pid}.json")
    taches = json.load(open(chemin)) if os.path.exists(chemin) else {}
    imgs = {"perso": Image.open(profil).convert("RGB"), "fantome": Image.open(fantome).convert("RGB")}
    for anim in anims or pretes():
        if anim in taches:
            continue
        pl = payload(pid, anim)
        pl["input_image"] = ex.b64(imgs["fantome" if anim in FANTOMES else "perso"])
        taches[anim] = pf._post_json(pf.PF + "/v2/inferences", pl, timeout=300)["task_id"]
        json.dump(taches, open(chemin, "w"), indent=1)
        print("déposé", anim, taches[anim], flush=True)


def suivant(pid):
    taches = json.load(open(os.path.join(HERE, f"taches_{pid}.json")))
    out = os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "anims")
    os.makedirs(out, exist_ok=True)
    vus_p = os.path.join(out, "_vus.json")
    vus = json.load(open(vus_p)) if os.path.exists(vus_p) else []
    while True:
        reste = 0
        for anim, tid in taches.items():
            if tid in vus:
                continue
            try:
                r = json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
            except Exception as e:  # redémarrage de pixelforge
                print("relève impossible :", e, flush=True)
                time.sleep(30)
                continue
            if r["status"] not in FINI:
                reste += 1
                continue
            for f in r.get("result", {}).get("pixelforge", {}).get("files", []):
                if f["name"] == "animation_00.gif":
                    open(os.path.join(out, f"{anim}.gif"), "wb").write(
                        urllib.request.urlopen(f["url"], timeout=120).read())
            vus.append(tid)
            json.dump(vus, open(vus_p, "w"))
            print(anim, r["status"], str(r.get("error", ""))[:300], os.path.join(out, f"{anim}.gif"), flush=True)
            return
        if not reste:
            print("FINI : plus rien en attente", flush=True)
            return
        time.sleep(15)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "depose":
        depose(args[0], args[1], args[2], args[3:])
    elif cmd == "suivant":
        suivant(args[0])
    else:
        print(json.dumps(payload(args[0], args[1]), ensure_ascii=False, indent=1))
