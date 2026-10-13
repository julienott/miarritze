#!/usr/bin/env python3
"""Refait le décor lointain 512×216 d'un stage sans miroir (SPEC §11.4).
RD ne génère pas plus de 384 px de large : centre 384×216 (txt2img rd_plus) puis
outpainting RD de 64 px de chaque côté, raccord tramé (même méthode que widen.py).
  new  <id> <seed>…         nouvelle composition complète → candidats
  side <id> left|right <seed>…  refait un seul côté du far_0 actuel → candidats
  pano  <id> <seed>…        txt2img panoramique 384×160 agrandi en 512×216 (sans raccord)
  panoi <id> <strength> <seed>…  idem en img2img depuis le far_0 actuel (efface les raccords)
  pick <id> <candidat>      installe : far_0..2 (pour `side`, les côtés seuls sont
                            recopiés sur les 3 frames animées)
Candidats : tests/out/stages/cand/. Puis build_stage.py <id>."""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "rd"))
import client  # noqa: E402

CAND = os.path.join(ROOT, "tests", "out", "stages", "cand")
COMMON = ("wide side-scrolling fighting game stage background, side view, eye level, horizon at 55% height, "
          "the bottom 15% is plain ground, detailed pixel art, vibrant colors, no people, no characters, "
          "no text, no letters, no signs, no logos")
PROMPTS = {
    "phare_sommet": "standing on the round stone balcony at the top of the Biarritz lighthouse at dusk, "
                    "the big glowing lighthouse lantern room with glass panes and a brass lamp on the left, "
                    "white stone lighthouse wall, black iron railing running across, beyond the railing the "
                    "Biarritz coastline far below with warm town lights, rocks and ocean, purple and orange "
                    "sunset sky with first stars",
    "port_vieux": "the Port Vieux small sandy cove in Biarritz, calm turquoise water, old stone breakwater, "
                  "tall basque houses with white walls and red shutters on the cliff, tamarisk trees, rocky "
                  "points, sunny summer day, blue sky with a few clouds",
    "cote_basques": "Cote des Basques surf beach in Biarritz, rows of rolling surf waves and white foam, "
                    "open ocean, distant rocky headland, blue sky",
    "grande_plage": "Grande Plage of Biarritz, golden sand beach, waves, dark rocks, white belle epoque "
                    "hotels along the promenade, blue sky",
}
BLEND = 12


def outpaint(center, side, seed, sid):
    text = PROMPTS[sid] + ", pixel art, seamless continuation of the scene, no people, no text"
    if side == "left":
        pl = {"input_image": client.b64_png(center.crop((0, 0, 192, 216))), "expand_left": 64}
    else:
        pl = {"input_image": client.b64_png(center.crop((192, 0, 384, 216))), "expand_right": 64}
    pl.update({"prompt": text, "seed": int(seed)})
    img = Image.open(client.edit_tool("outpainting", pl, f"stage/{sid}/side_{side}_{seed}")[0]).convert("RGB")
    return img.resize((256, 216), Image.NEAREST) if img.size != (256, 216) else img


def put_side(frame, gen, side):
    if side == "left":
        frame.paste(gen.crop((0, 0, 64, 216)), (0, 0))
        cols, src = range(64, 64 + BLEND), (lambda x: x)
    else:
        frame.paste(gen.crop((192, 0, 256, 216)), (448, 0))
        cols, src = range(448 - BLEND, 448), (lambda x: x - 256)
    for k, x in enumerate(cols):
        w = (BLEND - k) / (BLEND + 1) if side == "left" else (k + 1) / (BLEND + 1)
        for y in range(216):
            if ((x * 7 + y * 13) % 17) / 17.0 < w:
                frame.putpixel((x, y), gen.getpixel((src(x), y)))


def new(sid, seed):
    payload = {"prompt": PROMPTS[sid] + ", " + COMMON, "prompt_style": "rd_plus__default",
               "width": 384, "height": 216, "num_images": 1, "seed": int(seed)}
    center = Image.open(client.generate(payload, f"stage/{sid}/center_{seed}")[0]).convert("RGB").resize((384, 216), Image.NEAREST)
    frame = Image.new("RGB", (512, 216))
    frame.paste(center, (64, 0))
    for side in ("left", "right"):
        put_side(frame, outpaint(center, side, seed, sid), side)
    dst = os.path.join(CAND, f"{sid}_new_{seed}.png")
    frame.save(dst)
    print(dst)


def _pano_to_far(img):
    # 384×160 → 512×213 (nearest, ×4/3 : le jeu est de toute façon mis à l'échelle
    # fractionnaire sur téléphone), + 3 lignes de ciel en haut → 512×216.
    big = img.convert("RGB").resize((512, 213), Image.NEAREST)
    far = Image.new("RGB", (512, 216))
    far.paste(big.crop((0, 0, 512, 1)).resize((512, 3), Image.NEAREST), (0, 0))
    far.paste(big, (0, 3))
    return far


def pano(sid, seed, src=None, strength=0.45):
    payload = {"prompt": PROMPTS[sid] + ", " + COMMON, "prompt_style": "rd_plus__default",
               "width": 384, "height": 160, "num_images": 1, "seed": int(seed)}
    tag = "pano"
    if src is not None:
        payload["input_image"] = client.b64_png(src.resize((384, 160), Image.NEAREST))
        payload["strength"] = strength
        tag = f"panoi{int(strength * 100)}"
    img = Image.open(client.generate(payload, f"stage/{sid}/{tag}_{seed}")[0])
    dst = os.path.join(CAND, f"{sid}_{tag}_{seed}.png")
    _pano_to_far(img).save(dst)
    print(dst)


def side(sid, which, seed):
    far = Image.open(os.path.join(ROOT, "assets", "stages", sid, "far_0.png")).convert("RGB")
    center = far.crop((64, 0, 448, 216))
    put_side(far, outpaint(center, which, seed, sid), which)
    dst = os.path.join(CAND, f"{sid}_side-{which}_{seed}.png")
    far.save(dst)
    print(dst)


def pick(sid, path):
    d = os.path.join(ROOT, "assets", "stages", sid)
    cand = Image.open(path).convert("RGB")
    name = os.path.basename(path)
    for i in range(3):
        if "_side-" in name:
            frame = Image.open(os.path.join(d, f"far_{i}.png")).convert("RGB")
            which = name.split("_side-")[1].split("_")[0]
            box = (0, 0, 64 + BLEND, 216) if which == "left" else (448 - BLEND, 0, 512, 216)
            frame.paste(cand.crop(box), box[:2])
            frame.save(os.path.join(d, f"far_{i}.png"))
        else:
            cand.save(os.path.join(d, f"far_{i}.png"))
    print(sid, "installé depuis", path)


if __name__ == "__main__":
    os.makedirs(CAND, exist_ok=True)
    a = sys.argv[1:]
    if a[0] == "new":
        for s in a[2:]:
            new(a[1], s)
    elif a[0] == "side":
        for s in a[3:]:
            side(a[1], a[2], s)
    elif a[0] == "pano":
        for s in a[2:]:
            pano(a[1], s)
    elif a[0] == "panoi":
        src = Image.open(os.path.join(ROOT, "assets", "stages", a[1], "far_0.png")).convert("RGB")
        for s in a[3:]:
            pano(a[1], s, src, float(a[2]))
    elif a[0] == "pick":
        pick(a[1], a[2])
