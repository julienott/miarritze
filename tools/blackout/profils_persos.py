#!/usr/bin/env python3
"""Profils 2D des persos de Blackout (pf_2d__character, description seule : partir du pixel art de
Borroka donne un rendu pixelisé). 3 variantes par perso, déposées toutes ensemble dans la file
pixelforge, relevées au fil de l'eau.

  profils_persos.py [<id> …]      (par défaut : tous ceux de PROMPTS)

Sorties : tools/rd/out/<id>/gk2d/profil/ (image_0N.png, image_0N_white.png, params.json, planche.png)
et tools/rd/out/gk2d_profils.png (tous les persos). Les prompts sont recopiés dans SPEC-GORDEKA.md §16.2.
Les accessoires tenus en main (canne, poêle, makila) sont portés sur le dos ou à la ceinture pour
laisser les mains libres aux animations (mouvements Quaternius).
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

FIN = ", smooth clean cartoon, no pixel art"
PROMPTS = {
    "maia": "a young Basque surfer girl with wet brown hair in a ponytail, deep turquoise wetsuit with a navy panel, a small "
            "yellow surfboard carried upright behind her back with two shoulder straps, only its edge visible behind her "
            "shoulder, nothing in front of her body, barefoot, hands empty, confident cheerful smile",
    "patxi": "a bearded Basque fisherman, blue beanie, yellow raincoat, navy trousers, black boots, a fishing rod strapped "
             "on his back, hands empty, friendly smile",
    "xabi": "a Basque pelota player boy with light peach skin, rosy cheeks and short dark brown hair, white shirt and white "
            "trousers, red sash belt, arms relaxed along his body, a long curved wicker chistera worn like a glove on his "
            "right hand, the narrow curved basket hanging down along his leg and curving up at the tip, cheerful smile",
    "mattin": "a strong Basque stone lifter man, black mustache, red beret, red and white horizontally striped shirt, "
              "navy trousers, big muscular arms, friendly smile",
    "amaia": "a Basque folk dancer girl, red headscarf, green vest over a white blouse, red skirt, white espadrilles, a "
             "wooden makila walking stick slung on her back, hands empty, cheerful smile",
    "kaio": "a cheeky anthropomorphic seagull standing upright on two orange webbed feet, big yellow beak with a red dot, "
            "white head and belly, light grey wings used as arms with feathered fingertips, small grey tail, mischievous grin",
    "karramarro": "a cheerful orange cartoon crab seen strictly from the side, in profile facing right, standing on its thin "
                  "legs, two big orange pincers raised, eyes on stalks, yellow belly, big happy open mouth",
    "ramuntxo": "a jolly Basque chef with light peach skin and rosy cheeks, tall white chef hat, white chef jacket, red neck scarf, checkered trousers, a frying "
                "pan hanging from his belt, hands empty, big smile",
    "itsaso": "a girl made of sea water, pale cyan skin, long wavy aqua hair, a dress of deep blue waves edged with white "
              "sea foam, barefoot, gentle smile",
    "peio": "a sturdy young Basque rugby player with dark brown skin and short black hair, red and white hooped rugby "
            "jersey, black shorts, white socks, black boots, hands empty, no logo, big cheerful smile",
}


def main():
    ids = sys.argv[1:] or list(PROMPTS)
    tasks = {}
    for cid in ids:
        out = os.path.join(ROOT, "tools", "rd", "out", cid, "gk2d", "profil")
        os.makedirs(out, exist_ok=True)
        payload = {"prompt_style": "pf_2d__character", "prompt": PROMPTS[cid] + FIN, "num_images": 3, "seed": 1,
                   "tag": f"miarritze/gk2d_{cid}", "priority": "normal"}
        tid = pf._post_json(pf.PF + "/v2/inferences", payload, timeout=300)["task_id"]
        json.dump({"style": "pf_2d__character", "prompt": payload["prompt"], "seed": 1, "num_images": 3,
                   "entree": "aucune (description seule)", "task": tid}, open(os.path.join(out, "params.json"), "w"),
                  ensure_ascii=False, indent=1)
        tasks[cid] = tid
        print("déposé", cid, tid, flush=True)
    left = dict(tasks)
    while left:
        for cid, tid in list(left.items()):
            r = json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
            if r["status"] not in ("succeeded", "failed", "canceled", "expired"):
                continue
            del left[cid]
            print(cid, r["status"], str(r.get("error", ""))[:200], flush=True)
            out = os.path.join(ROOT, "tools", "rd", "out", cid, "gk2d", "profil")
            for f in r.get("result", {}).get("pixelforge", {}).get("files", []):
                open(os.path.join(out, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())
        time.sleep(15)
    # Planche de tous les persos : une ligne par perso, 3 variantes.
    H = 260
    rows = []
    for cid in ids:
        out = os.path.join(ROOT, "tools", "rd", "out", cid, "gk2d", "profil")
        ims = [Image.open(os.path.join(out, f"image_0{i}_white.png")).convert("RGB") for i in range(3)
               if os.path.exists(os.path.join(out, f"image_0{i}_white.png"))]
        rows.append((cid, [im.resize((im.width * H // im.height, H)) for im in ims]))
    W = 120 + max(sum(i.width + 10 for i in r[1]) for r in rows)
    sheet = Image.new("RGB", (W, H * len(rows)), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    for k, (cid, ims) in enumerate(rows):
        d.text((8, k * H + H // 2), cid, fill=(0, 0, 0))
        x = 120
        for j, im in enumerate(ims):
            sheet.paste(im, (x, k * H))
            d.text((x + 4, k * H + 4), str(j + 1), fill=(0, 0, 0))
            x += im.width + 10
    sheet.save(os.path.join(ROOT, "tools", "rd", "out", "gk2d_profils.png"))
    print("FINI", flush=True)


if __name__ == "__main__":
    main()
