#!/usr/bin/env python3
"""Génère toutes les animations d'un combattant avec les modes d'animation
Retro Diffusion (rd_advanced_animation__*), via client.py (plafond, cache).

Bonne pratique RD : chaque mouvement part d'une pose neutre (garde, membres
groupés) ; les mouvements qui commencent ailleurs (au sol, en l'air,
accroupi) partent d'une image d'une animation déjà générée.

Usage : gen_anims.py <id> [anim …] [--dry]   (sans anim : toutes)
Les sorties brutes vont dans le cache ; tools/rd/out/<id>/anims.json liste
la planche RD de chaque animation pour build_rd_anims.py.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client  # noqa: E402
sys.path.insert(0, os.path.join(HERE, "..", "specs"))
import spec as fiche  # noqa: E402
import gen_fighter as gf  # noqa: E402

CELL = 160
W, A, C, J, K = ("rd_advanced_animation__walking", "rd_advanced_animation__attack",
                 "rd_advanced_animation__custom_action", "rd_advanced_animation__jump",
                 "rd_advanced_animation__crouch")
IDLE = "rd_advanced_animation__idle"
SIDE = "side view facing right, cartoon, kid friendly"

# anim -> (mode, images générées, geste, départ)
# départ : "neutral" ou (anim, index d'image) d'une animation déjà générée.
LOUIS = {
    "idle": (IDLE, 8, "subtle breathing in fighting guard, fists up, happy", "neutral"),
    "walk": (W, 8, "cheerful brisk walk forward, fists kept up in guard", "neutral"),
    "run": (W, 8, "runs forward fast, leaning forward, arms pumping", "neutral"),
    "crouch": (C, 6, "squats down very low with knees deeply bent, head lowered to half height, fists up in guard, then holds the low crouch", "neutral"),
    "jump": (J, 8, "jumps straight up high and lands, fists up", "neutral"),
    "jump_fwd": (C, 6, "leaps forward through the air in a tucked forward jump", "neutral"),
    "block": (C, 4, "raises both forearms in front of the face to block, braced", "neutral"),
    "crouch_block": (C, 4, "stays in the low crouch and raises both forearms in front of the face to block", ("crouch", "low")),
    "punch_1": (A, 6, "quick straight jab with the front fist", "neutral"),
    "punch_2": (A, 6, "quick straight punch with the back fist", "neutral"),
    "punch_3": (A, 6, "big powerful hook punch with the back fist and a full body turn, empty hands", "neutral"),
    "kick": (A, 6, "front kick at belly height with the front leg", "neutral"),
    "kick_high": (A, 6, "high kick at head height with the front leg, clean pose", "neutral"),
    "uppercut": (C, 6, "crouches slightly then springs up driving his back fist straight up high above his head in a big uppercut, arm fully extended upward", "neutral"),
    "crouch_punch": (A, 6, "stays in the low crouch and throws a quick low punch forward at knee height", ("crouch", "low")),
    "sweep": (C, 6, "from the low crouch, stretches the front leg far out along the ground in a wide sweeping kick, foot skimming the floor, then pulls it back", ("crouch", "low")),
    "jump_punch": (C, 4, "in mid-air, legs tucked, throws one fist straight forward and down, arm fully extended", ("jump", "air")),
    "jump_kick": (C, 4, "in mid-air, kicks one leg straight forward fully extended like a flying kick, other leg tucked", ("jump", "air")),
    "throw": (C, 8, "alone, mimes grabbing with both hands in front of him then swings both arms over his shoulder in a throwing motion, no other character, empty hands", "neutral"),
    "thrown": (C, 6, "is lifted off his feet and spins backward through the air upside down with arms and legs flailing, surprised face, cartoon, no injury", "neutral"),
    "hit_high": (C, 4, "head snaps back after getting bopped on the head, cartoon, no injury", "neutral"),
    "hit_low": (C, 4, "bends forward holding his belly with both arms after a bump, eyes squeezed shut, staggers back a step, cartoon, no injury", "neutral"),
    "hit_air": (C, 4, "knocked backward in mid-air, body leaning far back, arms and legs flung forward, eyes squeezed shut, cartoon, no injury", ("jump", "air")),
    "knockdown": (C, 6, "falls backward onto the ground and lies flat on his back, cartoon, no injury", "neutral"),
    "getup": (C, 6, "gets back up from lying on the ground to a fighting guard", ("knockdown", -1)),
    "dizzy": (C, 6, "dizzy and wobbling in place with swirly eyes, cartoon stars, no injury", "neutral"),
    "ko": (C, 8, "falls backward knocked out and lies on the ground with closed eyes, cartoon, no injury", "neutral"),
    "win": (C, 8, "cheers and jumps with a fist raised in victory, big smile", "neutral"),
    "intro": (C, 8, "waves hello with a big smile then takes a fighting guard", "neutral"),
    "sp_neutral": (C, 8, "takes off one espadrille shoe and throws it forward like a boomerang", "neutral"),
    "sp_forward": (C, 8, "charges forward headfirst like a bull, head down, red beret first, both arms back", "neutral"),
    "sp_down": (C, 8, "drops low and does a spinning sweep kick along the ground", "neutral"),
    "sp_up": (C, 8, "jumps straight up with a rising knee and fist raised high", "neutral"),
    "super": (C, 12, "flurry of fast punches and kicks ending with a big jumping uppercut", "neutral"),
    "finisher": (C, 12, "proudly raises both arms to the sky, then gives a big thumbs up and a happy wink, keeps his red beret on his head", "neutral"),
}
def _her(t):
    return t.replace(" his ", " her ").replace(" him ", " her ").replace(" he ", " she ")


MAIA = {k: (st, n, _her(" " + g + " ").strip(), start) for k, (st, n, g, start) in LOUIS.items()}
MAIA.update({
    "intro": (C, 8, "waves hello with a big smile, then takes a fighting guard", "neutral"),
    "win": (C, 8, "jumps with joy and makes a surfer shaka hand sign, big smile", "neutral"),
    "throw": (C, 8, "alone, mimes grabbing with both hands in front of her then swings both arms over her shoulder in a throwing motion, no other character, empty hands", "neutral"),
    "sp_neutral": (C, 8, "pulls the surfboard off her back and swings it forward in a wide horizontal arc, then puts it back", "neutral"),
    "sp_forward": (C, 8, "slides forward low on her knees as if surfing on the sand, arms spread for balance", "neutral"),
    "sp_down": (C, 8, "crouches and pushes both palms forward low along the ground, launching a small rolling wave", "neutral"),
    "sp_up": (C, 8, "leaps high into the air spinning like a surfer doing an aerial trick, knees tucked", "neutral"),
    "super": (C, 12, "raises both arms as a giant wave rises behind her, then rides forward on her surfboard", "neutral"),
    "finisher": (C, 12, "plants her surfboard upright in the sand and leans on it with a proud smile and a shaka sign", "neutral"),
})
NOFX = ", no glow, no halo, no aura, no bubble, no effects around her"
MAIA.update({
    "idle": (C, 8, "stands in fighting guard with fists up and breathes calmly, shoulders rising slightly" + NOFX, "neutral"),
    "crouch": (C, 6, "bends both knees deeply and squats down very low until her head is at half height, fists up, then holds the low squat" + NOFX, "neutral"),
    "block": (C, 4, "crosses both forearms in front of her face to shield it, elbows up, braced" + NOFX, "neutral"),
    "crouch_block": (C, 4, "stays in the low squat and crosses both forearms in front of her face" + NOFX, ("crouch", "low")),
    "punch_1": (C, 6, "throws a fast straight jab, the front arm shoots fully forward at face height then pulls back" + NOFX, "neutral"),
    "punch_2": (C, 6, "throws a straight punch with the back arm, arm fully extended forward at chest height, body turning" + NOFX, "neutral"),
    "hit_high": (C, 4, "head snaps backward and she staggers back one step with eyes squeezed shut, cartoon, no injury" + NOFX, "neutral"),
    "knockdown": (C, 6, "falls backward and lands flat on her back lying on the ground, arms spread, cartoon, no injury" + NOFX, "neutral"),
    "getup": (C, 6, "lying flat on her back, she sits up, then stands back up into a fighting guard" + NOFX, ("knockdown", "low")),
    "ko": (C, 8, "falls backward and lies flat on the ground with closed eyes, cartoon, no injury" + NOFX, "neutral"),
    "sp_down": (C, 8, "drops into a deep squat and sweeps both palms forward along the ground" + NOFX, "neutral"),
    "super": (C, 12, "spins around once, then dashes forward and throws a big two-handed push with both arms fully extended" + NOFX, "neutral"),
    "finisher": (C, 12, "jumps up and down with joy, then makes a big surfer shaka sign with one hand raised high and a wide smile" + NOFX, "neutral"),
})
PEIO = {k: v for k, v in LOUIS.items()}
PEIO.update({k: v for k, v in MAIA.items() if k in ("idle", "block", "crouch", "crouch_block", "punch_1", "punch_2", "hit_high", "knockdown", "getup", "ko")})
PEIO.update({
    "intro": (C, 8, "claps his hands twice with a big grin, then takes a fighting guard" + NOFX, "neutral"),
    "win": (C, 8, "raises both fists in victory and jumps with joy, big smile" + NOFX, "neutral"),
    "sp_neutral": (C, 8, "drops a brown oval rugby ball from his hands and kicks it forward with a big swinging drop kick" + NOFX, "neutral"),
    "sp_forward": (C, 8, "charges forward low with his shoulder lowered for a rugby tackle, arms wide open" + NOFX, "neutral"),
    "sp_down": (C, 8, "pushes one open hand straight forward at arm's length in a strong rugby hand-off, braced" + NOFX, "neutral"),
    "sp_up": (C, 8, "jumps straight up high with both arms stretched above his head to catch a ball in a rugby lineout" + NOFX, "neutral"),
    "super": (C, 12, "lowers his head and shoulders and drives forward hard in a powerful rugby scrum push, legs pumping" + NOFX, "neutral"),
    "finisher": (C, 12, "lifts both arms high and cheers, then puts one hand on his heart and bows to the crowd" + NOFX, "neutral"),
    "throw": (C, 8, "alone, mimes grabbing with both hands in front of him then swings both arms over his shoulder in a throwing motion, no other character, empty hands" + NOFX, "neutral"),
})
PEIO = {k: (st, n, g.replace(" her ", " his ").replace("her ", "his ").replace(" she ", " he "), start) for k, (st, n, g, start) in PEIO.items()}
PEIO.update({
    "crouch": (C, 6, "squats down very low on bent knees like a rugby player ready to scrum, back bent forward, head at half height, fists up, then holds the low squat" + NOFX, "neutral"),
    "knockdown": (C, 6, "topples backward and lands lying flat on his back on the ground, legs in the air then flat, cartoon, no injury" + NOFX, "neutral"),
    "sp_forward": (C, 8, "dives forward almost horizontally with his shoulder first and both arms stretched forward to tackle, body parallel to the ground" + NOFX, "neutral"),
})
SPECS = {"louis": LOUIS, "maia": MAIA, "peio": PEIO}


def out_dir(fid):
    d = os.path.join(HERE, "out", fid)
    os.makedirs(d, exist_ok=True)
    return d


def frames_of(sheet_path):
    im = Image.open(sheet_path).convert("RGBA")
    cols = im.width // CELL
    out = []
    for k in range(cols * (im.height // CELL)):
        fr = im.crop(((k % cols) * CELL, (k // cols) * CELL, (k % cols + 1) * CELL, (k // cols + 1) * CELL))
        if fr.getbbox():
            out.append(fr)
    return out


def start_image(fid, start, done):
    if start == "neutral":
        return os.path.join(out_dir(fid), "neutral_160.png")
    anim, idx = start
    frames = frames_of(done[anim])
    if idx == "air":      # image la plus haute (pieds au plus haut)
        idx = min(range(len(frames)), key=lambda i: frames[i].getbbox()[3])
    elif idx == "low":    # image la plus basse (tête au plus bas)
        idx = max(range(len(frames)), key=lambda i: frames[i].getbbox()[1])
    path = os.path.join(out_dir(fid), f"start_{anim}_{idx}.png")
    frames[idx].save(path)
    return path


def main():
    fid = sys.argv[1]
    if fiche.exists(fid):
        SPECS[fid] = fiche.moves(fid)
    names = [a for a in sys.argv[2:] if not a.startswith("--")] or list(SPECS[fid])
    dry = "--dry" in sys.argv
    reg_path = os.path.join(out_dir(fid), "anims.json")
    done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    total = 0.0
    for name in names:
        style, n, gesture, start = SPECS[fid][name]
        if not isinstance(start, str) and start[0] not in done:
            print(f"{name}: départ {start[0]} pas encore généré, ignoré")
            continue
        src = start_image(fid, start, done)
        prompt = f"{gesture}, {SIDE}"
        if dry:
            total += 0.25 if style in (C,) else 0.14
            print(f"{name}: {style} {n} images depuis {os.path.basename(src)}")
            continue
        paths = gf.animate(fid, src, name, style, prompt, n)
        done[name] = paths[0]
        json.dump(done, open(reg_path, "w"), indent=1)
        print(f"{name}: {paths[0]}")
    if dry:
        print(f"coût estimé : {total:.2f} $")


if __name__ == "__main__":
    main()
