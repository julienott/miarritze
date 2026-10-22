#!/usr/bin/env python3
"""Images de contrôle des formes du décor telles que le jeu les utilise (empreinte, masquage, tri).

  masques_decor.py [--dest DIR]

Lance le jeu sans fenêtre (`--bk-export-masques=<dest>`) : c'est exactement l'algorithme du jeu
(src/blackout/bk_decor.gd) qui choisit et prépare les formes au chargement de la carte : masques de
pixelforge (assets/blackout/decor/masques/<id>/, masques_pf.py) quand ils existent, sinon le calcul
local sur la silhouette (repli). Une image par objet en image (sa première pose sur la carte),
2 px par px de jeu, avec en bandeau la source de la forme :
- l'image de l'objet sur un damier ;
- en vert, l'empreinte qui bloque (polygones de collision du jeu, coupés aux cases) ;
- en violet, ce qui passe devant un perso situé derrière et le masque ;
- en rouge, la ligne de tri (pieds au-dessus : perso derrière l'objet) ;
- en pointillé blanc, les cases de l'objet sur la carte.
Défaut : tools/blackout/masques/jeu/ (versionné, affiché par tools/producer/build_index.py à côté des
aperçus de pixelforge, tools/blackout/masques/<id>.png, écrits par masques_pf.py).
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DEST = os.path.join(HERE, "masques", "jeu")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=DEST)
    o = ap.parse_args()
    dest = os.path.abspath(o.dest)
    if os.path.isdir(dest):
        for f in glob.glob(os.path.join(dest, "*.png")):
            os.remove(f)
    godot = shutil.which("godot") or sys.exit("godot introuvable dans le PATH")
    r = subprocess.run([godot, "--headless", "--path", ROOT, "--", "--scene=bk_game",
                        f"--bk-export-masques={dest}"], capture_output=True, text=True, timeout=600)
    for line in (r.stdout + r.stderr).splitlines():
        if "masques du décor" in line or "ERROR" in line:
            print(line)
    n = len(glob.glob(os.path.join(dest, "*.png")))
    if n == 0:
        sys.exit("aucune image produite")
    bandeaux(dest)
    print(f"{n} images dans {dest}")


def bandeaux(dest):
    """Bandeau en haut de chaque image : source de la forme (pixelforge et sa confiance, ou repli)."""
    from PIL import Image, ImageDraw
    sources = json.load(open(os.path.join(dest, "_sources.json")))
    for eid, s in sources.items():
        p = os.path.join(dest, eid + ".png")
        img = Image.open(p).convert("RGB")
        if s["source"] == "pixelforge":
            texte = f"{eid} : masques pixelforge (confiance {s.get('confidence', '?')})"
            fond = (30, 110, 60)
        elif s.get("refus_pixelforge"):
            texte = f"{eid} : repli, masques pixelforge écartés ({s['refus_pixelforge']})"
            fond = (170, 50, 40)
        else:
            texte = f"{eid} : repli, calcul local sur la silhouette (pas de masques pixelforge)"
            fond = (150, 90, 20)
        texte += " · bloque la vue" if s.get("bloque_vue") else " · passage seul"
        out = Image.new("RGB", (max(img.width, 8 * len(texte) // 1 + 8), img.height + 18), fond)
        out.paste(img, (0, 18))
        ImageDraw.Draw(out).text((4, 3), texte, fill=(255, 255, 255))
        out.save(p, optimize=True)


if __name__ == "__main__":
    main()
