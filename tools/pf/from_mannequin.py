#!/usr/bin/env python3
"""Perso refait ENTIÈREMENT depuis son modèle propre (retour de Julien, 2026-10-18 :
« les persos à refaire entièrement, il faut les refaire entièrement »).

Rien n'est repris des anciennes images ni du rig découpé :
  - gestes : mannequin articulé propre (tools/mannequin, mêmes poses que le jeu),
    rendu SANS accessoire, mis à la taille du modèle → contrôles du guidé ;
  - images : pf_anim__guided redessine le modèle propre sur chaque contrôle ;
  - rotations (saltos, chutes) : le guidé perd le perso tête en bas → le contrôle
    est rendu corps droit (bassin à 0°), le perso redessiné droit, puis tourné
    du même angle et recalé sur la silhouette tournée ;
  - accessoire (chistera, makila, pierre…) : découpé dans le modèle propre (pièce
    du rig RD : image d'origine) et posé sur la main du mannequin à chaque image,
    devant (accf/acc) ou derrière (accb) le corps → fidèle, jamais redessiné.
Sorties : tools/rd/out/<id>/pf/<anim>_m<graine>.png, anims.json, verdicts.json,
planche tests/out/pf/<id>.png ; ensuite build_rd_anims.py / build_fighter.py.
Usage : from_mannequin.py <id> [anim …] [--essais 3] [--graine D] [--refaire]
"""
import hashlib
import json
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
for sub in ("tools/rig", "tools/sprites", "tools/mannequin", "tools", "tools/pf"):
    sys.path.insert(0, os.path.join(ROOT, sub))

import animate  # noqa: E402
import make_palettes  # noqa: E402
import pieces  # noqa: E402
import rd_rig  # noqa: E402
from mannequin import FICHES, build_rig  # noqa: E402

import gen_anims_pf as pf  # noqa: E402

fiche = pf.fiche

CELL = 256           # case des persos refaits (jeu et génération) : chistera à bout de bras,
FOOT = (128, 240)    # perso couché ou tourné, rien n'est rogné (le jeu lit cell/foot par perso)
AIR_MARGIN = 14      # px (case) gardés sous un perso en l'air : la boule tournée est plus large
ROT_LIFT = 32        # px : remontée des images tournées (couché, salto) dans la case
TILT = 40            # au-delà (degrés d'inclinaison du buste), le contrôle est rendu corps droit
CANVAS = (CELL * 2, CELL * 2)
ROOTPOS = (float(CELL), CELL * 150.0 / 128.0)
QA = dict(pieces.QA, max_drift=0.45)
# Animations où l'accessoire est caché (le bras redessiné ne suit pas la main du
# mannequin et l'objet barre le visage) : relecture de la planche.
NO_ACC_ANIMS = {"amaia": {"jump_kick"}}
# Accessoire du rig RD abandonné par le nouveau design (bouée de Txomin → palmes).
NO_RD_ACC = {"txomin"}
# Accessoires dessinés accrochés au bassin : (image, point d'accroche dans l'image,
# décalage du point depuis le bassin du mannequin, à l'échelle du modèle, devant le
# corps ?). Palmes de Txomin pendues à la ceinture côté visible : tools/pf/draw_palme.py.
HIP_ACC = {"txomin": ("tools/rd/out/txomin/palmes_ceinture.png", (16, 1), (-8, -3), True)}


def out_dir(fid):
    return os.path.join(ROOT, "tools", "rd", "out", fid)


# Animations accroupies : le guidé ne plie pas un modèle debout (il recopie la pose
# debout) → référence = modèle accroupi (prep_refonte.py accroupi) s'il existe.
CROUCH_ANIMS = {"crouch", "crouch_idle", "crouch_block", "crouch_punch", "sweep"}


def model(fid, name="modele_sans_acc.png"):
    """Modèle propre sans accessoire (prep_refonte.py), dans une case du jeu, pieds en FOOT."""
    p = os.path.join(out_dir(fid), name)
    im = Image.open(p).convert("RGBA")
    im = im.crop(im.getbbox())
    out = Image.new("RGBA", (CELL, CELL))
    out.paste(im, (FOOT[0] - im.width // 2, FOOT[1] - im.height), im)
    return out


def strip(frames):
    s = Image.new("RGBA", (CELL * len(frames), CELL))
    for i, f in enumerate(frames):
        s.paste(f, (i * CELL, 0))
    return s


class Mannequin:
    """Mannequin du perso : rendus corps entier (sans accessoire) et positions des os."""

    def __init__(self, fid):
        self.fid = fid
        f = FICHES[fid]
        self.amp = f.get("amp", 1.0)
        self.rig = build_rig(f)
        self.acc = [k for k in self.rig.draw_order if k.split(":")[0] in ("acc", "accf", "accb")]
        self.rig.draw_order = [k for k in self.rig.draw_order if k not in self.acc]
        self.rig._cache8 = {}
        self.pal = np.array(make_palettes.build(f))[0]
        self.poses = animate.load_poses(fid)
        self.named = self.poses["named"]
        idle = self.rig.render(self.expand("idle")[0], CANVAS, ROOTPOS)
        ys = np.nonzero(idle.any(1))[0]
        self.height = int(ys.max() - ys.min() + 1)
        self.idle_mid = (ys.max() + ys.min()) / 2 - ys.max()       # centre relatif au sol

    def expand(self, name):
        return animate.expand(self.poses["anims"][name], self.named, self.amp)

    def rgba(self, idx):
        return Image.fromarray(self.pal[idx].astype(np.uint8), "RGBA")


def place(canvas_img, name, scale, ref_rows=None):
    """Image du canevas (RGBA 320²) → case de 160, pied en FOOT, à l'échelle du modèle.
    Renvoie (case, transformation canevas→case (s, tx, ty))."""
    a = np.array(canvas_img)[..., 3] > 0
    rows = np.nonzero(a.any(1))[0] if ref_rows is None else ref_rows
    if not len(rows):
        return Image.new("RGBA", (CELL, CELL)), (scale, 0, 0)
    if name in animate.AIR_ANIMS:
        ground = (rows.max() + rows.min()) / 2 - IDLE_MID[0]
        ground = max(ground, rows.max() + AIR_MARGIN / scale)    # en l'air : jamais sous le sol de la case
    else:
        ground = rows.max()
    # pied (sol, bassin en x) → FOOT, échelle autour de ce point
    tx = FOOT[0] - ROOTPOS[0] * scale
    ty = FOOT[1] - (ground + 0.5) * scale
    big = canvas_img.resize((round(CANVAS[0] * scale), round(CANVAS[1] * scale)), Image.NEAREST)
    cell = Image.new("RGBA", (CELL, CELL))
    cell.paste(big, (round(tx), round(ty)), big)
    return cell, (scale, tx, ty)


IDLE_MID = [0.0]


def b64(im):
    return pieces.b64(im)


class Accessory:
    """Accessoire découpé dans le modèle propre (pièce du rig RD), posé par le serveur
    (overlays) sur la main du mannequin : position de l'os du mannequin, angle de l'os
    du rig RD pour la même pose. Jamais redessiné (Julien : « chistera fidèle »)."""

    def __init__(self, fid, man):
        self.ok = rd_rig.has_rd_rig(fid) and bool(man.acc) and fid not in NO_RD_ACC
        if not self.ok:
            return
        self.rd, guard = rd_rig.build_rig(fid)
        self.rd_poses = animate.load_poses(fid, guard_override=guard)
        over = rd_rig.pose_overrides(fid)
        for name, pose in over.get("named", {}).items():
            self.rd_poses["named"][name] = {**self.rd_poses["named"].get(name, {}), **pose}
        self.rd_bone = next((b for b in self.rd.bones.values() if b.name.split(":")[0] in ("acc", "accf", "accb")), None)
        if self.rd_bone is None:
            self.ok = False
            return
        self.man_bone = man.acc[0]
        self.front = not self.rd_bone.name.startswith("accb")
        from redraw import load
        import rig as rigmod
        pal = load(fid)[3]
        piece = self.rd.pieces[self.rd_bone.piece]
        idx = np.pad(piece.img, 1)                       # place pour le contour
        self.image = Image.fromarray(pal[rigmod.add_outline(idx)].astype(np.uint8), "RGBA")
        self.pivot = [float(piece.pivot[0]) + 1, float(piece.pivot[1]) + 1]
        self.base = piece.base
        self.man = man

    def overlay(self, pose, rd_pose, tf):
        s, tx, ty = tf
        pos = self.man.rig.solve(pose, ROOTPOS)[self.man_bone][0]
        ang = self.rd.solve(rd_pose, ROOTPOS)[self.rd_bone.name][1]
        return {"image": 0, "pivot": self.pivot, "position": [float(pos[0] * s + tx), float(pos[1] * s + ty)],
                "angle": float(ang - self.base), "front": bool(self.front)}


def acc_dummy():
    """Image vide pour garder l'indice 1 des palmes quand il n'y a pas d'accessoire RD."""
    return Image.new("RGBA", (1, 1))


def hip_overlay(fid, man, pose, tf):
    """Accessoire accroché au bassin (palmes de Txomin), tourne avec le bassin."""
    import rig as rigmod
    _, grip, off, front = HIP_ACC[fid]
    s, tx, ty = tf
    pos, ang, _ = man.rig.solve(pose, ROOTPOS)["pel"]
    ox, oy = rigmod.rotate(off, ang)
    return {"image": 1, "pivot": [float(g) for g in grip],
            "position": [float(pos[0] * s + tx + ox), float(pos[1] * s + ty + oy)],
            "angle": float(ang), "front": bool(front)}


class Perso:
    """Un perso à refaire : prépare les requêtes guidées (une par animation) et
    enregistre les résultats ; utilisé en direct (main) ou par la file (file_pf.py)."""

    def __init__(self, fid, retries=3, shift=0):
        self.fid, self.retries, self.shift = fid, retries, shift
        self.od = out_dir(fid)
        self.pd = os.path.join(self.od, "pf")
        os.makedirs(self.pd, exist_ok=True)
        self.ref = model(fid)
        cp = os.path.join(self.od, "modele_accroupi.png")
        self.ref_crouch = model(fid, "modele_accroupi.png") if os.path.exists(cp) else None
        self.ref.save(os.path.join(self.od, f"neutral_{CELL}.png"))   # pour build_rd_anims (échelle, centrage)
        self.man = Mannequin(fid)
        IDLE_MID[0] = self.man.idle_mid
        mh = self.ref.getbbox()
        self.scale = (mh[3] - mh[1]) / self.man.height
        self.acc = Accessory(fid, self.man)
        bp = os.path.join(self.od, "boule.png")
        self.boule = Image.open(bp).convert("RGBA") if os.path.exists(bp) else None
        s = fiche.load(fid) if fiche.exists(fid) else {}
        self.look = (s.get("apparence") or fid).strip()
        self.reg_path = os.path.join(self.od, "anims.json")
        self.ok_path = os.path.join(self.pd, "verdicts.json")
        self.log_path = os.path.join(self.od, "gen_log.jsonl")

    def state(self):
        done = json.load(open(self.reg_path)) if os.path.exists(self.reg_path) else {}
        verdicts = json.load(open(self.ok_path)) if os.path.exists(self.ok_path) else {}
        return done, verdicts

    def prepare(self, name):
        """→ (requête, graine, contrôles)."""
        fid, man, acc = self.fid, self.man, self.acc
        IDLE_MID[0] = man.idle_mid
        poses = man.expand(name)
        rd_poses = animate.expand(acc.rd_poses["anims"][name], acc.rd_poses["named"], man.amp) if acc.ok else poses
        targets, controls, angles, overlays, tucks = [], [], [], [], []
        for i, p in enumerate(poses):
            cell, tf = place(man.rgba(man.rig.render(p, CANVAS, ROOTPOS)), name, self.scale)
            # inclinaison du buste dans le monde (bassin + buste) : couché, salto…
            ang = float(man.rig.solve(p, ROOTPOS)["tor"][1])
            if abs(ang) > TILT:
                q = dict(p)
                q["pel"] = float(p.get("pel", 0.0)) - ang
                up, _ = place(man.rgba(man.rig.render(q, CANVAS, ROOTPOS)), name, self.scale)
                controls.append(up)
                # cible remontée : le perso redessiné, plus épais que le mannequin, déborderait
                # sous la case (build_rd_anims recale ensuite chaque image sur le sol)
                lifted = Image.new("RGBA", (CELL, CELL))
                lifted.paste(cell, (0, -ROT_LIFT), cell)
                targets.append(lifted)
                angles.append(float(ang))
                if name in animate.AIR_ANIMS and self.boule is not None:
                    tucks.append(int(i))                 # salto : la boule tourne
            else:
                controls.append(cell)
                targets.append(None)
                angles.append(0.0)
            ov = []
            if angles[-1] or name in NO_ACC_ANIMS.get(fid, ()):
                # perso couché ou en salto (redessiné droit puis tourné) : l'accessoire posé sur la
                # main du mannequin flotterait à côté du corps → caché (il « lâche » son objet)
                overlays.append(None)
                continue
            if acc.ok:
                ov.append(acc.overlay(p, rd_poses[i], tf))
            if fid in HIP_ACC:
                ov.append(hip_overlay(fid, man, p, tf))
            overlays.append(ov or None)
        extra = {"frame_angles": angles, "target_frames": [b64(t) if t else None for t in targets],
                 "ignore_masks": True}
        imgs = []
        if acc.ok:
            imgs.append(b64(acc.image))
        if fid in HIP_ACC:
            if not acc.ok:
                imgs.append(b64(acc_dummy()))
            imgs.append(b64(Image.open(os.path.join(ROOT, HIP_ACC[fid][0])).convert("RGBA")))
        if imgs:
            extra["overlay_images"] = imgs
            extra["overlays"] = overlays
        if tucks:
            extra["tuck_image"] = b64(self.boule)
            extra["tuck_frames"] = tucks
        seed = int(hashlib.sha1(f"{fid}:{name}:mannequin".encode()).hexdigest()[:6], 16) + self.shift
        keep_txt = "same character, same face, same colors, side view facing right, clean pixel art, no weapon, no object, no effects"
        ref = self.ref_crouch if name in CROUCH_ANIMS and self.ref_crouch is not None else self.ref
        payload = pieces.guided_payload(ref, controls, f"{self.look}, {name.replace('_', ' ')}, {keep_txt}",
                                        seed, None, clean=True, retries=self.retries, qa=QA, extra=extra)
        return payload, seed, controls

    def store(self, name, seed, controls, fr, gqa, seconds=0.0):
        """Enregistre le résultat d'une animation ; renvoie la liste des défauts."""
        n = len(controls)
        errs = pieces.qa_errors(gqa, QA) if len(fr) == n else [f"{len(fr)} images au lieu de {n}"]
        done, verdicts = self.state()
        if len(fr) == n:
            path = os.path.join(self.pd, f"{name}_m{seed}.png")
            strip(fr).save(path)
            strip(controls).save(os.path.join(self.pd, f"{name}_m{seed}_ctl.png"))
            done[name] = path
            verdicts[name] = "OK" if not errs else "À REVOIR : " + " ; ".join(errs)
            json.dump(done, open(self.reg_path, "w"), indent=1)
            json.dump(verdicts, open(self.ok_path, "w"), indent=1, ensure_ascii=False)
        with open(self.log_path, "a") as fh:
            fh.write(json.dumps({"anim": name, "outil": "pixelforge depuis le mannequin (refait entièrement)",
                                 "graine": seed, "defauts": errs, "essais": gqa.get("attempts"),
                                 "tournees": gqa.get("rotated"), "boules": gqa.get("tucked"),
                                 "secondes": round(seconds, 1)}, ensure_ascii=False) + "\n")
        return errs

    def report(self):
        done, verdicts = self.state()
        print("planche :", pf.contact_sheet(self.fid, done, verdicts))
        bad = [k for k, v in verdicts.items() if v != "OK"]
        print(f"réussis : {len(verdicts) - len(bad)}/{len(verdicts)}" + (f" ; à revoir : {', '.join(bad)}" if bad else ""))


def main():
    fid = sys.argv[1]
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    job = Perso(fid, opt("--essais", 3), opt("--graine", 0))
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.lstrip("-").isdigit()] or list(animate.ANIM_ORDER)
    done, verdicts = job.state()
    for name in names:
        if verdicts.get(name) == "OK" and name in done and "--refaire" not in sys.argv:
            print(f"{name}: déjà réussi, gardé")
            continue
        payload, seed, controls = job.prepare(name)
        t = time.time()
        fr, gqa = [], {}
        for tries in range(3):
            pf.wait_ready()
            try:
                r = pf._post_json(pf.PF + "/v1/inferences", payload, timeout=7200)
                fr, gqa = pieces.guided_parse(r, controls[0].size, len(controls))
                break
            except Exception as e:
                print(f"{name}: erreur {e}", flush=True)
        errs = job.store(name, seed, controls, fr, gqa, time.time() - t)
        print(f"{name} ({time.time() - t:.0f} s): {'OK' if not errs else ' ; '.join(errs)}", flush=True)
    job.report()


if __name__ == "__main__":
    main()
