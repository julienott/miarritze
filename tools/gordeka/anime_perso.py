#!/usr/bin/env python3
"""Anime un perso de Gordeka chez pixelforge, un perso à la fois (Julien, 2026-10-20) :
13 animations pf_2d__animate depuis le profil choisi, plus le fantôme (le même perso avec de petites
ailes d'ange, pf_2d__character) animé en ghost / ghost_move.

  anime_perso.py <id> <profil.png> "<tenue>" "<description>" "<prompt du fantôme>"

Écrit tools/gordeka/taches_<id>.json (relu par import_perso.py) et rapatrie le GIF de chaque
animation dans tools/rd/out/<id>/gk2d/pf/<anim>/ pour la relecture. Les paramètres sont recopiés
dans SPEC-GORDEKA.md §16.2.
"""
import json
import os
import sys
import time
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402
import extras_pf as ex  # noqa: E402

MOTIONS = ["idle", "walk", "run_scared", "hide_in", "hide_out", "found", "trap", "trapped", "search", "detect",
           "extract", "victory", "sad"]
FINI = ("succeeded", "failed", "canceled", "expired")


def tache(tid):
    return json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())


def deposer(payload):
    return pf._post_json(pf.PF + "/v2/inferences", payload, timeout=300)["task_id"]


def main():
    pid, profil, tenue, desc, fantome = sys.argv[1:6]
    tag = f"miarritze/gk2d_{pid}"
    chemin = os.path.join(HERE, f"taches_{pid}.json")
    taches = json.load(open(chemin)) if os.path.exists(chemin) else {}
    src = Image.open(profil).convert("RGB")
    for m in MOTIONS:
        if m not in taches:
            taches[m] = deposer({"prompt_style": "pf_2d__animate", "input_image": ex.b64(src), "motion": m,
                                 "tenue": tenue, "description": desc, "tag": tag})
            print("déposé", m, taches[m], flush=True)
    # Le fantôme : d'abord son profil (même perso + ailes), puis ses deux animations.
    if "ghost_profil" not in taches:
        taches["ghost_profil"] = deposer({"prompt_style": "pf_2d__character", "input_image": ex.b64(src),
                                          "prompt": fantome, "num_images": 1, "seed": 7, "tag": tag})
        print("déposé ghost_profil", taches["ghost_profil"], flush=True)
    json.dump(taches, open(chemin, "w"), indent=1)

    revue = os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "pf")
    left = {k: v for k, v in taches.items()}
    while left:
        for k, tid in list(left.items()):
            r = tache(tid)
            if r["status"] not in FINI:
                continue
            del left[k]
            print(k, r["status"], str(r.get("error", ""))[:200], flush=True)
            if r["status"] != "succeeded":
                continue
            files = r["result"]["pixelforge"]["files"]
            if k == "ghost_profil":
                d = os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "fantome")
                os.makedirs(d, exist_ok=True)
                for f in files:
                    open(os.path.join(d, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())
                g = Image.open(os.path.join(d, "image_00_white.png" if os.path.exists(
                    os.path.join(d, "image_00_white.png")) else "image_00.png")).convert("RGB")
                for m, mot in (("ghost", "idle"), ("ghost_move", "walk")):
                    if m not in taches:
                        taches[m] = left[m] = deposer({
                            "prompt_style": "pf_2d__animate", "input_image": ex.b64(g), "motion": mot, "tenue": tenue,
                            "expression": "mischievous sly smile", "tag": tag,
                            "description": desc + " and small white angel wings on his back, the wings flapping"})
                        print("déposé", m, taches[m], flush=True)
                json.dump(taches, open(chemin, "w"), indent=1)
                continue
            for f in files:
                if f["name"] == "animation_00.gif":
                    os.makedirs(os.path.join(revue, k), exist_ok=True)
                    open(os.path.join(revue, k, f["name"]), "wb").write(
                        urllib.request.urlopen(f["url"], timeout=120).read())
        time.sleep(15)
    print("FINI", flush=True)


if __name__ == "__main__":
    main()
