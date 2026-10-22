#!/usr/bin/env python3
"""Backlog des assets de la Plage de la Côte des Basques (catalogue de tools/blackout/make_plage.py).

  backlog_plage.py prompts [--fichier <prompts_decor.json>]   section « cartes → plage » de prompts_decor.json
  backlog_plage.py kanban [--essai]                            chapeau « Carte : Plage de la Côte des Basques »
                                                               + une carte par asset (Backlog)

Prompts : description POSITIVE de l'objet (le générateur ajoute ce qu'on nomme, même précédé de « sans »), puis
le style commun du jeu (flat cartoon, contour bleu marine épais) et la caméra 3/4 de face (front34). Rien n'est
déposé chez pixelforge : Julien priorise. Les cartes déjà créées sont notées dans tools/blackout/taches_plage.json
(pas de doublon si l'on relance). Les images communes reprises du port (« fichier » dans le catalogue) n'ont pas
de carte.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import make_plage as mp  # noqa: E402

PROMPTS = os.path.join(HERE, "prompts_decor.json")
SUIVI = os.path.join(HERE, "taches_plage.json")
CLI = os.path.join(ROOT, "tools", "producer", "cli.py")
PX = 128

STYLE = ("Clean flat 2D vector cartoon game art in the style of our game Miarritze Blackout: thick uniform dark navy "
         "#1d2230 outline, flat bright colours with one darker cel-shadow tone and tiny white highlights, chunky rounded "
         "friendly shapes, cute and readable from far away for 9 year old children. Setting: the Côte des Basques beach "
         "of Biarritz in the Basque Country under a summer sun: golden sand, ochre sandstone cliffs, turquoise and navy "
         "sea, with Basque red #9e1b1b and dark green #1f6b3a touches.")
CAMERA = {
    "pf_hd__prop": ("Camera front34: three-quarter top-down view from the front, about 40 degrees above the ground, the "
                    "top face and the front face both visible, the front face square to the viewer, orthographic. "
                    "Light from the upper left. One single object centred on a plain transparent background."),
    "pf_hd__ground": ("Seamless tileable ground texture seen straight from above, filling the square edge to edge, calm "
                      "low-contrast flat colours with thin slightly darker joint lines so that characters stand out. "
                      "Light from the upper left."),
    "pf_hd__texture": ("Camera front34: the front face of a cliff in a three-quarter top-down map, square to the viewer, "
                       "orthographic, seamless from left to right. Light from the upper left."),
    "decal": ("Flat decal lying on the ground, seen straight from above, slightly faded like paint on the floor, thin "
              "outline, on a plain transparent background."),
    "anim": ("Camera front34: three-quarter top-down view from the front, about 40 degrees above the ground, "
             "orthographic. Light from the upper left. Animation frames side by side on a plain transparent background, "
             "same size and position in every frame, seamless loop."),
}


def style_de(eid, el, kind):
    if kind == "anim":
        return "anim"
    if kind == "sol":
        return "pf_hd__texture" if eid == "falaise_face" else "pf_hd__ground"
    if el.get("type") == "decal":
        return "decal"
    return "pf_hd__prop"


def poses(eid):
    return sum(1 for p in mp.placed if p[0] == eid)


def entree(eid, el, kind):
    st = style_de(eid, el, kind)
    if kind == "sol":
        w, h = (2, 1) if eid == "falaise_face" else (2, 2)
        deb, ch, cat, typ = 0, el["car"], "sol", "tuile_sol"
    elif kind == "anim":
        (w, h), deb, ch, cat, typ = el["taille"], 0, "", "anime", "anim"
    else:
        (w, h), deb, ch, cat, typ = el["taille"], el["haut"], el["car"], el["cat"], el.get("type", "objet")
    prompt = f"{el['prompt']} {STYLE} {CAMERA[st]}"
    walk = ch in mp.WALK or ch == "." or kind == "anim"
    return {
        "id": eid, "nom": el["nom"], "caractere": ch, "categorie": cat, "type": typ,
        "taille_cases": [w, h], "debord_haut_cases": deb,
        "taille_sortie_px": [w * PX, int(round((h + deb) * PX))],
        "gameplay": {"bloque_vue": ch in mp.OCCLUDE, "bloque_passage": not walk,
                     "cachette": ch == "H", "sortie": ch == "E"},
        "poses_sur_la_carte": poses(eid) if kind == "objet" else 0,
        "zones": el.get("zones", []) if kind != "objet" else sorted({mp.ZONES[mp.zone_of(x, y)][0] if mp.zone_of(x, y) >= 0
                                                                    else "tunnels" for (i, x, y, _, _) in mp.placed if i == eid}),
        "style_pixelforge_suggere": "pf_hd__ground" if st == "decal" else ("pf_2d__loop" if st == "anim" else st),
        "prompt_specifique": el["prompt"], "prompt": prompt,
        "animation": el.get("anim", "") if kind != "anim" else "boucle (planche d'images)",
        "placeholder": f"assets/maps/plage/decor/provisoires/{eid}.png" if kind != "anim" else "",
        "etat_ouvert": ch == "H",
    }


def catalogue():
    mp.build()
    out = []
    for eid, el in mp.ELEMENTS.items():
        if "fichier" not in el and poses(eid):
            out.append(entree(eid, el, "objet"))
    for eid, el in mp.FLOORS.items():
        if "fichier" not in el and "fichier_de" not in el:
            out.append(entree(eid, el, "sol"))
    for eid, el in mp.ANIMES.items():
        out.append(entree(eid, el, "anim"))
    return out


def section():
    repris = sorted({el["fichier"].split("/")[-1].removesuffix(".png") for el in list(mp.ELEMENTS.values()) +
                     list(mp.FLOORS.values()) if "fichier" in el})
    return {
        "_doc": "Assets à créer pour la Plage de la Côte des Basques (tools/blackout/backlog_plage.py, catalogue de "
                "make_plage.py). Prompts positifs (sans négation), style commun et caméra front34 ; tailles en cases de "
                "64 px, images à 128 px par case. Les cachettes demandent aussi une image « ouverte » (pf_hd__edit). "
                "Rien n'est déposé chez pixelforge : Julien priorise sur /producer (carte chapeau « Carte : Plage de la "
                "Côte des Basques »). Repris du port sans nouvelle image : " + ", ".join(repris) + ".",
        "style_commun": STYLE, "camera_commune": CAMERA,
        "elements": catalogue(),
    }


def cmd_prompts(args):
    path = args.fichier or PROMPTS
    d = json.load(open(path, encoding="utf-8"))
    d.setdefault("cartes", {})["plage"] = section()
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(d, ensure_ascii=False, indent=1))
    print(path, len(d["cartes"]["plage"]["elements"]), "éléments")


def cli(*a):
    r = subprocess.run([sys.executable, CLI, *a], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"cli.py {a[0]} : {r.stderr.strip() or r.stdout.strip()}")
    return r.stdout


def _id(sortie):
    """Numéro de carte dans la sortie de cli.py add-card."""
    try:
        return int(json.loads(sortie)["id"])
    except (ValueError, KeyError, TypeError):
        m = re.search(r"#?(\d+)", sortie)
        return int(m.group(1)) if m else 0


def desc(e):
    lignes = [f"Prompt proposé ({e['style_pixelforge_suggere']}) :", e["prompt"], "",
              f"Taille : {e['taille_cases'][0]} × {e['taille_cases'][1]} cases"
              + (f", débord vers le haut {e['debord_haut_cases']} case(s)" if e["debord_haut_cases"] else "")
              + f" → image {e['taille_sortie_px'][0]} × {e['taille_sortie_px'][1]} px (128 px par case)."]
    if e["type"] == "anim":
        lignes.append("Type : animation (planche en boucle), sans place fixe sur la grille.")
    else:
        lignes.append(f"Type : {e['type']} · caractère « {e['caractere']} »"
                      + (f" · posé {e['poses_sur_la_carte']} fois sur la carte." if e["poses_sur_la_carte"] else "."))
    g = e["gameplay"]
    jeu = [k for k, v in (("cache la vue", g["bloque_vue"]), ("bloque le passage", g["bloque_passage"]),
                          ("cachette (1 joueur, image fermée + image ouverte)", g["cachette"]),
                          ("sortie (on marche dessus)", g["sortie"])) if v]
    if jeu:
        lignes.append("Jeu : " + ", ".join(jeu) + ".")
    if g["bloque_vue"] and e["debord_haut_cases"]:
        lignes.append("Base au sol qui bloque, haut qui passe devant un perso caché derrière (masques pf_2d__footprint).")
    if e["animation"]:
        lignes.append("Animation : " + e["animation"] + ".")
    if e["placeholder"]:
        lignes.append("Placeholder actuel : " + e["placeholder"])
    lignes.append(f"Élément : {e['id']} (tools/blackout/prompts_decor.json → cartes → plage).")
    return "\n".join(lignes)


def cmd_kanban(args):
    suivi = json.load(open(SUIVI, encoding="utf-8")) if os.path.exists(SUIVI) else {}
    els = catalogue()
    if args.essai:
        for e in els:
            print("—", e["nom"], e["taille_cases"], e["style_pixelforge_suggere"])
        print(len(els), "cartes")
        return
    if "chapeau" not in suivi:
        d = ("Assets à créer pour la nouvelle carte Plage de la Côte des Basques (falaise et grottes reliées par des "
             "tunnels sombres, cabines rayées, deux restaurants avec cuisine, poste de secours, rochers du Basta, "
             "bateaux tirés au sec, Port-Vieux et sa digue). Carte jouable en partie rapide avec des placeholders "
             "dessinés par le code (assets/maps/plage/decor/provisoires/). Une carte enfant par asset, prompt proposé "
             "dans la description (tools/blackout/prompts_decor.json → cartes → plage). À prioriser par Julien : rien "
             "n'est déposé chez pixelforge. Section de la carte : GDD-BLACKOUT.md")
        suivi["chapeau"] = _id(cli("add-card", "--type", "asset", "--title", "Carte : Plage de la Côte des Basques",
                                   "--desc", d, "--status", "backlog"))
        print("chapeau", suivi["chapeau"])
    for e in els:
        if e["id"] in suivi:
            continue
        typ = "animation" if e["type"] == "anim" else "asset"
        suivi[e["id"]] = _id(cli("add-card", "--type", typ, "--title", e["nom"], "--desc", desc(e),
                                 "--parent", str(suivi["chapeau"]), "--status", "backlog"))
        print(e["id"], suivi[e["id"]])
        with open(SUIVI, "w", encoding="utf-8") as fh:
            json.dump(suivi, fh, ensure_ascii=False, indent=1)
        # Animation d'un objet : carte à part (sur l'image fixe validée).
        if e["animation"] and e["type"] != "anim" and e["id"] + ":anim" not in suivi:
            suivi[e["id"] + ":anim"] = _id(cli(
                "add-card", "--type", "animation", "--title", f"{e['nom']} : animation",
                "--desc", f"{e['animation']}.\nÀ faire sur l'image fixe validée de « {e['nom']} » ({e['id']}).",
                "--parent", str(suivi["chapeau"]), "--status", "backlog"))
    with open(SUIVI, "w", encoding="utf-8") as fh:
        json.dump(suivi, fh, ensure_ascii=False, indent=1)
    print(len(suivi), "cartes notées dans", SUIVI)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prompts")
    p.add_argument("--fichier", default="")
    k = sub.add_parser("kanban")
    k.add_argument("--essai", action="store_true")
    a = ap.parse_args()
    {"prompts": cmd_prompts, "kanban": cmd_kanban}[a.cmd](a)


if __name__ == "__main__":
    main()
