#!/usr/bin/env python3
"""Limite de travail en cours du kanban /producer (Julien 2026-10-21) : « on va limiter les doing actifs à 5
items, sauf la file night shift qui peut passer sans problème » ; « lorsqu'un item de QA est invalidé, tu le
refais passer dans la Todo avec la bonne priorité ».

  wip.py [--essai]          appelé par tools/gordeka/veille_nuit.sh toutes les 5 min

1. Une carte refusée en QA (rework, revenue en Doing) repart en Todo, priorité haute, si elle n'a pas de
   tâche pixelforge en cours.
2. Julien passe les cartes de Backlog en Todo (21/10) ; la Todo entre en Doing par priorité, 5 cartes actives
   au plus (hors night shift) : animation de perso → recette.py ko (texte du dernier refus en consigne),
   décor du suivi → decor_matin.py relance ; carte qu'on ne sait pas lancer : « BESOIN » (réveille Claude).
3. Décor sorti de la file : intégré tel quel (variante 00), Julien tranche en QA.
4. Cartes de Doing terminées (anims intégrées ; décor intégré, objet avec masque) → en ligne et en QA
   (tools/producer/pousse_qa.sh).
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
LANCEES = os.path.join(ROOT, "tools", "rd", "out", "recette", "wip_lancees.json")
POUSSE = os.path.join(HERE, "pousse_qa.sh")
BESOINS = os.path.join(ROOT, "tools", "rd", "out", "recette", "wip_besoins.json")


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


def decor_auto():
    """Décor sorti de la file : intégré tel quel (variante 00, piste 0 ; Julien tranche en QA, 21/10)."""
    for k, e in list(lire(SUIVI, {}).items()):
        if e.get("statut") != "a_voir":
            continue
        v = {"image": "image_00", "refaire": "image_00", "toit": "image_00", "ouvert": "image_00", "anim": "0"}.get(e.get("sorte"))
        if ESSAI:
            print(f"décor #{k} à intégrer ({e.get('sorte')}, {v})"); continue
        r = subprocess.run([PY, os.path.join(HERE, "decor_matin.py"), "integre", k] + ([v] if v else []) + ["--sans-capture"],
                           cwd=ROOT, capture_output=True, text=True, timeout=1800)
        print(f"décor #{k} : " + (r.stdout + r.stderr).strip().splitlines()[-1][:120] if (r.stdout + r.stderr).strip() else "")


def main():
    doing = cli.call("cards", query={"status": "doing"})["cards"]
    # 1. refus de QA revenus en Doing → Todo, priorité haute (ils repartent par la Todo)
    for c in doing:
        if c.get("rework") and not en_cours(c["id"], c["title"]):
            print(f"#{c['id']} refusé en QA → Todo (haute)")
            if not ESSAI:
                cli.call("card_move", {"id": c["id"], "status": "todo"})
                cli.call("card_update", {"id": c["id"], "priority": "haute"})
    # 2. Julien choisit Backlog → Todo ; la Todo entre en Doing par priorité, 5 cartes actives au plus.
    besoins = lire(BESOINS, [])
    doing = cli.call("cards", query={"status": "doing"})["cards"]
    place = LIMITE - len([c for c in doing if not c.get("night") and not c.get("children")])
    todo = sorted(cli.call("cards", query={"status": "todo"})["cards"],
                  key=lambda c: (not c.get("night"), RANG.get(c.get("priority") or "", 3), c["id"]))
    for c in todo:
        if c.get("children") or c["id"] in besoins:
            continue
        night = bool(c.get("night"))
        if not night and place <= 0:
            break
        quoi = lancer(c, "night" if night else "normal")
        if quoi is None:
            print(f"BESOIN #{c['id']} {c['title']} : en Todo, à lancer par Claude")
            besoins.append(c["id"])
            continue
        print(f"#{c['id']} {c['title']} → Doing : {quoi}")
        if not ESSAI:
            cli.call("card_move", {"id": c["id"], "status": "doing"})
            cli.call("card_comment", {"id": c["id"], "body": f"Pris : {quoi}."})
            lancees = lire(LANCEES, {}); lancees[str(c["id"])] = 1; json.dump(lancees, open(LANCEES, "w"))
        if not night:
            place -= 1
    if not ESSAI:
        json.dump(besoins, open(BESOINS, "w"))
    # 3. décor sorti : intégré tel quel
    decor_auto()
    # 4. cartes de Doing terminées → en ligne et en QA
    pretes = [c["id"] for c in cli.call("cards", query={"status": "doing"})["cards"] if prete(c)]
    if pretes and not ESSAI:
        r = subprocess.run(["bash", POUSSE, "sorties de la file", *map(str, pretes)], cwd=ROOT,
                           capture_output=True, text=True, timeout=3000)
        print(("QA " if "→ QA" in r.stdout else "ALERTE mise en ligne : ") + (r.stdout + r.stderr).strip()[-300:])
    elif pretes:
        print("prêtes pour la QA :", pretes)


def prete(c):
    """Travail de la carte terminé : animations intégrées, ou décor intégré (avec son masque pour un objet)."""
    if str(c["id"]) not in lire(LANCEES, {}):
        return False
    cles = cles_perso(c["title"])
    if cles:
        etat = lire(ETAT, {"items": {}})["items"]
        return all(etat.get(k, {}).get("statut") == "ok" for k in cles)
    e = lire(SUIVI, {}).get(str(c["id"]))
    if not e or e.get("statut") != "integre":
        return False
    import masques_manquants as mm
    el = json.load(open(os.path.join(mm.DECOR, "index.json")))["elements"].get(e.get("element"), {})
    return el.get("type") != "objet" or not el.get("fichiers") or mm.a_besoin(e["element"], el) is None

if __name__ == "__main__":
    main()
