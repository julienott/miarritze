#!/usr/bin/env python3
"""Décors img2img : photos réelles de Biarritz → pixel art (Retro Diffusion).

Le réel d'abord : chaque décor part d'une photo cadrée en 16:9 « plan de
jeu » (saturation boostée), l'API ne fait que styliser. La géographie et
les monuments restent fidèles — le jeu est fait pour des locaux.
"""
from PIL import Image, ImageEnhance
import base64, io, json, os, sys, urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
SCRATCH = "/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad"
PHOTOS = os.path.join(SCRATCH, "photos", "miarritze photos")

STYLE = ("detailed pixel art video game background, vibrant sunny colors, "
         "warm palette, clean silhouettes, completely empty of people and boats, "
         "no characters, no text, no letters, no signs, no watermark")

# zones à pré-nettoyer par scène (coordonnées après crop)
PATCHES = {
    # Port Vieux : foule de la plage -> sable nu, baigneurs -> eau
    "espadrille": [
        (380, 420, 1330, 620, (212, 176, 136)),
        (200, 620, 1400, 788, (98, 166, 148)),
    ],
}

# (nom, photo, crop (l,t,r,b) ou None = auto 16:9 centré, décalage vertical, prompt, strength)
SCENES = [
    ("beach", "grande plage 1.webp", None, 0,
     "Grande Plage of Biarritz, white art deco Casino Municipal building along the "
     "promenade, apartment buildings behind, golden sand beach, foamy waves on the left, blank facades without any lettering", 0.72),
    ("surf", "cote des basques.jpg.webp", (0, 60, 2000, 1185), 0,
     "Cote des Basques Biarritz, Villa Belza manor with grey pointed turrets on the cliff, "
     "teal ocean with empty waves, rocky point, deserted ocean without anyone", 0.74),
    ("fishing", "port des pêcheurs.jpg", None, 0,
     "Port des Pecheurs of Biarritz, small fishing harbor with stone jetties, moored boats, "
     "white basque houses with red woodwork, town and lighthouse in the distance, blank walls without lettering", 0.7),
    ("rock", "cote des basques.jpg.webp", (60, 330, 1420, 1095), 0,
     "Rocher de la Vierge Biarritz, rocky islets with white statue of the virgin, iron "
     "footbridge, stone esplanade, empty ocean waves, nobody in the water", 0.74),
    ("espadrille", "port vieux 2.jpg", (0, 620, 1400, 1408), 0,
     "Port Vieux cove of Biarritz, turquoise water in the foreground, empty sandy beach, "
     "white arched bathing house, basque town with red roofs behind, rocky cliff on the left", 0.72),
    ("hub", "plan de biarritz.jpg", (0, 120, 559, 434), 0,
     "top down video game map of Biarritz, coastline with beaches, ocean on the left, "
     "cute zelda style overworld, red roofed tiny houses clusters, lush green parks and headlands, white lighthouse tower on the north point, rocher de la vierge rocky islet, golden sand beaches, bright teal ocean, no roads, no text anywhere", 0.82),
    ("menu", "grande plage 2.jpg", (0, 240, 1400, 1027), 0,
     "panoramic view of the Grande Plage bay of Biarritz, turquoise ocean, headland with "
     "the white lighthouse of Biarritz in the distance, golden beach in the foreground", 0.72),
]


def prepare(photo: str, crop, width=320, height=180, patches=None) -> str:
    img = Image.open(os.path.join(PHOTOS, photo)).convert("RGB")
    if crop:
        img = img.crop(crop)
    # patches : [(l,t,r,b,(r,g,b))] — peint une zone (ex. foule -> sable)
    import random as _rnd
    for (l, t, r, b, colr) in (patches or []):
        for y in range(t, b):
            for x in range(l, r):
                n = _rnd.randint(-10, 10)
                img.putpixel((x, y), (colr[0] + n, colr[1] + n, colr[2] + n))
    else:
        w, h = img.size
        target = w * 9 // 16
        if target <= h:
            top = (h - target) // 2
            img = img.crop((0, top, w, top + target))
        else:
            target_w = h * 16 // 9
            left = (w - target_w) // 2
            img = img.crop((left, 0, left + target_w, h))
    img = img.resize((width, height), Image.LANCZOS)
    img = ImageEnhance.Color(img).enhance(1.45)
    img = ImageEnhance.Brightness(img).enhance(1.06)
    img = ImageEnhance.Contrast(img).enhance(1.08)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def generate(name, photo, crop, _dy, prompt, strength) -> str:
    with open(os.path.join(ROOT, ".rd_api_key")) as f:
        key = f.read().strip()
    body = {
        "prompt": "%s, %s" % (prompt, STYLE),
        "width": 320, "height": 180, "num_images": 1,
        "input_image": prepare(photo, crop, patches=PATCHES.get(name)),
        "strength": strength,
    }
    req = urllib.request.Request(
        "https://api.retrodiffusion.ai/v1/inferences",
        data=json.dumps(body).encode(),
        headers={"X-RD-Token": key, "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read())
    out = os.path.join(SCRATCH, "rd", "i2i_%s.png" % name)
    with open(out, "wb") as f:
        f.write(base64.b64decode(data["base64_images"][0]))
    return out


if __name__ == "__main__":
    only = sys.argv[1:] or None
    for scene in SCENES:
        if only and scene[0] not in only:
            continue
        print(scene[0], "->", generate(*scene))
