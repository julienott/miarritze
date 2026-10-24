#!/usr/bin/env python3
"""Importe la sauvegarde du board en ligne (exporte_prod.py) dans la base du board local, ids conservés
(Julien, 24/10 : migrer puis supprimer /producer en ligne). Base vide exigée ; le service local doit
avoir créé le schéma (une requête suffit).
  tools/producer/importe_local.py [.studio/sauvegardes/prod_….json]
"""
import glob
import json
import os
import sqlite3
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BASE = os.path.join(ROOT, ".studio", "site", "producer", "data", "producer.sqlite")

src = sys.argv[1] if len(sys.argv) > 1 else sorted(glob.glob(os.path.join(ROOT, ".studio", "sauvegardes", "prod_*.json")))[-1]
d = json.load(open(src))
db = sqlite3.connect(BASE)
db.execute("PRAGMA foreign_keys = OFF")
if db.execute("SELECT COUNT(*) FROM cards").fetchone()[0]:
    sys.exit("la base locale a déjà des cartes : import refusé")
cols = {r[1] for r in db.execute("PRAGMA table_info(cards)")}

for m in d["milestones"]["milestones"]:
    db.execute("INSERT INTO milestones (id, title, description, due, position, closed, created_at, updated_at)"
               " VALUES (?,?,?,?,?,?,?,?)", (m["id"], m["title"], m["description"], m["due"], m["position"],
                                             int(m["closed"]), m["created_at"], m["updated_at"]))
champs = ["id", "type", "title", "description", "priority", "asset", "detail", "status", "position", "parent_id",
          "origin", "rework", "night", "milestone_id", "due", "created_at", "updated_at"]
for c in d["cards"]:
    db.execute(f"INSERT INTO cards ({','.join(champs)}) VALUES ({','.join('?' * len(champs))})",
               [int(c[k]) if isinstance(c.get(k), bool) else c.get(k) for k in champs])
    for n in c.get("notes", []):
        db.execute("INSERT INTO card_notes (id, card_id, author, body, kind, created_at) VALUES (?,?,?,?,?,?)",
                   (n["id"], c["id"], n["author"], n["body"], n.get("kind", ""), n["created_at"]))
vus = set()
for det in d["details"].values():
    for e in det["events"]:
        if e["id"] in vus:
            continue
        vus.add(e["id"])
        db.execute("INSERT INTO card_events (id, card_id, at, author, type, old, new) VALUES (?,?,?,?,?,?,?)",
                   (e["id"], e["card_id"], e["at"], e["author"], e["type"], e["old"], e["new"]))
for e in d["events"]["events"]:          # suppressions (cartes disparues) et le reste du fil récent
    if e["id"] not in vus:
        vus.add(e["id"])
        db.execute("INSERT INTO card_events (id, card_id, at, author, type, old, new) VALUES (?,?,?,?,?,?,?)",
                   (e["id"], e["card_id"], e["at"], e["author"], e["type"], e["old"], e["new"]))
for c in d["comments"]["comments"]:
    db.execute("INSERT INTO comments (id, asset, version, build, context, kind, body, status, reply, card_id,"
               " created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
               (c["id"], c["asset"], c["version"], c["build"], c["context"], c["kind"], c["body"], c["status"],
                c["reply"], c.get("card_id"), c["created_at"], c["updated_at"]))
# Les ids ne sont jamais réutilisés : la séquence repart après le plus grand id connu en ligne.
plus_grand = max([c["id"] for c in d["cards"]] + [e["card_id"] for e in d["events"]["events"]] + [0])
db.execute("UPDATE sqlite_sequence SET seq = MAX(seq, ?) WHERE name = 'cards'", (plus_grand,))
db.commit()
print(src, ":", len(d["cards"]), "cartes,", len(vus), "événements,", len(d["comments"]["comments"]), "avis,",
      len(d["milestones"]["milestones"]), "jalons")
