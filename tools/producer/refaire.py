#!/usr/bin/env python3
"""Refus à refaire (Julien, 24/10 ; GDD §14.2, docs/PRODUCER.md).

Une carte « Refuser et refaire » attend Claude : le watcher (studio.py) l'écrit dans .studio/a_traiter.json
avec le commentaire du refus et la demande pixelforge qui serait redéposée. Claude, qui relève ce fichier
toutes les 30 min, écrit .studio/refaire/<id>.json :
  {"modifs": {"prompt": "…", "extras": [...], "elements": [...], "expression": "…"}, "explication": "…"}
(modifs vide : même demande, autre graine). Le watcher contrôle les modifs (controle) et redépose depuis le
profil validé ; l'explication est postée sur la carte. Une demande refusée devient <id>.json.refuse.

  refaire.py                 liste les refus en attente
  refaire.py N modifs.json   contrôle les modifs pour la carte N et les dépose dans .studio/refaire/N.json
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
A_TRAITER = os.path.join(ROOT, ".studio", "a_traiter.json")
REFAIRE = os.path.join(ROOT, ".studio", "refaire")
MODIFIABLES = {"prompt", "extras", "elements", "expression"}
CLES_EXTRA = {"name", "motion", "action", "loop", "fps", "object"}
NEGATION = re.compile(r"\b(sans|pas|ne|aucun|aucune|jamais|ni|no|not|without|never|none)\b|\bn'", re.I)
VISAGE = re.compile(r"\b(sourire|souriant|bouche|yeux|regard|sourcils|visage|smil\w*|mouth|eyes?|eyebrows?|"
                    r"face|facial|grin\w*|frown\w*)\b", re.I)


def controle(avant: dict, apres: dict) -> None:
    """Lève ValueError si la demande ajustée sort du cadre : seuls prompt, extras, elements et expression
    changent (le profil validé reste le socle) ; prompts et actions sans négation ni visage (GDD §8.2, §8.5)."""
    for k in set(avant) | set(apres):
        if k not in MODIFIABLES and avant.get(k) != apres.get(k):
            raise ValueError(f"champ {k} modifié")
    ex = apres.get("extras", [])
    if not isinstance(ex, list) or len(ex) > 4:
        raise ValueError("extras : liste de 4 au plus")
    textes = [apres.get("prompt", "")]
    for x in ex:
        if not isinstance(x, dict) or set(x) - CLES_EXTRA or not x.get("motion"):
            raise ValueError("extra mal formé (clés name, motion, action, loop, fps, object ; motion requis)")
        textes.append(str(x.get("action", "")))
    if not isinstance(apres.get("elements", []), list):
        raise ValueError("elements : liste attendue")
    for t in textes:
        if t and t != avant.get("prompt") and NEGATION.search(t):
            raise ValueError(f"négation dans « {t[:80]} »")
        if t and t != avant.get("prompt") and VISAGE.search(t):
            raise ValueError(f"visage décrit dans « {t[:80]} »")


def main() -> None:
    attente = json.load(open(A_TRAITER)) if os.path.exists(A_TRAITER) else {}
    if len(sys.argv) < 3:
        if not attente:
            print("aucun refus à refaire")
        for cid, a in attente.items():
            print(f"#{cid} {a['titre']} ({a['perso']} · {a['element']})\n  refus : « {a['commentaire']} »")
        return
    cid, dem = sys.argv[1].lstrip("#"), json.load(open(sys.argv[2]))
    if cid not in attente:
        sys.exit(f"#{cid} n'est pas en attente (refaire.py pour la liste)")
    avant = attente[cid]["requete"]
    controle(avant, {**avant, **(dem.get("modifs") or {})})
    if not str(dem.get("explication", "")).strip():
        sys.exit("explication requise (postée sur la carte)")
    os.makedirs(REFAIRE, exist_ok=True)
    json.dump(dem, open(os.path.join(REFAIRE, f"{cid}.json"), "w"), ensure_ascii=False, indent=1)
    print(f"#{cid} : demande ajustée déposée ; le watcher la redépose au prochain tour")


if __name__ == "__main__":
    main()
