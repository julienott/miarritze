#!/usr/bin/env python3
"""Couleurs (hex, nombre de pixels) d'une pose RD, globalement ou dans un
rectangle : aide à écrire les règles « groups » de rig.json.
Usage : rd_colors.py <id> [x0,y0,x1,y1]"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
fid = sys.argv[1]
p = os.path.join(ROOT, "assets", "fighters", fid, "rd_pose.png")
if not os.path.exists(p):
    p = os.path.join(ROOT, json.load(open(os.path.join(ROOT, "tools", "rd", "out", "finals.json")))[fid])
a = np.array(Image.open(p).convert("RGBA"))
if len(sys.argv) > 2:
    x0, y0, x1, y1 = map(int, sys.argv[2].split(","))
    a = a[y0:y1, x0:x1]
m = a[..., 3] > 127
cols, counts = np.unique(a[m][:, :3], axis=0, return_counts=True)
for c, n in sorted(zip(cols.tolist(), counts.tolist()), key=lambda t: -t[1])[:24]:
    print("%02x%02x%02x %4d" % (*c, n))
