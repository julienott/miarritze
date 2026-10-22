"""Planche contact : une ligne par objet (tag), les captures de ce tag côte à côte, légendées.
planche.py <dossier> <sortie.png> [motif d'ordre des suffixes séparés par des virgules] [--tags=a,b] [--h=220]
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
order = sys.argv[3].split(",") if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else None
tags_only = None
H = 220
for a in sys.argv[3:]:
    if a.startswith("--tags="):
        tags_only = a[7:].split(",")
    if a.startswith("--h="):
        H = int(a[4:])
files = sorted(glob.glob(os.path.join(src, "*__*.png")))
rows = {}
for f in files:
    tag, suf = os.path.basename(f)[:-4].split("__", 1)
    if tags_only and not any(tag.startswith(t) for t in tags_only):
        continue
    rows.setdefault(tag, {})[suf] = f
lines = []
for tag, d in rows.items():
    sufs = [s for s in order if s in d] if order else sorted(d)
    ims = []
    for s in sufs:
        im = Image.open(d[s]).convert("RGB")
        k = H / im.height
        im = im.resize((max(1, int(im.width * k)), H), Image.LANCZOS)
        lab = Image.new("RGB", (im.width, H + 16), (20, 20, 20))
        lab.paste(im, (0, 16))
        ImageDraw.Draw(lab).text((3, 2), s, fill=(255, 230, 120))
        ims.append(lab)
    w = sum(i.width for i in ims) + 6 * len(ims) + 230
    line = Image.new("RGB", (w, H + 16), (40, 40, 40))
    ImageDraw.Draw(line).text((4, 4), tag, fill=(255, 255, 255))
    x = 230
    for i in ims:
        line.paste(i, (x, 0))
        x += i.width + 6
    lines.append(line)
W = max(l.width for l in lines)
out = Image.new("RGB", (W, sum(l.height + 6 for l in lines)), (40, 40, 40))
y = 0
for l in lines:
    out.paste(l, (0, y))
    y += l.height + 6
out.save(dst)
print(dst, out.size)
