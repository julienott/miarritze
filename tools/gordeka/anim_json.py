"""Écriture des <anim>.json des persos, commune aux post-traitements (pieds.py, lampe.py,
post_anims.py) : un seul format, pour que relancer un traitement ne réécrive rien si rien n'a changé.

- une paire [dx, dy] de flottants par ligne (frame_offsets, decalage) ;
- après "lampe" : une paire d'entiers par ligne (points de la main) ;
- après "entrees" : chaque liste d'entiers sur une ligne (tables de points d'entrée) ;
- cell, feet_anchor et le reste : format json.dumps(indent=1) d'origine.
"""
import json
import re

_PAIRE_F = re.compile(r"\[\s*(-?\d+\.\d+),\s*(-?\d+\.\d+)\s*\]")
_PAIRE_I = re.compile(r"\[\s*(-?\d+),\s*(-?\d+)\s*\]")
_LISTE_I = re.compile(r"\[\s*((?:-?\d+,\s*)*-?\d+)\s*\]")


# Clés ajoutées par les post-traitements, toujours dans cet ordre et après celles de pixelforge :
# chaque outil peut retirer puis remettre les siennes sans que le fichier change.
ORDRE_POST = ("frame_offsets", "stride_px", "lampe", "echelle", "decalage", "debut", "fin", "entrees")


def formater(j: dict) -> str:
    j = {**{k: v for k, v in j.items() if k not in ORDRE_POST}, **{k: j[k] for k in ORDRE_POST if k in j}}
    texte = json.dumps(j, indent=1, ensure_ascii=False)
    texte = _PAIRE_F.sub(r"[\1, \2]", texte)
    for cle, motif, rempl in (('"lampe"', _PAIRE_I, r"[\1, \2]"),
                              ('"entrees"', _LISTE_I, lambda m: "[" + ", ".join(re.split(r",\s*", m.group(1))) + "]")):
        i = texte.find(cle)
        if i >= 0:
            # Jusqu'à la clé de premier niveau suivante (indentation d'un espace).
            k = texte.find('\n "', i + len(cle))
            k = len(texte) if k < 0 else k
            texte = texte[:i] + motif.sub(rempl, texte[i:k]) + texte[k:]
    return texte


def ecrire(chemin: str, j: dict) -> bool:
    """Écrit `j` au format commun ; False (rien d'écrit) si le fichier est déjà identique."""
    texte = formater(j)
    try:
        if open(chemin).read() == texte:
            return False
    except OSError:
        pass
    with open(chemin, "w") as fh:
        fh.write(texte)
    return True
