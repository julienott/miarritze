#!/usr/bin/env python3
"""Rejeu de la bibliothèque de prompts persos v2 (GDD-BLACKOUT.md §8.2, copie machine
data/blackout/style_party_hard.json) : une chaîne moteur A (pf_px__character_set) → moteur B
(pf_px__reduce) par perso, déposée dans la FILE de pixelforge.

  party_hard_v2.py --montre [louis …]            affiche les requêtes, n'envoie rien
  party_hard_v2.py --depose [louis …] [--prio high|normal|night]

Sans liste de persos : les 13. Écrit les ids des tâches dans tools/blackout/taches_partyhard_v2.json.
Ne rien déposer sans l'accord de Julien (GDD §14).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))

SPEC = json.load(open(os.path.join(ROOT, "data", "blackout", "style_party_hard.json"), encoding="utf-8"))
SORTIE = os.path.join(HERE, "taches_persos_v3.json")
TAG = "miarritze/persos_v3"
GRAINE = 7


def prompt(pid: str) -> str:
    p = SPEC["persos"][pid]
    # Détail clé « clearly visible » déjà dans la description (règles de pixelforge, GDD §8.2), sinon ajouté.
    if "clearly visible" in p["description"]:
        return p["description"] + "."
    return f"{p['description']}, with {p['signature']} clearly visible."


def casts(pid: str) -> list:
    """Lancements des deux coups spéciaux (GDD §4.6), extras cast_chasse et cast_chasseur."""
    c = SPEC.get("casts", {}).get(pid, {})
    return [{"name": n, "motion": c[n]["clip"], "action": c[n]["action"], "object": c[n]["objet"] or False,
             "loop": False, "fps": 12} for n in ("cast_chasse", "cast_chasseur") if n in c]


def requete(pid: str, prio: str) -> dict:
    il = SPEC["idle_long"][pid]
    return {
        "prompt_style": "pf_px__character_set", "prompt": prompt(pid), "colors": 20, "seed": GRAINE,
        "priority": prio, "tag": TAG,
        "skip": ["ghost"],                       # fantôme commun (pf_px__ghost, GDD §8.1)
        "extras": [{"name": "idle_long", "motion": il["clip"], "action": il["geste"], "loop": True, "fps": 10,
                    "object": il.get("objet") or False}] + casts(pid),
        # B lit la ligne des pieds dans le set.json de A (60 en 32 px, case 64) : pas de feet_y.
        "then": [{"prompt_style": "pf_px__reduce", "factor": 4, "colors": 10}],
    }


def main() -> None:
    args = sys.argv[1:]
    prio = args[args.index("--prio") + 1] if "--prio" in args else "high"
    pids = [a for a in args if not a.startswith("--") and a != prio] or \
        [k for k in SPEC["persos"] if not k.startswith("_")]
    reqs = {pid: requete(pid, prio) for pid in pids}
    if "--depose" not in args:
        print(json.dumps(reqs, ensure_ascii=False, indent=1))
        return
    import gen_anims_pf as pf  # noqa: E402
    taches = json.load(open(SORTIE)) if os.path.exists(SORTIE) else {}
    for pid, r in reqs.items():
        rep = pf._post_json(pf.PF + "/v2/inferences", r, timeout=120)
        taches[pid] = {"A": rep["task_id"], "chaine": rep.get("then") or rep.get("chain"), "prompt": r["prompt"],
                       "idle_long": r["extras"][0]}
        print(pid, rep["task_id"], flush=True)
    json.dump(taches, open(SORTIE, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
