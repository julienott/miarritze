#!/usr/bin/env python3
"""Retouche d'un profil de perso choisi par Julien (pf_hd__edit), ou nouveau profil (pf_2d__character).
Dépose la tâche, attend sa fin, rapatrie les images : le script rend la main dès que CE job est fini,
pour montrer chaque résultat à Julien sans attendre les autres (Julien, 2026-10-20).

  retouche_profil.py edit <id> <image.png> "<prompt>" <dossier_sortie> [num_images]
  retouche_profil.py char <id> "<prompt>" <dossier_sortie> [num_images]
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

# Priorité de file pixelforge (Julien) : 0 urgence = high, 1 persos et animations = normal, 2 décor = low.
# PF_URGENT=1 passe la retouche en urgence.
PRIORITE = "high" if os.environ.get("PF_URGENT") else "normal"


def main():
    mode, pid = sys.argv[1], sys.argv[2]
    if mode == "edit":
        src, prompt, out = sys.argv[3:6]
        n = int(sys.argv[6]) if len(sys.argv) > 6 else 2
        im = Image.open(src).convert("RGBA")
        bg = Image.new("RGBA", im.size, "white")
        bg.alpha_composite(im)
        payload = {"prompt_style": "pf_hd__edit", "input_image": ex.b64(bg.convert("RGB")), "prompt": prompt,
                   "num_images": n, "seed": 1, "tag": f"miarritze/gk2d_{pid}", "priority": PRIORITE}
        params = {"style": "pf_hd__edit", "entree": src, "prompt": prompt, "seed": 1, "num_images": n}
    else:
        prompt, out = sys.argv[3:5]
        n = int(sys.argv[5]) if len(sys.argv) > 5 else 3
        payload = {"prompt_style": "pf_2d__character", "prompt": prompt, "num_images": n, "seed": 1,
                   "tag": f"miarritze/gk2d_{pid}", "priority": PRIORITE}
        params = {"style": "pf_2d__character", "entree": "aucune (description seule)", "prompt": prompt, "seed": 1,
                  "num_images": n}
    os.makedirs(out, exist_ok=True)
    tid = pf._post_json(pf.PF + "/v2/inferences", payload, timeout=300)["task_id"]
    params["task"] = tid
    json.dump(params, open(os.path.join(out, "params.json"), "w"), ensure_ascii=False, indent=1)
    print("déposé", pid, tid, flush=True)
    while True:
        try:
            r = json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
        except Exception as e:  # redémarrage de pixelforge : on réessaie
            print("relève impossible :", e, flush=True)
            time.sleep(30)
            continue
        if r["status"] in ("succeeded", "failed", "canceled", "expired"):
            break
        time.sleep(10)
    print(pid, r["status"], str(r.get("error", ""))[:300], flush=True)
    for f in r.get("result", {}).get("pixelforge", {}).get("files", []):
        open(os.path.join(out, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())
        print(f["name"], flush=True)


if __name__ == "__main__":
    main()
