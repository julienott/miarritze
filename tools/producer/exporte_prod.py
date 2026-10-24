#!/usr/bin/env python3
"""Sauvegarde complète du board en ligne par l'API (cartes, commentaires de cartes, historique, avis
d'asset, jalons), avant sa suppression (Julien, 24/10). Écrit .studio/sauvegardes/prod_<date>.json.
  PRODUCER_URL=https://miarritze.ijulien.com/producer/ tools/producer/exporte_prod.py
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cli  # noqa: E402

cartes = cli.call("cards")
cartes = cartes.get("cards", cartes) if isinstance(cartes, dict) else cartes
details = {c["id"]: cli.call("card", query={"id": c["id"]}) for c in cartes}
evts = cli.call("events", query={"since": 0})
out = {"exporte_le": int(time.time()), "cards": cartes, "details": details, "events": evts,
       "comments": cli.call("comments"), "milestones": cli.call("milestones")}
f = os.path.join(cli.ROOT, ".studio", "sauvegardes", time.strftime("prod_%Y%m%d_%H%M.json"))
json.dump(out, open(f, "w"), ensure_ascii=False, indent=1)
print(f, len(cartes), "cartes")
