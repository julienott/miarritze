#!/usr/bin/env python3
"""Fin illustrée d'un combattant (SPEC §11.5) : UNE image 320×180 rd_plus,
img2img depuis une composition (décor maison + pose RD du perso, txapela
rouge sur la tête), ton « carte postale d'été », aucun texte.
Les 3 temps de la fin sont 3 cadrages de cette image (fait en jeu).
Usage : gen_ending.py <id> [<id>…] [--strength 0.55]"""
import json, os, sys
import numpy as np
from PIL import Image
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import client  # noqa: E402

PROMPTS = yaml.safe_load(open(os.path.join(HERE, "prompts", "fighters.yaml")))
STAGE_FOR = {"grande_plage": "grande_plage", "cote_basques": "cote_basques", "port_pecheurs": "port_pecheurs",
             "cote_basques_crepuscule": "cote_basques", "grande_plage_soir": "grande_plage"}
FALLBACK_BG = {"fronton": "bg_espadrille_0", "stade": "bg_beach_0", "halles": "bg_fishing_0",
               "rocher_vierge": "bg_rock_0", "port_vieux": "bg_espadrille_0", "aquarium": "bg_surf_0",
               "phare_sommet": "bg_lighthouse_intro"}


def compose(fid):
    data = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "data.json")))
    stage = data.get("home_stage", "grande_plage")
    st = STAGE_FOR.get(stage)
    if st and os.path.exists(os.path.join(ROOT, "assets", "stages", st, "far_0.png")):
        bg = Image.open(os.path.join(ROOT, "assets", "stages", st, "far_0.png")).convert("RGB").crop((96, 18, 416, 198))
    else:
        bg = Image.open(os.path.join(ROOT, "assets", "sprites", FALLBACK_BG.get(stage, "bg_beach_0") + ".png")).convert("RGB").resize((320, 180))
    finals = json.load(open(os.path.join(HERE, "out", "finals.json")))
    pose = Image.open(os.path.join(ROOT, finals[fid])).convert("RGBA") if fid in finals else None
    if pose is not None:
        bbox = pose.getbbox()
        pose = pose.crop(bbox)
        scale = min(150 / pose.height, 1.4)
        pose = pose.resize((max(1, int(pose.width * scale)), max(1, int(pose.height * scale))), Image.NEAREST)
        bg.paste(pose, (160 - pose.width // 2, 178 - pose.height), pose)
    return bg


def generate(fid, strength=0.55):
    img = compose(fid)
    desc = PROMPTS["fighters"][fid]
    prompt = (f"summer postcard illustration, {desc}, proudly wearing a red basque beret trophy, "
              "cheering crowd far away, sunny Biarritz coast, joyful kid friendly cartoon, "
              "no text, no letters")
    payload = {"prompt": prompt, "prompt_style": "rd_plus__default", "width": 320, "height": 180,
               "num_images": 1, "seed": 21, "input_image": client.b64_png(img), "strength": strength}
    paths = client.generate(payload, f"{fid}/ending")
    out = os.path.join(ROOT, "assets", "fighters", fid, "ending.png")
    Image.open(paths[0]).convert("RGB").save(out)
    comp = os.path.join(HERE, "out", fid, "ending_input.png")
    os.makedirs(os.path.dirname(comp), exist_ok=True)
    img.save(comp)
    return out


if __name__ == "__main__":
    st = float(sys.argv[sys.argv.index("--strength") + 1]) if "--strength" in sys.argv else 0.55
    for fid in [a for a in sys.argv[1:] if not a.startswith("--") and a != str(st)]:
        print(generate(fid, st))
