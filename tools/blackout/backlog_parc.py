#!/usr/bin/env python3
"""Backlog des assets du Parc Mazon (catalogue de tools/blackout/make_parc_mazon.py).

  backlog_parc.py prompts [--fichier <prompts_decor.json>]   section « cartes → parc_mazon » de prompts_decor.json
  backlog_parc.py kanban [--essai]                            chapeau « Carte : Parc Mazon » + une carte par asset (Backlog)

Prompts : description POSITIVE de l'objet (FLUX ajoute ce qu'on nomme, même précédé de « sans »), puis le
style commun du jeu (flat cartoon, contour bleu marine épais) et la caméra 3/4 de face (front34). Rien n'est
déposé chez pixelforge : Julien priorise. Les cartes déjà créées sont notées dans
tools/blackout/taches_parc_mazon.json (pas de doublon si l'on relance).
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import make_parc_mazon as mp  # noqa: E402

PROMPTS = os.path.join(HERE, "prompts_decor.json")
SUIVI = os.path.join(HERE, "taches_parc_mazon.json")
CLI = os.path.join(ROOT, "tools", "producer", "cli.py")
PX = 128

STYLE = ("Clean flat 2D vector cartoon game art in the style of our game Miarritze Blackout: thick uniform dark navy "
         "#1d2230 outline, flat bright colours with one darker cel-shadow tone and tiny white highlights, chunky rounded "
         "friendly shapes, cute and readable from far away for 9 year old children. Setting: a leafy city park of "
         "Biarritz in the Basque Country, with Basque red #9e1b1b and dark green #1f6b3a touches.")
CAMERA = {
    "pf_hd__prop": ("Camera front34: three-quarter top-down view from the front, about 40 degrees above the ground, the "
                    "top face and the front face both visible, the front face square to the viewer, orthographic. "
                    "Light from the upper left. One single object centred on a plain transparent background."),
    "pf_hd__ground": ("Seamless tileable ground texture seen straight from above, filling the square edge to edge, calm "
                      "low-contrast flat colours with thin slightly darker joint lines so that characters stand out. "
                      "Light from the upper left."),
    "decal": ("Flat decal lying on the ground, seen straight from above, slightly faded like paint on the floor, thin "
              "outline, on a plain transparent background."),
}

# Assets du backlog sans placeholder dans le jeu (décor seulement, ou animations à part).
EXTRA = {
    "pm_lisiere": dict(nom="Lisière des massifs (troncs au bord des allées)", type="bande_facade", taille=(4, 1), deb=2,
        cat="vegetation", anim="planche : feuillage qui bouge",
        prompt="Front edge of a dense park grove seen from the path: a row of tree trunks of different sizes, ferns and "
               "shrubs at their feet, the low leafy branches above, seamless from left to right.",
        remarques="Posée sur le bord sud des massifs « v » qui donnent sur une allée (comme les façades du port)."),
    "pm_cloture_bande": dict(nom="Clôture du parc vue de face", type="bande_facade", taille=(4, 1), deb=1, cat="mur",
        prompt="Dark green iron park railing with round gilded finials on a low pale stone wall, a strip of hedge behind it, "
               "seamless from left to right."),
    "pm_marquage_cancha": dict(nom="Marquage du terrain de pelote", type="decal", taille=(14, 12), deb=0, cat="sol",
        prompt="Painted lines of a Basque pelota court on pale cement: long straight white side lines, numbered cross lines "
               "every few metres in red, the service line in front of the wall."),
    "pm_canards": dict(nom="Canards de la mare (animés)", type="anim", taille=(1, 1), deb=0, cat="animal",
        anim="planche : 2 canards qui nagent en rond, 6 à 8 images en boucle ; envol quand un chassé passe",
        prompt="Two cute white and brown ducks swimming side by side, small ripples around them, seen from above with a "
               "slight three-quarter tilt.",
        remarques="Comme les mouettes du port (idee_mouettes) : ils s'envolent en cancanant quand un chassé passe."),
    "pm_pigeons": dict(nom="Pigeons du parc (animés)", type="anim", taille=(1, 1), deb=0, cat="animal",
        anim="planche : picorent (4 images) et s'envolent (4 images)",
        prompt="Small group of three plump grey park pigeons pecking crumbs on the ground, one with a shiny green neck.",
        remarques="Remplacent les mouettes du port sur cette carte (même règle d'envol)."),
    "pm_fontaine_jet": dict(nom="Fontaine : jet d'eau animé", type="anim", taille=(4, 4), deb=0, cat="repere",
        anim="planche : jet d'eau et rides du bassin, boucle (sur l'image fontaine_place reprise du port)",
        prompt="Water spouting from the top of the stone fountain and falling back in sparkling drops, ripples spreading "
               "in the turquoise basin.",
        remarques="La fontaine est reprise du port (fontaine_place) ; son animation sert aux deux cartes."),
    "pm_feuilles": dict(nom="Feuilles qui tombent (effet)", type="anim", taille=(1, 1), deb=0, cat="effet",
        anim="planche : 3 feuilles de platane qui tombent en tournoyant, boucle",
        prompt="Three golden plane tree leaves gently falling and spinning, light and airy.",
        remarques="Petites particules lâchées de temps en temps sous les gros arbres."),
}


def style_de(el):
    t = el.get("type", "objet")
    if t == "tuile_sol":
        return "pf_hd__ground"
    if t == "decal" or el.get("cat") == "sortie":
        return "decal"
    return "pf_hd__prop"


def entree(eid, el):
    w, h = el["taille"]
    deb = el.get("deb", 0)
    st = style_de(el)
    prompt = f"{el['prompt']} {STYLE} {CAMERA[st]}"
    ch = el.get("car", "")
    bloque = el.get("bloque_vue")
    if bloque is None:
        bloque = ch in mp.OCCLUDE
    poses = sum(1 for (i, _, _) in mp.PLACES if i == eid)
    return {
        "id": eid, "nom": el["nom"], "caractere": ch, "categorie": el.get("cat", ""), "type": el.get("type", "objet"),
        "taille_cases": [w, h], "debord_haut_cases": deb,
        "taille_sortie_px": [w * PX, int((h + deb) * PX)],
        "gameplay": {"bloque_vue": bool(bloque) and ch not in mp.WALK, "bloque_passage": ch not in mp.WALK and ch != "",
                     "cachette": ch == "H", "sortie": ch == "E"},
        "poses_sur_la_carte": poses,
        "style_pixelforge_suggere": st if st != "decal" else "pf_hd__ground",
        "prompt_specifique": el["prompt"], "prompt": prompt,
        "animation": el.get("anim", ""),
        "placeholder": (f"assets/maps/parc_mazon/decor/{'sols' if el.get('type') == 'tuile_sol' else 'objets'}/{eid}.png"
                        if el.get("dessin") or el.get("type") in ("tuile_sol", "decal") and eid in mp.CAT else ""),
        "remarques": el.get("remarques", ""),
    }


def catalogue():
    mp.build(argparse.Namespace(sortie_sud=False, version=mp.VERSION))
    out = []
    for eid, el in list(mp.CAT.items()) + list(EXTRA.items()):
        if el.get("reprise"):
            continue
        out.append(entree(eid, el))
    return out


def section():
    return {
        "_doc": "Assets à créer pour le Parc Mazon (tools/blackout/backlog_parc.py, catalogue de make_parc_mazon.py). "
                "Prompts positifs (sans négation), style commun et caméra front34 ; tailles en cases de 64 px, "
                "images à 128 px par case. Rien n'est déposé chez pixelforge : Julien priorise sur /producer "
                "(carte chapeau « Carte : Parc Mazon »). Repris du port sans nouvelle image : banc_vert, fontaine_place, "
                "table_terrasse, cachette_poubelle_ruelle.",
        "style_commun": STYLE, "camera_commune": CAMERA,
        "elements": catalogue(),
    }


def cmd_prompts(args):
    path = args.fichier or PROMPTS
    d = json.load(open(path, encoding="utf-8"))
    d.setdefault("cartes", {})["parc_mazon"] = section()
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(d, ensure_ascii=False, indent=1))
    print(path, len(d["cartes"]["parc_mazon"]["elements"]), "éléments")


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
        import re
        m = re.search(r"#?(\d+)", sortie)
        return int(m.group(1)) if m else 0


def desc(e):
    lignes = [f"Prompt proposé ({e['style_pixelforge_suggere']}) :", e["prompt"], "",
              f"Taille : {e['taille_cases'][0]} × {e['taille_cases'][1]} cases"
              + (f", débord vers le haut {e['debord_haut_cases']} case(s)" if e["debord_haut_cases"] else "")
              + f" → image {e['taille_sortie_px'][0]} × {e['taille_sortie_px'][1]} px (128 px par case).",
              f"Type : {e['type']} · caractère « {e['caractere']} » · posé {e['poses_sur_la_carte']} fois sur la carte."]
    g = e["gameplay"]
    jeu = [k for k, v in (("cache la vue", g["bloque_vue"]), ("bloque le passage", g["bloque_passage"]),
                          ("cachette (1 joueur)", g["cachette"]), ("sortie", g["sortie"])) if v]
    if jeu:
        lignes.append("Jeu : " + ", ".join(jeu) + ".")
    if e["animation"]:
        lignes.append("Animation : " + e["animation"] + ".")
    if e["placeholder"]:
        lignes.append("Placeholder actuel : " + e["placeholder"])
    if e["remarques"]:
        lignes.append("Remarques : " + e["remarques"])
    lignes.append(f"Élément : {e['id']} (tools/blackout/prompts_decor.json → cartes → parc_mazon).")
    return "\n".join(lignes)


def cmd_kanban(args):
    suivi = json.load(open(SUIVI, encoding="utf-8")) if os.path.exists(SUIVI) else {}
    els = catalogue()
    if args.essai:
        for e in els:
            print("—", e["nom"])
        print(len(els), "cartes")
        return
    if "chapeau" not in suivi:
        d = ("Assets à créer pour la nouvelle carte Parc Mazon (parc urbain pour enfants, fronton central, aires de jeux "
             "des petits et des grands). Carte jouable en partie rapide avec des placeholders dessinés par le code "
             "(assets/maps/parc_mazon/decor/). Une carte enfant par asset, prompt proposé dans la description "
             "(tools/blackout/prompts_decor.json → cartes → parc_mazon). À prioriser par Julien : rien n'est déposé chez "
             "pixelforge. Section de la carte : GDD-BLACKOUT.md")
        suivi["chapeau"] = _id(cli("add-card", "--type", "asset", "--title", "Carte : Parc Mazon", "--desc", d,
                                   "--status", "backlog"))
        print("chapeau", suivi["chapeau"])
    for e in els:
        if e["id"] in suivi:
            continue
        suivi[e["id"]] = _id(cli("add-card", "--type", "asset", "--title", e["nom"], "--desc", desc(e),
                                 "--parent", str(suivi["chapeau"]), "--status", "backlog"))
        print(e["id"], suivi[e["id"]])
        with open(SUIVI, "w", encoding="utf-8") as fh:
            json.dump(suivi, fh, ensure_ascii=False, indent=1)
        # Animation : carte à part (sur l'image fixe validée), sauf pour les éléments qui ne sont qu'une animation.
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
