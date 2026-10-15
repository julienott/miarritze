#!/usr/bin/env python3
"""Génération RD d'un combattant (SPEC §11.3), via tools/rd/client.py (plafond).

Étapes :
  explore  <id> [--round N]  rd_fast i2i depuis la pose de garde du mannequin, 4 images
  final    <id> <choix.png>  rd_pro 128×128 (ou 160), remove_bg, palette du perso, référence
  refine   <id> <pose.png> [--size 128] [--strength 0.3]  rd_pro fidèle, autre taille de case
  neutral  <id> <choix.png>  pose neutre de garde (départ de toutes les animations)
  prep_neutral <id> <neutre_rd.png>  bordures + hauteur commune TARGET_H → neutral_160.png
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


def refine(fid, src_path, size=128, strength=0.3):
    """Reprend une pose validée à une autre taille de case (échelle commune
    des combattants) en restant fidèle : elle sert d'entrée et de référence."""
    src = Image.open(src_path).convert("RGBA")
    box = src.getbbox()
    crop = src.crop(box)
    k = (size - 10) / max(crop.size)
    crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.NEAREST)
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    canvas.alpha_composite(crop, ((size - crop.width) // 2, size - 4 - crop.height))
    payload = {
        "prompt": prompt(fid), "prompt_style": "rd_pro__default",
        "width": size, "height": size, "num_images": 1, "seed": 7,
        "input_image": client.b64_png(canvas.convert("RGB")), "strength": strength,
        "reference_images": [client.b64_png(src)],
        "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/refine_{size}")


NEUTRAL = ("neutral fighting guard stance, side view facing right, both fists raised in front of the chest, "
           "elbows bent, feet apart, nothing extended, whole body visible")


def neutral(fid, src_path, size=128, strength=0.55):
    """Pose neutre de départ pour les animations RD (bonne pratique : les
    animations partent d'une pose calme, membres groupés)."""
    src = Image.open(src_path).convert("RGBA")
    body = src.crop(src.getbbox())
    k = (size - 28) / body.height
    body = body.resize((round(body.width * k), size - 28), Image.NEAREST)
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    canvas.alpha_composite(body, ((size - body.width) // 2, size - 8 - body.height))
    payload = {
        "prompt": PROMPTS["template"].replace("open fighting stance", NEUTRAL + ", small margin around the character").format(description=PROMPTS["fighters"][fid]),
        "prompt_style": "rd_pro__default",
        "width": size, "height": size, "num_images": 1, "seed": 10,
        "input_image": client.b64_png(canvas.convert("RGB")), "strength": strength,
        "reference_images": [client.b64_png(src)],
        "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/neutral_{size}")


# Hauteur commune des combattants régénérés (pose neutre, en px). Les
# animations RD gardent l'échelle de leur image de départ : fixer la pose
# neutre suffit à donner la même taille à tout le monde. Boss : × BOSS_SCALE.
TARGET_H = 112
BOSS_SCALE = {"itsasargi": 1.15}


def prep_neutral(fid, rd_path):
    """Pose neutre RD → tools/rd/out/<id>/neutral_160.png : bordures
    corrigées, ramenée à TARGET_H (plus proche voisin), pieds en bas de case."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
    import check_borders as cb
    a = np.array(Image.open(rd_path).convert("RGBA"))
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    a = cb.fix(a)
    ys, xs = np.nonzero(a[..., 3])
    body = Image.fromarray(a[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")
    target = round(TARGET_H * BOSS_SCALE.get(fid, 1.0))
    if body.height != target:
        k = target / body.height
        body = body.resize((max(1, round(body.width * k)), target), Image.NEAREST)
        body = Image.fromarray(cb.fix(np.array(body)), "RGBA")
    cell = 160
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    out.alpha_composite(body, ((cell - body.width) // 2, cell - 4 - body.height))
    path = os.path.join(OUT, fid, "neutral_160.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    print(f"{fid}: pose neutre {body.width}×{body.height} px → {path}")
    return path


def animate(fid, pose_path, anim, style, prompt_text, frames, attempt=0, description=None):
    """Animation RD d'un mouvement à partir de la pose neutre (case élargie
    pour laisser de la place au geste)."""
    pose = Image.open(pose_path).convert("RGBA")
    size = 160
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(pose, ((size - pose.width) // 2, size - pose.height))
    payload = {
        "prompt": f"{prompt_text}, {description or PROMPTS['fighters'][fid]}",
        "prompt_style": style, "width": size, "height": size, "num_images": 1,
        **({"seed": 1000 + attempt} if attempt else {}),
        "frames_duration": frames, "input_image": client.b64_png(canvas),
        "return_spritesheet": True, "input_palette": client.b64_png(palette_image(fid)), "remove_bg": True,
    }
    return client.generate(payload, f"{fid}/anim_{anim}" + (f"_essai{attempt}" if attempt else ""))


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
    elif step == "refine":
        size = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 128
        st = float(sys.argv[sys.argv.index("--strength") + 1]) if "--strength" in sys.argv else 0.3
        paths = refine(fid, sys.argv[3], size, st)
        print(contact([sys.argv[3]] + paths, os.path.join(OUT, fid, f"refine_{size}.png")))
    elif step == "neutral":
        print(neutral(fid, sys.argv[3]))
    elif step == "prep_neutral":
        prep_neutral(fid, sys.argv[3])
    elif step == "animate":
        # animate <id> <pose.png> <anim> <style> <frames> "<description du geste>"
        print(animate(fid, sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[7], int(sys.argv[6])))
    elif step == "idle":
        print(idle(fid, sys.argv[3]))
    elif step == "portrait":
        paths = portrait(fid, sys.argv[3])
        print(contact(paths, os.path.join(OUT, fid, "portrait.png")))
