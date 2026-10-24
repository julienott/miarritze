#!/usr/bin/env python3
"""Dépose chez pixelforge une ou plusieurs requêtes écrites dans un fichier JSON du dépôt (clé par requête),
les marque keep et imprime les ids (le watcher du board les suit). Pour les cartes à commande (docs/PRODUCER.md).
  depose_json.py tools/blackout/essai_chat.json wan marionnette
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import iteration as it  # noqa: E402

fichier, cles = sys.argv[1], sys.argv[2:]
reqs = json.load(open(fichier))
for k in cles or [k for k in reqs if not k.startswith("_")]:
    rep = it.depose(reqs[k], False)
    suite = " ".join(t.get("task_id", "") for t in (rep.get("then") or []))
    print(k, rep["task_id"], suite)
