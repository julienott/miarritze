#!/usr/bin/env python3
"""Client terminal du service /producer, pour l'agent (stdlib seulement).

Configuration :
  PRODUCER_URL    défaut https://miarritze.ijulien.com/producer/
  PRODUCER_TOKEN  jeton de l'agent ; sinon lu dans .producer_token (racine du
                  dépôt, gitignoré, le jeton seul sur la première ligne).

Exemples :
  cli.py comments --open
  cli.py reply 12 "Couleurs du maillot corrigées (commit abc1234)" --done
  cli.py cards --status todo
  cli.py show 4
  cli.py move 4 doing          (todo | doing | review | done)
  cli.py note 4 "Commencé : nouvelle palette"
  cli.py add-card --type bug --title "Ombre de Maia décalée" --asset fighters/maia/sheet.png
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

DEFAULT_URL = "https://miarritze.ijulien.com/producer/"
ROOT = Path(__file__).resolve().parents[2]
STATUS_ALIASES = {
    "todo": "todo", "afaire": "todo", "a-faire": "todo",
    "doing": "doing", "encours": "doing", "en-cours": "doing",
    "review": "review", "averifier": "review", "a-verifier": "review",
    "done": "done", "fait": "done",
}
STATUS_LABEL = {"todo": "À faire", "doing": "En cours", "review": "À vérifier", "done": "Fait"}


def token() -> str:
    tok = os.environ.get("PRODUCER_TOKEN", "").strip()
    if not tok:
        f = ROOT / ".producer_token"
        if f.exists():
            lines = [ln.strip() for ln in f.read_text().splitlines() if ln.strip()]
            tok = lines[0] if lines else ""
    if not tok:
        sys.exit("Jeton absent : définir PRODUCER_TOKEN ou créer .producer_token")
    return tok


def call(route: str, body: dict | None = None, query: dict | None = None) -> dict:
    base = os.environ.get("PRODUCER_URL", DEFAULT_URL)
    if not base.endswith("/"):
        base += "/"
    params = {"r": route, **(query or {})}
    url = base + "index.php?" + urllib.parse.urlencode(params)
    tok = token()
    headers = {
        "Authorization": "Bearer " + tok,
        "X-Producer-Token": tok,  # repli si Apache supprime Authorization
        "Accept": "application/json",
        "User-Agent": "miarritze-producer-cli",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode()).get("error", "")
        except (ValueError, AttributeError):
            msg = ""
        sys.exit(f"Erreur {e.code} : {msg or e.reason}")
    except urllib.error.URLError as e:
        sys.exit(f"Connexion impossible : {e.reason}")


def when(ts: int) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")


def status_arg(s: str) -> str:
    key = s.lower().replace("à", "a").replace("é", "e").replace(" ", "-")
    if key not in STATUS_ALIASES:
        raise argparse.ArgumentTypeError("statut : todo | doing | review | done")
    return STATUS_ALIASES[key]


# ------------------------------------------------------------------ commandes

def cmd_comments(a: argparse.Namespace) -> None:
    q = {}
    if a.open:
        q["status"] = "open"
    if a.asset:
        q["asset"] = a.asset
    r = call("comments", query=q)
    if a.json:
        print(json.dumps(r["comments"], ensure_ascii=False, indent=1))
        return
    if not r["comments"]:
        print("Aucun commentaire.")
    for c in r["comments"]:
        flag = " [version précédente : actuelle " + str(c["current_version"]) + "]" if c["outdated"] else ""
        print(f"#{c['id']} [{c['status']}] {c['kind']} · {c['asset']} · v {c['version']} · build {c['build']}"
              f" · {when(c['created_at'])}{flag}")
        if c["context"]:
            print(f"    contexte : {c['context']}")
        for line in (c["body"] or "(sans texte)").splitlines():
            print("    " + line)
        if c["reply"]:
            print("    ↳ réponse : " + c["reply"].replace("\n", "\n      "))


def cmd_reply(a: argparse.Namespace) -> None:
    body = {"id": a.id, "reply": a.text}
    if a.done:
        body["status"] = "done"
    call("comment_update", body)
    print(f"Commentaire #{a.id} : réponse enregistrée" + (" (traité)" if a.done else ""))


def cmd_close(a: argparse.Namespace) -> None:
    call("comment_update", {"id": a.id, "status": "open" if a.reopen else "done"})
    print(f"Commentaire #{a.id} : " + ("rouvert" if a.reopen else "traité"))


def print_card(c: dict, full: bool) -> None:
    prio = f" !{c['priority']}" if c["priority"] else ""
    asset = f" · {c['asset']}" if c["asset"] else ""
    print(f"#{c['id']} [{STATUS_LABEL[c['status']]}] {c['type']}{prio} · {c['title']}{asset}")
    if full:
        print(f"    créée {when(c['created_at'])}, modifiée {when(c['updated_at'])}")
        for line in (c["description"] or "").splitlines():
            print("    " + line)
        for n in c["notes"]:
            print(f"    — {n['author']} {when(n['created_at'])} : " + n["body"].replace("\n", "\n      "))


def cmd_cards(a: argparse.Namespace) -> None:
    q = {"status": a.status} if a.status else {}
    r = call("cards", query=q)
    if a.json:
        print(json.dumps(r["cards"], ensure_ascii=False, indent=1))
        return
    if not r["cards"]:
        print("Aucune carte.")
    order = list(STATUS_LABEL)
    for c in sorted(r["cards"], key=lambda c: (order.index(c["status"]), c["position"])):
        print_card(c, a.full)


def cmd_show(a: argparse.Namespace) -> None:
    for c in call("cards")["cards"]:
        if c["id"] == a.id:
            print_card(c, True)
            return
    sys.exit(f"Carte #{a.id} introuvable")


def cmd_move(a: argparse.Namespace) -> None:
    call("card_move", {"id": a.id, "status": a.status})
    print(f"Carte #{a.id} -> {STATUS_LABEL[a.status]}")


def cmd_note(a: argparse.Namespace) -> None:
    call("card_note", {"id": a.id, "body": a.text})
    print(f"Note ajoutée à la carte #{a.id}")


def cmd_add_card(a: argparse.Namespace) -> None:
    body = {"type": a.type, "title": a.title, "description": a.desc or "", "priority": a.priority or "",
            "asset": a.asset or "", "status": a.status}
    r = call("card", body)
    print(f"Carte #{r['id']} créée")


def main() -> None:
    p = argparse.ArgumentParser(description="Client du service /producer (commentaires d'assets, kanban).")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("comments", help="lister les commentaires")
    s.add_argument("--open", action="store_true", help="seulement les ouverts")
    s.add_argument("--asset", help="filtrer par id d'asset (ex. fighters/maia/sheet.png)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_comments)

    s = sub.add_parser("reply", help="répondre à un commentaire")
    s.add_argument("id", type=int)
    s.add_argument("text")
    s.add_argument("--done", action="store_true", help="marquer traité")
    s.set_defaults(fn=cmd_reply)

    s = sub.add_parser("close", help="marquer un commentaire traité (ou --reopen)")
    s.add_argument("id", type=int)
    s.add_argument("--reopen", action="store_true")
    s.set_defaults(fn=cmd_close)

    s = sub.add_parser("cards", help="lister les cartes du kanban")
    s.add_argument("--status", type=status_arg)
    s.add_argument("--full", action="store_true", help="description et notes")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_cards)

    s = sub.add_parser("show", help="détail d'une carte")
    s.add_argument("id", type=int)
    s.set_defaults(fn=cmd_show)

    s = sub.add_parser("move", help="déplacer une carte")
    s.add_argument("id", type=int)
    s.add_argument("status", type=status_arg)
    s.set_defaults(fn=cmd_move)

    s = sub.add_parser("note", help="ajouter une note à une carte")
    s.add_argument("id", type=int)
    s.add_argument("text")
    s.set_defaults(fn=cmd_note)

    s = sub.add_parser("add-card", help="créer une carte")
    s.add_argument("--type", choices=["feature", "bug"], default="feature")
    s.add_argument("--title", required=True)
    s.add_argument("--desc")
    s.add_argument("--priority", choices=["basse", "normale", "haute"])
    s.add_argument("--asset")
    s.add_argument("--status", type=status_arg, default="todo")
    s.set_defaults(fn=cmd_add_card)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
