#!/usr/bin/env python3
"""Décor depuis une photo de Julien, avec pixelforge (Kontext, gratuit).

La photo (tools/rd/out/photos/ref_*/<id>.jpg) est recadrée en 16:9 sur la
zone utile (boîte ci-dessous), convertie en pixel art 384×216 par pf__edit en
gardant la composition, puis élargie en 512×216 par widen_mirror (bords en
miroir). Le bas (y ≥ 176) est caché par le sol du stage : rien d'important.
Candidats : tools/rd/out/photos/<id>_<graine>.png, planche tests/out/pf/decor_<id>.png.
  photo_stage.py gen <id> [--graines 3] [--depuis 301]
  photo_stage.py install <id> <graine>     → assets/stages/<id>/src.png puis far_0..2
  photo_stage.py gen-large <id> / install-large <id> <graine>   (sans miroir, cf. WIDE)
  photo_stage.py outpaint <id> <graine> / install-outpaint <id> <graine> <k>   (version 384 prolongée)
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import extras_pf as ex  # noqa: E402

REF = os.path.join(ROOT, "tools", "rd", "out", "photos", "ref_2026_10_17")
STYLE = ("convert this photo into a detailed 16-bit pixel art fighting game background, keep the exact "
         "composition, sunny warm colors, crisp pixels, no text")
# id : (fichier, boîte de recadrage (x0, y0, x1, y1) en 16:9, consigne en plus)
SOURCES = {
    "cote_basques": ("cote_basques.jpg", (0, 30, 588, 361),
                     "the Biarritz Cote des Basques beach, villa on the cliff, rocks, waves and small people on the sand"),
    "rocher_vierge": ("rocher_vierge.jpg", (24, 0, 563, 303),
                      "clean stylized pixel art with flat color shapes and dark outlines, not a filtered photo: the Rocher de la Vierge in Biarritz, white iron footbridge, rough sea with white foam, dramatic grey cloudy sky with a bright gap, keep the cloudy daylight mood"),
    "fronton": ("fronton.jpg", (26, 0, 586, 315),
                "a basque pelota fronton wall centered, sunny day, houses with red roofs behind"),
    "stade": ("stade.jpg", (225, 110, 975, 532),
              "a rugby stadium, the red stands are packed with a crowd of many small colorful cheering spectators sitting in every seat, no empty seats, green pitch, sunny sky, no text"),
}


def crop(sid):
    f, box, _ = SOURCES[sid]
    im = Image.open(os.path.join(REF, f)).convert("RGB").crop(box)
    return im.resize((384, 216), Image.LANCZOS)


def gen(sid, seeds):
    src = crop(sid)
    od = os.path.join(ROOT, "tools", "rd", "out", "photos")
    items = [("photo", src.convert("RGBA"))]
    for s in seeds:
        im = ex.infer({"prompt_style": "pf__edit", "input_image": ex.b64(src), "width": 384, "height": 216,
                       "seed": s, "quality": "high", "prompt": f"{STYLE}: {SOURCES[sid][2]}"})[0]
        im.save(os.path.join(od, f"{sid}_{s}.png"))
        items.append((str(s), im))
    return ex.sheet(f"decor_{sid}", "candidats", items, 2)


# Décors larges sans miroir : photo recadrée en 512×216 et convertie d'un bloc
# (pf__edit accepte jusqu'à 640 px de côté).
WIDE = {"stade": (0, 60, 1200, 566)}


def gen_wide(sid, seeds):
    f, _, extra = SOURCES[sid]
    x0, y0, x1, y1 = WIDE[sid]
    ph = Image.open(os.path.join(REF, f)).convert("RGB").crop((x0, y0, x1, y1)).resize((512, 216), Image.LANCZOS)
    od = os.path.join(ROOT, "tools", "rd", "out", "photos")
    items = [("photo", ph.convert("RGBA"))]
    for s in seeds:
        # pf__edit accepte 512×216 depuis le 2026-10-17 : un seul appel, pas de raccord
        out = ex.infer({"prompt_style": "pf__edit", "input_image": ex.b64(ph), "width": 512, "height": 216,
                        "seed": s, "quality": "high", "prompt": f"{STYLE}: {extra}"})[0].convert("RGB")
        out.save(os.path.join(od, f"{sid}_large_{s}.png"))
        items.append((str(s), out.convert("RGBA")))
    return ex.sheet(f"decor_{sid}", "larges", items, 2)


def install_wide(sid, seed):
    d = os.path.join(ROOT, "assets", "stages", sid)
    Image.open(os.path.join(ROOT, "tools", "rd", "out", "photos", f"{sid}_large_{seed}.png")).convert("RGB") \
        .save(os.path.join(d, "far_0.png"))
    return d


def outpaint(sid, seed, n=2):
    """Version choisie (384×216) prolongée de 64 px de chaque côté par Kontext
    (centre gardé au pixel près) → candidats <id>_<graine>_large_<k>.png."""
    od = os.path.join(ROOT, "tools", "rd", "out", "photos")
    src = Image.open(os.path.join(od, f"{sid}_{seed}.png")).convert("RGB").resize((384, 216), Image.NEAREST)
    items = []
    for k in range(n):
        out = ex.infer({"prompt_style": "pf__edit", "input_image": ex.b64(src), "width": 384, "height": 216,
                        "outpaint_left": 64, "outpaint_right": 64, "seed": 400 + k, "quality": "high",
                        "prompt": f"seamlessly extend this pixel art scene to the left and right: {SOURCES[sid][2]}"})[0].convert("RGB")
        out = out.resize((512, 216), Image.NEAREST) if out.size != (512, 216) else out
        out.save(os.path.join(od, f"{sid}_{seed}_large_{k}.png"))
        items.append((str(k), out.convert("RGBA")))
    return ex.sheet(f"decor_{sid}", "prolonge", items, 2)


def install(sid, seed):
    d = os.path.join(ROOT, "assets", "stages", sid)
    os.makedirs(d, exist_ok=True)
    Image.open(os.path.join(ROOT, "tools", "rd", "out", "photos", f"{sid}_{seed}.png")).convert("RGB") \
        .resize((384, 216), Image.NEAREST).save(os.path.join(d, "src.png"))
    sys.path.insert(0, HERE)
    import widen_mirror
    widen_mirror.main(sid)
    return d


if __name__ == "__main__":
    cmd, sid = sys.argv[1], sys.argv[2]
    if cmd == "outpaint":
        print(outpaint(sid, sys.argv[3]))
    elif cmd == "install-outpaint":
        d = os.path.join(ROOT, "assets", "stages", sid)
        Image.open(os.path.join(ROOT, "tools", "rd", "out", "photos", f"{sid}_{sys.argv[3]}_large_{sys.argv[4]}.png")) \
            .convert("RGB").save(os.path.join(d, "far_0.png"))
        print(d)
    elif cmd == "gen-large":
        print(gen_wide(sid, [311, 312, 313]))
    elif cmd == "install-large":
        print(install_wide(sid, sys.argv[3]))
    elif cmd == "gen":
        n = int(sys.argv[sys.argv.index("--graines") + 1]) if "--graines" in sys.argv else 3
        first = int(sys.argv[sys.argv.index("--depuis") + 1]) if "--depuis" in sys.argv else 301
        print(gen(sid, [first + i for i in range(n)]))
    else:
        print(install(sid, sys.argv[3]))
