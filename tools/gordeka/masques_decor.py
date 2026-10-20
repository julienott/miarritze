#!/usr/bin/env python3
"""Images de contrôle des formes du décor (empreinte au sol, zone qui masque un perso).

  masques_decor.py [--dest DIR]

Lance le jeu sans fenêtre (`--gk-export-masques=<dest>`) : c'est exactement l'algorithme du jeu
(src/gordeka/gk_decor.gd, `_shape`) qui calcule les formes, au chargement de la carte, avec les
réglages de data/gordeka/rules.json. Une image par objet en image (sa première pose sur la carte),
2 px par px de jeu :
- l'image de l'objet sur un damier ;
- en vert, l'empreinte au sol (on bute dessus, la vue du chasseur s'y arrête), coupée aux cases ;
- en violet, le reste de la silhouette : passe devant un perso qui est derrière et le masque ;
- en pointillé blanc, les cases de l'objet sur la carte.
Défaut : tools/gordeka/masques/ (versionné, affiché par tools/producer/build_index.py).
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DEST = os.path.join(HERE, "masques")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=DEST)
    o = ap.parse_args()
    dest = os.path.abspath(o.dest)
    if os.path.isdir(dest):
        for f in glob.glob(os.path.join(dest, "*.png")):
            os.remove(f)
    godot = shutil.which("godot") or sys.exit("godot introuvable dans le PATH")
    r = subprocess.run([godot, "--headless", "--path", ROOT, "--", "--scene=gk_game",
                        f"--gk-export-masques={dest}"], capture_output=True, text=True, timeout=600)
    for line in (r.stdout + r.stderr).splitlines():
        if "masques du décor" in line or "ERROR" in line:
            print(line)
    n = len(glob.glob(os.path.join(dest, "*.png")))
    if n == 0:
        sys.exit("aucune image produite")
    print(f"{n} images dans {dest}")


if __name__ == "__main__":
    main()
