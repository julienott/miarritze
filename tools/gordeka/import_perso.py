#!/usr/bin/env python3
"""Rapatrie les animations 2D d'un perso produites par pixelforge (pf_2d__anim) dans le jeu.

  import_perso.py <id> <taches.json>

taches.json : {"idle": "<task_id>", "walk": "<task_id>", …} (un task_id par chorégraphie).
Pour chaque animation, on enregistre dans assets/gordeka/persos/<id>/ :
  <anim>.png (planche), <anim>_tenue.png (masque de tenue), <anim>.json (fps, boucle, ancrage).
Un GIF d'aperçu par animation va dans tools/rd/out/<id>/gk2d/pf/<anim>/ pour la relecture.
"""
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

ROLES = {"spritesheet_00.png": "{a}.png", "tenue_sheet_00.png": "{a}_tenue.png", "animation_00.json": "{a}.json"}


def main() -> None:
    pid, taches = sys.argv[1], json.load(open(sys.argv[2]))
    dest = os.path.join(ROOT, "assets", "gordeka", "persos", pid)
    revue = os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "pf")
    os.makedirs(dest, exist_ok=True)
    for anim, tid in taches.items():
        r = json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
        if r.get("status") != "succeeded":
            print(f"{anim} : tâche {tid} {r.get('status')}, ignorée")
            continue
        for f in r["result"]["pixelforge"]["files"]:
            data = None
            if f["name"] in ROLES:
                data = urllib.request.urlopen(f["url"], timeout=120).read()
                open(os.path.join(dest, ROLES[f["name"]].format(a=anim)), "wb").write(data)
            elif f["name"] == "animation_00.gif":
                os.makedirs(os.path.join(revue, anim), exist_ok=True)
                data = urllib.request.urlopen(f["url"], timeout=120).read()
                open(os.path.join(revue, anim, f["name"]), "wb").write(data)
        print(f"{anim} : ok")


if __name__ == "__main__":
    main()
