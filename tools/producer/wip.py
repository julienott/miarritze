#!/usr/bin/env python3
"""Limite de travail en cours du kanban /producer (Julien 2026-10-21) : « on va limiter les doing actifs à 5
items, sauf la file night shift qui peut passer sans problème » ; « lorsqu'un item de QA est invalidé, tu le
refais passer dans la Todo avec la bonne priorité ».

  wip.py [--essai]          appelé par tools/gordeka/veille_nuit.sh toutes les 5 min

1. Une carte refusée en QA (rework, revenue en Doing) repart en Todo, priorité haute, si elle n'a pas de
   tâche pixelforge en cours.
2. Tant qu'il y a moins de LIMITE cartes actives en Doing (hors night shift et hors chapeaux), la première carte
   de Todo (priorité haute > normale > basse > aucune, puis la plus ancienne) qu'on sait lancer est lancée :
   animation de perso → recette.py ko (le dernier refus de Julien sert de consigne) ;
   décor du suivi (image, refaire, ouverte, animation, masque) → decor_matin.py relance ;
   puis la carte passe en Doing. Les cartes qu'on ne sait pas lancer seul (fonctionnalités, fantômes
   générés…) sont laissées en Todo et listées.
Une carte night shift en Todo est lancée en priorité « night » sans compter dans la limite.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import cli  # noqa: E402
import todo_vers_file as tv  # noqa: E402

LIMITE = 5
ESSAI = "--essai" in sys.argv
PY = os.path.join(ROOT, ".venv", "bin", "python")
ETAT = os.path.join(ROOT, "tools", "rd", "out", "recette", "etat.json")
SUIVI = os.path.join(ROOT, "tools", "gordeka", "taches_decor_nuit.json")
RANG = {"haute": 0, "normale": 1, "basse": 2, "": 3}


def lire(p, d):
    return json.load(open(p)) if os.path.exists(p) else d


def cles_perso(titre):
    """Clés recette d'une carte « <Perso> · <animation|emotes> », ou []."""
    if " · " not in titre or titre.split(" · ")[0] not in tv.NOMS:
        return []
    nom, reste = titre.split(" · ", 1)
    pid = tv.NOMS[nom]
    if reste in tv.ANIMS:
        return [f"perso/{pid}/{tv.ANIMS[reste]}"]
    if reste.startswith("emotes"):
        return [f"perso/{pid}/{e}" for e in tv.EMOTES]
    return []


def dernier_refus(cid):
    """Texte du dernier refus de Julien sur la carte (sert de consigne), ou ""."""
    for ev in reversed(cli.call("card", query={"id": cid}).get("events") or []):
        if ev.get("author") == "julien" and ev.get("type") == "refuse":
            return ev.get("new", "")
    return ""


def en_cours(cid, titre):
    etat = lire(ETAT, {"items": {}})["items"]
    if any(etat.get(k, {}).get("statut") in ("en_vol", "attente") for k in cles_perso(titre)):
        return True
    s = lire(SUIVI, {})
    el = s.get(str(cid), {}).get("element")
    # la carte, ou une tâche du même élément (masque d'une image retouchée…) en file
    return s.get(str(cid), {}).get("statut") == "en_file" or bool(el) and any(
        e.get("element") == el and e.get("statut") == "en_file" for e in s.values())


def lancer(c, prio):
    """Lance la carte ; renvoie un résumé, ou None si on ne sait pas la lancer seul."""
    cles = cles_perso(c["title"])
    consigne = dernier_refus(c["id"])
    if cles:
        etat = lire(ETAT, {"items": {}})
        a_faire = [k for k in cles if etat["items"].get(k, {}).get("statut") != "ok" or len(cles) == 1]
        if ESSAI:
            return f"anim {a_faire} « {consigne[:60]} »"
        for k in a_faire:
            subprocess.run([PY, os.path.join(ROOT, "tools", "gordeka", "recette.py"), "ko", k] + ([consigne] if consigne else []),
                           cwd=ROOT, check=True, capture_output=True)
        return f"animation(s) relancée(s) : {', '.join(k.split('/')[-1] for k in a_faire)}"
    ent = lire(SUIVI, {}).get(str(c["id"]))
    if ent and ent.get("statut") in ("todo", "attend", "integre", "a_voir", None):
        if ESSAI:
            return f"décor {ent.get('sorte')} « {consigne[:60]} »"
        subprocess.run([PY, os.path.join(HERE, "decor_matin.py"), "relance", str(c["id"])] + ([consigne] if consigne else []),
                       cwd=ROOT, check=True, capture_output=True, timeout=900)
        return f"décor ({ent.get('sorte')}) relancé"
    return None


def main():
    doing = cli.call("cards", query={"status": "doing"})["cards"]
    # 1. refus de QA revenus en Doing → Todo, priorité haute
    for c in doing:
        if c.get("rework") and not en_cours(c["id"], c["title"]):
            print(f"#{c['id']} refusé en QA → Todo (haute)")
            if not ESSAI:
                cli.call("card_move", {"id": c["id"], "status": "todo"})
                cli.call("card_update", {"id": c["id"], "priority": "haute"})
    doing = cli.call("cards", query={"status": "doing"})["cards"]
    actives = [c for c in doing if not c.get("night") and not c.get("children")]
    place = LIMITE - len(actives)
    todo = sorted(cli.call("cards", query={"status": "todo"})["cards"],
                  key=lambda c: (not c.get("night"), RANG.get(c.get("priority") or "", 3), c["id"]))
    laissees = []
    for c in todo:
        if c.get("children"):
            continue
        night = bool(c.get("night"))
        if not night and place <= 0:
            break
        quoi = lancer(c, "night" if night else "normal")
        if quoi is None:
            laissees.append(c["id"])
            continue
        print(f"#{c['id']} {c['title']} → Doing : {quoi}")
        if not ESSAI:
            cli.call("card_move", {"id": c["id"], "status": "doing"})
            cli.call("card_comment", {"id": c["id"], "body": f"Pris (place libre en Doing) : {quoi}."})
        if not night:
            place -= 1
    if laissees and ESSAI:
        print("laissées en Todo (à lancer à la main) :", laissees)


if __name__ == "__main__":
    main()
