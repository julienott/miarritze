#!/usr/bin/env python3
"""Client terminal du service /producer, pour l'agent (stdlib seulement).

Configuration :
  PRODUCER_URL    défaut https://miarritze.ijulien.com/producer/
  PRODUCER_TOKEN  jeton de l'agent ; sinon lu dans .producer_token (racine du
                  dépôt, gitignoré, le jeton seul sur la première ligne).

Exemples :
  cli.py comments --open
  cli.py reply 12 "Couleurs du maillot corrigées (commit abc1234)" --done
  cli.py cards --status todo [--parent 3] [--json]
  cli.py show 4                (détail + historique + enfants)
  cli.py move 4 doing          (backlog | todo | doing | qa | done)
  cli.py comment 4 "Commencé : nouvelle palette"
  cli.py add-card --type perso --title "Amaia" --status backlog
  cli.py add-card --type animation --title "Amaia : run" --parent 12
  cli.py set 4 --priority haute --parent 12
  cli.py set 4 --night on      (night shift : la carte part en file la nuit)
  cli.py cards --night
  cli.py events --since 15m    (tout ce qui a bougé ; aussi epoch ou "2026-10-20 14:00")
  cli.py qa 4 "marche ralentie à 8 i/s"   (carte retraitée -> QA, commentaire « retraité : … »)
  cli.py stats                 (tableau de bord : QA, refus, Doing immobiles, jalons)
  cli.py cards --type animation --search louis --milestone 2
  cli.py bulk 4 5 6 --status todo --night on   (même changement sur plusieurs cartes)
  cli.py milestones            (jalons de la roadmap, avec leur avancement)
  cli.py add-milestone --title "Contenu v1" --due 2026-12-01
  cli.py set-milestone 2 --due 2026-12-15 [--closed on]
  cli.py set 4 --milestone 2 --due 2026-11-30   (0 / aucune pour retirer)
  cli.py asset-comment gordeka/persos/louis/animations "pieds qui glissent" --detail walk
                               (commentaire d'asset reporté sur la carte liée, ou nouvelle carte)
  cli.py routes                (toutes les routes de l'API)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import time
from datetime import datetime
from pathlib import Path

DEFAULT_URL = "https://miarritze.ijulien.com/producer/"
ROOT = Path(__file__).resolve().parents[2]
# Colonnes du kanban, et alias de l'ancien CLI (afaire, encours, averifier, review, fait).
STATUS_LABEL = {"backlog": "Backlog", "todo": "Todo", "doing": "Doing", "qa": "QA", "done": "Done"}
STATUS_ALIASES = {
    "backlog": "backlog",
    "todo": "todo", "afaire": "todo", "a-faire": "todo",
    "doing": "doing", "encours": "doing", "en-cours": "doing",
    "qa": "qa", "review": "qa", "averifier": "qa", "a-verifier": "qa",
    "done": "done", "fait": "done",
}
CARD_TYPES = ["feature", "bug", "perso", "animation", "asset", "gameplay", "pixelforge"]
EVENT_LABEL = {
    "creation": "création", "deplacement": "déplacement", "titre": "titre", "description": "description",
    "priorite": "priorité", "type": "type", "asset": "asset", "detail": "détail", "parent": "chapeau",
    "commentaire": "commentaire", "suppression": "suppression",
    "accepte": "ACCEPTÉE", "refuse": "REFUSÉE", "night": "NIGHT", "jalon": "jalon", "echeance": "échéance",
}


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


def since_arg(s: str) -> int:
    """Epoch, durée relative (90s, 15m, 2h, 1d) ou date locale « AAAA-MM-JJ[ HH:MM[:SS]] »."""
    s = s.strip()
    if s.isdigit():
        return int(s)
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400, "j": 86400}
    if len(s) > 1 and s[-1] in units and s[:-1].isdigit():
        return int(time.time()) - int(s[:-1]) * units[s[-1]]
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d"):
        try:
            return int(datetime.strptime(s, fmt).timestamp())
        except ValueError:
            pass
    raise argparse.ArgumentTypeError("--since : epoch, 15m / 2h / 1d, ou AAAA-MM-JJ HH:MM")


def status_arg(s: str) -> str:
    key = s.lower().replace("à", "a").replace("é", "e").replace(" ", "-")
    if key not in STATUS_ALIASES:
        raise argparse.ArgumentTypeError("colonne : backlog | todo | doing | qa | done")
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


def short(text: str, n: int = 70) -> str:
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1] + "…"


def print_card(c: dict, full: bool, titles: dict | None = None) -> None:
    prio = f" !{c['priority']}" if c["priority"] else ""
    asset = f" · {c['asset']}" + (f" [{c['detail']}]" if c.get("detail") else "") if c["asset"] else ""
    rework = " [À RETRAITER]" if c.get("rework") else ""
    rework += " [NIGHT]" if c.get("night") else ""
    rework += f" [⏱ {c['due']}]" if c.get("due") else ""
    rework += f" [jalon {c['milestone_id']}]" if c.get("milestone_id") else ""
    kids = f" · enfants {c['children_done']}/{c['children']}" if c.get("children") else ""
    parent = ""
    if c.get("parent_id"):
        t = (titles or {}).get(c["parent_id"])
        parent = f" · ↑ #{c['parent_id']}" + (f" {short(t, 30)}" if t else "")
    print(f"#{c['id']} [{STATUS_LABEL[c['status']]}]{rework} {c['type']}{prio} · {c['title']}{asset}{parent}{kids}"
          f" · par {c.get('origin', '?')}")
    if full:
        print(f"    créée {when(c['created_at'])}, modifiée {when(c['updated_at'])}")
        for line in (c["description"] or "").splitlines():
            print("    " + line)
        for n in c["notes"]:
            print(f"    — {n['author']}{' (refus)' if n.get('kind') == 'refus' else ''} {when(n['created_at'])} : " + n["body"].replace("\n", "\n      "))


def event_line(e: dict, with_card: bool) -> str:
    t = e["type"]
    if t == "deplacement":
        what = f"{STATUS_LABEL.get(e['old'], e['old'])} -> {STATUS_LABEL.get(e['new'], e['new'])}"
    elif t == "creation":
        what = f"dans {STATUS_LABEL.get(e['new'], e['new'])}"
    elif t == "night":
        what = "ON (traitée la nuit, 1 h – 8 h Paris)" if e["new"] == "on" else "OFF"
    elif t == "accepte":
        what = "QA -> Done"
    elif t == "refuse":
        what = "QA -> Doing, à retraiter : « " + e["new"].replace("\n", "\n      ") + " »"
    elif t == "commentaire":
        what = "« " + e["new"].replace("\n", "\n      ") + " »"
    elif t == "suppression":
        what = f"« {e['old']} »"
    elif t == "parent":
        what = f"#{e['old'] or '—'} -> #{e['new'] or '—'}"
    elif t == "description":
        what = f"« {short(e['new'])} »"
    else:
        what = f"{e['old'] or '—'} -> {e['new'] or '—'}"
    card = ""
    if with_card:
        title = e.get("card_title") or "(supprimée)"
        col = f" [{STATUS_LABEL.get(e.get('card_status'), '')}]" if e.get("card_status") else ""
        card = f"#{e['card_id']}{col} {short(title, 40)} · "
    return f"{when(e['at'])} {e['author']:<6} {card}{EVENT_LABEL.get(t, t)} {what}"


def cmd_cards(a: argparse.Namespace) -> None:
    q = {}
    if a.status:
        q["status"] = a.status
    if a.parent:
        q["parent"] = a.parent
    if a.night:
        q["night"] = "1"
    for key in ("type", "milestone", "asset"):
        if getattr(a, key, None):
            q[key] = str(getattr(a, key))
    if a.search:
        q["q"] = a.search
    r = call("cards", query=q)
    if a.json:
        print(json.dumps(r["cards"], ensure_ascii=False, indent=1))
        return
    if not r["cards"]:
        print("Aucune carte.")
    titles = {c["id"]: c["title"] for c in r["cards"]}
    order = list(STATUS_LABEL)
    for c in sorted(r["cards"], key=lambda c: (order.index(c["status"]), c["position"])):
        print_card(c, a.full, titles)


def cmd_show(a: argparse.Namespace) -> None:
    r = call("card", query={"id": a.id})
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return
    c = r["card"]
    print_card({**c, "notes": []}, True)
    if r["children"]:
        print(f"  Enfants ({c['children_done']}/{c['children']} en QA ou Done) :")
        for k in r["children"]:
            print(f"    #{k['id']} [{STATUS_LABEL[k['status']]}] {k['type']} · {k['title']}")
    print("  Historique :")
    for e in r["events"]:
        print("    " + event_line(e, False))


def cmd_events(a: argparse.Namespace) -> None:
    q = {"since": a.since}
    if a.card:
        q["card"] = a.card
    r = call("events", query=q)
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return
    if not r["events"]:
        print("Rien de neuf.")
    for e in r["events"]:
        print(event_line(e, True))
    print(f"(serveur : {r['now']} — repasser --since {r['now']} au prochain tour)", file=sys.stderr)


def cmd_move(a: argparse.Namespace) -> None:
    call("card_move", {"id": a.id, "status": a.status})
    print(f"Carte #{a.id} -> {STATUS_LABEL[a.status]}")


def asset_version(card: dict) -> str:
    """« asset <id>[ · <anim>] version <empreinte> » de l'asset lié, tel que /producer le sert."""
    if not card.get("asset"):
        return ""
    idx = call("index")
    for x in idx.get("assets", []):
        if x.get("id") == card["asset"]:
            anim = f" · {card['detail']}" if card.get("detail") else ""
            return f"asset {card['asset']}{anim} version {x.get('version', '?')}"
    return f"asset {card['asset']} absent de l'index publié"


def cmd_qa(a: argparse.Namespace) -> None:
    text = a.text if a.text.lower().startswith("retraité") else "retraité : " + a.text
    ver = asset_version(call("card", query={"id": a.id})["card"])
    if ver:
        text += f" ({ver})"     # Julien sait qu'il voit la bonne version
    call("card_comment", {"id": a.id, "body": text})
    call("card_move", {"id": a.id, "status": "qa"})
    print(f"Carte #{a.id} -> QA (« {short(text)} »)")


def cmd_comment(a: argparse.Namespace) -> None:
    call("card_comment", {"id": a.id, "body": a.text})
    print(f"Commentaire ajouté à la carte #{a.id}")


def cmd_add_card(a: argparse.Namespace) -> None:
    body = {"type": a.type, "title": a.title, "description": a.desc or "", "priority": a.priority or "",
            "asset": a.asset or "", "detail": a.detail or "", "status": a.status, "night": a.night}
    if a.parent:
        body["parent"] = a.parent
    if a.milestone:
        body["milestone"] = a.milestone
    if a.due:
        body["due"] = a.due
    r = call("card", body)
    print(f"Carte #{r['id']} créée ({STATUS_LABEL[a.status]})")


def cmd_set(a: argparse.Namespace) -> None:
    body: dict = {"id": a.id}
    for key in ("title", "type", "asset", "detail"):
        if getattr(a, key) is not None:
            body[key] = getattr(a, key)
    if a.desc is not None:
        body["description"] = a.desc
    if a.priority is not None:
        body["priority"] = "" if a.priority == "aucune" else a.priority
    if a.parent is not None:
        body["parent"] = a.parent
    if a.night is not None:
        body["night"] = a.night == "on"
    if a.milestone is not None:
        body["milestone"] = a.milestone
    if a.due is not None:
        body["due"] = "" if a.due == "aucune" else a.due
    if len(body) == 1:
        sys.exit("Rien à modifier (--title, --desc, --type, --priority, --parent, --asset, --detail, --night, --milestone, --due)")
    r = call("card_update", body)
    print(f"Carte #{a.id} : {r.get('changed', 0)} champ(s) modifié(s)")


def cmd_bulk(a: argparse.Namespace) -> None:
    body: dict = {"ids": a.ids}
    if a.status:
        body["status"] = a.status
    if a.night is not None:
        body["night"] = a.night == "on"
    if a.priority is not None:
        body["priority"] = "" if a.priority == "aucune" else a.priority
    if a.milestone is not None:
        body["milestone"] = a.milestone
    if len(body) == 1:
        sys.exit("Rien à modifier (--status, --night, --priority, --milestone)")
    r = call("cards_bulk", body)
    print(f"{r.get('changed', 0)} carte(s) modifiée(s) sur {len(a.ids)}")


def bar(done: int, qa: int, total: int, width: int = 24) -> str:
    """Barre d'avancement : █ Done, ▓ QA, · le reste."""
    if not total:
        return "·" * width
    d = round(width * done / total)
    q = round(width * (done + qa) / total) - d
    return "█" * d + "▓" * q + "·" * (width - d - q)


def cmd_milestones(a: argparse.Namespace) -> None:
    r = call("stats")
    if a.json:
        print(json.dumps(r["milestones"], ensure_ascii=False, indent=1))
        return
    if not r["milestones"]:
        print("Aucun jalon (add-milestone --title …).")
    for m in r["milestones"]:
        bs = m["by_status"]
        due = f" · échéance {m['due']}" if m["due"] else ""
        print(f"#{m['id']} {m['title']}{due}{' [CLOS]' if m['closed'] else ''}")
        print(f"    {bar(bs['done'], bs['qa'], m['total'])} {bs['done']} faites, {bs['qa']} en QA, {bs['doing']} en cours,"
              f" {bs['todo']} todo, {bs['backlog']} backlog / {m['total']}" + (f" · {m['rework']} à retraiter" if m["rework"] else ""))


def cmd_add_milestone(a: argparse.Namespace) -> None:
    r = call("milestone", {"title": a.title, "description": a.desc or "", "due": a.due or ""})
    print(f"Jalon #{r['id']} créé")


def cmd_set_milestone(a: argparse.Namespace) -> None:
    body: dict = {"id": a.id}
    if a.title is not None:
        body["title"] = a.title
    if a.desc is not None:
        body["description"] = a.desc
    if a.due is not None:
        body["due"] = "" if a.due == "aucune" else a.due
    if a.closed is not None:
        body["closed"] = a.closed == "on"
    if a.position is not None:
        body["position"] = a.position
    if len(body) == 1:
        sys.exit("Rien à modifier (--title, --desc, --due, --closed, --position)")
    call("milestone_update", body)
    print(f"Jalon #{a.id} modifié")


def cmd_stats(a: argparse.Namespace) -> None:
    q = {"stale_days": str(a.stale_days)} if a.stale_days else {}
    r = call("stats", query=q)
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return
    lv = r["leaves"]
    print("Cartes sans enfant : " + " · ".join(f"{STATUS_LABEL[k]} {lv[k]}" for k in STATUS_LABEL))
    print(f"À valider (QA) : {r['qa']} · à retraiter : {len(r['rework'])} · night shift en Todo : {r['night_todo']}"
          f" · avis d'asset ouverts : {r['comments_open']} · événements 24 h : {r['events_24h']}")
    for title, key in (("Refusées, à retraiter", "rework"), (f"Doing immobiles depuis {r['stale_days']} j", "stale"),
                       ("Échéances dépassées", "overdue")):
        if r[key]:
            print(f"{title} :")
            for c in r[key]:
                extra = f" depuis {when(c['since'])}" if key == "stale" else f" (échéance {c['due']})" if key == "overdue" else ""
                print(f"    #{c['id']} [{STATUS_LABEL[c['status']]}] {c['title']}{extra}")
    if r["milestones"]:
        print("Jalons :")
        for m in r["milestones"]:
            bs = m["by_status"]
            print(f"    #{m['id']} {short(m['title'], 40):<40} {bar(bs['done'], bs['qa'], m['total'], 16)} "
                  f"{bs['done'] + bs['qa']}/{m['total']}" + (f" · échéance {m['due']}" if m["due"] else ""))


def cmd_asset_comment(a: argparse.Namespace) -> None:
    body: dict = {"asset": a.asset, "body": a.text, "kind": "valide" if a.valide else "amelioration"}
    if a.detail:
        body["detail"] = a.detail
    if a.card:
        body["card"] = a.card
    if a.title:
        body["title"] = a.title
    if a.parent:
        body["parent"] = a.parent
    r = call("asset_comment", body)
    if r.get("created"):
        print(f"Carte #{r['card']} créée dans le Backlog (commentaire d'asset #{r.get('comment')})")
    elif r.get("card"):
        print(f"Reporté sur la carte #{r['card']} (commentaire d'asset #{r.get('comment')})")
    else:
        print(f"Commentaire d'asset #{r.get('comment')} enregistré (aucune carte)")


def cmd_routes(a: argparse.Namespace) -> None:
    r = call("routes")
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return
    group = ""
    for x in r["routes"]:
        if x["group"] != group:
            group = x["group"]
            print(f"{group}")
        print(f"  {x['method']:<4} {x['route']:<17} {x['params']}")
        print(f"       {x['effect']}" + (f"  [cli : {x['cli']}]" if x["cli"] else ""))


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
    s.add_argument("--status", type=status_arg, help="backlog | todo | doing | qa | done")
    s.add_argument("--parent", type=int, help="seulement les enfants de cette carte chapeau")
    s.add_argument("--night", action="store_true", help="seulement les cartes night shift")
    s.add_argument("--type", choices=CARD_TYPES)
    s.add_argument("--milestone", help="id du jalon, ou none (sans jalon)")
    s.add_argument("--asset", help="id exact de l'asset lié")
    s.add_argument("--search", help="texte cherché dans le titre et la description")
    s.add_argument("--full", action="store_true", help="description et commentaires")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_cards)

    s = sub.add_parser("show", help="détail d'une carte, enfants et historique")
    s.add_argument("id", type=int)
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_show)

    s = sub.add_parser("events", help="tous les événements du board depuis --since")
    s.add_argument("--since", type=since_arg, default="1d", help="epoch, 15m / 2h / 1d, ou AAAA-MM-JJ HH:MM (défaut 1d)")
    s.add_argument("--card", type=int, help="une seule carte")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_events)

    s = sub.add_parser("move", help="déplacer une carte")
    s.add_argument("id", type=int)
    s.add_argument("status", type=status_arg, help="backlog | todo | doing | qa | done")
    s.set_defaults(fn=cmd_move)

    for name in ("comment", "note"):   # « note » : ancien nom
        s = sub.add_parser(name, help="commenter une carte" if name == "comment" else "alias de comment")
        s.add_argument("id", type=int)
        s.add_argument("text")
        s.set_defaults(fn=cmd_comment)

    s = sub.add_parser("add-card", help="créer une carte")
    s.add_argument("--type", choices=CARD_TYPES, default="feature")
    s.add_argument("--title", required=True)
    s.add_argument("--desc")
    s.add_argument("--priority", choices=["basse", "normale", "haute"])
    s.add_argument("--asset")
    s.add_argument("--detail", help="précise l'asset : nom de l'animation (ex. walk)")
    s.add_argument("--parent", type=int, help="carte chapeau")
    s.add_argument("--night", action="store_true", help="night shift : à traiter la nuit (1 h – 8 h Paris)")
    s.add_argument("--milestone", type=int, help="id du jalon")
    s.add_argument("--due", help="échéance AAAA-MM-JJ")
    s.add_argument("--status", type=status_arg, default="backlog")
    s.set_defaults(fn=cmd_add_card)

    s = sub.add_parser("set", help="modifier une carte")
    s.add_argument("id", type=int)
    s.add_argument("--title")
    s.add_argument("--desc")
    s.add_argument("--type", choices=CARD_TYPES)
    s.add_argument("--priority", choices=["basse", "normale", "haute", "aucune"])
    s.add_argument("--parent", type=int, help="0 pour détacher")
    s.add_argument("--asset")
    s.add_argument("--detail", help="nom de l'animation de l'asset (vide pour effacer)")
    s.add_argument("--night", choices=["on", "off"], help="night shift : traitée la nuit (1 h – 8 h Paris)")
    s.add_argument("--milestone", type=int, help="id du jalon (0 pour retirer)")
    s.add_argument("--due", help="échéance AAAA-MM-JJ (aucune pour retirer)")
    s.set_defaults(fn=cmd_set)

    s = sub.add_parser("bulk", help="même changement sur plusieurs cartes")
    s.add_argument("ids", type=int, nargs="+")
    s.add_argument("--status", type=status_arg)
    s.add_argument("--night", choices=["on", "off"])
    s.add_argument("--priority", choices=["basse", "normale", "haute", "aucune"])
    s.add_argument("--milestone", type=int, help="id du jalon (0 pour retirer)")
    s.set_defaults(fn=cmd_bulk)

    s = sub.add_parser("stats", help="tableau de bord du kanban")
    s.add_argument("--stale-days", type=int, help="seuil « Doing immobile » en jours (défaut 3)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_stats)

    s = sub.add_parser("milestones", help="jalons de la roadmap et leur avancement")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_milestones)

    s = sub.add_parser("add-milestone", help="créer un jalon")
    s.add_argument("--title", required=True)
    s.add_argument("--desc")
    s.add_argument("--due", help="échéance AAAA-MM-JJ")
    s.set_defaults(fn=cmd_add_milestone)

    s = sub.add_parser("set-milestone", help="modifier un jalon")
    s.add_argument("id", type=int)
    s.add_argument("--title")
    s.add_argument("--desc")
    s.add_argument("--due", help="AAAA-MM-JJ, ou aucune")
    s.add_argument("--closed", choices=["on", "off"])
    s.add_argument("--position", type=int)
    s.set_defaults(fn=cmd_set_milestone)

    s = sub.add_parser("asset-comment", help="commenter un asset ; reporté sur sa carte (ou nouvelle carte)")
    s.add_argument("asset", help="id de l'asset (ex. gordeka/persos/louis/animations, jeu/regles/partie)")
    s.add_argument("text")
    s.add_argument("--detail", help="animation visée (ex. walk)")
    s.add_argument("--card", type=int, help="carte où reporter le commentaire (sinon : choisie par le serveur)")
    s.add_argument("--title", help="titre de la carte créée s'il n'y en a pas")
    s.add_argument("--parent", type=int, help="chapeau de la carte créée")
    s.add_argument("--valide", action="store_true", help="« Validé » au lieu d'« Amélioration »")
    s.set_defaults(fn=cmd_asset_comment)

    s = sub.add_parser("routes", help="routes de l'API")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_routes)


    s = sub.add_parser("qa", help="repasser en QA une carte retraitée, avec ce qui a été corrigé")
    s.add_argument("id", type=int)
    s.add_argument("text")
    s.set_defaults(fn=cmd_qa)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
