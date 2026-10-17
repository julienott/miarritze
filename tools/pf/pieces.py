#!/usr/bin/env python3
"""Animation par morceaux redessinée par pixelforge (méthode validée le 2026-10-17).

Le perso (tools/rd/out/<id>/neutral_160.png) est découpé en pièces décrites
dans tools/pf/choreo/<id>.py (masques, pivots, ordre de dessin) ; chaque
mouvement y est une suite de poses clés (rotation, décalage, échelle par
pièce), interpolées sur le nombre d'images de la fiche. Deux rendus :
  « guide »  : silhouettes sombres sur fond blanc envoyées à pf_anim__guided
               (Wan 2.2 Fun Control 14B) qui redessine le perso ;
  « pieces » : les pièces elles-mêmes (grosses rotations : le guidé perd le
               visage quand le perso est retourné).
Un rendu guidé est rejeté (puis relancé avec une autre graine) si l'identité
dérive, si la silhouette ne suit pas le contrôle, ou sur les contrôles de
gen_anims_pf (objet étranger, change de perso). Après les essais, on retombe
sur le rendu des pièces.
Sorties identiques à gen_anims_pf.py : tools/rd/out/<id>/pf/<anim>_*.png,
anims.json, gen_log.jsonl, pf/verdicts.json, planche tests/out/pf/<id>.png ;
plus la planche des contrôles tests/out/pf/<id>_pieces.png.
Usage : pieces.py <id> [anim …] [--essais N] [--graine D] [--refaire] [--controle]
  (--controle : planche des pièces seulement, aucun appel pixelforge)
"""
import base64
import hashlib
import importlib
import io
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402

ga, fiche = pf.ga, pf.fiche
CELL = pf.CELL
DRIFT_MAX = 0.25    # identity_drift renvoyé par le guidé (coup de pince 0,13 ; chute retournée 0,34)
FOLLOW_MIN = 0.72   # recouvrement minimal silhouette rendue / contrôle (IoU)
LOOSE_MAX = 12      # pixels détachés tolérés en plus de ceux du contrôle
KEYS = ("rot", "dx", "dy", "sx", "sy")


# --- pièces ---------------------------------------------------------------
class Rig:
    def __init__(self, fid, ch):
        self.img = Image.open(os.path.join(ga.out_dir(fid), "neutral_160.png")).convert("RGBA")
        a = np.array(self.img)
        yy, xx = np.mgrid[:CELL, :CELL]
        masks = ch.masks(a[..., 3] > 0, xx, yy)
        self.pieces = {k: Image.fromarray(np.where(m[..., None], a, 0).astype(np.uint8), "RGBA")
                       for k, m in masks.items()}
        self.pivot, self.order, self.ground_parts = ch.PIVOTS, ch.ORDER, ch.GROUND_PARTS
        self.ground = ch.GROUND
        self.arms = getattr(ch, "ARMS", {})      # {pièce: (épaule sur le corps, largeur, couleur)}

    def piece(self, k, rot=0.0, dx=0.0, dy=0.0, sx=1.0, sy=1.0):
        """rot en degrés (sens horaire à l'écran) autour du pivot ; échelle autour du pivot."""
        im, (px, py) = self.pieces[k], self.pivot[k]
        if sx != 1.0 or sy != 1.0:
            w, h = max(1, round(CELL * sx)), max(1, round(CELL * sy))
            c = Image.new("RGBA", (CELL, CELL))
            c.paste(im.resize((w, h), Image.NEAREST), (round(px - px * sx), round(py - py * sy)))
            im = c
        if rot:
            im = im.rotate(-rot, resample=Image.NEAREST, center=(px, py))
        if dx or dy:
            c = Image.new("RGBA", (CELL, CELL))
            c.paste(im, (round(dx), round(dy)), im)
            im = c
        return im

    def render(self, pose):
        """pose : {pièce: {rot, dx, dy, sx, sy}, 'all': {dx, dy}, 'tilt': deg,
        'air': px au-dessus du sol, 'order': [...], 'sink': px sous le sol (coupé)}."""
        big = Image.new("RGBA", (3 * CELL, 3 * CELL))
        feet = Image.new("RGBA", (3 * CELL, 3 * CELL))
        g = pose.get("all", {})
        # bras : relie l'épaule (fixe sur le corps) au pivot déplacé de la pince
        from PIL import ImageDraw
        dr = ImageDraw.Draw(big)
        for k, (sh, w, col) in self.arms.items():
            t = pose.get(k, {})
            ddx, ddy = t.get("dx", 0), t.get("dy", 0)
            bt = pose.get("body", {})
            a = (sh[0] + CELL + g.get("dx", 0) + bt.get("dx", 0), sh[1] + CELL + g.get("dy", 0) + bt.get("dy", 0))
            b = (self.pivot[k][0] + CELL + g.get("dx", 0) + ddx, self.pivot[k][1] + CELL + g.get("dy", 0) + ddy)
            dr.line([a, b], fill=(58, 38, 52, 255), width=w + 2)
            dr.line([a, b], fill=col + (255,), width=w)
        for k in pose.get("order", self.order):
            t = {key: v for key, v in pose.get(k, {}).items() if key in KEYS}
            t["dx"] = t.get("dx", 0) + g.get("dx", 0)
            t["dy"] = t.get("dy", 0) + g.get("dy", 0)
            p = self.piece(k, **t)
            big.alpha_composite(p, (CELL, CELL))
            if k in self.ground_parts:
                feet.alpha_composite(p, (CELL, CELL))
        tilt = pose.get("tilt", 0)
        if tilt:
            c = tuple(v + CELL for v in pose.get("tilt_pivot", (77, self.ground)))
            big = big.rotate(-tilt, resample=Image.NEAREST, center=c)
            # recentré sur l'axe du corps : la rotation déporte le perso (pinces coupées au bord)
            bb = big.getbbox()
            if bb:
                want = CELL + self.pivot["body"][0] + g.get("dx", 0)
                shift = round(want - (bb[0] + bb[2]) / 2)
                shift = max(CELL - bb[0] - CELL, min(shift, 2 * CELL - bb[2]))
                moved = Image.new("RGBA", big.size)
                moved.paste(big, (shift, 0), big)
                big = moved
            feet = big   # retourné : c'est le bas du perso entier qui touche le sol
        fb = feet.getbbox() or big.getbbox()
        # pieds au sol, puis élévation ; abscisse : celle de la pose (pas de recentrage)
        oy = self.ground - (fb[3] - CELL) - round(pose.get("air", 0)) + round(pose.get("sink", 0))
        out = seal(big.crop((CELL, CELL - oy, 2 * CELL, 2 * CELL - oy)))
        if pose.get("sink"):
            a = np.array(out)
            a[self.ground:, :, 3] = 0
            out = Image.fromarray(a)
        return out


def seal(im, passes=2):
    """Bouche les fentes d'un pixel entre pièces (pixel vide entre deux pleins, en ligne ou en colonne)."""
    a = np.array(im)
    for _ in range(passes):
        op = a[..., 3] > 0
        h = np.zeros_like(op)
        v = np.zeros_like(op)
        h[:, 1:-1] = op[:, :-2] & op[:, 2:] & ~op[:, 1:-1]
        v[1:-1, :] = op[:-2, :] & op[2:, :] & ~op[1:-1, :]
        if not (h.any() or v.any()):
            break
        src = np.roll(a, 1, axis=1)
        a[h] = src[h]
        src = np.roll(a, 1, axis=0)
        a[v & ~h] = src[v & ~h]
    return Image.fromarray(a)


def silhouette(im):
    m = np.array(im)[..., 3] > 0
    s = np.full((CELL, CELL, 3), 255, np.uint8)
    s[m] = 30
    return Image.fromarray(s, "RGB")


# --- poses clés -------------------------------------------------------------
def _lerp(a, b, u, key=""):
    if isinstance(a, dict) or isinstance(b, dict):
        a, b = a or {}, b or {}
        return {k: _lerp(a.get(k), b.get(k), u, k) for k in set(a) | set(b)}
    if isinstance(a, (list, tuple, str)) or isinstance(b, (list, tuple, str)):
        return a if (u < 0.5 and a is not None) or b is None else b
    rest = 1.0 if key in ("sx", "sy") else 0.0   # valeur d'une clé absente
    a = rest if a is None else a
    b = rest if b is None else b
    return a + (b - a) * u


def tween(n, keys):
    """keys : {image: pose} (indices entiers ; la dernière clé est tenue) → n poses."""
    idx = sorted(keys)
    out = []
    for i in range(n):
        if i <= idx[0]:
            out.append(keys[idx[0]])
            continue
        if i >= idx[-1]:
            out.append(keys[idx[-1]])
            continue
        j = max(k for k in idx if k <= i)
        k = min(k for k in idx if k > i)
        out.append(_lerp(keys[j], keys[k], (i - j) / (k - j)))
    return out


# --- pixelforge -------------------------------------------------------------
def b64(im):
    b = io.BytesIO()
    im.save(b, "PNG")
    return base64.b64encode(b.getvalue()).decode()


CHUNK = 8   # ancien découpage (avant le 2026-10-17 la planche passait sur 2 lignes au-delà de 8)

# Seuils de la QA serveur (pixelforge, guided_qa) ; relances faites par le serveur.
QA = {"min_iou": 0.72, "max_drift": 0.25, "max_detached": 12, "max_foreign": 220}


def guided_server(ref, controls, prompt, seed, lora=None, clean=False, keep_frames=None, keep_masks=None,
                  retries=3, qa=None):
    """Un seul appel pf_anim__guided : une image par contrôle (planche sur une ligne),
    fond enfermé retiré, contrôle nettoyé (clean : sprite couleur → silhouette),
    accessoires recollés (keep_frames/keep_masks), relances serveur avec seuils.
    Renvoie (images, guided_qa)."""
    p = {"prompt_style": "pf_anim__guided", "input_image": b64(ref),
         "control_frames": [b64(c) for c in controls], "prompt": prompt, "seed": seed,
         "return_spritesheet": True, "sheet_cols": len(controls), "control_clean": clean,
         "retries": retries, **(qa or QA)}
    if lora:
        p["sprite_lora"] = lora
    if keep_masks:
        p["keep_masks"] = [b64(m) for m in keep_masks]
        if keep_frames:
            p["keep_frames"] = [b64(f) for f in keep_frames]
    r = pf._post_json(pf.PF + "/v1/inferences", p, timeout=7200)
    sheet = Image.open(io.BytesIO(base64.b64decode(r["base64_images"][0]))).convert("RGBA")
    info = r.get("pixelforge", {}).get("info", {})
    w, h = controls[0].size
    frames = [sheet.crop((i * w, 0, (i + 1) * w, h)) for i in range(sheet.width // w)][:len(controls)]
    return frames, info.get("guided_qa", {})


def qa_errors(gqa):
    """Défauts lisibles d'après guided_qa (essai retenu)."""
    pf_ = gqa.get("per_frame") or []
    if not pf_:
        return []
    errs = []
    iou = min(f.get("iou", 1) for f in pf_)
    drift = max(f.get("drift", 0) for f in pf_)
    det = max(f.get("detached_px", 0) for f in pf_)
    fo = max(f.get("foreign_px", 0) for f in pf_)
    extra = max(f.get("extra_area_vs_control", 0) for f in pf_)
    if iou < QA["min_iou"]:
        errs.append(f"ne suit pas le contrôle ({iou:.0%})")
    if drift > QA["max_drift"]:
        errs.append(f"identité qui dérive ({drift:.2f})")
    if det > QA["max_detached"]:
        errs.append(f"morceaux détachés ({det} px)")
    if fo > QA["max_foreign"]:
        errs.append(f"objet étranger ({fo} px)")
    if extra > 0.15:
        errs.append(f"silhouette débordante, fantôme ? ({extra:.0%})")
    return errs


def guided(rig, controls, prompt, seed, lora=None):
    """Par morceaux de CHUNK images ; dérive = la pire des morceaux."""
    frames, drift = [], 0.0
    for k in range(0, len(controls), CHUNK):
        f, d = _guided(rig, controls[k:k + CHUNK], prompt, seed, lora)
        frames += f[:len(controls[k:k + CHUNK])]
        drift = max(drift, d)
    return frames, drift


def _guided(rig, controls, prompt, seed, lora=None):
    p = {"prompt_style": "pf_anim__guided", "input_image": b64(rig.img),
         "control_frames": [b64(silhouette(c)) for c in controls],
         "prompt": prompt, "seed": seed, "return_spritesheet": True}
    if lora:
        p["sprite_lora"] = lora
    r = pf._post_json(pf.PF + "/v1/inferences", p, timeout=3600)
    sheet = Image.open(io.BytesIO(base64.b64decode(r["base64_images"][0]))).convert("RGBA")
    info = r.get("pixelforge", {}).get("info", {})
    frames = [sheet.crop((i * CELL, 0, (i + 1) * CELL, CELL)) for i in range(sheet.width // CELL)]
    return frames, info.get("guided_qa", {}).get("identity_drift", 0.0)


def loose(frames):
    """Pixels hors de la plus grande composante (débris détachés), pire image."""
    worst = 0
    for f in frames:
        m = np.array(f)[..., 3] > 127
        lab = np.zeros(m.shape, int)
        sizes = []
        for sy, sx in zip(*np.nonzero(m)):
            if lab[sy, sx]:
                continue
            sizes.append(0)
            stack = [(sy, sx)]
            lab[sy, sx] = len(sizes)
            while stack:
                y, x = stack.pop()
                sizes[-1] += 1
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = len(sizes)
                        stack.append((ny, nx))
        worst = max(worst, sum(sizes) - max(sizes, default=0))
    return worst


def unfill(frames, controls):
    """Fond blanc enfermé entre les pattes (le détourage du guidé part des bords) :
    pixel presque blanc là où le contrôle est vide → transparent."""
    out = []
    for f, c in zip(frames, controls):
        a = np.array(f)
        empty = np.array(c)[..., 3] == 0
        white = (a[..., :3].min(-1) > 225) & (a[..., 3] > 0)
        a[white & empty] = 0
        out.append(Image.fromarray(a))
    return out + frames[len(out):]


def follow(frames, controls):
    """Plus mauvais recouvrement (IoU) entre la silhouette rendue et le contrôle."""
    worst = 1.0
    for f, c in zip(frames, controls):
        a, b = np.array(f)[..., 3] > 127, np.array(c)[..., 3] > 0
        worst = min(worst, (a & b).sum() / max((a | b).sum(), 1))
    return worst


def strip(frames):
    s = Image.new("RGBA", (CELL * len(frames), CELL))
    for i, f in enumerate(frames):
        s.paste(f, (i * CELL, 0))
    return s


def control_sheet(fid, rows):
    from PIL import ImageDraw, ImageFont
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf"), 10)
    W = Image.new("RGB", (12 * 124 + 4, 148 * len(rows)), (60, 50, 70))
    for r, (name, mode, frames) in enumerate(rows):
        ImageDraw.Draw(W).text((4, r * 148 + 4), f"{name} ({mode})", font=font, fill=(240, 230, 200))
        for i, f in enumerate(frames[:12]):
            bg = Image.new("RGBA", f.size, (214, 236, 246, 255))
            bg.alpha_composite(f)
            W.paste(bg.convert("RGB").resize((120, 120), Image.NEAREST), (4 + i * 124, r * 148 + 22))
    p = os.path.join(ROOT, "tests", "out", "pf", f"{fid}_pieces.png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    W.save(p)
    return p


def main():
    fid = sys.argv[1]
    ch = importlib.import_module(f"choreo.{fid}")
    rig = Rig(fid, ch)
    mv = fiche.moves(fid)
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.isdigit()] or [m for m in mv if m in ch.MOVES]
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    retries = opt("--essais", 3)
    shift = opt("--graine", 0)    # décalage des graines (refaire un rendu jugé moyen à l'œil)
    od = ga.out_dir(fid)
    pd = os.path.join(od, "pf")
    os.makedirs(pd, exist_ok=True)
    reg_path, log_path, ok_path = os.path.join(od, "anims.json"), os.path.join(od, "gen_log.jsonl"), os.path.join(pd, "verdicts.json")
    done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    verdicts = json.load(open(ok_path)) if os.path.exists(ok_path) else {}
    rows = []
    for name in names:
        n = mv[name][1]
        m = ch.MOVES[name]
        controls = [rig.render(p) for p in tween(n, m["keys"])]
        rows.append((name, m["mode"], controls))
        if "--controle" in sys.argv:
            continue
        if name in done and "/pf/" in done[name] and verdicts.get(name) == "OK" and "--refaire" not in sys.argv:
            print(f"{name}: déjà réussi, gardé")
            continue
        best, errs = None, []
        if m["mode"] == "guide":
            prompt = f"{m['prompt']}, {ch.KEEP}"
            for attempt in range(retries + 1):
                seed = int(hashlib.sha1(f"{fid}:{name}:guide".encode()).hexdigest()[:6], 16) + attempt + shift
                t = time.time()
                pf.wait_ready()
                try:
                    frames, drift = guided(rig, controls, prompt, seed, m.get("lora"))
                except Exception as e:  # service coupé : on attend et on recommence
                    print(f"{name} essai {attempt}: erreur {e}", flush=True)
                    continue
                frames = unfill(frames[:n], controls)
                fol = follow(frames, controls)
                errs = pf.wan_checks(frames, keys=True)
                lo, lo_ref = loose(frames), loose(controls)
                if lo > lo_ref + LOOSE_MAX:
                    errs.append(f"morceaux détachés ({lo} px)")
                if len(frames) < n:
                    errs.append(f"{len(frames)} images au lieu de {n}")
                if drift > DRIFT_MAX:
                    errs.append(f"identité qui dérive ({drift:.2f})")
                if fol < FOLLOW_MIN:
                    errs.append(f"ne suit pas le contrôle (recouvrement {fol:.0%})")
                path = os.path.join(pd, f"{name}_g{seed}.png")
                strip(frames).save(path)
                with open(log_path, "a") as fh:
                    fh.write(json.dumps({"anim": name, "outil": "pixelforge guidé", "essai": attempt, "graine": seed,
                                         "fichier": path, "defauts": errs, "derive": drift, "suivi": round(fol, 3),
                                         "secondes": round(time.time() - t, 1)}, ensure_ascii=False) + "\n")
                print(f"{name} essai {attempt} (graine {seed}, {time.time() - t:.0f} s, dérive {drift:.2f}, "
                      f"suivi {fol:.0%}): {'OK' if not errs else ' ; '.join(errs)}", flush=True)
                if not errs:
                    best = path
                    break
        if best is None:   # pièces seules (choisi, ou guidé raté)
            best = os.path.join(pd, f"{name}_pieces.png")
            strip(controls).save(best)
            why = "" if m["mode"] == "pieces" else " (guidé raté : " + " ; ".join(errs) + ")"
            print(f"{name}: rendu des pièces{why}", flush=True)
        done[name] = best
        verdicts[name] = "OK"
        json.dump(done, open(reg_path, "w"), indent=1)
        json.dump(verdicts, open(ok_path, "w"), indent=1, ensure_ascii=False)
    print("contrôles :", control_sheet(fid, rows))
    if "--controle" not in sys.argv:
        print("planche :", pf.contact_sheet(fid, done, verdicts))


if __name__ == "__main__":
    main()
