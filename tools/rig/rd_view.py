#!/usr/bin/env python3
"""Vue de travail d'une pose RD : agrandie ×S avec grille (4 px fine, 16 px
forte, coordonnées), et superposition optionnelle du rig (pivots, masques).
Usage : rd_view.py <id> [--rig] [--scale 6] [--crop x0,y0,x1,y1]
Écrit tests/out/rig/<id>_view.png"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
COLORS = [(255, 60, 60), (60, 200, 60), (60, 120, 255), (255, 200, 0), (255, 0, 255),
          (0, 220, 220), (255, 128, 0), (160, 80, 255), (128, 255, 128), (255, 128, 192),
          (0, 160, 255), (200, 200, 200), (120, 60, 0), (255, 255, 255)]


def main():
    fid = sys.argv[1]
    S = int(sys.argv[sys.argv.index("--scale") + 1]) if "--scale" in sys.argv else 6
    finals = json.load(open(os.path.join(ROOT, "tools", "rd", "out", "finals.json")))
    prepped = os.path.join(ROOT, "assets", "fighters", fid, "rd_pose.png")
    img = Image.open(prepped if os.path.exists(prepped) else os.path.join(ROOT, finals[fid])).convert("RGBA")
    crop = (0, 0, img.width, img.height)
    if "--crop" in sys.argv:
        crop = tuple(int(v) for v in sys.argv[sys.argv.index("--crop") + 1].split(","))
    img = img.crop(crop)
    bg = Image.new("RGBA", img.size, (120, 126, 150, 255))
    bg.alpha_composite(img)
    big = bg.resize((img.width * S, img.height * S), Image.NEAREST)
    d = ImageDraw.Draw(big, "RGBA")
    font = ImageFont.load_default()
    for x in range(0, img.width + 1, 4):
        X = x * S
        strong = (x + crop[0]) % 16 == 0
        d.line([(X, 0), (X, big.height)], fill=(0, 0, 0, 110 if strong else 40), width=2 if strong else 1)
        if strong:
            d.text((X + 2, 2), str(x + crop[0]), fill=(255, 255, 255, 255), font=font)
    for y in range(0, img.height + 1, 4):
        Y = y * S
        strong = (y + crop[1]) % 16 == 0
        d.line([(0, Y), (big.width, Y)], fill=(0, 0, 0, 110 if strong else 40), width=2 if strong else 1)
        if strong:
            d.text((2, Y + 2), str(y + crop[1]), fill=(255, 255, 255, 255), font=font)
    if "--rig" in sys.argv:
        rig = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "rig.json")))
        for i, (name, b) in enumerate(rig["bones"].items()):
            col = COLORS[i % len(COLORS)]
            pts = [((x - crop[0]) * S, (y - crop[1]) * S) for x, y in b["mask"]]
            if len(pts) > 2:
                d.polygon(pts, outline=col + (255,), fill=col + (40,))
            px, py = b["pivot"]
            P = ((px - crop[0]) * S, (py - crop[1]) * S)
            d.ellipse([P[0] - 5, P[1] - 5, P[0] + 5, P[1] + 5], fill=col + (255,), outline=(0, 0, 0, 255))
            d.text((P[0] + 7, P[1] - 6), name, fill=col + (255,), font=font)
            if "tip" in b:
                tx, ty = b["tip"]
                T = ((tx - crop[0]) * S, (ty - crop[1]) * S)
                d.line([P, T], fill=col + (255,), width=2)
    out = os.path.join(ROOT, "tests", "out", "rig")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, f"{fid}_view{'_rig' if '--rig' in sys.argv else ''}.png")
    big.save(path)
    print(path, big.size)


if __name__ == "__main__":
    main()
