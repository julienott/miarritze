#!/usr/bin/env python3
"""Modèle accroupi d'un perso refait, par pf__pose (pixelforge) : le modèle propre
redessiné dans la pose du mannequin accroupi (crouch_idle, image 0). Proportions
gardées (Kontext au prompt ne fait que des fentes, et grossit les poings).
→ tools/rd/out/<id>/accroupi_pose_<g>.png, planche tests/out/pf/<id>_accroupi_pose.png
  pose_accroupi.py <id> [graines…]   /   pose_accroupi.py <id> --choisir <graine>
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extras_pf as ex  # noqa: E402
import from_mannequin as fm  # noqa: E402


def main():
    fid = sys.argv[1]
    od = fm.out_dir(fid)
    if "--choisir" in sys.argv:
        s = sys.argv[sys.argv.index("--choisir") + 1]
        im = Image.open(os.path.join(od, f"accroupi_pose_{s}.png")).convert("RGBA")
        im.crop(im.getbbox()).save(os.path.join(od, "modele_accroupi.png"))
        print(os.path.join(od, "modele_accroupi.png"))
        return
    seeds = [int(x) for x in sys.argv[2:]] or [1, 2, 3]
    job = fm.Perso(fid)
    _, _, controls = job.prepare("crouch_idle")
    items = [("modele", job.ref), ("pose", controls[0])]
    for s in seeds:
        im = ex.infer({"prompt_style": "pf__pose", "input_image": ex.b64(job.ref),
                       "control_image": ex.b64(controls[0]), "priority": "high", "width": fm.CELL, "height": fm.CELL, "seed": s,
                       "prompt": f"{job.look}, crouching, same character, same proportions, small fists, side view facing right"})[0]
        im.save(os.path.join(od, f"accroupi_pose_{s}.png"))
        items.append((str(s), im))
    print(ex.sheet(fid, "accroupi_pose", items, 2))


if __name__ == "__main__":
    main()
