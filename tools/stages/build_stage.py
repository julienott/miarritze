#!/usr/bin/env python3
"""Assemble un stage (SPEC §10.6) : voile de 15 % vers le ciel sur le plan
lointain (décolle les personnages), sol procédural 576×40 tuilé dans la
palette du stage, stage.json (calques, parallaxe, animations, particules).
Usage : build_stage.py <id> [<id>...]"""
import json, os, random, sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from palette import RAMPS  # noqa: E402

STAGES = {
    "grande_plage": {"floor": "sand", "particles": "sand", "music": "grande_plage",
                     "props": [{"kind": "gull", "y": 40, "speed": 9, "parallax": 0.5}]},
    "cote_basques": {"floor": "wet_sand", "particles": "water", "music": "cote_basques",
                     "props": [{"kind": "gull", "y": 30, "speed": -7, "parallax": 0.45}]},
    "port_pecheurs": {"floor": "quay", "particles": "wood", "music": "port_pecheurs",
                      "props": [{"kind": "gull", "y": 50, "speed": 6, "parallax": 0.5}]},
    "rocher_vierge": {"floor": "planks", "particles": "water", "music": "rocher_vierge",
                      "props": [{"kind": "gull", "y": 36, "speed": 8, "parallax": 0.45}, {"kind": "spray", "y": 120}]},
    "port_vieux": {"floor": "sand", "particles": "sand", "music": "port_vieux",
                   "props": [{"kind": "gull", "y": 44, "speed": -6, "parallax": 0.5}]},
    "halles": {"floor": "tiles", "particles": "flour", "music": "halles", "props": []},
    "fronton": {"floor": "parquet", "particles": "wood", "music": "fronton",
                "props": [{"kind": "gull", "y": 30, "speed": 7, "parallax": 0.4}]},
    "stade": {"floor": "grass", "particles": "sand", "music": "stade", "props": [{"kind": "confetti"}]},
    "aquarium": {"floor": "aqua_tiles", "particles": "water", "music": "aquarium", "props": [{"kind": "bubbles"}]},
    "phare_sommet": {"floor": "balcony", "particles": "wood", "music": "phare_sommet",
                     "props": [{"kind": "beam", "x": 96, "y": 58, "dot": False}]},
}
# Variantes recolorées (soir / crépuscule) : même décor, LUT chaude ou bleutée.
VARIANTS = {"grande_plage_soir": ("grande_plage", "sunset"), "cote_basques_crepuscule": ("cote_basques", "dusk")}
VEIL = 0.15


def veil(img):
    sky = img.getpixel((img.width // 2, 2))
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y][:3]
            px[x, y] = (round(r + (sky[0] - r) * VEIL), round(g + (sky[1] - g) * VEIL),
                        round(b + (sky[2] - b) * VEIL))
    return img


def floor(kind, seed=7):
    rnd = random.Random(seed)
    w, h = 576, 40
    img = Image.new("RGB", (w, h))
    px = img.load()
    if kind in ("sand", "wet_sand"):
        ramp = RAMPS["sand"]
        for y in range(h):
            for x in range(w):
                base = ramp[0] if y < 3 else ramp[1 if (x * 3 + y * 5) % 23 else 2]
                if kind == "wet_sand" and y > 26:
                    base = tuple(int(c * 0.82) for c in base)
                px[x, y] = base
        for _ in range(260):   # grains et coquillages
            x, y = rnd.randrange(w), rnd.randrange(4, h)
            px[x, y] = ramp[2] if rnd.random() < 0.8 else RAMPS["linen"][0]
        for x in range(w):     # liseré du bord
            px[x, 0] = RAMPS["sand"][2]
        if kind == "wet_sand":
            for x in range(w):  # écume au fond
                if (x // 6) % 3 != 0:
                    px[x, 27] = RAMPS["foam"][0]
    elif kind in ("planks", "parquet"):
        ramp = RAMPS["wood"]
        plank = 12 if kind == "planks" else 6
        for y in range(h):
            for x in range(w):
                if kind == "parquet":
                    # Lames horizontales, joints décalés d'une rangée à l'autre.
                    row = y // 7
                    seam = y % 7 == 0 or (x + row * 29) % 58 == 0
                    px[x, y] = ramp[2] if seam else ramp[0 if row % 2 else 1]
                    continue
                seam = x % (plank * 4) == 0
                gap = y % 10 == 0
                px[x, y] = ramp[3] if (seam or gap) else ramp[0 if (x // plank + y // 10) % 3 else 1]
        for x in range(w):
            px[x, 0] = RAMPS["steel"][2] if kind == "planks" else ramp[3]
    elif kind in ("tiles", "aqua_tiles"):
        # Carrelage discret : deux tons proches (les combattants doivent ressortir).
        a, b = (RAMPS["linen"][2], RAMPS["linen"][3]) if kind == "tiles" else (RAMPS["night"][1], RAMPS["sea"][2])
        for y in range(h):
            for x in range(w):
                edge = x % 16 == 0 or (y - 2) % 12 == 0
                px[x, y] = RAMPS["stone"][2] if edge else (a if ((x // 16) + ((y - 2) // 12)) % 2 else b)
    elif kind == "grass":
        ramp = RAMPS["green"]
        for y in range(h):
            for x in range(w):
                px[x, y] = ramp[0] if (x // 48) % 2 else ramp[1]
        for x in range(0, w, 96):
            for y in range(h):
                px[x, y] = RAMPS["linen"][0]
        for _ in range(300):
            px[rnd.randrange(w), rnd.randrange(h)] = ramp[2]
    elif kind == "balcony":
        # Dalles de pierre du balcon du phare, au coucher de soleil : rangées
        # décalées, teintes variées, liseré chaud (lumière du soleil) en haut.
        ramp = RAMPS["stone"]
        warm = RAMPS["sand"]
        for y in range(h):
            for x in range(w):
                row = (y - 3) // 10
                off = 11 if row % 2 else 0
                cell = ((x + off) // 22, row)
                edge = (y - 3) % 10 == 0 or (x + off) % 22 == 0
                shade = ramp[2] if edge else ramp[(cell[0] * 7 + cell[1] * 3) % 3 // 2]
                px[x, y] = shade
        for x in range(w):
            px[x, 0] = warm[1]
            px[x, 1] = warm[2]
            px[x, 2] = ramp[2]
        for _ in range(500):
            x, y = rnd.randrange(w), rnd.randrange(4, h)
            if px[x, y] != ramp[2]:
                px[x, y] = ramp[1]
    elif kind == "stone_night":
        ramp = RAMPS["night"]
        for y in range(h):
            for x in range(w):
                edge = x % 24 == 0 or (y - 2) % 13 == 0
                px[x, y] = ramp[2] if edge else ramp[1 if ((x // 24) + (y // 13)) % 2 else 0]
        for x in range(w):
            px[x, 0] = RAMPS["steel"][1]
    else:  # pavés de quai
        ramp = RAMPS["stone"]
        for y in range(h):
            for x in range(w):
                row = (y - 2) // 9
                off = 8 if row % 2 else 0
                edge = (y - 2) % 9 == 0 or (x + off) % 16 == 0
                px[x, y] = ramp[2] if edge else ramp[0 if ((x + off) // 16 + row) % 3 else 1]
        for x in range(w):
            px[x, 0] = RAMPS["wood"][3]
            px[x, 1] = RAMPS["wood"][2]
    return img


def recolor(img, mode):
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y][:3]
            if mode == "sunset":     # coucher de soleil chaud
                px[x, y] = (min(255, int(r * 1.08 + 22)), int(g * 0.86 + 6), int(b * 0.68))
            else:                    # crépuscule bleuté
                px[x, y] = (int(r * 0.62 + 18), int(g * 0.66 + 10), min(255, int(b * 0.9 + 34)))
    return img


def build_variant(vid):
    base, mode = VARIANTS[vid]
    src = os.path.join(ROOT, "assets", "stages", base)
    d = os.path.join(ROOT, "assets", "stages", vid)
    os.makedirs(d, exist_ok=True)
    data = json.load(open(os.path.join(src, "stage.json")))
    for i in range(3):
        recolor(Image.open(os.path.join(src, f"far_v_{i}.png")).convert("RGB"), mode).save(os.path.join(d, f"far_v_{i}.png"))
    recolor(Image.open(os.path.join(src, "floor.png")).convert("RGB"), mode).save(os.path.join(d, "floor.png"))
    data["id"] = vid
    json.dump(data, open(os.path.join(d, "stage.json"), "w"), indent=1)
    print(vid, "ok")


def build(sid):
    if sid in VARIANTS:
        build_variant(sid)
        return
    d = os.path.join(ROOT, "assets", "stages", sid)
    cfg = STAGES[sid]
    frames = []
    for i in range(3):
        src = os.path.join(d, f"far_{i}.png")
        out = os.path.join(d, f"far_v_{i}.png")
        veil(Image.open(src).convert("RGB")).save(out)
        frames.append(f"far_v_{i}.png")
    floor(cfg["floor"]).save(os.path.join(d, "floor.png"))
    data = {
        "id": sid, "ground_y": 196, "walls": [16, 560],
        "layers": [
            {"file": frames[0], "frames": frames, "fps": 3, "parallax": 0.25, "y": 0, "z": -10},
            {"file": "floor.png", "parallax": 1.0, "y": 176, "z": -5},
        ],
        "props": cfg["props"], "music": cfg["music"], "ambient_sfx": "",
        "impact_particles": cfg["particles"],
    }
    json.dump(data, open(os.path.join(d, "stage.json"), "w"), indent=1)
    print(sid, "ok")


if __name__ == "__main__":
    for sid in sys.argv[1:] or (list(STAGES) + list(VARIANTS)):
        build(sid)
