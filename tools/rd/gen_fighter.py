#!/usr/bin/env python3
"""Génération RD d'un combattant (SPEC §11.3), via tools/rd/client.py (plafond).

Étapes :
  explore  <id> [--round N]  rd_fast i2i depuis la pose de garde du mannequin, 4 images
  final    <id> <choix.png>  rd_pro 128×128 (ou 160), remove_bg, palette du perso, référence
  idle     <id>              rd_advanced_animation__idle sur la pose finale (8 frames)
  portrait <id>              rd_pro 96×96 buste, pose finale en référence
Toutes les images sont contraintes à la palette du personnage (costume 1) :
leurs couleurs retombent directement sur les index de palette.
"""
import json, os, sys
import numpy as np
from PIL import Image
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import client  # noqa: E402

OUT = os.path.join(HERE, "out")
PROMPTS = yaml.safe_load(open(os.path.join(HERE, "prompts", "fighters.yaml")))


def fighter_dir(fid):
    return os.path.join(ROOT, "assets", "fighters", fid)


def palette_rgb(fid):
    pal = np.array(Image.open(os.path.join(fighter_dir(fid), "palettes.png")).convert("RGBA"))
    return pal[0, :, :3]


def palette_image(fid):
    """Image N×1 des couleurs du costume 1 (index 1..31, sans le transparent)."""
    cols = palette_rgb(fid)[1:]
    uniq = []
    for c in cols:
        t = tuple(int(v) for v in c)
        if t not in uniq:
            uniq.append(t)
    img = Image.new("RGB", (len(uniq), 1))
    for i, c in enumerate(uniq):
        img.putpixel((i, 0), c)
    return img


def mannequin_frame(fid, anim="idle", frame=0, bg=(255, 255, 255)):
    meta = json.load(open(os.path.join(fighter_dir(fid), "anims.json")))
    cell, cols = meta["cell"], meta.get("cols", 16)
    sheet = np.array(Image.open(os.path.join(fighter_dir(fid), "sheet.png")))
    k = meta["anims"][anim]["first"] + frame
    y, x = (k // cols) * cell, (k % cols) * cell
    idx = sheet[y:y + cell, x:x + cell]
    pal = palette_rgb(fid)
    rgb = pal[idx].astype(np.uint8)
    rgb[idx == 0] = bg
    return Image.fromarray(rgb, "RGB"), cell


def prompt(fid, kind="template"):
    return PROMPTS[kind].format(description=PROMPTS["fighters"][fid]).strip()


def explore(fid, rnd=0, strength=0.62):
    img, cell = mannequin_frame(fid)
    payload = {
        "prompt": prompt(fid), "prompt_style": "rd_fast__default",
        "width": cell, "height": cell, "num_images": 4, "seed": 100 + rnd,
        "input_image": client.b64_png(img), "strength": strength,
        "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/explore_{rnd}")


def final(fid, choice_path, strength=0.5):
    img, cell = mannequin_frame(fid)
    refs = [client.b64_png(choice_path)]
    legacy = os.path.join(ROOT, "assets", "sprites", "louis.png")
    if fid == "louis" and os.path.exists(legacy):
        big = Image.open(legacy).convert("RGBA")
        big = big.resize((big.width * 4, big.height * 4), Image.NEAREST)
        refs.append(client.b64_png(big))
    payload = {
        "prompt": prompt(fid), "prompt_style": "rd_pro__default",
        "width": cell, "height": cell, "num_images": 1, "seed": 7,
        "input_image": client.b64_png(Image.open(choice_path)), "strength": strength,
        "reference_images": refs,
        "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/final")


def idle(fid, pose_path):
    img = Image.open(pose_path).convert("RGBA")
    payload = {
        "prompt": "subtle breathing fighting stance idle, " + PROMPTS["fighters"][fid],
        "prompt_style": "rd_advanced_animation__idle",
        "width": img.width, "height": img.height, "num_images": 1, "frames_duration": 8,
        "input_image": client.b64_png(img), "return_spritesheet": True,
        "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/idle")


def portrait(fid, pose_path):
    payload = {
        "prompt": prompt(fid, "portrait"), "prompt_style": "rd_pro__default",
        "width": 96, "height": 96, "num_images": 1, "seed": 11,
        "reference_images": [client.b64_png(pose_path)],
        "input_palette": client.b64_png(palette_image(fid)),
    }
    return client.generate(payload, f"{fid}/portrait")


def contact(paths, out, scale=4):
    ims = [Image.open(p).convert("RGBA") for p in paths]
    w = sum(i.width for i in ims) * scale + 8 * (len(ims) + 1)
    h = max(i.height for i in ims) * scale + 16
    sheet = Image.new("RGBA", (w, h), (90, 96, 120, 255))
    x = 8
    for im in ims:
        sheet.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST), (x, 8))
        x += im.width * scale + 8
    sheet.save(out)
    return out


if __name__ == "__main__":
    step, fid = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(OUT, fid), exist_ok=True)
    if step == "explore":
        rnd = int(sys.argv[sys.argv.index("--round") + 1]) if "--round" in sys.argv else 0
        st = float(sys.argv[sys.argv.index("--strength") + 1]) if "--strength" in sys.argv else 0.62
        paths = explore(fid, rnd, st)
        ref, _ = mannequin_frame(fid)
        ref_path = os.path.join(OUT, fid, "mannequin.png")
        ref.save(ref_path)
        print(contact([ref_path] + paths, os.path.join(OUT, fid, f"explore_{rnd}.png")))
    elif step == "final":
        paths = final(fid, sys.argv[3])
        print(contact([sys.argv[3]] + paths, os.path.join(OUT, fid, "final.png")))
    elif step == "idle":
        print(idle(fid, sys.argv[3]))
    elif step == "portrait":
        paths = portrait(fid, sys.argv[3])
        print(contact(paths, os.path.join(OUT, fid, "portrait.png")))
