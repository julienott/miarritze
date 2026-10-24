#!/usr/bin/env python3
"""Refait la seule réduction pixel (moteur B) d'une animation itérée, sur la même tâche HD (A), sans refaire
Wan. La nouvelle réduction remplace l'ancienne dans iterations.json (l'ancienne est notée dans « refaites ») ;
l'intégration suivante (iteration.py integre) la prend.
  rereduit.py louis run [--prio high] [--famille persos]
Imprime l'id de la nouvelle tâche (le watcher du board la suit).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import iteration as it  # noqa: E402

args = sys.argv[1:]
prio = args[args.index("--prio") + 1] if "--prio" in args else "normal"
fam = args[args.index("--famille") + 1] if "--famille" in args else "persos"
pid, el = [a for a in args if not a.startswith("--") and a not in (prio, fam)][:2]
e = it.etat()
s = e[f"{fam}/{pid}"]
a = s["animations"][el]
rep = it.depose({"prompt_style": "pf_px__reduce", "px_task": a["A"], "priority": prio,
                 "tag": f"{it.TAG}/{fam}/reduce"}, False)
s.setdefault("refaites", {})[f"{el}_reduction_{a['B'][:8]}"] = a["B"]
a["B"] = rep["task_id"]
s.get("integre", {}).pop(el, None)          # à réintégrer avec la nouvelle réduction
it.sauve(e)
print(pid, el, "réduction", rep["task_id"])
