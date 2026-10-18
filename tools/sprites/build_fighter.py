#!/usr/bin/env python3
"""Assemble assets/fighters/<id>/data.json (SPEC §8.5).

Fusion, par ordre de priorité croissante :
  tools/fighters/_common.json  (coups normaux communs)
  anims.json du pipeline       (anims, hurtboxes, hitboxes inférées)
  tools/fighters/<id>.json     (fiche du perso, prime toujours)

Hitboxes : celles écrites dans la fiche du perso priment ; sinon la boîte
inférée du sprite (anims.json boxes.hit[anim]) ; sinon celle de _common.
Usage : build_fighter.py <id> [<id>...] | --all
"""
import copy, json, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
FIGHTERS = os.path.join(ROOT, "tools", "fighters")
ASSETS = os.path.join(ROOT, "assets", "fighters")

ANIMS = ["intro", "idle", "walk", "run", "crouch", "crouch_idle", "jump_up", "jump_fwd",
         "fall", "block", "crouch_block", "punch_1", "punch_2", "punch_3", "kick",
         "kick_high", "crouch_punch", "sweep", "uppercut", "jump_punch", "jump_kick",
         "throw", "thrown", "hit_high", "hit_low", "hit_air", "knockdown", "getup",
         "dizzy", "ko", "win", "sp_neutral", "sp_forward", "sp_down", "sp_up", "super",
         "finisher"]
DEFAULT_FRAMES = dict(intro=8, idle=8, walk=8, run=6, crouch=3, crouch_idle=4, jump_up=4,
    jump_fwd=6, fall=2, block=2, crouch_block=2, punch_1=4, punch_2=4, punch_3=6, kick=6,
    kick_high=6, crouch_punch=4, sweep=6, uppercut=6, jump_punch=3, jump_kick=3, throw=8,
    thrown=6, hit_high=3, hit_low=3, hit_air=4, knockdown=6, getup=6, dizzy=6, ko=8, win=8,
    sp_neutral=8, sp_forward=8, sp_down=8, sp_up=8, super=12, finisher=12)
# Portée des coups normaux (px au-delà de la boîte de référence de _common) :
# au moins MIN (tolérance enfant), au plus MAX + « allonge » de la fiche.
REACH_EXTRA_MIN = 8
REACH_EXTRA_MAX = 24
LOOPS = {"idle", "walk", "run", "crouch_idle", "dizzy", "win", "block", "crouch_block", "fall"}


def deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def default_anims():
    anims = {}
    for row, name in enumerate(ANIMS):
        n = DEFAULT_FRAMES[name]
        anims[name] = {"row": row, "frames": n, "fps": 10 if name in LOOPS else 16,
                       "loop": name in LOOPS}
        if name not in LOOPS:
            anims[name]["hit_frame"] = n // 2
    return anims


def build(fid):
    common = json.load(open(os.path.join(FIGHTERS, "_common.json")))
    common.pop("_doc", None)
    own = json.load(open(os.path.join(FIGHTERS, f"{fid}.json")))
    # Les clés « _ » (notes d'équilibrage, bornes) restent dans la fiche.
    own = {k: v for k, v in own.items() if not k.startswith("_")}
    data = deep_merge(common, own)
    out_dir = os.path.join(ASSETS, fid)
    anims_path = os.path.join(out_dir, "anims.json")
    pipe = json.load(open(anims_path)) if os.path.exists(anims_path) else {}
    data["anims"] = pipe.get("anims") or default_anims()
    data["cell"] = pipe.get("cell", 128)
    data["cols"] = pipe.get("cols", 16)
    data["foot"] = pipe.get("foot", [64, 120])
    boxes = pipe.get("boxes", {})
    data["hurtboxes"] = boxes.get("hurt", {})
    # Boîte de poussée asymétrique mesurée sur l'idle (torse, accessoires bornés).
    ext = torso_extent(out_dir, pipe) if pipe else None
    if ext and "push_front" not in own:
        back, front = ext
        data["push_front"] = max(18, min(36, round(front * 0.8)))
        data["push_back"] = max(14, min(28, round(back * 0.8)))
    auto_hit = boxes.get("hit", {})
    own_moves = own.get("moves", {})
    for name, mv in data["moves"].items():
        if "hitboxes" in own_moves.get(name, {}):
            continue
        box = auto_hit.get(mv.get("anim", name))
        if box and box[2] > 2 and box[3] > 2:
            # Tolérance enfant : union de la boîte inférée du sprite et de
            # la boîte de référence de _common (jamais plus petite que celle-ci).
            ref = (mv.get("hitboxes") or [None])[0]
            if ref:
                x0, y0 = min(box[0], ref[0]), min(box[1], ref[1])
                x1 = max(box[0] + box[2], ref[0] + ref[2])
                y1 = max(box[1] + box[3], ref[1] + ref[3])
                # Allonge bornée (équilibrage, docs/EQUILIBRAGE.md) : la boîte
                # du sprite (bras, canne, pinces…) dépasse la référence de 0 à
                # 55 px selon le dessin ; on la ramène dans [MIN, MAX] + l'allonge
                # d'archétype de la fiche, pour que la portée ne dépende pas
                # du dessin (refonte graphique en cours).
                ref_x1 = ref[0] + ref[2]
                x1 = max(ref_x1 + REACH_EXTRA_MIN,
                         min(x1, ref_x1 + REACH_EXTRA_MAX + int(own.get("allonge", 0))))
                box = [x0, y0, x1 - x0, y1 - y0]
            mv["hitboxes"] = [box]
    data.setdefault("palettes", "palettes.png")
    data.setdefault("palette_roles", {
        "skin": [3, 4, 5, 6], "hair": [7, 8, 9], "outfit_a": [10, 11, 12, 13],
        "outfit_b": [14, 15, 16, 17], "hat": [18, 19, 20, 21], "acc_b": [22, 23, 24, 25],
        "acc_c": [26, 27, 28], "extra": [29, 30, 31]})
    data.setdefault("ending", ["ending_0.png", "ending_1.png", "ending_2.png"])
    # Équilibrage : multiplicateur de dégâts par perso, réglage fin dans les
    # bornes de l'archétype (tools/balance/tune.py, docs/EQUILIBRAGE.md).
    pct = int(data.get("damage_pct", 100))
    if pct != 100:
        for mv in data["moves"].values():
            if mv.get("damage"):
                mv["damage"] = max(1, round(mv["damage"] * pct / 100))
        for pr in data.get("projectiles", {}).values():
            if pr.get("damage"):
                pr["damage"] = max(1, round(pr["damage"] * pct / 100))
    errors = validate(data)
    if errors:
        raise SystemExit(f"{fid} invalide :\n  " + "\n  ".join(errors))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "data.json"), "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"{fid}: {len(data['moves'])} coups, {len(data['anims'])} anims"
          f"{' (anims par défaut)' if not pipe else ''}")


def torso_extent(out_dir, pipe):
    """(arrière, avant) du torse en px depuis le pied, idle frame 0."""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        return None
    sheet_path = os.path.join(out_dir, "sheet.png")
    if not os.path.exists(sheet_path) or "idle" not in pipe.get("anims", {}):
        return None
    cell, cols, foot = pipe["cell"], pipe.get("cols", 16), pipe["foot"]
    k = pipe["anims"]["idle"].get("first", 0)
    sh = np.array(Image.open(sheet_path))
    c = sh[(k // cols) * cell:(k // cols + 1) * cell, (k % cols) * cell:(k % cols + 1) * cell]
    ys, xs = np.nonzero(c)
    if xs.size == 0:
        return None
    top = ys.min()
    h = foot[1] - top
    band = (ys > top + h * 0.25) & (ys < top + h * 0.75)
    return int(foot[0] - xs[band].min()), int(xs[band].max() - foot[0])


REQUIRED = ["punch_1", "punch_2", "punch_3", "kick", "kick_high", "crouch_punch", "sweep",
            "uppercut", "jump_punch", "jump_kick", "throw", "sp_neutral", "sp_forward",
            "sp_down", "sp_up", "super"]


def validate(data):
    errors = []
    for key in ("id", "name", "health", "moves", "anims"):
        if key not in data:
            errors.append(f"champ manquant : {key}")
    moves = data.get("moves", {})
    for name in REQUIRED:
        if name not in moves:
            errors.append(f"coup manquant : {name}")
    projs = data.get("projectiles", {})
    for name, mv in moves.items():
        if mv.get("anim", name) not in ANIMS:
            errors.append(f"{name}: anim inconnue {mv.get('anim')}")
        for k in ("startup", "active", "recovery"):
            if not isinstance(mv.get(k, 1), int) or mv.get(k, 1) < 0:
                errors.append(f"{name}: {k} invalide")
        has_effect = "spawn" in mv or mv.get("hit_level") == "throw" or "counter" in mv \
            or mv.get("damage", 0) == 0
        if not has_effect and not mv.get("hitboxes"):
            errors.append(f"{name}: aucune hitbox")
        if "spawn" in mv and mv["spawn"].get("projectile") not in projs:
            errors.append(f"{name}: projectile inconnu {mv['spawn'].get('projectile')}")
        for ref in ([mv["chain"]] if "chain" in mv else []) + ([mv["counter"]] if "counter" in mv else []):
            if ref not in moves:
                errors.append(f"{name}: référence inconnue {ref}")
    for name in ANIMS:
        if name not in data.get("anims", {}):
            errors.append(f"anim manquante : {name}")
    return errors


if __name__ == "__main__":
    ids = sys.argv[1:]
    if ids == ["--all"] or not ids:
        ids = sorted(f[:-5] for f in os.listdir(FIGHTERS) if f.endswith(".json") and not f.startswith("_"))
    for fid in ids:
        build(fid)
