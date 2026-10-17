#!/usr/bin/env python3
"""Redessine la feuille existante d'un combattant avec pixelforge (guidé).

Les images actuelles du jeu (assets/fighters/<id>/sheet.png, rig découpé)
servent de silhouettes de contrôle à pf_anim__guided ; la référence
d'identité est la première image de l'attente. Le rendu suit exactement la
silhouette d'origine : les hitboxes et le calage (anims.json) restent valides.
Chaque animation passe les contrôles de pieces.py (identité, suivi du
contrôle, objet étranger) ; ratée après les essais, l'image d'origine reste.
Le résultat est réindexé sur la palette du perso (costumes intacts).
Sorties : tools/rd/out/<id>/redraw/sheet.png (candidate, mode L),
journal redraw.jsonl, planche avant/après tests/out/pf/<id>_redraw.png.
Usage : redraw.py <id> [anim …] [--essais N] [--installer]
  (--installer : copie la feuille candidate dans assets/fighters/<id>/)
"""
import hashlib
import json
import os
import shutil
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402
import pieces  # noqa: E402

MIN_FRAMES = 5   # le guidé travaille mal sur 2-3 images : on complète en répétant la dernière
KEEP = ("same character, same face, same clothes, same colors, side view facing right, "
        "clean pixel art, no weapon, no object, no effects")


def load(fid):
    d = os.path.join(ROOT, "assets", "fighters", fid)
    meta = json.load(open(os.path.join(d, "anims.json")))
    data = json.load(open(os.path.join(d, "data.json")))
    idx = np.array(Image.open(os.path.join(d, "sheet.png")))
    pal = np.array(Image.open(os.path.join(d, "palettes.png")).convert("RGBA"))[0]
    return meta, data, idx, pal


def cell_box(meta, k):
    c, cols = meta["cell"], meta["cols"]
    return (k % cols) * c, (k // cols) * c


def frames(meta, idx, pal, anim):
    a, c = meta["anims"][anim], meta["cell"]
    out = []
    for k in range(a["first"], a["first"] + a["frames"]):
        x, y = cell_box(meta, k)
        out.append(Image.fromarray(pal[idx[y:y + c, x:x + c]].astype(np.uint8), "RGBA"))
    return out


def reindex(im, pal):
    """RGBA → index de palette (couleur la plus proche ; 0 = transparent)."""
    a = np.array(im).astype(int)
    op = a[..., 3] > 127
    cols = pal[1:, :3].astype(int)
    d = ((a[..., None, :3] - cols[None, None]) ** 2).sum(-1)
    out = (d.argmin(-1) + 1).astype(np.uint8)
    out[~op] = 0
    return out


def run_guided(ref, controls, prompt, seed, lora):
    """Comme pieces.guided, à la taille de la case (le guidé accepte jusqu'à 384)."""
    import base64
    import io
    def sil(im):
        m = np.array(im)[..., 3] > 0
        s = np.full(m.shape + (3,), 255, np.uint8)
        s[m] = 30
        return Image.fromarray(s, "RGB")
    p = {"prompt_style": "pf_anim__guided", "input_image": pieces.b64(ref),
         "control_frames": [pieces.b64(sil(c)) for c in controls],
         "prompt": prompt, "seed": seed, "return_spritesheet": True}
    if lora:
        p["sprite_lora"] = lora
    r = pf._post_json(pf.PF + "/v1/inferences", p, timeout=3600)
    sheet = Image.open(io.BytesIO(base64.b64decode(r["base64_images"][0]))).convert("RGBA")
    info = r.get("pixelforge", {}).get("info", {})
    w = controls[0].width
    out = [sheet.crop((i * w, j * w, (i + 1) * w, (j + 1) * w))
           for j in range(sheet.height // w) for i in range(sheet.width // w)]
    out = [f for f in out if f.getbbox()]
    return out, info.get("guided_qa", {}).get("identity_drift", 0.0)


def lora_for(anim, a):
    if anim in ("walk", "run"):
        return "walk"
    return "attack" if "hit_frame" in a else None


def follow(fr, ctl):
    worst = 1.0
    for f, c in zip(fr, ctl):
        a, b = np.array(f)[..., 3] > 127, np.array(c)[..., 3] > 0
        worst = min(worst, (a & b).sum() / max((a | b).sum(), 1))
    return worst


def odd(im):
    """Pixels gris, blancs ou bleus (objets inventés par Wan), cf. gen_anims_pf.wan_checks."""
    a = np.array(im)
    px = a[a[..., 3] > 127][:, :3].astype(float) / 255
    if not len(px):
        return 0
    mx, mn = px.max(1), px.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    return int((((px[:, 2] > px[:, 0] + 0.05) & (sat > 0.15)) | ((sat < 0.18) & (mx > 0.3))).sum())


def mean_col(im):
    a = np.array(im)
    op = a[..., 3] > 127
    return a[op][:, :3].mean(0) if op.any() else np.zeros(3)


def checks(new, old):
    """Image par image contre l'image d'origine (les habits clairs du perso ne comptent pas)."""
    errs = []
    foreign = max(odd(n) - odd(o) for n, o in zip(new, old))
    ident = max(np.abs(mean_col(n) - mean_col(o)).sum() for n, o in zip(new, old))
    if foreign > pf.FOREIGN_MAX:
        errs.append(f"objet étranger ({foreign} px gris/blancs/bleus)")
    if ident > pf.IDENT_MAX:
        errs.append(f"change de perso (couleur {ident:.0f})")
    return errs


def before_after(fid, rows):
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf"), 10)
    S = 104
    W = Image.new("RGB", (12 * (S + 4) + 4, len(rows) * (2 * S + 30)), (60, 50, 70))
    for r, (name, verdict, old, new) in enumerate(rows):
        y = r * (2 * S + 30)
        ImageDraw.Draw(W).text((4, y + 4), f"{name}  {verdict}"[:110], font=font,
                               fill=(120, 230, 120) if verdict == "OK" else (244, 198, 62))
        for line, fr in enumerate((old, new)):
            for i, f in enumerate(fr[:12]):
                bg = Image.new("RGBA", f.size, (214, 236, 246, 255))
                bg.alpha_composite(f)
                W.paste(bg.convert("RGB").resize((S, S), Image.NEAREST), (4 + i * (S + 4), y + 22 + line * (S + 2)))
    p = os.path.join(ROOT, "tests", "out", "pf", f"{fid}_redraw.png")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    W.save(p)
    return p


def main():
    fid = sys.argv[1]
    meta, data, idx, pal = load(fid)
    od = os.path.join(ROOT, "tools", "rd", "out", fid, "redraw")
    os.makedirs(od, exist_ok=True)
    out_path = os.path.join(od, "sheet.png")
    if "--installer" in sys.argv:
        dst = os.path.join(ROOT, "assets", "fighters", fid, "sheet.png")
        shutil.copy(out_path, dst)
        print("installée :", dst)
        return
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    retries = opt("--essais", 2)
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.isdigit()] or list(meta["anims"])
    new_idx = np.array(Image.open(out_path)) if os.path.exists(out_path) else idx.copy()
    ref = frames(meta, idx, pal, "idle")[0]
    who = data.get("name", fid)
    log = open(os.path.join(od, "redraw.jsonl"), "a")
    state_path = os.path.join(od, "verdicts.json")
    verdicts = json.load(open(state_path)) if os.path.exists(state_path) else {}
    rows = []
    c = meta["cell"]
    for name in names:
        a = meta["anims"][name]
        old = frames(meta, idx, pal, name)
        n = len(old)
        ctl = old + [old[-1]] * max(0, MIN_FRAMES - n)
        best, errs = None, []
        for attempt in range(retries + 1):
            seed = int(hashlib.sha1(f"{fid}:{name}:redraw".encode()).hexdigest()[:6], 16) + attempt
            t = time.time()
            pf.wait_ready()
            try:
                fr, drift = run_guided(ref, ctl, f"{who}, the cartoon fighter, {name.replace('_', ' ')}, {KEEP}", seed, lora_for(name, a))
            except Exception as e:
                print(f"{name} essai {attempt}: erreur {e}", flush=True)
                continue
            fr = fr[:n]
            if len(fr) < n:
                errs = [f"{len(fr)} images au lieu de {n}"]
            else:
                fol = follow(fr, old)
                errs = checks(fr, old)
                if drift > pieces.DRIFT_MAX:
                    errs.append(f"identité qui dérive ({drift:.2f})")
                if fol < pieces.FOLLOW_MIN:
                    errs.append(f"ne suit pas le contrôle ({fol:.0%})")
            log.write(json.dumps({"anim": name, "essai": attempt, "graine": seed, "derive": drift, "defauts": errs,
                                  "secondes": round(time.time() - t, 1)}, ensure_ascii=False) + "\n")
            log.flush()
            print(f"{name} essai {attempt} ({time.time() - t:.0f} s, dérive {drift:.2f}): {'OK' if not errs else ' ; '.join(errs)}", flush=True)
            if not errs:
                best = fr
                break
        if best:
            for k, f in zip(range(a["first"], a["first"] + n), best):
                x, y = cell_box(meta, k)
                new_idx[y:y + c, x:x + c] = reindex(f, pal)
            verdicts[name] = "OK"
        else:
            verdicts[name] = "gardé d'origine : " + " ; ".join(errs)
        Image.fromarray(new_idx, "L").save(out_path)
        json.dump(verdicts, open(state_path, "w"), indent=1, ensure_ascii=False)
        rows.append((name, verdicts[name], old, frames(meta, new_idx, pal, name)))
    print("planche :", before_after(fid, rows))
    bad = [k for k, v in verdicts.items() if v != "OK"]
    print(f"redessinées : {len(verdicts) - len(bad)}/{len(verdicts)}" + (f" ; gardées : {', '.join(bad)}" if bad else ""))


if __name__ == "__main__":
    main()
