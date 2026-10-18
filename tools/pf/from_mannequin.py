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
Usage : from_mannequin.py <id> [anim …] [--essais 3] [--graine D] [--refaire] [--sec]
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

CELL = pieces.CELL
FOOT = (80, 152)
TILT = 40            # au-delà (degrés d'inclinaison du buste), le contrôle est rendu corps droit
CANVAS = (CELL * 2, CELL * 2)
ROOTPOS = (float(CELL), CELL * 150.0 / 128.0)
QA = dict(pieces.QA, max_drift=0.45)
# Accessoire du rig RD abandonné par le nouveau design (bouée de Txomin → palmes).
NO_RD_ACC = {"txomin"}
# Accessoires dessinés accrochés au bassin : (image, point d'accroche dans l'image,
# décalage du point depuis le bassin du mannequin, à l'échelle du modèle, devant le
# corps ?). Palmes de Txomin pendues à la ceinture côté visible : tools/pf/draw_palme.py.
HIP_ACC = {"txomin": ("tools/rd/out/txomin/palmes_ceinture.png", (16, 1), (-8, -3), True)}


def out_dir(fid):
    return os.path.join(ROOT, "tools", "rd", "out", fid)


def model(fid):
    """Modèle propre sans accessoire (model_sans_acc.py) ou pose RD d'origine."""
    p = os.path.join(out_dir(fid), "modele_sans_acc.png")
    if os.path.exists(p):
        return Image.open(p).convert("RGBA")
    import from_rig
    return from_rig.model(fid)


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


def centroid(im):
    a = np.array(im)[..., 3] > 127
    ys, xs = np.nonzero(a)
    return (xs.mean(), ys.mean()) if len(xs) else (CELL / 2, CELL / 2)


def iou(a, b):
    a, b = np.array(a)[..., 3] > 127, np.array(b)[..., 3] > 127
    return (a & b).sum() / max((a | b).sum(), 1)


def rotsprite(im, angle, center):
    """Rotation propre d'un sprite RGBA (méthode du rig : ×8 par scale2x, rotation,
    vote ×8 → 1) autour de `center` ; pas de dents de scie du plus proche voisin."""
    import rig as rigmod
    a = np.array(im)
    op = a[..., 3] > 127
    cols, inv = np.unique(a[op][:, :3], axis=0, return_inverse=True)
    idx = np.zeros(op.shape, np.uint8)
    idx[op] = (inv.reshape(-1) % 254) + 1
    pc = rigmod.Piece(img=idx, pivot=(center[0], center[1]), shade=False)
    r = rigmod.Rig([], {"s": pc}, [], {})
    layer, x0, y0 = r.render_piece("s", pc, angle, (center[0], center[1]), (1.0, 1.0))
    out = np.zeros((CELL, CELL, 4), np.uint8)
    if layer is None:
        return Image.fromarray(out)
    lut = np.zeros((256, 4), np.uint8)
    lut[1:len(cols) + 1, :3] = cols[:255]
    lut[1:len(cols) + 1, 3] = 255
    rgba = lut[layer]
    h, w = layer.shape
    ys, xs = slice(max(0, y0), min(CELL, y0 + h)), slice(max(0, x0), min(CELL, x0 + w))
    src = rgba[ys.start - y0:ys.stop - y0, xs.start - x0:xs.stop - x0]
    out[ys, xs] = src
    return Image.fromarray(out)


def turn(drawn, upright_ctrl, target_ctrl, angle):
    """Perso redessiné droit → tourné comme le contrôle d'origine (sens choisi par
    recouvrement), centroïde recalé sur celui de la silhouette cible."""
    best = None
    for sgn in (1, -1):
        c = rotsprite(upright_ctrl, sgn * angle, centroid(upright_ctrl))
        sc = iou_shift(c, target_ctrl)
        if best is None or sc[0] > best[0]:
            best = (sc[0], sgn, sc[1])
    _, sgn, (dx, dy) = best
    r = rotsprite(drawn, sgn * angle, centroid(upright_ctrl))
    out = Image.new("RGBA", (CELL, CELL))
    out.paste(r, (round(dx), round(dy)), r)
    return out


def iou_shift(c, target):
    cx, cy = centroid(c)
    tx, ty = centroid(target)
    dx, dy = tx - cx, ty - cy
    moved = Image.new("RGBA", (CELL, CELL))
    moved.paste(c, (round(dx), round(dy)), c)
    return iou(moved, target), (dx, dy)


class Accessory:
    """Accessoire découpé dans le modèle propre (pièce du rig RD) et posé sur la main
    du mannequin : position de l'os du mannequin, angle de l'os du rig RD (même pose)."""

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
        self.pal = load(fid)[3]
        self.man = man

    def layer(self, pose, rd_pose, tf):
        """Accessoire seul (RGBA, case de 160) pour une pose du mannequin."""
        s, tx, ty = tf
        man_solved = self.man.rig.solve(pose, ROOTPOS)
        # l'os d'accessoire du mannequin n'est plus dessiné mais reste dans la cinématique
        pos, _, _ = man_solved[self.man_bone]
        _, ang, st = self.rd.solve(rd_pose, ROOTPOS)[self.rd_bone.name]
        piece = self.rd.pieces[self.rd_bone.piece]
        cell_pos = (pos[0] * s + tx, pos[1] * s + ty)
        img, x0, y0 = self.rd.render_piece(self.rd_bone.piece, piece, ang, cell_pos, st)
        out = Image.new("RGBA", (CELL, CELL))
        if img is None:
            return out
        img = rd_rig_outline(img)
        out.paste(Image.fromarray(self.pal[img].astype(np.uint8), "RGBA"), (x0, y0))
        return out


def rd_rig_outline(layer):
    import rig as rigmod
    return rigmod.add_outline(layer)


def hip_layer(fid, man, pose, tf):
    """Accessoire accroché au bassin (palmes de Txomin), tourné avec le bassin."""
    path, grip, off, _ = HIP_ACC[fid]
    im = Image.open(os.path.join(ROOT, path)).convert("RGBA")
    s, tx, ty = tf
    pos, ang, _ = man.rig.solve(pose, ROOTPOS)["pel"]
    px_, py_ = pos[0] * s + tx, pos[1] * s + ty
    import rig as rigmod
    ox, oy = rigmod.rotate(off, ang)
    big = Image.new("RGBA", (CELL, CELL))
    big.paste(im, (round(px_ + ox - grip[0]), round(py_ + oy - grip[1])), im)
    if abs(ang) < 1:
        return big
    return rotsprite(big, ang, (px_ + ox, py_ + oy))


def tuck_sprite(fid, ctrl):
    """Position groupée d'un salto : la boule dessinée une fois par Kontext
    (tools/rd/out/<id>/boule.png) mise à la hauteur du contrôle, centrée dessus ;
    le guidé rate les jambes repliées (lambeaux). None si pas de boule."""
    p = os.path.join(out_dir(fid), "boule.png")
    if not os.path.exists(p):
        return None
    b = Image.open(p).convert("RGBA")
    bb = ctrl.getbbox()
    h = bb[3] - bb[1]
    b = b.resize((max(1, round(b.width * h / b.height)), h), Image.NEAREST)
    cx, cy = centroid(ctrl)
    out = Image.new("RGBA", (CELL, CELL))
    out.paste(b, (round(cx - b.width / 2), round(cy - b.height / 2)), b)
    return out


def compose(body, acc, front):
    if acc is None:
        return body
    out = Image.new("RGBA", (CELL, CELL))
    if front:
        out.alpha_composite(body)
        out.alpha_composite(acc)
    else:
        out.alpha_composite(acc)
        out.alpha_composite(body)
    return out


def main():
    fid = sys.argv[1]
    od = out_dir(fid)
    pd = os.path.join(od, "pf")
    os.makedirs(pd, exist_ok=True)
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    retries, shift = opt("--essais", 3), opt("--graine", 0)
    ref = model(fid)
    man = Mannequin(fid)
    IDLE_MID[0] = man.idle_mid
    mh = ref.getbbox()
    scale = (mh[3] - mh[1]) / man.height
    acc = Accessory(fid, man)
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.lstrip("-").isdigit()] or list(animate.ANIM_ORDER)
    s = fiche.load(fid) if fiche.exists(fid) else {}
    look = (s.get("apparence") or fid).strip()
    keep_txt = "same character, same face, same colors, side view facing right, clean pixel art, no weapon, no object, no effects"
    reg_path, ok_path, log_path = (os.path.join(od, "anims.json"), os.path.join(pd, "verdicts.json"),
                                   os.path.join(od, "gen_log.jsonl"))
    done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    verdicts = json.load(open(ok_path)) if os.path.exists(ok_path) else {}
    for name in names:
        if verdicts.get(name) == "OK" and name in done and "--refaire" not in sys.argv:
            print(f"{name}: déjà réussi, gardé")
            continue
        poses = man.expand(name)
        rd_poses = animate.expand(acc.rd_poses["anims"][name], acc.rd_poses["named"], man.amp) if acc.ok else poses
        targets, controls, turned, tfs = [], [], [], []
        for p in poses:
            full = man.rgba(man.rig.render(p, CANVAS, ROOTPOS))
            cell, tf = place(full, name, scale)
            targets.append(cell)
            tfs.append(tf)
            # inclinaison du buste dans le monde (bassin + buste) : couché, salto…
            ang = float(man.rig.solve(p, ROOTPOS)["tor"][1])
            if abs(ang) > TILT:
                q = dict(p)
                q["pel"] = float(p.get("pel", 0.0)) - ang
                up, _ = place(man.rgba(man.rig.render(q, CANVAS, ROOTPOS)), name, scale)
                controls.append(up)
                turned.append(ang)
            else:
                controls.append(cell)
                turned.append(None)
        seed = int(hashlib.sha1(f"{fid}:{name}:mannequin".encode()).hexdigest()[:6], 16) + shift
        lora = None
        t = time.time()
        fr, gqa = [], {}
        for tries in range(0 if "--sec" in sys.argv else 3):     # --sec : sans serveur (contrôle redessiné = contrôle)
            pf.wait_ready()
            try:
                fr, gqa = pieces.guided_server(ref, controls, f"{look}, {name.replace('_', ' ')}, {keep_txt}", seed,
                                               lora, clean=True, retries=retries, qa=QA)
                break
            except Exception as e:
                print(f"{name}: erreur {e}", flush=True)
        if "--sec" in sys.argv:
            fr = [c.copy() for c in controls]
        n = len(poses)
        errs = pieces.qa_errors(gqa, QA) if len(fr) == n else [f"{len(fr)} images au lieu de {n}"]
        if len(fr) == n:
            out = []
            for i, f in enumerate(fr):
                if turned[i] is not None and name in animate.AIR_ANIMS:
                    f = tuck_sprite(fid, controls[i]) or f      # salto : la boule tourne
                body = turn(f, controls[i], targets[i], abs(turned[i])) if turned[i] is not None else f
                a = acc.layer(poses[i], rd_poses[i], tfs[i]) if acc.ok else None
                body = compose(body, a, acc.front if acc.ok else True)
                if fid in HIP_ACC:
                    body = compose(body, hip_layer(fid, man, poses[i], tfs[i]), HIP_ACC[fid][3])
                out.append(body)
            path = os.path.join(pd, f"{name}_m{seed}.png")
            pieces.strip(out).save(path)
            pieces.strip(controls).save(os.path.join(pd, f"{name}_m{seed}_ctl.png"))
            done[name] = path
            verdicts[name] = "OK" if not errs else "À REVOIR : " + " ; ".join(errs)
            json.dump(done, open(reg_path, "w"), indent=1)
            json.dump(verdicts, open(ok_path, "w"), indent=1, ensure_ascii=False)
        with open(log_path, "a") as fh:
            fh.write(json.dumps({"anim": name, "outil": "pixelforge depuis le mannequin (refait entièrement)",
                                 "graine": seed, "defauts": errs, "essais": gqa.get("attempts"),
                                 "tournees": sum(1 for x in turned if x is not None),
                                 "secondes": round(time.time() - t, 1)}, ensure_ascii=False) + "\n")
        print(f"{name} ({time.time() - t:.0f} s): {'OK' if not errs else ' ; '.join(errs)}", flush=True)
    print("planche :", pf.contact_sheet(fid, done, verdicts))
    bad = [k for k, v in verdicts.items() if v != "OK"]
    print(f"réussis : {len(verdicts) - len(bad)}/{len(verdicts)}" + (f" ; à revoir : {', '.join(bad)}" if bad else ""))


if __name__ == "__main__":
    main()
