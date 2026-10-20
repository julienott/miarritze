#!/usr/bin/env python3
"""Remplit le kanban /producer avec tout ce qui est fait ou reste à faire sur Gordeka (Julien 2026-10-20 :
« créer tout ce qu'il y a à faire ou reste à faire sur le kanban pour pouvoir décider »).

  remplit_kanban.py [--essai]       --essai : affiche sans rien créer

Colonnes : QA = en ligne, à tester ; Backlog = à faire, Julien priorise et passe en Todo.
Cartes chapeau : un perso (profil + animations), le décor (sols, objets, cachettes, sorties, animations
du décor, masques), le gameplay, les bugs. Idempotent par titre : une carte déjà présente n'est pas recréée.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import cli  # noqa: E402

ESSAI = "--essai" in sys.argv
PERSOS = ["louis", "txomin", "patxi", "maia", "xabi", "mattin", "amaia", "kaio", "karramarro", "ramuntxo",
          "itsaso", "peio"]
NOMS = {"louis": "Louis", "txomin": "Txomin", "patxi": "Patxi", "maia": "Maïa", "xabi": "Xabi", "mattin": "Mattin",
        "amaia": "Amaia", "kaio": "Kaio", "karramarro": "Karramarro", "ramuntxo": "Ramuntxo", "itsaso": "Itsaso",
        "peio": "Peio"}
ANIMS = {"idle": "repos", "walk": "marche", "run_scared": "fuite apeurée", "hide_in": "se cacher",
         "hide_out": "sortir de cachette", "found": "trouvé", "trap": "poser un piège", "trapped": "pris au piège",
         "search": "fouiller", "detect": "détecter", "extract": "sortir un chassé", "victory": "victoire",
         "sad": "tristesse", "hunter_reveal": "apparition du chasseur"}
# Défauts connus des versions en ligne (recette de Claude, à confirmer par Julien).
DEFAUTS = {
    ("xabi", "hide_out"): "Chistera stable mais geste de sortie presque immobile (3e essai).",
    ("patxi", "hunter_reveal"): "Le faisceau monte vers le haut (torche brandie) au lieu de partir devant.",
    ("xabi", "hunter_reveal"): "La lumière sort de la chistera, qui rétrécit un peu.",
    ("kaio", "run_scared"): "Ailes qui battent sur une partie des images, un bras gris au-dessus de la tête sur l'autre "
                            "(avant le réglage arms « wings » de pixelforge) : à refaire avec arms wings.",
    ("kaio", "walk"): "Une ou deux images un peu floues sur l'aile.",
    ("kaio", "found"): "Masque de tenue vide : le foulard ne prend pas la couleur du joueur (recalcul pf_2d__tenue).",
    ("louis", "emote_salut"): "Ancien clip wave : main près de la joue.",
    ("mattin", "ghost_move"): "Bon dans l'ensemble (3e essai), le buste tourne encore très légèrement.",
}

existantes = {c["title"]: c for c in cli.call("cards")["cards"]}
crees = 0


def carte(titre, typ, statut, parent=None, desc="", asset="", prio=""):
    global crees
    if titre in existantes:
        return existantes[titre]["id"]
    if ESSAI:
        print(f"[{statut}] {typ} · {titre}" + (f"  ↑{parent}" if parent else ""))
        existantes[titre] = {"id": f"?{len(existantes)}"}
        return existantes[titre]["id"]
    body = {"type": typ, "title": titre, "description": desc, "priority": prio, "asset": asset, "status": statut}
    if parent and not str(parent).startswith("?"):
        body["parent"] = parent
    r = cli.call("card", body)
    existantes[titre] = {"id": r["id"]}
    crees += 1
    return r["id"]


def a_png(pid, a):
    return os.path.exists(os.path.join(ROOT, "assets", "gordeka", "persos", pid, a + ".png"))


# ------------------------------------------------------------------ persos
chap_persos = carte("Personnages", "perso", "doing",
                    desc="Les 12 persos de Gordeka : profil validé + 14 animations de base chacun. Emotes et "
                         "fantômes générés en pause (décision de Julien, 20/10).")
for pid in PERSOS:
    n = NOMS[pid]
    faites = sum(a_png(pid, a) for a in ANIMS)
    chap = carte(f"Perso : {n}", "perso", "qa" if faites == len(ANIMS) else "backlog", parent=chap_persos,
                 desc=f"{faites}/{len(ANIMS)} animations de base en ligne.", asset=f"gordeka/persos/{pid}/animations")
    carte(f"{n} · profil de référence", "asset", "qa", parent=chap, asset=f"gordeka/persos/{pid}/modele.png")
    for a, nom in ANIMS.items():
        ok = a_png(pid, a)
        d = DEFAUTS.get((pid, a), "")
        carte(f"{n} · {nom}", "animation", "qa" if ok else "backlog", parent=chap,
              desc=("En ligne." + (" Défaut connu : " + d if d else "")) if ok
              else "À générer chez pixelforge (pf_2d__animate, prompts dans tools/gordeka/prompts_anims.json).",
              asset=f"gordeka/persos/{pid}/animations")
    if a_png(pid, "ghost"):
        carte(f"{n} · fantôme (ailes générées)", "animation", "qa", parent=chap,
              desc="Fantôme immobile et en déplacement générés avec ailes, plus vol stationnaire du jeu.")
    else:
        carte(f"{n} · fantôme : vol stationnaire + ailes par le code", "animation", "qa", parent=chap,
              desc="Provisoire : idle/walk du perso qui flottent avec des ailes blanches dessinées par le code.")
        carte(f"{n} · fantôme avec ailes générées", "animation", "backlog", parent=chap,
              desc="Retouche du profil (pf_2d__character edit) puis ghost + ghost_move. En pause (Julien 20/10).")
    carte(f"{n} · emotes (salut, rire, danse, pouce, chut, langue)", "animation", "backlog", parent=chap,
          desc="6 clips sur mesure pixelforge, prompts gardés. En pause : pas besoin aujourd'hui (Julien 20/10)."
          + (" Salut, rire, pouce et chut déjà faits pour Louis ; rire, pouce et chut pour Txomin." if pid in ("louis", "txomin") else ""))

carte("Karramarro : pinces animées par le code", "pixelforge", "backlog", parent=chap_persos,
      desc="Le squelette ne fait pas bouger ses pinces. Piste pixelforge : détourer les pinces (SAM) et les faire "
           "claquer par rotation périodique. Écarté pour l'instant (Julien 20/10).")
carte("Masques de tenue : recalcul pf_2d__tenue sur les animations de Kaio", "pixelforge", "backlog",
      parent=chap_persos, desc="Correctif pixelforge du masque de cou (foulard) ; repos, se cacher et sortir déjà refaits.")

# ------------------------------------------------------------------ décor
idx = json.load(open(os.path.join(ROOT, "assets", "gordeka", "decor", "index.json")))["elements"]
pr = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "tools", "gordeka", "prompts_decor.json")))["elements"]}
masques = os.path.join(ROOT, "assets", "gordeka", "decor", "masques")
REFAIRE = {"chambre_froide", "coque_sur_ber", "maison_crampotte", "comptoir_bar", "etabli_atelier", "marches_escalier",
           "caisses_poisson", "lavoir_bassin", "treteaux_cale", "banc_chapelle", "fronton", "autel_chapelle",
           "table_terrasse", "coque_chantier"}
chap_decor = carte("Décor du port", "asset", "backlog",
                   desc="Décor en images (pf_2d__prop / pf_2d__ground), intégré par tools/gordeka/integre_decor.py. "
                        "En pause depuis le 20/10 (décision de Julien).")
sous = {
    "sol": carte("Décor · sols", "asset", "backlog", parent=chap_decor),
    "objet": carte("Décor · objets", "asset", "backlog", parent=chap_decor),
    "cachette": carte("Décor · cachettes", "asset", "backlog", parent=chap_decor,
                      desc="Chaque cachette : image fermée, image ouverte (pf_hd__edit), tremblement joué par le jeu."),
    "sortie": carte("Décor · sorties et marquages", "asset", "backlog", parent=chap_decor),
    "anim": carte("Décor · animations", "asset", "backlog", parent=chap_decor,
                  desc="pf_2d__loop : warp (eau, drapeau, algue), particules (bulles, gouttes), vidéo (jet d'eau)."),
    "masque": carte("Décor · masques de gameplay", "pixelforge", "backlog", parent=chap_decor,
                    desc="pf_2d__footprint : emprise au sol, zone qui cache, ligne de tri. v3 en ligne (ground_y par "
                         "pixel, retrait de tolérance, correction manuelle)."),
}
for eid, el in idx.items():
    nom = el.get("nom", eid)
    a_img = bool(el.get("fichiers"))
    if eid.startswith("cachette_"):
        g = "cachette"
    elif eid.startswith("sortie_") or el.get("type") == "decal":
        g = "sortie"
    elif el.get("type", "").startswith("tuile"):
        g = "sol"
    else:
        g = "objet"
    if not a_img:
        carte(f"{nom} : image", "asset", "backlog", parent=sous[g], desc=f"{eid} : pas encore d'image.")
    elif eid in REFAIRE:
        carte(f"{nom} : refaire de face", "asset", "backlog", parent=sous[g],
              desc=f"{eid} : la version en ligne est en vue en coin ou avec un socle de sol. Verrou de caméra "
                   "pixelforge disponible ; 14 jobs annulés le 20/10.")
    else:
        carte(f"{nom}", "asset", "qa", parent=sous[g], desc=f"{eid} : en ligne.",
              asset=f"gordeka/decor/{el['fichiers'][0]}")
    if g == "cachette":
        carte(f"{nom} : version ouverte", "asset", "backlog", parent=sous[g],
              desc="Image ouverte (pf_hd__edit) + integre_decor.py --etat ouvert.")
    anim = pr.get(eid, {}).get("animation")
    if anim and anim.get("methode") == "planche":
        carte(f"{nom} : animation", "asset", "backlog", parent=sous["anim"], desc=anim.get("description", ""))
    if el.get("type") == "objet" and a_img:
        m = os.path.join(masques, eid, "masks.json")
        carte(f"{nom} : masque v3", "pixelforge", "backlog", parent=sous["masque"],
              desc=("Masque v2 en ligne ; à refaire en v3 (ground_y)." if os.path.exists(m)
                    else "Pas de masque pixelforge : calcul local de repli."))
carte("Décor · dalles du quai : passer la tuile à 4×4 cases ?", "asset", "backlog", parent=sous["sol"],
      desc="Question ouverte : le motif actuel (2×2 cases) est chargé.")
carte("Décor · toit en tuiles : version calme", "asset", "backlog", parent=sous["sol"],
      desc="Renvoi annulé le 20/10 ; reprendre avec colors 6 + max_saturation, description sans négation.")

# ------------------------------------------------------------------ gameplay et bugs
chap_gp = carte("Gameplay", "gameplay", "qa",
                desc="Idées testées en parties IA le 20/10 et activées, à valider par Julien (SPEC-GORDEKA).")
for t, d in [
    ("Chatouille : un fantôme qui touche le chasseur le ralentit 1,5 s", "Répit de 8 s. Activée."),
    ("Délivrance : un chassé libre reste 3 s près d'un fantôme pour le remettre en jeu", "Une fois par manche. Activée."),
    ("Gâteaux basques : 4 au sol, 1 point et 4 s de sprint", "Activée."),
    ("Mouettes qui s'envolent quand un chassé passe trop près", "Indice pour le chasseur. Activée."),
    ("Se cacher derrière les gros objets (masquage, portée de vue réduite)", "Masques de forme + transparence pour les coéquipiers."),
    ("Mode visite (debug) : chassé / chasseur", "Temporaire. Menu DEBUG, touches F (formes), C (perso), G (fantôme)."),
]:
    carte(t, "gameplay", "qa", parent=chap_gp, desc=d)
carte("Tremblement des cachettes : garder comme indice pour un chasseur humain ?", "gameplay", "backlog",
      parent=chap_gp, desc="Question ouverte.")
carte("Jeu en ligne avec les copains", "gameplay", "backlog", parent=chap_gp,
      desc="Bouton du menu marqué « bientôt » ; réseau WebRTC + signalisation PHP déjà là pour Borroka.")
chap_bug = carte("Bugs", "bug", "backlog")
carte("Web : Patxi affiché dans un rectangle noir", "bug", "backlog", parent=chap_bug,
      desc="Vu au test web du 20/10 (version web seulement). À vérifier sur la version en ligne.")

print("cartes créées :", crees)
