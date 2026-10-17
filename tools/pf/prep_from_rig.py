#!/usr/bin/env python3
"""Prépare un perso « rig découpé » pour from_rig.py (à lancer AVANT la reconstruction).

1. Fiche minimale tools/specs/fighters/<id>.yaml si absente : apparence (data.json),
   groupes de couleur déduits des groupes du rig (teinte/saturation/valeur des
   couleurs du groupe, élargies), costumes repris du rig — la reconstruction
   (build_rd_anims.py) ne garde les costumes que par la fiche.
2. Source du portrait : le portrait actuel colorisé avec la palette ACTUELLE
   (avant qu'elle soit réécrite) → tools/rd/out/<id>/portrait_src.png, déclarée
   dans make_rd_portraits.FACES (clé « src »).
Usage : prep_from_rig.py <id> [<id> …]
"""
import colorsys
import json
import os
import re
import sys

import numpy as np
import yaml
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def hsv(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)


def fiche(fid):
    path = os.path.join(ROOT, "tools", "specs", "fighters", f"{fid}.yaml")
    if os.path.exists(path):
        return f"fiche existante : {path}"
    rig = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "rig.json")))
    data = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "data.json")))
    groups = {}
    for g in rig.get("groups", []):
        hs = [hsv(c) for c in g["colors"]]
        h = [x[0] * 360 for x in hs]
        s = [x[1] for x in hs]
        v = [x[2] for x in hs]
        rule = {"sat": [round(max(0, min(s) - 0.08), 2), round(min(1, max(s) + 0.08), 2)],
                "val": [round(max(0, min(v) - 0.08), 2), round(min(1, max(v) + 0.08), 2)],
                "composante_min": 60}
        if max(s) > 0.15:   # couleur franche : la teinte compte (sinon blanc/gris : saturation seule)
            rule["teinte"] = [round((min(h) - 10) % 360), round((max(h) + 10) % 360)]
        groups[g["group"]] = rule
    doc = {"id": fid, "statut": "brouillon",
           "apparence": f"{data.get('name', fid)}, {data.get('title', '')}, the same cartoon character, kid friendly",
           "hauteur": 112, "groupes_couleur": groups,
           "costumes": {int(k): v for k, v in rig.get("costumes", {}).items()}}
    head = (f"# Fiche minimale — {data.get('name', fid)} (écrite par tools/pf/prep_from_rig.py pour\n"
            f"# from_rig.py : modèle = pose RD propre, gestes = ceux du rig). Groupes de couleur\n"
            f"# déduits du rig : à relire (apparence en anglais pour pixelforge).\n")
    with open(path, "w") as fh:
        fh.write(head + yaml.safe_dump(doc, allow_unicode=True, sort_keys=False))
    return f"fiche écrite : {path}"


def portrait(fid):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    idx = np.array(Image.open(os.path.join(d, "portrait.png")))
    rgba = pal[idx].astype(np.uint8)
    rgba[idx == 0] = (214, 236, 246, 255)       # fond plat, retiré par le détourage
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    os.makedirs(od, exist_ok=True)
    src = f"tools/rd/out/{fid}/portrait_src.png"
    Image.fromarray(rgba).save(os.path.join(ROOT, src))
    p = os.path.join(ROOT, "tools", "sprites", "make_rd_portraits.py")
    s = open(p).read()
    m = re.search(rf'^    "{fid}": \{{(.*)$', s, re.M)
    if m and '"src"' not in m.group(0):
        s = s.replace(m.group(0), m.group(0).replace(f'"{fid}": {{', f'"{fid}": {{"src": "{src}", ', 1))
        open(p, "w").write(s)
    elif m:
        s = re.sub(rf'("{fid}": \{{"src": )"[^"]*"', rf'\1"{src}"', s)
        open(p, "w").write(s)
    return f"portrait source : {src}"


if __name__ == "__main__":
    for fid in sys.argv[1:]:
        print(fid, "|", fiche(fid), "|", portrait(fid))
