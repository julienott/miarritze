#!/usr/bin/env python3
"""Post-traitement des animations 2D d'un perso, en une commande (Julien, 2026-10-20 : « un pipeline
générique pour tous les persos existants et à venir »). Les PNG ne sont jamais réécrits : tout va
dans les <anim>.json, lus par src/gordeka/gk_perso.gd.

  post_anims.py <id>… | --tous  [--controle] [--sortie <dossier>]

Étapes, dans l'ordre (chacune idempotente : relancer ne réécrit rien si rien n'a changé) :
 1. pieds   (pieds.py)  frame_offsets (pieds posés fixes, recalés sur l'idle), stride_px ;
 2. lampe   (lampe.py)  main qui tient la lampe dans hunter_reveal ;
 3. échelle             `echelle` : taille de l'anim ramenée à celle de l'idle (tête mesurée) ;
 4. calage              `decalage` [dx, dy] : planches de déplacement calées sur leur pose de repos ;
 5. durées              `debut`, `fin` : images jouées d'un geste (sans images figées ni rupture) ;
 6. entrées             `entrees` {B: {"i", "e"}} : point d'entrée et écart de chaque transition.
Un nouvel idle change la référence de tout le perso : on recalcule donc toujours tout le perso.

--controle : en plus, rapport d'audit (audit_anims.py : durées, transitions, raccord, déplacement)
et planches des pires transitions dans --sortie (défaut tools/rd/out/<id>/gk2d/controle/).

Exceptions par perso, jamais dans le code : section facultative "post" du perso dans
tools/gordeka/prompts_anims.json, ex. {"echelle": {"found": 1.0}, "decalage": {"walk": [0, -4]},
"echelle_tol": 0.05, "fige": 0.6}.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import anim_json  # noqa: E402
import audit_anims as au  # noqa: E402

ROOT = au.ROOT
PERSOS = au.PERSOS
PROMPTS = os.path.join(HERE, "prompts_anims.json")
CLES = ("echelle", "decalage", "debut", "fin", "entrees")


def reglages(pid: str) -> dict:
    """Section "post" du perso dans prompts_anims.json (facultative)."""
    try:
        return dict(json.load(open(PROMPTS)).get("persos", {}).get(pid, {}).get("post", {}) or {})
    except (OSError, ValueError):
        return {}


def _maj(pid: str, anim: str, champs: dict) -> bool:
    """Remplace les champs `champs` (None = retiré) du .json de l'anim (ordre des clés : anim_json.py)."""
    chemin = os.path.join(PERSOS, pid, anim + ".json")
    j = json.load(open(chemin))
    for k, v in champs.items():
        if v is None:
            j.pop(k, None)
        else:
            j[k] = v
    return anim_json.ecrire(chemin, j)


def traiter(pid: str, journal=print) -> dict:
    """Toutes les étapes pour un perso ; renvoie {étape: nb de .json modifiés}."""
    bilan = {}
    anims = au.anims_du_perso(pid)
    if not anims:
        journal(f"{pid} : aucune animation, rien à faire")
        return bilan
    post = reglages(pid)
    for nom, f in (("pieds", lambda: __import__("pieds").corriger_perso(pid)),
                   ("lampe", lambda: __import__("lampe").corriger_perso(pid))):
        try:
            f()
            bilan[nom] = "ok"
        except Exception as e:  # noqa: BLE001 — une étape ratée n'empêche pas les suivantes
            bilan[nom] = f"ignorée ({e})"
    # 3. échelle (mesurée sans échelle ni calage : la référence est l'idle brut).
    n = 0
    faites = {}
    for a in sorted(anims, key=lambda x: x in au.MOUVEMENT):     # les poses de repos d'abord
        base = "ghost" if a == "ghost_move" and "ghost" in anims else "idle"
        e = au.echelle_conseillee(pid, a, post, faites.get(base, 1.0) if a in au.MOUVEMENT else 1.0)
        faites[a] = e
        n += _maj(pid, a, {"echelle": e if abs(e - 1.0) > 1e-6 else None})
    bilan["echelle"] = n
    # 4. calage des planches de déplacement (mesuré avec l'échelle).
    n = 0
    for a in anims:
        n += _maj(pid, a, {"decalage": au.decalage_conseille(pid, a, post)})
    bilan["decalage"] = n
    # 5. images jouées des gestes.
    n = 0
    for a in anims:
        d, f = au.bornes(pid, a, post)
        meta_n = int(json.load(open(os.path.join(PERSOS, pid, a + ".json"))).get("frames", f))
        n += _maj(pid, a, {"debut": d or None, "fin": f if f < meta_n else None})
    bilan["bornes"] = n
    # 6. tables d'entrée (mesurées telles que dessinées, tout appliqué).
    n = 0
    cache = {}
    for a in anims:
        t = au.entrees(pid, a, anims, cache) if a in au.TRANSITIONS else {}
        n += _maj(pid, a, {"entrees": t or None})
    bilan["entrees"] = n
    journal(f"{pid} : " + ", ".join(f"{k} {v}" for k, v in bilan.items()))
    return bilan


def controle(pid: str, sortie: str) -> str:
    res = au.auditer(pid, False, sortie)
    os.makedirs(sortie, exist_ok=True)
    t = au.texte(res)
    open(os.path.join(sortie, f"{pid}_audit.txt"), "w").write(t + "\n")
    json.dump(res, open(os.path.join(sortie, f"{pid}_audit.json"), "w"), indent=1, ensure_ascii=False)
    return t


def main() -> None:
    args = sys.argv[1:]
    sortie = None
    if "--sortie" in args:
        i = args.index("--sortie")
        sortie = args[i + 1]
        del args[i:i + 2]
    ctl = "--controle" in args
    if "--tous" in args or not [a for a in args if not a.startswith("--")]:
        ids = sorted(d for d in os.listdir(PERSOS) if os.path.isdir(os.path.join(PERSOS, d)))
    else:
        ids = [a for a in args if not a.startswith("--")]
    for pid in ids:
        traiter(pid)
        if ctl:
            dossier = sortie or os.path.join(ROOT, "tools", "rd", "out", pid, "gk2d", "controle")
            print(controle(pid, dossier))
            print(f"  -> {dossier}")


if __name__ == "__main__":
    main()
