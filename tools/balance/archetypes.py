#!/usr/bin/env python3
"""Profil statique des combattants, lu dans les data.json construits.

Pour vérifier que les archétypes restent distincts (rapide, lourd, zoneur...) :
  vie, marche/course (px/s), saut (durée, distance), portée des coups normaux,
  dégâts moyens d'un coup, auto-combo (dégâts, durée), startup le plus rapide,
  avantage à la garde des coups clés, nombre de projectiles.
Usage : archetypes.py [--md FICHIER] [ids...]
"""
import json, os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "balance"))
ROSTER = ["louis", "maia", "patxi", "xabi", "mattin", "amaia", "txomin", "kaio",
          "karramarro", "ramuntxo", "itsaso", "peio"]
SUB, FPS = 256, 60
NORMALS = ["punch_1", "punch_2", "punch_3", "kick", "kick_high", "crouch_punch", "sweep",
           "uppercut", "jump_punch", "jump_kick"]
SPECIALS = ["sp_neutral", "sp_forward", "sp_down", "sp_up"]


def reach(mv):
    return max((b[0] + b[2] for b in mv.get("hitboxes", []) or []), default=0)


def on_block(mv):
    """Avantage à la garde (frames) : blockstun - (frames actives restantes + récupération)."""
    if not mv.get("damage"):
        return None
    return mv.get("blockstun", 8) - (mv.get("active", 2) - 1 + mv.get("recovery", 8))


def profile(fid):
    d = json.load(open(os.path.join(ROOT, "assets", "fighters", fid, "data.json")))
    mv = d["moves"]
    air = 2 * abs(d["jump_v"]) // d["gravity"]
    combo = [mv[k] for k in ("punch_1", "punch_2", "punch_3")]
    combo_frames = sum(m["startup"] + m["active"] for m in combo[:2]) + sum(combo[2][k] for k in ("startup", "active", "recovery"))
    dmg_normals = [mv[k]["damage"] for k in NORMALS if mv.get(k, {}).get("damage")]
    dmg_sp = []
    for k in SPECIALS:
        m = mv[k]
        if m.get("damage"):
            dmg_sp.append(m["damage"] * m.get("hits", 1))
        elif "spawn" in m:
            pr = d["projectiles"][m["spawn"]["projectile"]]
            dmg_sp.append(pr.get("damage", 0) * pr.get("hits", 1))
    return {
        "id": fid,
        "arch": d.get("archetype", "?"),
        "pv": d["health"],
        "marche": round(d["walk_fwd"] * FPS / SUB),
        "recul": round(d["walk_back"] * FPS / SUB),
        "course": round(d["run"] * FPS / SUB),
        "saut_f": air,
        "saut_px": round(d["jump_h"] * air / SUB),
        "portee": max(reach(mv[k]) for k in ("punch_1", "kick", "kick_high", "sweep", "crouch_punch")),
        "coup_moy": round(sum(dmg_normals) / len(dmg_normals)),
        "combo": sum(m["damage"] for m in combo),
        "combo_dps": round(sum(m["damage"] for m in combo) * FPS / combo_frames),
        "startup_min": min(mv[k]["startup"] for k in NORMALS if k in mv),
        "kick_garde": on_block(mv["kick"]),
        "sp_moy": round(sum(dmg_sp) / max(len(dmg_sp), 1)),
        "projectiles": sum(1 for k in SPECIALS if "spawn" in mv[k]),
        "pct": d.get("damage_pct", 100),
    }


COLS = [("id", "perso"), ("arch", "archétype"), ("pv", "PV"), ("marche", "marche px/s"),
        ("recul", "recul px/s"), ("course", "course px/s"), ("saut_f", "saut (f)"),
        ("saut_px", "saut px"), ("portee", "portée px"), ("coup_moy", "coup normal moy."),
        ("combo", "P,P,P"), ("combo_dps", "P,P,P dégâts/s"), ("startup_min", "startup min"),
        ("kick_garde", "K gardé (f)"), ("sp_moy", "spécial moy."), ("projectiles", "proj."),
        ("pct", "damage_pct")]


def table(ids):
    rows = [profile(i) for i in ids]
    out = ["| " + " | ".join(h for _, h in COLS) + " |", "|" + "---|" * len(COLS)]
    for r in rows:
        out.append("| " + " | ".join(str(r[k]) for k, _ in COLS) + " |")
    return "\n".join(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    md = ""
    if "--md" in args:
        i = args.index("--md")
        md = args[i + 1]
        del args[i:i + 2]
    text = table(args or ROSTER)
    print(text)
    if md:
        open(md, "w").write(text + "\n")
