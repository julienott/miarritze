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
SORTIE = os.path.join(HERE, "taches_partyhard_v2.json")
TAG = "miarritze/partyhard_v2"
GRAINE = 7


def prompt(pid: str) -> str:
    p = SPEC["persos"][pid]
    return f"{p['description']}. Signature detail drawn large and bright: {p['signature']}."


def requete(pid: str, prio: str) -> dict:
    il = SPEC["idle_long"][pid]
    return {
        "prompt_style": "pf_px__character_set", "prompt": prompt(pid), "colors": 20, "seed": GRAINE,
        "priority": prio, "tag": TAG,
        "extras": [{"name": "idle_long", "motion": il["clip"], "action": il["geste"], "loop": True,
                    "fps": 10}],
        "then": [{"prompt_style": "pf_px__reduce", "factor": 4, "colors": 10, "feet_y": 31}],
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
