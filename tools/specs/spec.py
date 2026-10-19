#!/usr/bin/env python3
"""Fiches de conception (tools/specs/fighters/<id>.yaml) : source unique
de ce qu'on génère pour un combattant (apparence, mouvements, spéciaux,
couleurs des costumes, reprises d'images). Voir docs/PIPELINE.md.

Usage : spec.py check <id>   (valide la fiche, affiche le coût estimé)
"""
from __future__ import annotations

import colorsys
import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

STYLES = {
    "attente": "rd_advanced_animation__idle",
    "marche": "rd_advanced_animation__walking",
    "attaque": "rd_advanced_animation__attack",
    "saut": "rd_advanced_animation__jump",
    "accroupi": "rd_advanced_animation__crouch",
    "action": "rd_advanced_animation__custom_action",
}
COST = {"rd_advanced_animation__custom_action": 0.25}
DEFAULT_COST = 0.14
SELECTIONS = {"tout": None, "tenue": "hold", "a_l_envers": "reverse", "chute_puis_sol": "end_hold"}
STARTS = {"en_l_air": "air", "au_plus_bas": "low"}
# Les 37 animations du jeu, dans l'ordre de la feuille.
GAME_ANIMS = ["intro", "idle", "walk", "run", "crouch", "crouch_idle", "jump_up", "jump_fwd", "fall",
              "block", "crouch_block", "punch_1", "punch_2", "punch_3", "kick", "kick_high",
              "crouch_punch", "sweep", "uppercut", "jump_punch", "jump_kick", "throw", "thrown",
              "hit_high", "hit_low", "hit_air", "knockdown", "getup", "dizzy", "ko", "win",
              "sp_neutral", "sp_forward", "sp_down", "sp_up", "super", "finisher"]


def path(fid: str) -> str:
    return os.path.join(HERE, "fighters", f"{fid}.yaml")


def exists(fid: str) -> bool:
    return os.path.exists(path(fid))


def load(fid: str) -> dict:
    with open(path(fid), encoding="utf-8") as f:
        return yaml.safe_load(f)


def moves(fid: str) -> dict:
    """{anim RD: (style, images, geste, départ)} ; départ = "neutral" ou (anim, index|"air"|"low")."""
    out = {}
    for name, m in load(fid)["mouvements"].items():
        dep = m.get("depart", "neutre")
        if dep == "neutre":
            start = "neutral"
        else:
            anim, idx = dep.split(":")
            start = (anim, STARTS.get(idx, int(idx) if idx.lstrip("-").isdigit() else idx))
        out[name] = (STYLES[m["mode"]], int(m["images"]), m["geste"], start)
    return out


def reuses(fid: str) -> dict:
    """{anim du jeu: (anim RD source, sélection)} ; sélection : None, "hold", "reverse",
    "end_hold" ou slice."""
    out = {}
    if not exists(fid):          # perso refait sans fiche (Txomin) : aucune reprise
        return out
    for name, r in (load(fid).get("reprises") or {}).items():
        sel = r.get("images", "tout")
        if sel in SELECTIONS:
            sel = SELECTIONS[sel]
        else:
            a, b = sel.split()[-1].split("-")
            sel = slice(int(a), int(b))
        out[name] = (r["depuis"], sel)
    return out


def _in(v, rng) -> bool:
    lo, hi = rng
    return lo <= v <= hi


def group_rules(fid: str):
    """Liste [(groupe, fonction(rgb) -> bool)] : couleurs recolorées par les costumes."""
    rules = []
    for g, r in (load(fid).get("groupes_couleur") or {}).items():
        r = r or {}
        def rule(c, r=r):
            h, s, v = colorsys.rgb_to_hsv(*(int(x) / 255 for x in c[:3]))
            h *= 360
            if "teinte" in r:
                lo, hi = r["teinte"]
                if not (lo <= h <= hi if lo <= hi else (h >= lo or h <= hi)):
                    return False
            return _in(s, r.get("sat", [0, 1])) and _in(v, r.get("val", [0, 1]))
        rules.append((g, rule))
    return rules


def min_components(fid: str) -> dict:
    """{groupe: taille minimale d'une zone d'un seul tenant} (clé composante_min)."""
    return {g: int(r["composante_min"]) for g, r in (load(fid).get("groupes_couleur") or {}).items()
            if "composante_min" in r}


def check(fid: str) -> list:
    """Erreurs de la fiche (liste vide = fiche exploitable)."""
    s = load(fid)
    err = []
    for k in ("id", "apparence", "mouvements"):
        if k not in s:
            err.append(f"champ manquant : {k}")
    mv = s.get("mouvements", {})
    rep = s.get("reprises", {}) or {}
    for name, m in mv.items():
        if m.get("mode") not in STYLES:
            err.append(f"{name} : mode inconnu {m.get('mode')!r} ({', '.join(STYLES)})")
        if int(m.get("images", 0)) not in (4, 6, 8, 10, 12, 16):
            err.append(f"{name} : images doit valoir 4, 6, 8, 10, 12 ou 16")
        dep = m.get("depart", "neutre")
        if dep != "neutre" and dep.split(":")[0] not in mv:
            err.append(f"{name} : départ {dep} vers un mouvement absent")
    covered = set(mv) | set(rep) | {"jump_up", "fall"} if "jump" in mv else set(mv) | set(rep)
    for a in GAME_ANIMS:
        if a not in covered:
            err.append(f"animation du jeu sans source : {a}")
    for name, r in rep.items():
        if r.get("depuis") not in mv:
            err.append(f"reprise {name} : source {r.get('depuis')} absente des mouvements")
    for sp in ("sp_neutral", "sp_forward", "sp_down", "sp_up", "super"):
        if sp not in (s.get("speciaux") or {}) and s.get("statut") != "validée":
            err.append(f"spécial non décrit : {sp} (section speciaux)")
    return err


def cost(fid: str) -> float:
    return sum(COST.get(st, DEFAULT_COST) for st, _, _, _ in moves(fid).values())


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] != "check":
        print(__doc__)
        sys.exit(2)
    fid = sys.argv[2]
    e = check(fid)
    print(f"{fid} : {len(load(fid)['mouvements'])} mouvements, génération estimée {cost(fid):.2f} $ (hors essais)")
    for line in e:
        print("  ✗", line)
    sys.exit(1 if e else 0)
