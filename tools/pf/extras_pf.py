#!/usr/bin/env python3
"""Assets d'un combattant hors animations, avec pixelforge (gratuit, local).

  portrait <id>  portrait de face 96×96 (Kontext depuis la garde) → candidats
                 tools/rd/out/<id>/pf_portrait_<graine>.png, à déclarer dans
                 tools/rd/out/portraits.json puis make_rd_portraits.py <id>
                 (yeux/bouche du K.O. relevés à la main dans FACES).
  fin <id>       image de fin 320×180 (Kontext sur une composition : décor
                 du stage du perso + perso avec la txapela) → candidats
                 tools/rd/out/<id>/pf_fin_<graine>.png
  effets <id>    projectiles et effets des spéciaux (pf__vfx, fond transparent)
                 d'après VFX ci-dessous → tools/rd/out/<id>/pf_vfx_<effet>_<graine>.png
Chaque commande écrit une planche de choix tests/out/pf/<id>_<commande>.png.
  installer <id> nom=graine …   copie les candidats choisis dans le jeu :
                 fin=102 → assets/fighters/<id>/ending.png ; proj_x=101,
                 sp_down=103… → assets/vfx/<id>/<nom>.png (recadré au contenu).
                 Le portrait passe par make_rd_portraits.py (FACES).
Usage : extras_pf.py portrait|fin|effets <id> [effet …] [--graines 3] [--refaire]
"""
import base64
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402
import redraw  # noqa: E402

STYLE = "kid friendly cartoon, crisp pixel art, sunny basque coast palette, thick dark plum outline, no shadow, no ground, no text"
# effets des spéciaux : (fichier assets/vfx/<id>/<nom>.png, largeur, hauteur, consigne)
# Le jeu lit : proj_<anim> (vfx_pool.gd) ; sp_forward (traînée), sp_down (au sol devant), super (derrière) (move_fx.gd).
TRAIL, FOAM, BURST = (64, 24), (40, 40), (88, 96)
ELEM = (32, 32)
SMALL = 24   # en dessous, généré ×2 puis réduit à l'installation (le générateur rate les tout petits formats)
VFX = {
    "karramarro": [
        ("proj_bulles", 24, 24, "a single big round soap bubble, light blue and transparent looking, white shine highlight"),
        ("sp_down", *FOAM, "bright white and gold sparkle shine burst, four pointed star glint"),
        ("dust", 20, 20, "a single small round puff of beige sand dust cloud"),
        ("star", 16, 16, "a single golden yellow cartoon star"),
    ],
    # Autres persos : projectiles + deux éléments (objets 32 px) que l'installation assemble en
    # traînée (sp_forward=trail:elem_a.N), arc au sol (sp_down=arc:…) et couronne (super=ring:…).
    "amaia": [
        ("elem_a", *ELEM, "a single red and white dance ribbon bow"),
        ("elem_b", *ELEM, "a single small red flower with green leaves"),
    ],
    "itsasargi": [
        ("proj_faisceau", 96, 24, "horizontal glowing golden energy ray, bright yellow light laser beam, nothing else"),
        ("elem_a", *ELEM, "a single bright golden four pointed star sparkle"),
        ("elem_b", *ELEM, "a single small puff of pale grey sea fog cloud"),
    ],
    "itsaso": [
        ("proj_perle", 16, 16, "a single shiny white pearl with a pink glint"),
        ("proj_flaque", 40, 16, "a flat oval puddle of blue sea water with white reflections, seen from the side"),
        ("elem_a", *ELEM, "a single blue water droplet with a white shine"),
        ("elem_b", *ELEM, "a single round white sea foam bubble"),
    ],
    "kaio": [
        ("proj_fiente", 14, 14, "a single funny white cartoon blob splat"),
        ("elem_a", *ELEM, "a single white bird feather"),
        ("elem_b", *ELEM, "a single small white cartoon seagull flying"),
    ],
    "maia": [
        ("proj_rouleau", 28, 18, "a small curling sea wave rolling on the ground, blue with white foam"),
        ("elem_a", *ELEM, "a single blue water droplet with a white shine"),
        ("elem_b", *ELEM, "a single round white sea foam bubble"),
    ],
    "mattin": [
        ("proj_pierre", 22, 22, "a single round grey granite stone"),
        ("proj_onde", 32, 16, "a low brown dust cloud with small pebbles flying, seen from the side"),
        ("elem_a", *ELEM, "a single small puff of brown dust cloud"),
        ("elem_b", *ELEM, "a single small grey pebble"),
    ],
    "patxi": [
        ("proj_sardines", 26, 30, "three small silver sardine fish flying together"),
        ("proj_hamecon", 14, 14, "a single silver fishing hook"),
        ("proj_filet", 26, 38, "a cast fishing net, brown rope mesh spread open"),
        ("elem_a", *ELEM, "a single small silver sardine fish"),
        ("elem_b", *ELEM, "a single blue water droplet with a white shine"),
    ],
    "peio": [
        ("elem_a", *ELEM, "a single small brown and green clod of earth with grass blades"),
        ("elem_b", *ELEM, "a single bright golden four pointed star sparkle"),
    ],
    "ramuntxo": [
        ("proj_gateau", 28, 16, "a round gateau basque cake seen from the side, golden crust"),
        ("elem_a", *ELEM, "a single small puff of white steam cloud"),
        ("elem_b", *ELEM, "a single small red espelette pepper"),
    ],
    "txomin": [
        ("proj_bouee", 22, 22, "a red and white lifebuoy ring"),
        ("proj_pavillon", 50, 64, "a red beach warning flag on a wooden pole planted in sand"),
        ("elem_a", *ELEM, "a single blue water droplet with a white shine"),
        ("elem_b", *ELEM, "a single bright golden four pointed star sparkle"),
    ],
    "xabi": [
        ("proj_pelote", 12, 12, "a small white leather pelota ball with stitching"),
        ("elem_a", *ELEM, "a single small puff of white dust cloud"),
        ("elem_b", *ELEM, "a single bright golden four pointed star sparkle"),
    ],
    "louis": [],
}


def b64(im):
    b = io.BytesIO()
    im.save(b, "PNG")
    return base64.b64encode(b.getvalue()).decode()


def infer(payload):
    pf.wait_ready()
    r = pf._post_json(pf.PF + "/v1/inferences", payload, timeout=3600)
    return [Image.open(io.BytesIO(base64.b64decode(x))).convert("RGBA") for x in r["base64_images"]]


def guard(fid):
    p = os.path.join(ROOT, "tools", "rd", "out", fid, "neutral_160.png")
    if os.path.exists(p):
        return Image.open(p).convert("RGBA")
    meta, _, idx, pal = redraw.load(fid)
    return redraw.frames(meta, idx, pal, "idle")[0]


def flat(im, rgb=(214, 236, 246)):
    bg = Image.new("RGBA", im.size, rgb + (255,))
    bg.alpha_composite(im)
    return bg.convert("RGB")


def sheet(fid, what, items, scale=3):
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf"), 10)
    w = sum(i.width * scale + 8 for _, i in items) + 8
    h = max(i.height for _, i in items) * scale + 30
    S = Image.new("RGB", (w, h), (60, 50, 70))
    x = 8
    for label, im in items:
        S.paste(flat(im).resize((im.width * scale, im.height * scale), Image.NEAREST), (x, 24))
        ImageDraw.Draw(S).text((x, 6), label, font=font, fill=(240, 230, 200))
        x += im.width * scale + 8
    p = os.path.join(ROOT, "tests", "out", "pf", f"{fid}_{what}.png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    S.save(p)
    return p


def portrait(fid, seeds):
    src = flat(guard(fid), (255, 255, 255))
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    os.makedirs(od, exist_ok=True)
    items = []
    for s in seeds:
        im = infer({"prompt_style": "pf__edit", "input_image": b64(src), "width": 96, "height": 96, "seed": s,
                    "quality": "high", "prompt": "close-up bust portrait of this exact same character, facing the viewer "
                    "three-quarter view, head and upper body filling the frame, happy friendly expression, plain flat "
                    "light sky blue background, same colors, same pixel art style"})[0]
        im.save(os.path.join(od, f"pf_portrait_{s}.png"))
        items.append((str(s), im))
    return sheet(fid, "portrait", items, 4)


def compose_end(fid):
    data = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "data.json")))
    st = data.get("home_stage", "grande_plage")
    far = os.path.join(ROOT, "assets", "stages", st, "far_0.png")
    if not os.path.exists(far):
        far = os.path.join(ROOT, "assets", "stages", "grande_plage", "far_0.png")
    bg = Image.open(far).convert("RGBA")
    bg = bg.crop(((bg.width - 320) // 2, max(0, bg.height - 180 - 18), (bg.width - 320) // 2 + 320, max(0, bg.height - 18) or 180)).resize((320, 180))
    g = guard(fid)
    g = g.crop(g.getbbox())
    k = min(140 / g.height, 1.3)
    g = g.resize((round(g.width * k), round(g.height * k)), Image.NEAREST)
    bg.alpha_composite(g, (180 - g.width // 2, 172 - g.height))
    return bg, data.get("name", fid)


def fin(fid, seeds):
    comp, name = compose_end(fid)
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    comp.save(os.path.join(od, "pf_fin_composition.png"))
    items = [("composition", comp)]
    for s in seeds:
        im = infer({"prompt_style": "pf__edit", "input_image": b64(comp.convert("RGB")), "width": 320, "height": 180,
                    "seed": s, "quality": "high",
                    "prompt": f"turn this into a polished 16-bit pixel art summer postcard: the same character {name} "
                    "celebrating victory, wearing a small red basque beret (txapela) on its head, happy, same place, "
                    "keep the exact composition, warm sunny light, no text"})[0]
        im.save(os.path.join(od, f"pf_fin_{s}.png"))
        items.append((str(s), im))
    return sheet(fid, "fin", items, 2)


def effets(fid, seeds):
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    os.makedirs(od, exist_ok=True)
    items = []
    only = [a for a in sys.argv[3:] if not a.startswith("--") and not a.isdigit()]
    for name, w, h, desc in VFX[fid]:
        if only and name not in only:
            continue
        k = 2 if max(w, h) < SMALL else 1
        style = "pf__item" if name.startswith(("proj_", "elem_")) else "pf__vfx"
        ims = infer({"prompt_style": style, "prompt": f"{desc}, isolated game sprite, {STYLE}",
                     "width": w * k, "height": h * k, "num_images": len(seeds), "seed": seeds[0] + 10 * ("--refaire" in sys.argv), "quality": "high"})
        for s, im in zip(seeds, ims):
            im.save(os.path.join(od, f"pf_vfx_{name}_{s}.png"))
            items.append((f"{name[:9]} {s}", im))
    return sheet(fid, "effets", items, 3)


def clean(im):
    """Alpha binaire, ombre portée grise du bas retirée, recadré au contenu."""
    a = np.array(im.convert("RGBA"))
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    ys = np.nonzero(a[..., 3].any(1))[0]
    if len(ys):
        y0 = ys[0] + (ys[-1] - ys[0]) * 4 // 5
        px = a[y0:, :, :3].astype(float) / 255
        mx, mn = px.max(-1), px.min(-1)
        grey = ((mx - mn) / np.maximum(mx, 1e-6) < 0.15) & (mx < 0.75)
        a[y0:][grey] = 0
    im = Image.fromarray(a)
    return im.crop(im.getbbox())


def _elem(od, ref):
    name, seed = ref.split(".")
    im = clean(Image.open(os.path.join(od, f"pf_vfx_{name}_{seed}.png")))
    if max(im.size) < 14:   # trop petit pour se lire en jeu : ×2
        im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
    return im


def trail(elem):
    """Traînée (sp_forward) : trois bouffées de taille décroissante vers l'arrière, traits de vitesse."""
    W, H = 72, max(20, elem.height + 4)
    c = Image.new("RGBA", (W, H))
    for k, (x, sc) in enumerate(((W - elem.width, 1.0), (W // 2 - 8, 0.75), (4, 0.5))):
        e = elem.resize((max(1, round(elem.width * sc)), max(1, round(elem.height * sc))), Image.NEAREST)
        c.alpha_composite(e, (max(0, x), (H - e.height) // 2))
    d = ImageDraw.Draw(c)
    for y in (H // 2 - 5, H // 2 + 5):
        d.line([(2, y), (W - elem.width - 6, y)], fill=(255, 255, 255, 255))
    return c


def ring(elems, n=10, r=34):
    """Couronne (super) : éléments posés en cercle, centre vide."""
    W, H = BURST
    c = Image.new("RGBA", (W, H))
    for k in range(n):
        e = elems[k % len(elems)]
        ang = 2 * np.pi * k / n - np.pi / 2
        x, y = W / 2 + r * np.cos(ang) - e.width / 2, H / 2 + r * np.sin(ang) - e.height / 2
        c.alpha_composite(e, (round(x), round(y)))
    return c


def arc(elems, n=7):
    """Arc au sol (sp_down) : éléments en croissant ouvert vers le haut."""
    W, H = FOAM[0] + 24, FOAM[1]
    c = Image.new("RGBA", (W, H))
    for k in range(n):
        e = elems[k % len(elems)]
        ang = np.pi * (0.1 + 0.8 * k / (n - 1))
        x, y = W / 2 - (W / 2 - 10) * np.cos(ang) - e.width / 2, H - 6 - (H - 16) * np.sin(ang) * 0.9 - e.height / 2
        c.alpha_composite(e, (round(x), round(y)))
    return c


def installer(fid, choices):
    od = os.path.join(ROOT, "tools", "rd", "out", fid)
    done = []
    for c in choices:
        name, seed = c.split("=")
        if name == "fin":
            dst = os.path.join(ROOT, "assets", "fighters", fid, "ending.png")
            Image.open(os.path.join(od, f"pf_fin_{seed}.png")).convert("RGB").resize((320, 180), Image.NEAREST).save(dst)
        else:
            if seed.startswith("trail:"):      # sp_forward=trail:dust.101
                im = trail(_elem(od, seed[6:]))
            elif seed.startswith("arc:"):      # sp_down=arc:elem_a.101+elem_b.102
                im = arc([_elem(od, r) for r in seed[4:].split("+")])
            elif seed.startswith("ring:"):     # super=ring:star.102+proj_bulles.102
                im = ring([_elem(od, r) for r in seed[5:].split("+")])
            else:
                im = Image.open(os.path.join(od, f"pf_vfx_{name}_{seed}.png"))
            im = clean(im)
            target = next((max(w, h) for n_, w, h, _ in VFX.get(fid, []) if n_ == name), 0)
            if 0 < target < SMALL and max(im.size) > target:   # généré ×2
                k = target / max(im.size)
                im = clean(im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.NEAREST))
            dst = os.path.join(ROOT, "assets", "vfx", fid, f"{name}.png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im.save(dst)
        done.append(dst)
    return "\n".join(done)


def main():
    what, fid = sys.argv[1], sys.argv[2]
    if what == "installer":
        print(installer(fid, sys.argv[3:]))
        return
    n = int(sys.argv[sys.argv.index("--graines") + 1]) if "--graines" in sys.argv else 3
    seeds = [101 + i for i in range(n)]
    print({"portrait": portrait, "fin": fin, "effets": effets}[what](fid, seeds))


if __name__ == "__main__":
    main()
