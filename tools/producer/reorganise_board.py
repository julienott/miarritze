#!/usr/bin/env python3
"""Réorganise le board local selon la roadmap (GDD §15) et la règle « une carte par animation » (§14.2) :
jalons dans l'ordre du GDD ; chapeaux Persos, PNJ et animaux, Boss ; sous chacun, un chapeau par perso,
PNJ, animal ou boss, avec une carte par base, expression et animation (asset du set + détail).
Idempotent : une carte existante (même asset et même détail) est reprise, jamais dupliquée ; les
colonnes déjà avancées ne reculent pas.
  tools/producer/reorganise_board.py [--montre]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "blackout"))
os.environ.setdefault("PRODUCER_URL", "http://127.0.0.1:8099/producer/")
import cli  # noqa: E402
import enchaine as en  # noqa: E402
import iteration as it  # noqa: E402

MONTRE = "--montre" in sys.argv
RANG = {s: i for i, s in enumerate(["backlog", "todo", "doing", "qa", "valide", "done"])}
# Les persos se finissent dans cet ordre (veille du 23/10, accord de Julien) : tous en Todo, l'un après l'autre.
ORDRE = ["louis", "txomin", "maia", "patxi", "xabi", "mattin", "amaia", "kaio", "karramarro", "ramuntxo",
         "itsaso", "peio", "itsasargi"]
ANCIENS = {"R1": "Jalon 1 — jouable sur carte nue", "R2": "Persos v2", "R4": "Boss", "R7": "En ligne",
           "R8": "Finitions"}       # jalons du board d'avant la roadmap du GDD (repris, renommés)


def roadmap() -> list:
    """Jalons de la roadmap, lus dans GDD-BLACKOUT.md §15 : [(Rn, titre, description)]."""
    import re
    texte = open(os.path.join(ROOT, "GDD-BLACKOUT.md"), encoding="utf-8").read()
    s15 = texte.split("\n## 15.", 1)[1].split("\n## 16.", 1)[0]
    out = []
    for m in re.finditer(r"^\d+\. \*\*\[(R\d+)\] (.+?)\*\* : (.+?)(?=^\d+\. \*\*|^###|\Z)", s15, re.M | re.S):
        out.append((m.group(1), m.group(2), " ".join(m.group(3).split())))
    if not out:
        sys.exit("roadmap introuvable dans GDD-BLACKOUT.md §15")
    return out


JALONS = [(f"{r} · {t}", f"GDD-BLACKOUT.md §15 [{r}] : {d}", ANCIENS.get(r)) for r, t, d in roadmap()]
JR = {t.split(" · ")[0]: t for t, _d, _a in JALONS}


def appel(route, body=None, query=None):
    if MONTRE and body is not None:
        print("→", route, json.dumps(body, ensure_ascii=False)[:160])
        return {"card": {"id": -1}, "milestone": {"id": -1}, "id": -1}
    return cli.call(route, body, query)


cs = cli.call("cards")
cs = cs.get("cards", cs) if isinstance(cs, dict) else cs
par_cle = {(c.get("asset") or "", c.get("detail") or ""): c for c in cs if c.get("asset")}
par_id = {c["id"]: c for c in cs}


# ------------------------------------------------------------------ jalons
ms = cli.call("milestones")["milestones"]
jalon = {}
for pos, (titre, desc, ancien) in enumerate(JALONS):
    m = next((x for x in ms if x["title"] in (titre, ancien) or x["title"].startswith(titre.split(" · ")[0] + " · ")), None)
    if m is None:
        r = appel("milestone", {"title": titre, "description": desc})
        mid = r.get("milestone", r).get("id")
        appel("milestone_update", {"id": mid, "position": pos})
    else:
        mid = m["id"]
        maj = {"id": mid, "position": pos}
        if m["title"] != titre:
            maj["title"] = titre
        if m["description"] != desc:
            maj["description"] = desc
        appel("milestone_update", maj)
    jalon[titre] = mid


def carte(titre, type_, asset="", detail="", parent=None, statut="backlog", ms=None, desc="", ancien=None):
    """Reprend la carte (asset, détail) ou la crée ; règle chapeau et jalon ; n'en fait jamais reculer la colonne."""
    c = par_cle.get((asset, detail)) if asset else next((x for x in cs if x["title"] == titre), None)
    if c is None and ancien:
        c = next((x for x in cs if x["title"].startswith(ancien)), None)
    if c is None:
        body = {"title": titre, "type": type_, "status": statut, "description": desc}
        if asset:
            body.update(asset=asset, detail=detail)
        if parent:
            body["parent"] = parent
        if ms:
            body["milestone"] = ms
        r = appel("card", body)
        c = {**body, "id": r.get("card", r).get("id"), "parent_id": parent, "milestone_id": ms}
        cs.append(c)
        if asset:
            par_cle[(asset, detail)] = c
        return c["id"]
    maj = {}
    if parent and c.get("parent_id") != parent:
        maj["parent"] = parent
    if ms and c.get("milestone_id") != ms:
        maj["milestone"] = ms
    if titre and c["title"] != titre:
        maj["title"] = titre
    if c.get("type") != type_:
        maj["type"] = type_
    if maj:
        appel("card_update", {"id": c["id"], **maj})
    if RANG[statut] > RANG.get(c["status"], 0) and c["status"] in ("backlog", "todo"):
        appel("card_move", {"id": c["id"], "status": statut})
    return c["id"]


# ------------------------------------------------------------------ persos (itérations)
J = jalon[JR["R2"]]
persos = carte("Persos : les 13 en itérations (base, expressions, animations)", "pixelforge", parent=None, ms=J,
               desc="Chapeau des 13 persos et du fantôme commun. Mettre un perso en Todo le fait partir en file "
                    "(studio.py), dans l'ordre de la colonne, un perso après l'autre.", ancien="Persos v2 : run")
e = it.etat()
b = it.Persos()
noms = {c["asset"].split("/")[2]: c["title"] for c in cs
        if (c.get("asset") or "").startswith("blackout/persos/") and not c.get("detail")}
chapeau = {}
for pid in ORDRE:
    s = e.get(f"persos/{pid}", {})
    asset = f"blackout/persos/{pid}/animations"
    h = carte(noms.get(pid, f"Perso : {pid.capitalize()}"), "perso", asset, "", persos, "todo", J)
    chapeau[pid] = h
    nom = noms.get(pid, pid).split(":")[-1].strip()
    els, ks = en.utiles(b, pid)
    a_tache = lambda d: (d == "base" and s.get("base")) or (d.startswith("expr:") and d[5:] in s.get("expressions", {})) \
        or d in s.get("animations", {})  # noqa: E731
    lignes = [("base", f"{nom} · base neutre (profil et portrait)", "asset")] + \
        [(f"expr:{k}", f"{nom} · expression {k}", "asset") for k in ks] + \
        [(x, f"{nom} · {x}", "animation") for x in els]
    for d, titre, t in lignes:
        carte(titre, t, asset, d, h, "doing" if a_tache(d) else "todo", J)
fan = carte("Fantôme : commun", "perso", "blackout/fantome/fantome/animations", "", persos, "backlog", J)
for x in ("appear", "float", "advance"):
    carte(f"Fantôme · {x}", "animation", "blackout/fantome/fantome/animations", x, fan, "qa", J)
# Décision de Julien (24/10) : refaire la seule réduction de la course de Louis (cycle entier, pixelforge 6d2ce20).
carte("Louis · run : réduction refaite sur le cycle entier (pixelforge 6d2ce20)", "pixelforge", parent=chapeau["louis"],
      statut="todo", ms=J, desc="Proposé par pixelforge, accepté par Julien le 24/10 : même tâche Wan (c4897ae6), "
      "nouvelle réduction (8 poses à pas égal sur les deux foulées), à la place de f850bb52.\n"
      "$ tools/blackout/rereduit.py louis run --prio high\n$ apres: tools/blackout/iteration.py integre louis")

# ------------------------------------------------------------------ PNJ et animaux
J = jalon[JR["R3"]]
pnj = carte("PNJ : 42 humains et 4 animaux en itérations", "pixelforge", ms=J,
            desc="Chapeau des PNJ (GDD §8.4). Chaque PNJ : base neutre, expressions, marche, course, sursaut, "
                 "à terre, relever et ses activités. Mettre un PNJ en Todo le fait partir en file.", ancien="PNJ : génération")
bp = it.Pnj()
for pid, h in bp.p["humains"].items():
    asset = f"blackout/pnj/{pid}/animations"
    hid = carte(next((c["title"] for c in cs if c.get("asset") == asset and not c.get("detail")),
                     f"PNJ : {h['prenom']} ({pid})"), "perso", asset, "", pnj, "backlog", J)
    els = ["run"] + list(bp.extras(pid))
    ks = []
    for x in els + ["portrait"]:
        k = bp.expression(pid, x) if x != "portrait" else bp.base(pid)
        if k != it.NEUTRE and k not in ks:
            ks.append(k)
    nom = h["prenom"]
    for d, titre, t in [("base", f"{nom} · base neutre (profil et portrait)", "asset")] + \
            [(f"expr:{k}", f"{nom} · expression {k}", "asset") for k in ks] + [(x, f"{nom} · {x}", "animation") for x in els]:
        carte(titre, t, asset, d, hid, "backlog", J)
for aid in json.load(open(os.path.join(ROOT, "data", "blackout", "pnj.json")))["animaux"]:
    asset = f"blackout/animaux/{aid}/animations"
    hid = carte(f"Animal : {aid}", "perso", asset, "", pnj, "backlog", J)
    f = os.path.join(ROOT, "assets", "blackout", "animaux", aid, "px32", "animations.json")
    for x in [k for k in (json.load(open(f)) if os.path.exists(f) else {}) if k != "profile"]:
        carte(f"{aid.capitalize()} · {x}", "animation", asset, x, hid, "backlog", J)
    if aid == "chat":     # Julien 24/10 : essai sans marionnette, après les 13 persos (GDD §16)
        carte("Chat : essai Wan sans marionnette contre marionnette (après les 13 persos)", "pixelforge", parent=hid,
              statut="todo", ms=J, desc="Décision de Julien du 24/10 (GDD §16). Comparaison dans /history de pixelforge, "
              "filtre « essai_chat ».\n$ attend: #%d\n$ tools/blackout/depose_json.py tools/blackout/essai_chat.json wan "
              "marionnette" % persos)
gp = next((c for c in cs if c["title"].startswith("PNJ : vie, groupes")), None)
if gp:
    carte(gp["title"], gp["type"], parent=None, ms=J)

# ------------------------------------------------------------------ boss
J = jalon[JR["R4"]]
bos = carte("Boss : 7 boss en 64 px", "pixelforge", ms=J,
            desc="Chapeau des boss (GDD §8.3). Pas encore en itérations (iteration.py ne connaît que persos et PNJ) : "
                 "un boss mis en Todo est lancé par l'agent.", ancien="Boss : 5 boss")
for bid in json.load(open(os.path.join(ROOT, "data", "blackout", "rules.json")))["boss"]:
    asset = f"blackout/boss/{bid}/animations"
    titre = next((c["title"] for c in cs if c.get("asset") == asset and not c.get("detail")), f"Boss : {bid}")
    hid = carte(titre, "perso", asset, "", bos, "backlog", J)
    f = os.path.join(ROOT, "assets", "blackout", "boss", bid, "px32")
    an = json.load(open(os.path.join(f, "animations.json"))) if os.path.exists(os.path.join(f, "animations.json")) else {}
    reel = not json.load(open(os.path.join(f, "set.json"))).get("placeholder") if os.path.exists(os.path.join(f, "set.json")) else False
    for x in [k for k in an if k != "profile"] + ([] if "portrait" in an else ["portrait"]):
        carte(f"{titre.split(':')[-1].strip()} · {x}", "animation", asset, x, hid,
              "qa" if reel and x in an else "backlog", J)

# ------------------------------------------------------------------ autres assets (décisions du 24/10, GDD §16)
for titre, parent, r in (
        ("Basajaun pilote en itérations (après les 13 persos) : clips et actions de cri, pouvoirs ; iteration.py en boss", bos, "R4"),
        ("Portrait des boss en 128 px au versus (côté jeu)", bos, "R4"),
        ("pixelforge : pf_px__creature remis au contrat des persos (après Basajaun)", bos, "R4"),
        ("Prompts complets du chien et du goéland", pnj, "R3")):
    carte(titre, "pixelforge", parent=parent, ms=jalon[JR[r]])
for titre, r in (("Objets des coups (pf_px__prop, après les 13 persos) : phrase, taille, images par objet", "R1"),
                 ("Icônes des 26 coups : cercle bleu (chassé) ou rouge (chasseur), contrôle à 16 et 24 px", "R8"),
                 ("Sprites des effets : étoile, plume, résine, traits du ralenti", "R8"),
                 ("Décor pilote : Port des Pêcheurs (liste des objets et emprises)", "R6")):
    carte(titre, "pixelforge", ms=jalon[JR[r]])

# ------------------------------------------------------------------ studio local (ce chantier)
J = jalon[JR["R0"]]
st = carte("Studio local : board sur Tailscale, QA locale, prod groupée", "feature", ms=J,
           desc="GDD §14.2, docs/PRODUCER.md.")
for t in ("Migration du board en ligne vers le board local, puis suppression de /producer en ligne",
          "Service local : php -S + tailscale serve, launchd", "Colonnes Validé et En prod, accès Tailscale",
          "Watcher studio.py : Todo → file pixelforge, suivi en Doing, keep, chapeaux",
          "Build de QA automatique après intégration (/jeu/)", "Mise en prod groupée 10 min après le dernier accept",
          "Board : roadmap lue dans le GDD (§15, R0…R8)"):
    carte(t, "feature", parent=st, statut="doing", ms=J)
carte("Cartes IA (code) : prise en charge automatique depuis Todo (claude -p), à décider", "feature", parent=st,
      statut="backlog", ms=J)

# ------------------------------------------------------------------ cartes hors assets : jalons
for c in cs:
    t = c["title"]
    for mot, nom in (("En ligne", "R7"), ("Steam Deck", "R8"), ("Icônes", "R8"), ("Tourne ton appareil", "R8")):
        if mot in t and not c.get("asset") and c.get("milestone_id") != jalon[JR[nom]] and c["id"] > 0:
            appel("card_update", {"id": c["id"], "milestone": jalon[JR[nom]]})
print("board réorganisé" + (" (montre)" if MONTRE else ""))
