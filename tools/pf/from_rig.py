#!/usr/bin/env python3
"""Refait les animations d'un combattant « rig découpé » à partir d'un perso propre.

Le rig découpé (source « rd ») donne de bons gestes mais un rendu abîmé
(trous, membres qui disparaissent, artefacts). Ici :
  - modèle = la pose RD d'origine du rig (propre), posée dans une case de
    160 → tools/rd/out/<id>/neutral_160.png ;
  - contrôle = la silhouette de chaque image du jeu, nettoyée (trous bouchés,
    miettes retirées, fentes scellées) ;
  - pf_anim__guided redessine le perso propre sur ces silhouettes.
Depuis le 2026-10-17 tout passe par la QA de pixelforge (un appel par
animation) : contrôle nettoyé côté serveur (control_clean), relances avec
seuils (pieces.QA : recouvrement, dérive, morceaux détachés, couleurs absentes
de la référence), accessoire recollé tel quel (keep_masks, masque d'acc_mask.py).
Le meilleur essai est gardé ; s'il rate un seuil, il est « À REVOIR » sur la planche.
Sorties comme pieces.py : tools/rd/out/<id>/pf/<anim>_r<graine>.png,
anims.json (noms du jeu), pf/verdicts.json, planche tests/out/pf/<id>.png ;
puis build_rd_anims.py <id> et build_fighter.py <id>.
Usage : from_rig.py <id> [anim …] [--essais N] [--graine D] [--refaire] [--modele] [--rig]
  (--rig : garder les images du rig d'origine pour les anims citées)
  (--modele : écrit seulement neutral_160.png)
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
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402
import pieces  # noqa: E402
import redraw  # noqa: E402

ga, fiche = pf.ga, pf.fiche
CELL = pieces.CELL
FOOT = (80, 152)            # pied du perso dans la case de 160 (comme les rigs RD)
HOLE_MAX = 40               # trou enclos bouché dans le contrôle
SPECK_MAX = 12              # miette retirée du contrôle


def model(fid):
    """Pose RD d'origine du rig, pieds en FOOT, dans une case de 160."""
    spec = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "rig.json")))
    im = Image.open(os.path.join(ROOT, spec["image"])).convert("RGBA")
    a = np.array(im)
    a[a[..., 3] < 128] = 0
    a[a[..., 3] >= 128, 3] = 255
    im = Image.fromarray(a)
    bb = im.getbbox()
    im = im.crop(bb)
    out = Image.new("RGBA", (CELL, CELL))
    out.paste(im, (FOOT[0] - im.width // 2, FOOT[1] - im.height), im)
    return out


def window(f, foot):
    """Case du jeu (taille quelconque, pied en `foot`) → case de 160, pied en FOOT."""
    out = Image.new("RGBA", (CELL, CELL))
    out.paste(f, (FOOT[0] - foot[0], FOOT[1] - foot[1]), f)
    return out


# Poses accroupies cassées dans certains rigs (bras étiré, pierre hors case chez
# Mattin) : --accroupi refait le contrôle depuis la pose debout correspondante,
# jambes écrasées à la hauteur de l'accroupi d'origine (accessoire compris).
ACCROUPI = {"crouch": "idle", "crouch_idle": "idle", "crouch_block": "block", "crouch_punch": "punch_1"}
WAIST = 0.55                # part du haut du corps gardée telle quelle


def squash(f, height):
    """Image (case de 160, pied en FOOT) → même image, jambes écrasées pour que
    le perso fasse `height` px de haut ; le haut du corps est gardé, abaissé."""
    bb = f.getbbox()
    if not bb:
        return f
    t, b = bb[1], FOOT[1]
    yw = t + int(WAIST * (b - t))
    lower = max(int(0.3 * (b - yw)), height - (yw - t))
    out = Image.new(f.mode, f.size)
    out.paste(f.crop((0, yw, f.width, b)).resize((f.width, lower), Image.NEAREST), (0, b - lower))
    up = f.crop((0, 0, f.width, yw))
    out.paste(up, (0, b - lower - yw), up if f.mode == "RGBA" else None)
    return out


def crouch_from_standing(old_target, src_frames, src_masks):
    """Contrôles (et masques d'accessoire) d'un accroupi depuis la pose debout."""
    hs = sorted(FOOT[1] - f.getbbox()[1] for f in old_target if f.getbbox())
    h = hs[len(hs) // 2]
    n = len(old_target)
    pick = [src_frames[min(len(src_frames) - 1, i * len(src_frames) // n)] for i in range(n)]
    frames = [squash(f, h) for f in pick]
    masks = None
    if src_masks:
        mk = [src_masks[min(len(src_masks) - 1, i * len(src_masks) // n)] for i in range(n)]
        masks = [squash(m, h) for m in mk]
    return frames, masks


def clean_control(f):
    a = np.array(f)
    op = a[..., 3] > 0
    # trous enclos (pas reliés au bord) bouchés
    holes = ~op
    out = np.zeros_like(op)
    stack = [(y, x) for y in (0, CELL - 1) for x in range(CELL) if holes[y, x]] + \
            [(y, x) for x in (0, CELL - 1) for y in range(CELL) if holes[y, x]]
    for p in stack:
        out[p] = True
    while stack:
        y, x = stack.pop()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < CELL and 0 <= nx < CELL and holes[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                stack.append((ny, nx))
    from despeck_sheet import comps  # noqa: E402
    for pts in comps(holes & ~out):
        if len(pts) <= HOLE_MAX:
            for p in pts:
                op[p] = True
    cs = sorted(comps(op), key=len)
    for pts in cs[:-1]:
        if len(pts) <= SPECK_MAX:
            for p in pts:
                op[p] = False
    s = np.zeros((CELL, CELL, 4), np.uint8)
    s[op] = (30, 30, 30, 255)
    return pieces.seal(Image.fromarray(s))


def main():
    sys.path.insert(0, os.path.join(ROOT, "tools", "sprites"))
    fid = sys.argv[1]
    od = ga.out_dir(fid)
    pd = os.path.join(od, "pf")
    os.makedirs(pd, exist_ok=True)
    ref = model(fid)
    ref.save(os.path.join(od, "neutral_160.png"))
    sans = os.path.join(od, "modele_sans_acc.png")      # model_sans_acc.py : pas d'accessoire fantôme
    qa = dict(pieces.QA)
    if os.path.exists(sans):
        ref = Image.open(sans).convert("RGBA")
        qa["max_drift"] = 0.45      # l'accessoire recollé n'est pas dans le modèle : dérive mesurée plus forte
    if "--rig" in sys.argv:
        # Garder les images du rig d'origine pour ces animations (pirouettes,
        # transformations : le guidé perd le perso la tête en bas).
        meta, data, idx, pal = redraw.load(fid)
        reg_path, ok_path = os.path.join(od, "anims.json"), os.path.join(pd, "verdicts.json")
        done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
        verdicts = json.load(open(ok_path)) if os.path.exists(ok_path) else {}
        for name in [a for a in sys.argv[2:] if not a.startswith("--")]:
            path = os.path.join(pd, f"{name}_rig.png")
            pieces.strip([window(f, tuple(meta["foot"])) for f in redraw.frames(meta, idx, pal, name)]).save(path)
            done[name], verdicts[name] = path, "OK (rig d'origine)"
            print(f"{name}: images du rig d'origine")
        json.dump(done, open(reg_path, "w"), indent=1)
        json.dump(verdicts, open(ok_path, "w"), indent=1, ensure_ascii=False)
        print("planche :", pf.contact_sheet(fid, done, verdicts))
        return
    if "--modele" in sys.argv:
        print("modèle :", os.path.join(od, "neutral_160.png"))
        return
    meta, data, idx, pal = redraw.load(fid)
    foot = tuple(meta["foot"])
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    retries, shift = opt("--essais", 3), opt("--graine", 0)
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.isdigit()] or list(meta["anims"])
    s = fiche.load(fid) if fiche.exists(fid) else {}
    look = (s.get("apparence") or data.get("name", fid)).strip()
    keep_txt = "same character, same face, same colors, side view facing right, clean pixel art, no weapon, no object, no effects"
    import acc_mask
    accm = acc_mask.masks(fid)
    reg_path, ok_path, log_path = (os.path.join(od, "anims.json"), os.path.join(pd, "verdicts.json"),
                                   os.path.join(od, "gen_log.jsonl"))
    done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    verdicts = json.load(open(ok_path)) if os.path.exists(ok_path) else {}
    for name in names:
        if verdicts.get(name) == "OK" and name in done and "--refaire" not in sys.argv:
            print(f"{name}: déjà réussi, gardé")
            continue
        a = meta["anims"][name]
        old = [window(f, foot) for f in redraw.frames(meta, idx, pal, name)]
        n = len(old)
        lora = redraw.lora_for(name, a)
        best = None
        seed = int(hashlib.sha1(f"{fid}:{name}:rig".encode()).hexdigest()[:6], 16) + shift
        masks = accm.get(name)
        keep = [window(Image.fromarray(np.where(m, 255, 0).astype(np.uint8)).convert("RGBA"), foot) for m in masks] \
            if masks else None
        if "--accroupi" in sys.argv and name in ACCROUPI:
            src = ACCROUPI[name]
            sm = accm.get(src)
            skeep = [window(Image.fromarray(np.where(m, 255, 0).astype(np.uint8)).convert("RGBA"), foot)
                     for m in sm] if sm else None
            old, keep = crouch_from_standing(old, [window(f, foot) for f in redraw.frames(meta, idx, pal, src)], skeep)
            seed += 7000
            pieces.strip(old).save(os.path.join(pd, f"{name}_r{seed}_ctl.png"))   # pour fix_lot.py
            if keep:
                pieces.strip(keep).save(os.path.join(pd, f"{name}_r{seed}_msk.png"))
        for tries in range(3):      # coupure du service : on attend et on recommence
            t = time.time()
            pf.wait_ready()
            try:
                # relances, nettoyage du contrôle et accessoire recollé : côté serveur (pixelforge)
                fr, gqa = pieces.guided_server(ref, old, f"{look}, {name.replace('_', ' ')}, {keep_txt}", seed, lora,
                                               clean=True, keep_frames=old if keep else None, keep_masks=keep,
                                               retries=retries, qa=qa)
                break
            except Exception as e:
                print(f"{name}: erreur {e}", flush=True)
                fr, gqa = [], {}
        errs = pieces.qa_errors(gqa, qa) if len(fr) == n else [f"{len(fr)} images au lieu de {n}"]
        path = os.path.join(pd, f"{name}_r{seed}.png")
        if len(fr) == n:
            pieces.strip(fr).save(path)
            best = (path, errs)
        with open(log_path, "a") as fh:
            fh.write(json.dumps({"anim": name, "outil": "pixelforge depuis le rig (QA serveur)", "graine": seed,
                                 "fichier": path, "defauts": errs, "essais": gqa.get("attempts"),
                                 "secondes": round(time.time() - t, 1)}, ensure_ascii=False) + "\n")
        print(f"{name} ({time.time() - t:.0f} s, {len(gqa.get('attempts') or [])} essai(s)): "
              f"{'OK' if not errs else ' ; '.join(errs)}", flush=True)
        if best:
            done[name] = best[0]
            verdicts[name] = "OK" if not best[1] else "À REVOIR : " + " ; ".join(best[1])
            json.dump(done, open(reg_path, "w"), indent=1)
            json.dump(verdicts, open(ok_path, "w"), indent=1, ensure_ascii=False)
    print("planche :", pf.contact_sheet(fid, done, verdicts))
    bad = [k for k, v in verdicts.items() if v != "OK"]
    print(f"réussis : {len(verdicts) - len(bad)}/{len(verdicts)}" + (f" ; à revoir : {', '.join(bad)}" if bad else ""))


if __name__ == "__main__":
    main()
