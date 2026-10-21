#!/usr/bin/env python3
"""Masques de gameplay manquants ou périmés : dépôt pf_2d__footprint en priorité haute (Julien 2026-10-21 :
« pour les existants sans masque, fais générer le masque en haute prio » ; « ne mets pas d'objets hauts en
QA sans avoir généré le masque »).

  masques_manquants.py [--essai] [--sauf eid,eid]

Un objet (type « objet » de assets/gordeka/decor/index.json) a besoin d'un masque s'il n'a pas de masks.json,
ou si la taille notée dans masks.json n'est plus celle de son image (image refaite). Les masques déjà en file
sont repassés en priorité haute ; les autres sont déposés (entrée masque du suivi de decor_matin, carte
existante ou « m-<élément> »). Dépôt sans attente : si pixelforge est plein, on reprendra au passage suivant
(la veille appelle ce script).
"""
import json
import os
import sys
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import todo_decor as td  # noqa: E402

DECOR = os.path.join(ROOT, "assets", "gordeka", "decor")
ESSAI = "--essai" in sys.argv
SAUF = set(sys.argv[sys.argv.index("--sauf") + 1].split(",")) if "--sauf" in sys.argv else set()


def a_besoin(eid, el):
    m = os.path.join(DECOR, "masques", eid, "masks.json")
    if not os.path.exists(m):
        return "aucun masque"
    taille = json.load(open(m)).get("size")
    img = Image.open(os.path.join(DECOR, el["fichiers"][0])).size
    return f"masque périmé ({taille} ≠ {list(img)})" if taille and tuple(taille) != tuple(img) else None


def haute(tid):
    req = urllib.request.Request(f"{td.pf.PF}/v2/inferences/tasks/{tid}", data=json.dumps({"priority": "high"}).encode(),
                                 method="PATCH", headers={"Content-Type": "application/json", **td.pf.AUTH})
    urllib.request.urlopen(req, timeout=30).read()


def main():
    idx = json.load(open(os.path.join(DECOR, "index.json")))["elements"]
    s = json.load(open(td.SUIVI))
    td.deposer.__defaults__ = (1,)                   # pas d'attente : file pleine → passage suivant
    for eid, el in idx.items():
        if el.get("type") != "objet" or not el.get("fichiers") or eid in SAUF:
            continue
        pourquoi = a_besoin(eid, el)
        if not pourquoi:
            continue
        ents = [(k, e) for k, e in s.items() if e.get("sorte") == "masque" and e.get("element") == eid]
        en_file = [(k, e) for k, e in ents if e.get("statut") in ("en_file", "a_voir")]
        if en_file:
            k, e = en_file[0]
            if e.get("statut") == "en_file" and e.get("priorite") != "high" and not ESSAI:
                for j in e.get("jobs") or []:
                    try:
                        haute(j["tid"])
                    except Exception as ex:  # noqa: BLE001
                        print("  priorité non changée", j["tid"], str(ex)[:80])
                e["priorite"] = "high"
                json.dump(s, open(td.SUIVI, "w"), ensure_ascii=False, indent=1)
            print(f"{eid} : {pourquoi}, déjà {e['statut']} (#{k}, haute)")
            continue
        k, e = ents[0] if ents else (f"m-{eid}", {"titre": f"{el.get('nom', eid)} : masque", "sorte": "masque",
                                                  "element": eid})
        if ESSAI:
            print(f"{eid} : {pourquoi} → à déposer (#{k})")
            continue
        try:
            n = td.depose_entree(k, e, "high")
        except RuntimeError as ex:
            print(f"{eid} : pixelforge plein, reprise au prochain passage ({str(ex)[:60]})")
            return
        e.pop("depend", None)
        s[k] = e
        json.dump(s, open(td.SUIVI, "w"), ensure_ascii=False, indent=1)
        if k.isdigit():
            td.prise(k, e)
        print(f"{eid} : {pourquoi} → déposé #{k} ({n} job, haute)")


if __name__ == "__main__":
    main()
