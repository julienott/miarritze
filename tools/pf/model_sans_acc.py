#!/usr/bin/env python3
"""Modèle du guidé SANS l'accessoire (pierre de Mattin, chistera de Xabi…).

Le guidé redessine le modèle sur chaque contrôle : si le modèle tient
l'accessoire, il en redessine un à sa place d'origine en plus de celui que
le serveur recolle (keep_masks) sur le geste du rig → deux pierres, chistera
fantôme. Kontext (pf__edit) retire l'accessoire du modèle ; from_rig.py prend
tools/rd/out/<id>/modele_sans_acc.png s'il existe.
Usage : model_sans_acc.py <id> "<objet en anglais>" [graines…]
        model_sans_acc.py <id> --choisir <graine>
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import extras_pf as ex  # noqa: E402
import from_rig  # noqa: E402


def clean(im):
    """Fond du rendu Kontext retiré (couleur du coin), alpha binaire, pieds en FOOT."""
    a = np.array(im.convert("RGBA"))
    bg = a[2, 2, :3].astype(int)
    far = np.abs(a[..., :3].astype(int) - bg).sum(-1) > 40
    a[..., 3] = np.where(far, 255, 0)
    sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
    from despeck_sheet import comps
    m = a[..., 3] > 0
    cs = sorted(comps(m), key=len)
    for pts in cs[:-1]:
        if len(pts) < 30:
            ys, xs = zip(*pts)
            a[list(ys), list(xs), 3] = 0
    out = Image.fromarray(a)
    bb = out.getbbox()
    out = out.crop(bb)
    cell = Image.new("RGBA", (from_rig.CELL, from_rig.CELL))
    cell.paste(out, (from_rig.FOOT[0] - out.width // 2, from_rig.FOOT[1] - out.height), out)
    return cell


def main():
    fid = sys.argv[1]
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    if sys.argv[2] == "--choisir":
        shutil.copy(os.path.join(od, f"sans_acc_{sys.argv[3]}.png"), os.path.join(od, "modele_sans_acc.png"))
        print(os.path.join(od, "modele_sans_acc.png"))
        return
    obj = sys.argv[2]
    seeds = [int(s) for s in sys.argv[3:]] or [601, 602, 603]
    ref = from_rig.model(fid)
    bg = Image.new("RGBA", ref.size, (255, 255, 255, 255))
    bg.alpha_composite(ref)
    src = bg.convert("RGB").resize((320, 320), Image.NEAREST)
    items = [("modele", ref)]
    for s in seeds:
        im = ex.infer({"prompt_style": "pf__edit", "input_image": ex.b64(src), "width": 320, "height": 320,
                       "seed": s, "quality": "high",
                       "prompt": f"remove the {obj} completely, empty hands, arms relaxed at the sides, "
                                 f"keep the exact same character, face, clothes, colors, pose and pixel art style, "
                                 f"plain white background"})[0]
        im = clean(im.resize((160, 160), Image.NEAREST))
        im.save(os.path.join(od, f"sans_acc_{s}.png"))
        items.append((str(s), im))
    print(ex.sheet(f"{fid}_sans_acc", "candidats", items, 3))


if __name__ == "__main__":
    main()
