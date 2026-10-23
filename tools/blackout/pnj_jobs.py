#!/usr/bin/env python3
"""Jobs pixelforge des PNJ humains, depuis data/blackout/pnj.json (copie de GDD-BLACKOUT.md §8.4).

  pnj_jobs.py --montre [festayre …]           affiche les requêtes, n'envoie rien
  pnj_jobs.py --depose [festayre …] [--prio normal|high|night]
  pnj_jobs.py --montre --type generique|special  (filtre par type)

Un PNJ = character set (profil, idle, fuite apeurée en run) + 6 extras (10 au plus chez pixelforge) : marcher,
sursaut, a_terre, relever et ses 2 activités ; le reste est sauté. Les animaux attendent la méthode de pixelforge pour les corps non humains.
Ne rien déposer sans l'accord de Julien (GDD §14). Ids écrits dans tools/blackout/taches_pnj.json.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PNJ = json.load(open(os.path.join(ROOT, "data", "blackout", "pnj.json"), encoding="utf-8"))
SORTIE = os.path.join(HERE, "taches_pnj.json")


def requete(pid: str, prio: str) -> dict:
    p, base = PNJ["humains"][pid], PNJ["set_humain"]
    extras = [dict(e, fps=10, object=False) for e in base["extras_communs"]]
    for act in p["activites"]:
        a = PNJ["activites"][act]
        objet = a["objet"] or (p["signature"] if a.get("objet_du_pnj") else False)
        extras.append({"name": act, "motion": a["clip"], "action": a["action"], "object": objet, "loop": True,
                       "fps": 10})
    return {
        "prompt_style": base["prompt_style"], "seed": 7, "colors": 20, "priority": prio, "tag": f"miarritze/pnj_v1_{p['type']}",
        "prompt": f"{p['description']}. Signature detail drawn large and bright: {p['signature']}.",
        "clips": {"run": base["run"]["clip"]}, "actions": {"run": base["run"]["action"]},
        "skip": base["skip"], "extras": extras,
        "then": [{"prompt_style": "pf_px__reduce", "factor": 4, "colors": 10}],
    }


def main() -> None:
    args = sys.argv[1:]
    prio = args[args.index("--prio") + 1] if "--prio" in args else "normal"
    typ = args[args.index("--type") + 1] if "--type" in args else None
    pids = [a for a in args if not a.startswith("--") and a not in (prio, typ)] or \
        [k for k, v in PNJ["humains"].items() if typ is None or v["type"] == typ]
    reqs = {pid: requete(pid, prio) for pid in pids}
    if "--depose" not in args:
        print(json.dumps(reqs, ensure_ascii=False, indent=1))
        return
    sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
    import gen_anims_pf as pf  # noqa: E402
    taches = json.load(open(SORTIE)) if os.path.exists(SORTIE) else {}
    for pid, r in reqs.items():
        rep = pf._post_json(pf.PF + "/v2/inferences", r, timeout=120)
        taches[pid] = {"A": rep["task_id"], "chaine": rep.get("then") or rep.get("chain")}
        print(pid, rep["task_id"], flush=True)
    json.dump(taches, open(SORTIE, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
