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
}
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


def build(sid):
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
    for sid in sys.argv[1:] or list(STAGES):
        build(sid)
