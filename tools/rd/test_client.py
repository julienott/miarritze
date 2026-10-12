#!/usr/bin/env python3
"""Test hors ligne du plafond : aucun appel réseau, aucun centime dépensé."""
import os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import client

tmp = tempfile.mkdtemp()
client.BUDGET_PATH = os.path.join(tmp, "budget.json")
client.LEDGER_PATH = os.path.join(tmp, "ledger.jsonl")
client.CACHE_DIR = os.path.join(tmp, "cache")
client.OUT_DIR = os.path.join(tmp, "out")
client.LOCK_PATH = os.path.join(tmp, "out", ".lock")
client.PENDING_PATH = os.path.join(tmp, "out", "pending.jsonl")
client._write_json(client.BUDGET_PATH, {"cap_usd": 1.0, "start_balance": 10.0})
client._append_jsonl(client.LEDGER_PATH, {"label": "x", "balance_cost": 0.95})
client.check_cost = lambda payload: 0.18
sent = []
client._submit = lambda payload, idem: sent.append(1)
try:
    client.generate({"prompt": "p", "prompt_style": "rd_pro__default", "width": 64,
                     "height": 64, "num_images": 1}, "test/refus")
    print("ÉCHEC : la requête n'a pas été refusée"); sys.exit(1)
except client.BudgetExceeded as err:
    assert not sent, "une requête est partie malgré le refus"
    print("OK refus :", err)
# contrôle croisé : solde réel tombé plus que le registre
client.check_cost = lambda payload: 0.01
client.credits = lambda: 8.0   # baisse réelle 2 $ > registre 0,95 $
try:
    client.generate({"prompt": "q", "prompt_style": "rd_fast__default", "width": 64,
                     "height": 64, "num_images": 1}, "test/mismatch")
    print("ÉCHEC : écart non détecté"); sys.exit(1)
except client.BudgetMismatch as err:
    assert not sent
    print("OK écart :", err)
