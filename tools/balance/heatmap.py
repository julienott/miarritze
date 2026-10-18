#!/usr/bin/env python3
"""Heatmap de tests/out/balance.csv → tests/out/balance.png (SPEC §14.4).
Case (ligne i, colonne j) = victoires de i contre j ; vert = favorable."""
import csv, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
rows = list(csv.reader(open(os.path.join(ROOT, "tests", "out", "balance.csv"))))
ids = rows[0][1:-1]
n = len(ids)
C = 34
img = Image.new("RGB", (110 + C * n + 60, 30 + C * n), (36, 32, 44))
d = ImageDraw.Draw(img)
font = ImageFont.load_default()
for j, fid in enumerate(ids):
    d.text((110 + j * C + 2, 8), fid[:5], fill=(240, 236, 226), font=font)
for i, row in enumerate(rows[1:]):
    d.text((6, 30 + i * C + 12), row[0], fill=(240, 236, 226), font=font)
    for j in range(n):
        if i == j:
            continue
        w, l = int(row[j + 1] or 0), int(rows[j + 1][i + 1] or 0)
        r = w / max(w + l, 1)
        col = (int(220 * (1 - r)), int(200 * r), 70)
        d.rectangle([110 + j * C, 30 + i * C, 110 + j * C + C - 2, 30 + i * C + C - 2], fill=col)
        d.text((110 + j * C + 8, 30 + i * C + 12), f"{int(r * 100)}", fill=(255, 255, 255), font=font)
    d.text((110 + n * C + 6, 30 + i * C + 12), row[-1] + "%", fill=(244, 198, 62), font=font)
img.save(os.path.join(ROOT, "tests", "out", "balance.png"))
print("ok")
