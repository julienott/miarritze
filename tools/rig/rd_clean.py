"""Nettoyage ponctuel d'une pose RD avant découpe (écrit assets/fighters/<id>/rd_pose.png).

Opérations décrites en JSON dans rig.json["clean"] :
  {"fill": [x0, y0, x1, y1, "rrggbb"]}           rectangle plein (inclusif)
  {"erase": [x0, y0, x1, y1]}                     rectangle effacé (inclusif)
  {"interior": {"color": "rrggbb", "to": "rrggbb", "y0": Y}}
                                                  pixels de cette couleur entourés d'opaque, sous Y
                                                  (dans chaque case de --cell) : pantalon de la
                                                  couleur du contour, sinon troué au re-contourage
  {"ground": {"y": Y, "bands": [[x0, x1], ...]}}  efface tout sous Y sauf entre
                                                  les contours (3a2634) des pieds
Usage : rd_clean.py <id> [source.png]
        rd_clean.py <id> --idle planche.png --cell N   (ops "interior" seulement → rd_idle.png)
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTLINE = (58, 38, 52)


def rgb(h):
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def clean(img, ops, cell=None, only=None):
    img = img.copy()
    cell = cell or img.shape[0]
    for op in ops:
        if only and not any(k in op for k in only):
            continue
        if "interior" in op:
            g = op["interior"]
            c, to = rgb(g["color"]), rgb(g["to"])
            a = img[..., 3] > 127
            inner = a.copy()
            inner[1:] &= a[:-1]; inner[:-1] &= a[1:]; inner[:, 1:] &= a[:, :-1]; inner[:, :-1] &= a[:, 1:]
            inner[0] = inner[-1] = False
            m = inner & (img[..., 0] == c[0]) & (img[..., 1] == c[1]) & (img[..., 2] == c[2])
            ys = np.arange(img.shape[0])[:, None] % cell
            m &= np.broadcast_to(ys >= g["y0"], m.shape)
            img[m, :3] = to
        if "fill" in op:
            x0, y0, x1, y1, h = op["fill"]
            img[y0:y1 + 1, x0:x1 + 1, :3] = rgb(h)
            img[y0:y1 + 1, x0:x1 + 1, 3] = 255
        if "erase" in op:
            x0, y0, x1, y1 = op["erase"]
            img[y0:y1 + 1, x0:x1 + 1, 3] = 0
        if "ground" in op:
            g = op["ground"]
            dark = (img[..., 0] == OUTLINE[0]) & (img[..., 1] == OUTLINE[1]) & (img[..., 2] == OUTLINE[2])
            for y in range(g["y"], img.shape[0]):
                keep = np.zeros(img.shape[1], bool)
                for x0, x1 in g["bands"]:
                    xs = np.nonzero(dark[y, x0:x1 + 1])[0]
                    if len(xs):
                        keep[x0 + xs.min():x0 + xs.max() + 1] = True
                img[y, ~keep, 3] = 0
    return img


def main():
    fid = sys.argv[1]
    d = os.path.join(ROOT, "assets", "fighters", fid)
    spec = json.load(open(os.path.join(d, "rig.json")))
    if "--idle" in sys.argv:
        src = sys.argv[sys.argv.index("--idle") + 1]
        cell = int(sys.argv[sys.argv.index("--cell") + 1])
        img = np.array(Image.open(os.path.join(ROOT, src)).convert("RGBA"))
        Image.fromarray(clean(img, spec["clean"], cell, only=("interior",))).save(os.path.join(d, "rd_idle.png"))
        print(os.path.join(d, "rd_idle.png"))
        return
    src = sys.argv[2] if len(sys.argv) > 2 else spec["rd_source"]
    img = np.array(Image.open(os.path.join(ROOT, src)).convert("RGBA"))
    Image.fromarray(clean(img, spec["clean"])).save(os.path.join(d, "rd_pose.png"))
    print(os.path.join(d, "rd_pose.png"))


if __name__ == "__main__":
    main()
