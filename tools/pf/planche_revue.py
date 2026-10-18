#!/usr/bin/env python3
"""Planche de relecture d'un perso refait (cases de n'importe quelle taille, lue
sur la hauteur des bandes) : une ligne par animation, verdict en titre, fond
clair, ligne de sol (pieds) en pointillés. → tests/out/pf/<id>_revue_<k>.png
(découpée en pages de ~12 animations).
Usage : planche_revue.py <id> [anim …]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BG = (214, 236, 246, 255)
PER_PAGE = 12


def main():
    fid = sys.argv[1]
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    done = json.load(open(os.path.join(od, "anims.json")))
    vp = os.path.join(od, "pf", "verdicts.json")
    verdicts = json.load(open(vp)) if os.path.exists(vp) else {}
    names = sys.argv[2:] or list(done)
    pages = [names[i:i + PER_PAGE] for i in range(0, len(names), PER_PAGE)]
    outs = []
    for k, page in enumerate(pages):
        strips = [Image.open(done[n]).convert("RGBA") for n in page]
        C = strips[0].height
        W = max(s.width for s in strips)
        H = sum(C + 14 for _ in strips)
        sheet = Image.new("RGBA", (W, H), (24, 20, 28, 255))
        d = ImageDraw.Draw(sheet)
        y = 0
        for n, s in zip(page, strips):
            d.text((4, y + 1), f"{n}  {verdicts.get(n, '')[:110]}", fill=(255, 210, 90, 255))
            y += 14
            bg = Image.new("RGBA", s.size, BG)
            bg.alpha_composite(s)
            sheet.paste(bg, (0, y))
            for x in range(0, s.width, C):
                d.line([(x, y), (x, y + C - 1)], fill=(24, 20, 28, 255))
            y += C
        p = os.path.join(ROOT, "tests", "out", "pf", f"{fid}_revue_{k}.png")
        sheet.save(p)
        outs.append(p)
    print("\n".join(outs))


if __name__ == "__main__":
    main()
