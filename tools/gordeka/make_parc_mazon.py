#!/usr/bin/env python3
"""Parc Mazon (SPEC-GORDEKA §8) : parc urbain pour enfants, très arboré et clôturé, demandé par Julien
le 2026-10-20 (« deux aires de jeux, une pour les grands, une pour les petits, un grand terrain central
avec un fronton comme au parc Mazon, plein d'opportunités de se cacher »).

Même format et même taille que le Port des Pêcheurs (96 × 42 cases, 15 zones) : salles (pelouses, aires
de jeux, terrain du fronton) séparées par des massifs d'arbres et reliées par des allées et des
passages étroits où l'on se croise, une grande boucle autour du fronton et des raccourcis (allée
derrière le fronton, pont de la mare, labyrinthe de haies), un repère fort par zone, des cachettes
près des passages, 3 sorties (portillons de la clôture) dont 2 ouvertes par round.

Écrit :
- assets/maps/parc_mazon/map.txt et zones.json ;
- assets/gordeka/decor/index_parc_mazon.json : le décor de la carte, lu par GkDecor (index par carte) :
  images reprises du port (banc vert, fontaine, poubelle, table de terrasse) et placeholders dessinés
  par tools/gordeka/placeholders_parc.py (assets/gordeka/decor/parc_mazon/), chacun posé sur ses cases
  (`cases`) avec ses masques (emprise au sol, partie haute qui masque) ;
- avec --apercu <png> : un plan de la carte (lettres, zones, sorties).
Vérifie que tout est atteignable, sans cul-de-sac, que chaque objet posé a la taille de son image,
et affiche quelques mesures (sol, cachettes, sorties, lignes de vue).

Légende (GkMap) : . sol   # clôture, bâtiments, fronton   v arbres, buissons, haies, massifs
                  c gros jeux (toboggans, kiosque)   (tous trois cachent la vue)
                  t objets bas (bancs, tables, tourniquet, balançoires : on voit par-dessus)
                  r massifs de fleurs, carrés potagers (bas)   ~ eau de la mare   : sable   = pont
                  H cachette   E sortie (portillon)   S départ
Usage : make_parc_mazon.py [--apercu <png>] [--sans-images] [--variante <id>] [--sortie-sud]
"""
import argparse
import json
import math
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAP_ID = "parc_mazon"
DECOR = os.path.join(ROOT, "assets", "gordeka", "decor")           # décor commun (images reprises)
OWN = os.path.join(ROOT, "assets", "maps", MAP_ID, "decor")       # décor propre à la carte
W, H = 96, 42
WALK = ".ES:="
OCCLUDE = "#cBHRv"

# ------------------------------------------------------------------------------------------- catalogue
# Chaque élément : nom, caractère, taille en cases (w, h), débord vers le haut (cases), catégorie,
# bloque_vue (None : selon le caractère), dessin (placeholder) ou image reprise du port (`reprise`),
# animation, prompt (pour la génération : description POSITIVE, sans négation), remarques.
# Les prompts complets sont assemblés par tools/gordeka/backlog_parc.py (style commun + caméra).
CAT = {
    # --- sols (tuiles 2 × 2 cases)
    "pm_sol_gravier": dict(nom="Gravier des allées", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["allées", "Entrée du gardien", "Labyrinthe de haies", "Fontaine", "Allée du fronton", "Allée des platanes"],
        prompt="Light beige raked gravel of a city park path, tiny round pebbles in warm sand and pale grey tones, a few slightly darker pebbles, calm and even."),
    "pm_sol_pelouse": dict(nom="Pelouse", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Bosquet", "Kiosque à musique", "Mare aux canards", "Grande pelouse", "Jardin des cabanes"],
        prompt="Soft fresh green lawn of a city park, short grass drawn as small rounded tufts in two close greens, a few tiny white daisies, calm and even."),
    "pm_sol_souple": dict(nom="Sol souple des aires de jeux", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Aire des petits", "Aire des grands"],
        prompt="Soft rubber safety flooring of a children's playground, large rounded square tiles in muted terracotta red with thin darker joints, a few tiles in soft teal, calm and even."),
    "pm_sol_cancha": dict(nom="Ciment du terrain de pelote", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Terrain du fronton"],
        prompt="Smooth pale grey cement of a Basque pelota court, large square slabs with thin darker expansion joints, a few faint lighter patches, calm and even."),
    "pm_sol_terre": dict(nom="Terre du potager", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Potager du jardinier"],
        prompt="Warm brown garden soil path with small flat stepping stones and a few tiny pebbles, calm and even."),
    "pm_sol_terrasse": dict(nom="Plancher de la buvette", car=".", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Buvette"],
        prompt="Warm honey wooden deck planks of a park snack bar terrace, long horizontal boards with thin darker joints and a few round nail heads, calm and even."),
    "pm_sable": dict(nom="Sable des bacs et de la tyrolienne", car=":", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Aire des petits", "Aire des grands"],
        prompt="Fine golden play sand, soft little ripples and a few tiny shells and pebbles, calm and even."),
    "pm_pont": dict(nom="Planches du pont de la mare", car="=", taille=(2, 2), type="tuile_sol", cat="sol",
        zones=["Mare aux canards"],
        prompt="Wooden footbridge planks seen from above, boards running across in warm brown, thin darker gaps, round bolts at both ends."),
    "pm_canopee": dict(nom="Massifs d'arbres (vus d'en haut)", car="v", taille=(2, 2), type="tuile_sol", cat="vegetation",
        zones=["massifs entre les zones"], anim="planche : feuillages qui bougent doucement (4 images en boucle)",
        prompt="Dense canopy of park trees seen straight from above: big rounded clusters of leaves in three deep greens overlapping like clouds, small darker gaps between them, a few lighter leaf highlights."),
    "pm_haie": dict(nom="Haies taillées du labyrinthe", car="v", taille=(2, 2), type="tuile_sol", cat="vegetation",
        zones=["Labyrinthe de haies"],
        prompt="Top of a neatly trimmed boxwood hedge seen straight from above, tight small leaves in two greens forming a soft even carpet, a few tiny lighter leaves."),
    "pm_cloture": dict(nom="Clôture du parc (grille verte et haie)", car="#", taille=(2, 2), type="tuile_sol", cat="mur",
        zones=["clôture du parc"], hors_jeu=True,
        prompt="Edge of a city park seen from above: a dark green iron railing with round finials running along a low pale stone wall, a strip of hedge behind it, stone sidewalk outside."),
    # --- sorties
    "pm_portillon": dict(nom="Portillon de la clôture (sortie)", car="E", taille=(2, 2), deb=0, cat="sortie",
        dessin="portillon", anim="jeu : le portillon s'ouvre quand la sortie ouvre",
        prompt="Small dark green iron park gate standing wide open in a stone gateway, a little enamel sign on the pillar, a doormat of paving stones in front, a glimpse of street beyond.",
        remarques="Posé sur les cases de la sortie, à plat sous les persos : il doit se lire « on sort par là »."),
    # --- arbres et végétation (bloquent la vue)
    "pm_arbre": dict(nom="Gros platane", car="v", taille=(2, 1), deb=3, cat="vegetation", dessin="arbre", masques=True,
        anim="planche : feuillage qui ondule au vent, boucle lente",
        prompt="Big old plane tree of a Biarritz park: thick mottled trunk in cream, olive and grey patches with root flare, huge round leafy crown in fresh greens, a few birds' nest twigs.",
        remarques="Emprise au sol : le tronc et ses racines (2 × 1 cases) ; la couronne déborde de 3 cases et masque qui passe derrière."),
    "pm_buisson": dict(nom="Buisson rond", car="v", taille=(1, 1), deb=1, cat="vegetation", dessin="buisson", masques=True,
        anim="planche : feuilles qui frémissent",
        prompt="Round dense park shrub of laurel, glossy leaves in two greens, a few small white flowers.",
        remarques="Petit écran : coupe la vue à l'entrée d'une zone."),
    "pm_bosquet": dict(nom="Bosquet (petit arbre et buissons)", car="v", taille=(2, 2), deb=2, cat="vegetation", dessin="bosquet", masques=True,
        anim="planche : feuillages qui bougent",
        prompt="Cosy clump of a small young tree surrounded by thick shrubs and ferns, rounded leafy masses in several greens, a few pink hydrangea flowers at the base."),
    "pm_massif": dict(nom="Haie basse fleurie", car="v", taille=(3, 1), deb=1, cat="vegetation", dessin="massif", masques=True,
        prompt="Low flowering hedge of a park border, a long rounded row of shrubs with pink and blue Basque hydrangeas."),
    # --- bâtiments et repères
    "pm_fronton": dict(nom="Fronton du parc (mur de pelote)", car="#", taille=(14, 1), deb=4, cat="repere", dessin="fronton", masques=True,
        anim="planche : petit drapeau basque qui flotte au sommet",
        prompt="Big Basque pelota fronton wall of a city park seen from the front: wide pale pink rendered wall with a curved chapeau top, a bold red line painted across at knee height, a dark green metal strip, a small Basque flag on a short pole on top.",
        remarques="Repère central. Le mur de 14 cases masque l'allée qui passe derrière (débord de 4 cases)."),
    "pm_local_club": dict(nom="Local du club de pelote", car="#", taille=(3, 2), deb=1, cat="batiment", dessin="maison", masques=True,
        prompt="Small whitewashed clubhouse of a pelota club, red wooden door and red shutters, red tile roof, a chistera and a txapela hanging by the door."),
    "pm_gradins": dict(nom="Gradins en béton", car="t", taille=(6, 1), deb=0, cat="objet_bas", dessin="gradins",
        prompt="Three low steps of pale concrete bleachers along a pelota court, rounded edges, a few red painted seat marks."),
    "pm_maison_gardien": dict(nom="Maison du gardien", car="#", taille=(4, 3), deb=2, cat="batiment", dessin="maison", masques=True,
        prompt="Little Labourd style keeper's house at a park entrance: white walls, red half-timbering, red shutters, red tile roof with an uneven two slope shape, a bench and a flower pot by the door."),
    "pm_kiosque": dict(nom="Kiosque à musique", car="c", taille=(5, 5), deb=2, cat="repere", dessin="kiosque", masques=True,
        anim="planche : guirlande de fanions qui flotte",
        prompt="Octagonal park bandstand: raised stone base with a few steps, slender dark green iron columns, a pointed red and white zinc roof with a small weather vane, a garland of little Basque red and green pennants.",
        remarques="On en fait le tour ; la base cache la vue, le toit masque qui est derrière."),
    "pm_kiosque_glaces": dict(nom="Buvette (kiosque à glaces)", car="#", taille=(4, 2), deb=2, cat="batiment", dessin="buvette", masques=True,
        anim="planche : store rayé qui ondule",
        prompt="Small wooden snack and ice cream kiosk of a park, red and white striped awning, a big painted ice cream cone on the roof, a serving hatch with a counter."),
    "pm_cabane_outils": dict(nom="Cabane à outils du jardinier", car="#", taille=(3, 2), deb=1, cat="batiment", dessin="cabane", masques=True,
        prompt="Green painted wooden garden shed with a sloping roof, a rake and a watering can leaning by the door, a small window with a flower box."),
    "pm_serre": dict(nom="Serre du jardinier", car="t", taille=(5, 3), deb=1, cat="objet_bas", dessin="serre", bloque_vue=False, masques=True,
        prompt="Small glass greenhouse with a white painted frame and a pitched glass roof, green seedlings and red tomato plants visible through the clear panes.",
        remarques="Vitrée : on voit à travers (ne cache pas la vue), on ne passe pas."),
    # --- jeux des grands
    "pm_cabane_chateau": dict(nom="Cabane-château", car="#", taille=(4, 3), deb=3, cat="jeu", dessin="chateau", masques=True,
        anim="planche : fanions des tours qui flottent",
        prompt="Big wooden play castle for children: two towers with pointy red roofs and flags, a rope bridge between them, a climbing wall with colourful holds, a small wooden door at the bottom.",
        remarques="Repère de l'aire des grands. Cachette « sous la cabane » posée devant (case H)."),
    "pm_grand_toboggan": dict(nom="Grand toboggan", car="c", taille=(4, 2), deb=2, cat="jeu", dessin="toboggan", masques=True,
        prompt="Tall playground slide: a wooden tower with a little roof and a ladder on the left, a long bright yellow slide curving down to the right.",
        remarques="La tour cache la vue ; cachette « sous le toboggan » posée à côté."),
    "pm_toile": dict(nom="Toile d'araignée (pyramide de cordes)", car="t", taille=(3, 3), deb=2, cat="jeu", dessin="toile", bloque_vue=False,
        prompt="Rope climbing pyramid of a playground: a central steel mast with a red top, a web of thick blue ropes stretched to the ground in a cone.",
        remarques="On voit à travers les cordes, on ne passe pas."),
    "pm_tyrolienne": dict(nom="Plateforme de la tyrolienne", car="c", taille=(2, 2), deb=2, cat="jeu", dessin="plateforme", masques=True,
        anim="jeu ou planche : la poulie et son siège glissent le long du câble",
        prompt="Wooden starting platform of a playground zip line with a small ladder, a sturdy post holding the steel cable, a round rubber seat hanging from a pulley."),
    "pm_cable_tyrolienne": dict(nom="Câble et piste de la tyrolienne", car=":", taille=(16, 1), type="decal", cat="jeu", dessin="cable",
        zones=["Aire des grands"],
        prompt="Thin steel zip line cable seen from above running straight across sand, with a small pulley and a round seat in the middle.",
        remarques="À plat sur le sable entre les deux plateformes."),
    "pm_balancoires": dict(nom="Portique de balançoires", car="t", taille=(4, 1), deb=2, cat="jeu", dessin="balancoires", bloque_vue=False,
        anim="planche : les deux balançoires vont et viennent",
        prompt="Playground swing set: a sturdy wooden A-frame with two swings on chains, one flat red seat and one blue bucket seat."),
    # --- jeux des petits
    "pm_tourniquet": dict(nom="Tourniquet", car="t", taille=(2, 2), deb=0, cat="jeu", dessin="tourniquet", bloque_vue=False,
        anim="jeu ou planche : le plateau tourne lentement",
        prompt="Round playground merry-go-round for toddlers, a flat disc in yellow and red slices with a little steering wheel in the middle and curved handle bars."),
    "pm_petit_toboggan": dict(nom="Petit toboggan", car="c", taille=(3, 1), deb=1, cat="jeu", dessin="petit_toboggan", masques=True,
        prompt="Small toddler slide shaped like a friendly elephant, short ladder and a gentle green slide."),
    "pm_ressort": dict(nom="Jeu à ressort", car="t", taille=(1, 1), deb=0, cat="jeu", dessin="ressort", bloque_vue=False,
        anim="planche : il se balance d'avant en arrière",
        prompt="Spring rider toy for toddlers shaped like a smiling fishing boat on a big coiled spring.",
        remarques="Trois variantes souhaitées : barque, mouette, petit cheval."),
    # --- mobilier
    "banc_vert": dict(nom="Banc vert (repris du port)", car="t", taille=(3, 1), reprise=True, cat="objet_bas"),
    "fontaine_place": dict(nom="Fontaine (reprise du port)", car="t", taille=(4, 4), reprise=True, cat="repere"),
    "table_terrasse": dict(nom="Table de terrasse (reprise du port)", car="t", taille=(2, 1), reprise=True, cat="objet_bas"),
    "pm_table_piquenique": dict(nom="Table de pique-nique", car="t", taille=(3, 1), deb=0, cat="objet_bas", dessin="table",
        prompt="Wooden picnic table with two attached benches, a red and white Basque checked tablecloth, a basket on top."),
    "pm_fleurs": dict(nom="Massif d'hortensias", car="r", taille=(3, 1), deb=0, cat="objet_bas", dessin="fleurs",
        prompt="Low round flower bed edged with stones, full of pink, blue and violet hydrangeas."),
    "pm_carre_potager": dict(nom="Carré potager", car="r", taille=(3, 1), deb=0, cat="objet_bas", dessin="potager",
        prompt="Raised wooden vegetable bed with lettuces, carrots tops and a row of red Espelette pepper plants."),
    "pm_souche": dict(nom="Souche-tabouret", car="t", taille=(1, 1), deb=0, cat="objet_bas", dessin="souche",
        prompt="Short round tree stump used as a stool, light wood rings on top, a little mushroom at its foot."),
    # --- cachettes (accent orange commun, 1 case)
    "cachette_poubelle_ruelle": dict(nom="Poubelle (reprise du port)", car="H", taille=(1, 1), reprise=True, cat="cachette"),
    "pm_maisonnette": dict(nom="Maisonnette des petits", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="maisonnette", masques=True,
        prompt="Tiny plastic playhouse for toddlers with a round orange door, a red roof, a little window with flowers; clearly a hiding spot with a warm orange accent."),
    "pm_tunnel": dict(nom="Tunnel en tube", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="tunnel", masques=True,
        prompt="Short crawl tunnel of a playground, a fat orange plastic tube lying on the ground, round opening facing us; clearly a hiding spot."),
    "pm_sous_chateau": dict(nom="Sous la cabane-château", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="porte_basse", masques=True,
        prompt="Low wooden door at the foot of a play castle, an arched opening with an orange curtain; clearly a hiding spot."),
    "pm_sous_toboggan": dict(nom="Sous le grand toboggan", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="porte_basse", masques=True,
        prompt="Little den under a slide platform, wooden posts with an orange canvas hanging between them; clearly a hiding spot."),
    "pm_buisson_creux": dict(nom="Buisson creux", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="buisson_creux", masques=True,
        anim="jeu : il tremble quand on y entre",
        prompt="Big round hollow bush with a dark leafy opening at its foot, a few orange berries; clearly a hiding spot."),
    "pm_tronc_creux": dict(nom="Tronc creux", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="tronc_creux", masques=True,
        prompt="Thick hollow old tree trunk cut at child height, a dark round hole at the bottom big enough to crawl in, an orange mushroom on the side; clearly a hiding spot."),
    "pm_cabane_branches": dict(nom="Cabane en branches", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="tipi", masques=True,
        prompt="Children's hut made of branches leaning together like a tipi, tied with orange rope, a little entrance; clearly a hiding spot."),
    "pm_niche_haie": dict(nom="Niche dans la haie", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="niche", masques=True,
        prompt="Thick cube of trimmed hedge with a secret arched hollow inside, an orange garden lantern at the entrance; clearly a hiding spot."),
    "pm_estrade": dict(nom="Sous l'estrade du kiosque", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="trappe", masques=True,
        prompt="Small lattice door under the steps of a bandstand, painted dark green with an orange handle; clearly a hiding spot."),
    "pm_malle_pelotes": dict(nom="Malle à pelotes", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="malle", masques=True,
        prompt="Big red wooden chest of a pelota club with a curved lid, a few leather pelotas and a wicker chistera on top, orange metal corners; clearly a hiding spot."),
    "pm_roseaux": dict(nom="Touffe de roseaux", car="H", taille=(1, 1), deb=1, cat="cachette", dessin="roseaux", masques=True,
        anim="planche : roseaux qui ondulent",
        prompt="Tall clump of pond reeds and cattails with brown velvet tops, an orange dragonfly on one stem; clearly a hiding spot."),
    "pm_composteur": dict(nom="Composteur", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="caisse", masques=True,
        prompt="Wooden slatted compost bin with an orange lid, a few leaves sticking out; clearly a hiding spot."),
    "pm_coffre_glaces": dict(nom="Coffre à glaces", car="H", taille=(1, 1), deb=0, cat="cachette", dessin="coffre", masques=True,
        prompt="White chest freezer of an ice cream stand with a big orange lid and a painted ice cream cone; clearly a hiding spot."),
}

# ------------------------------------------------------------------------------------------- carte
ZONES = [
    ("Entrée du gardien", 1, 1, 16, 11),
    ("Labyrinthe de haies", 20, 1, 18, 11),
    ("Aire des grands", 40, 1, 22, 12),
    ("Mare aux canards", 64, 1, 16, 12),
    ("Potager du jardinier", 82, 1, 13, 12),
    ("Allée du fronton", 34, 14, 32, 2),
    ("Bosquet", 1, 14, 15, 15),
    ("Kiosque à musique", 18, 14, 16, 14),
    ("Terrain du fronton", 36, 17, 28, 13),
    ("Grande pelouse", 66, 14, 29, 15),
    ("Aire des petits", 1, 31, 19, 10),
    ("Fontaine", 22, 30, 14, 11),
    ("Buvette", 38, 32, 14, 9),
    ("Jardin des cabanes", 54, 32, 18, 9),
    ("Allée des platanes", 74, 31, 21, 10),
]

VERSION = 4                # plan retenu (les précédentes restent pour les A/B)
g = [["v"] * W for _ in range(H)]
PLACES = []        # (id, x, y)


def put(x, y, w, h, ch):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 < xx < W - 1 and 0 < yy < H - 1:
                g[yy][xx] = ch


def obj(eid, x, y):
    el = CAT[eid]
    w, h = el["taille"]
    put(x, y, w, h, el["car"])
    PLACES.append((eid, x, y))


def retire(eid, x, y):
    """Enlève un objet posé (retouche d'une version à l'autre) : ses cases redeviennent du sol."""
    w, h = CAT[eid]["taille"]
    PLACES.remove((eid, x, y))
    put(x, y, w, h, ".")


def bouge(eid, x, y, nx, ny):
    retire(eid, x, y)
    obj(eid, nx, ny)


def art(x, y, rows):
    """Motif dessiné à la main (labyrinthe) : une chaîne par ligne."""
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            g[y + j][x + i] = ch


def build(opts):
    for x in range(W):
        g[0][x] = g[H - 1][x] = "#"
    for y in range(H):
        g[y][0] = g[y][W - 1] = "#"
    for (_, x, y, w, h) in ZONES:
        put(x, y, w, h, ".")
    # ------------------------------------------------ portes et allées entre les zones (massifs ailleurs)
    for (x, y, w, h) in (
            (17, 6, 3, 2), (6, 12, 2, 2),                       # gardien → labyrinthe, → bosquet
            (38, 4, 2, 2), (27, 12, 2, 2),                      # labyrinthe → aire des grands, → kiosque
            (44, 13, 2, 1), (56, 13, 2, 1),                     # aire des grands → allée du fronton
            (62, 8, 2, 2), (80, 5, 2, 2),                       # grands → mare → potager
            (70, 13, 2, 1), (88, 13, 2, 1),                     # mare, potager → pelouse
            (40, 16, 2, 1), (60, 16, 2, 1),                     # allée du fronton → terrain
            (16, 19, 2, 2), (34, 22, 2, 2), (64, 22, 2, 2),     # bosquet → kiosque → terrain → pelouse
            (6, 29, 2, 2), (25, 28, 2, 2),                      # bosquet → petits, kiosque → fontaine
            (44, 30, 2, 2), (58, 30, 2, 2), (70, 29, 2, 3),     # terrain → buvette, → cabanes ; pelouse → cabanes
            (82, 29, 2, 2),                                     # pelouse → platanes
            (20, 35, 2, 2), (36, 36, 2, 2), (52, 35, 2, 2), (72, 36, 2, 2)):   # rangée du bas
        put(x, y, w, h, ".")

    # ------------------------------------------------ Entrée du gardien (portillon nord-ouest)
    obj("pm_portillon", 4, 1)
    obj("pm_maison_gardien", 10, 2)
    obj("banc_vert", 2, 6)
    obj("pm_fleurs", 10, 7)
    obj("pm_arbre", 4, 10)
    obj("pm_buisson", 15, 9)
    obj("cachette_poubelle_ruelle", 14, 5)
    obj("pm_buisson", 9, 10)

    # ------------------------------------------------ Labyrinthe de haies (x 20..37, y 1..11)
    art(20, 1, [
        "..................",
        ".vvvv.vvv..vvv.vv.",
        ".v.......v...v.vv.",
        ".v.vvv.v.v.v.v....",
        "...v...v...v...vv.",
        ".vvv.vvv.....vvv..",
        "......v...v.......",
        ".vv.v.v.vvvvv.vvv.",
        ".vv.v.........v...",
        ".vv.vvvv..vvv.v.v.",
        "..................",
    ])
    obj("pm_niche_haie", 30, 6)
    obj("pm_niche_haie", 24, 10)

    # ------------------------------------------------ Aire des grands (x 40..61, y 1..12)
    obj("pm_cabane_chateau", 42, 2)
    obj("pm_sous_chateau", 43, 5)
    obj("pm_grand_toboggan", 50, 2)
    obj("pm_sous_toboggan", 54, 3)
    obj("pm_toile", 57, 6)
    obj("pm_balancoires", 47, 8)
    put(43, 11, 16, 1, ":")                     # piste de la tyrolienne
    obj("pm_tyrolienne", 41, 10)
    obj("pm_tyrolienne", 59, 10)
    obj("pm_cable_tyrolienne", 43, 11)
    obj("pm_tunnel", 53, 7)
    obj("pm_buisson", 40, 7)

    # ------------------------------------------------ Mare aux canards (x 64..79, y 1..12)
    put(67, 3, 10, 6, "~")
    for (x, y) in ((67, 3), (76, 3), (67, 8), (76, 8), (68, 3), (75, 8)):
        g[y][x] = "."
    put(71, 3, 2, 6, "=")                       # pont de bois
    put(71, 2, 2, 1, ".")
    obj("pm_roseaux", 66, 6)
    obj("pm_roseaux", 77, 4)
    obj("banc_vert", 73, 10)
    obj("pm_arbre", 64, 10)
    obj("pm_buisson", 79, 1)
    obj("pm_bosquet", 64, 1)

    # ------------------------------------------------ Potager du jardinier (portillon est)
    obj("pm_portillon", 93, 8)
    obj("pm_serre", 84, 2)
    obj("pm_cabane_outils", 90, 2)
    obj("pm_composteur", 89, 6)
    obj("pm_carre_potager", 83, 7)
    obj("pm_carre_potager", 83, 10)
    obj("pm_carre_potager", 88, 10)

    # ------------------------------------------------ Allée du fronton (y 14..15, derrière le fronton)
    obj("pm_buisson", 37, 14)
    obj("pm_buisson", 50, 15)
    obj("pm_buisson", 63, 14)

    # ------------------------------------------------ Bosquet (x 1..15, y 14..28)
    obj("pm_arbre", 2, 15)
    obj("pm_arbre", 10, 15)
    obj("pm_bosquet", 5, 18)
    obj("pm_buisson_creux", 8, 18)
    obj("pm_arbre", 12, 19)
    obj("pm_buisson", 2, 21)
    obj("pm_bosquet", 9, 22)
    obj("pm_tronc_creux", 5, 24)
    obj("pm_arbre", 2, 26)
    obj("pm_arbre", 12, 26)
    obj("pm_buisson", 7, 27)
    obj("pm_buisson_creux", 14, 23)
    obj("pm_massif", 3, 23)

    # ------------------------------------------------ Kiosque à musique (x 18..33, y 14..27)
    obj("pm_kiosque", 23, 18)
    obj("pm_estrade", 25, 23)
    obj("banc_vert", 19, 16)
    obj("banc_vert", 29, 16)
    obj("banc_vert", 19, 25)
    obj("banc_vert", 29, 25)
    obj("pm_fleurs", 19, 21)
    obj("pm_arbre", 31, 22)
    obj("pm_buisson", 22, 14)
    obj("pm_bosquet", 30, 19)

    # ------------------------------------------------ Terrain du fronton (x 36..63, y 17..29)
    obj("pm_fronton", 43, 17)
    obj("pm_local_club", 37, 18)
    obj("pm_malle_pelotes", 37, 21)
    obj("pm_gradins", 38, 28)
    obj("pm_gradins", 50, 28)
    obj("cachette_poubelle_ruelle", 62, 19)
    obj("banc_vert", 60, 26)
    put(49, 23, 2, 1, "S")

    # ------------------------------------------------ Grande pelouse (x 66..94, y 14..28)
    obj("pm_arbre", 70, 17)
    obj("pm_arbre", 78, 16)
    obj("pm_arbre", 88, 18)
    obj("pm_arbre", 72, 24)
    obj("pm_arbre", 84, 25)
    obj("pm_arbre", 91, 23)
    obj("pm_table_piquenique", 74, 20)
    obj("pm_table_piquenique", 82, 21)
    obj("pm_table_piquenique", 67, 27)
    obj("pm_buisson", 76, 26)
    obj("pm_buisson", 93, 15)
    obj("pm_tronc_creux", 89, 21)
    obj("pm_buisson_creux", 68, 20)
    obj("pm_massif", 79, 13 + 1)

    # ------------------------------------------------ Aire des petits (portail sud-ouest)
    obj("pm_portillon", 17, 39)
    put(2, 33, 5, 4, ":")                       # bac à sable
    obj("pm_tourniquet", 9, 33)
    obj("pm_petit_toboggan", 13, 32)
    obj("pm_ressort", 3, 38)
    obj("pm_ressort", 6, 39)
    obj("pm_ressort", 9, 38)
    obj("pm_maisonnette", 16, 34)
    obj("pm_tunnel", 12, 37)
    obj("pm_buisson", 1, 31)

    # ------------------------------------------------ Fontaine (x 22..35, y 30..40)
    obj("fontaine_place", 27, 33)
    obj("banc_vert", 22, 32)
    obj("banc_vert", 32, 32)
    obj("banc_vert", 22, 38)
    obj("banc_vert", 32, 38)
    obj("cachette_poubelle_ruelle", 34, 35)
    obj("pm_bosquet", 23, 35 - 1)
    if opts.sortie_sud:
        obj("pm_portillon", 28, 39)

    # ------------------------------------------------ Buvette (x 38..51, y 32..40)
    obj("pm_kiosque_glaces", 43, 33)
    obj("pm_coffre_glaces", 47, 34)
    obj("table_terrasse", 39, 38)
    obj("table_terrasse", 43, 38)
    obj("table_terrasse", 47, 38)
    obj("table_terrasse", 40, 35)
    obj("pm_buisson", 51, 32)

    # ------------------------------------------------ Jardin des cabanes (x 54..71, y 32..40)
    obj("pm_cabane_branches", 57, 34)
    obj("pm_cabane_branches", 64, 37)
    obj("pm_cabane_branches", 69, 34)
    obj("pm_souche", 60, 36)
    obj("pm_souche", 62, 33)
    obj("pm_souche", 67, 39)
    obj("pm_bosquet", 55, 38)
    obj("pm_arbre", 64, 33)
    obj("pm_buisson", 60, 39)

    # ------------------------------------------------ Allée des platanes (x 74..94, y 31..40)
    for x in (76, 81, 86, 91):
        obj("pm_arbre", x, 33)
    for x in (78, 88):
        obj("pm_arbre", x, 38)
    obj("banc_vert", 83, 38)
    obj("cachette_poubelle_ruelle", 79, 35)
    obj("pm_buisson_creux", 90, 36)
    obj("pm_fleurs", 74, 36 + 0)
    if getattr(opts, "version", 1) >= 2:
        retouches_v2()
    if getattr(opts, "version", 1) >= 3:
        retouches_v3()
    if getattr(opts, "version", 1) >= 4:
        retouches_v4()
    if getattr(opts, "version", 1) == 5:
        retouches_v5()
    if getattr(opts, "version", 1) >= 6:
        retouches_v6()


def retouches_v2():
    """v2 (2026-10-21, après 120 manches : sorties trop faciles, 63 % des chassés sortis face au chasseur
    facile ; labyrinthe où l'on campe) : sorties déplacées vers des lieux exposés (rive nord de la mare au
    bout du pont, coin sud-est de l'allée des platanes ; le portail des petits reste), labyrinthe aéré."""
    # Sortie nord-ouest → rive nord de la mare (au bout du pont, à découvert).
    retire("pm_portillon", 4, 1)
    retire("pm_bosquet", 64, 1)
    bouge("pm_roseaux", 77, 4, 66, 9)
    obj("pm_portillon", 71, 1)
    # Sortie est (potager) → coin sud-est de l'allée des platanes, dégagé autour.
    retire("pm_portillon", 93, 8)
    retire("pm_arbre", 88, 38)
    bouge("pm_buisson_creux", 90, 36, 85, 36)
    obj("pm_portillon", 92, 39)
    # Labyrinthe aéré : allées plus larges, haies plus courtes (on y voit à 3 ou 4 cases).
    art(20, 1, [
        "..................",
        ".vvv..vvv...vv.vv.",
        ".v.........v...vv.",
        "...vv..v.v.v......",
        ".......v.........v",
        ".vv..vvv....vvv..v",
        "......v...v.......",
        ".vv.v.....vvv..vv.",
        ".vv.v...........v.",
        ".......vv..vv.v...",
        "..................",
    ])
    g[6][30] = "H"
    g[10][24] = "H"


def retouches_v3():
    """v3 : les sorties qui laissaient filer le plus (1,75 et 1,4 chassé par ouverture, contre 1,1 à la
    mare, ouverte et à découvert) sont dégagées comme elle : plus d'arbres ni de cachette à moins de
    6 cases du portillon sud-est (petite place au bout de l'allée des platanes) ; aux petits, la
    maisonnette et le tunnel passent du côté de l'entrée nord, loin du portail."""
    retire("pm_arbre", 91, 33)
    retire("pm_arbre", 86, 33)
    bouge("pm_buisson_creux", 85, 36, 77, 38 - 1)
    obj("banc_vert", 86, 33)
    bouge("pm_maisonnette", 16, 34, 9, 31)
    bouge("pm_tunnel", 12, 37, 4, 37)


def retouches_v4():
    """v4 : carte trop grande (2 800 cases de sol contre 2 035 au port ; le chasseur reste au centre, les
    salles du pourtour ne le voient presque jamais) : chaque zone rend son bord d'une case aux massifs
    (sauf l'allée du fronton). Les passages entre zones s'allongent d'autant : de vraies allées dans
    les massifs, où l'on se croise. Les arbres et buissons posés sur ce bord sont retirés."""
    global ZONES
    keep = {"Allée du fronton"}
    new = []
    ring = set()
    for (n, x, y, w, h) in ZONES:
        if n in keep:
            new.append((n, x, y, w, h))
            continue
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if xx in (x, x + w - 1) or yy in (y, y + h - 1):
                    ring.add((xx, yy, x, y, w, h))
        new.append((n, x + 1, y + 1, w - 2, h - 2))
    doors = set()
    for (xx, yy, x, y, w, h) in ring:
        for (nx, ny) in ((xx + 1, yy), (xx - 1, yy), (xx, yy + 1), (xx, yy - 1)):
            outside = not (x <= nx < x + w and y <= ny < y + h)
            if outside and 0 <= nx < W and 0 <= ny < H and g[ny][nx] in WALK:
                doors.add((xx, yy))
    cells = {(xx, yy) for (xx, yy, *_r) in ring}
    for (eid, ox, oy) in list(PLACES):
        el = CAT[eid]
        if el["car"] != "v":
            continue
        w, h = el["taille"]
        if any((ox + i, oy + j) in cells for i in range(w) for j in range(h)):
            retire(eid, ox, oy)
    # Les autres objets posés sur le bord rentrent d'une case dans la zone (si la place est libre).
    for (eid, ox, oy) in list(PLACES):
        el = CAT[eid]
        w, h = el["taille"]
        if el["car"] in "E" or not any((ox + i, oy + j) in cells for i in range(w) for j in range(h)):
            continue
        z = next((zz for zz in ZONES if zz[1] <= ox < zz[1] + zz[3] and zz[2] <= oy < zz[2] + zz[4]), None)
        if z is None:
            continue
        cx, cy = z[1] + z[3] / 2, z[2] + z[4] / 2
        dx = 1 if ox + w / 2 < cx else -1
        dy = 1 if oy + h / 2 < cy else -1
        for (mx, my) in ((dx, 0), (0, dy), (dx, dy)):
            nx, ny = ox + mx, oy + my
            sx = set((ox + i, oy + j) for i in range(w) for j in range(h))
            tgt = [(nx + i, ny + j) for i in range(w) for j in range(h)]
            if all(t in sx or g[t[1]][t[0]] == "." and t not in cells for t in tgt):
                bouge(eid, ox, oy, nx, ny)
                break
    for (xx, yy) in cells:
        if g[yy][xx] == "." and (xx, yy) not in doors:
            g[yy][xx] = "v"
    ZONES = new
    # Cachettes coincées par le nouveau bord (un seul côté libre) : déplacées.
    retire("pm_niche_haie", 24, 10)
    g[10][24] = "v"
    obj("pm_niche_haie", 31, 3)
    bouge("pm_maisonnette", 9, 32, 12, 35)
    # Recoins sans issue laissés par les objets contre le nouveau bord : comblés de buissons.
    for (xx, yy) in sorted(culs_de_sac()):
        if g[yy][xx] == ".":
            obj("pm_buisson", xx, yy)


def retouches_v5():
    """v5 : personne ne reste caché jusqu'au bout (tout chassé non trouvé finit par sortir) : le chasseur
    gagne en attrapant sur le chemin des sorties. La sortie sud-est (allée des platanes, couverte) passe
    au bout de la grande pelouse, à découvert (bord est) ; l'allée du fronton n'est plus une zone (le
    chasseur IA y passait 8 % de ses rondes pour rien) ; 4 cachettes de moins dans les zones calmes."""
    global ZONES
    retire("pm_portillon", 92, 39)
    put(92, 40, 2, 1, "v")
    for (eid, x, y) in (("pm_arbre", 91, 23), ("pm_arbre", 88, 18), ("pm_buisson", 93, 15)):
        if (eid, x, y) in PLACES:
            retire(eid, x, y)
    bouge("pm_tronc_creux", 89, 21, 80, 17)
    obj("banc_vert", 88, 25)
    obj("pm_portillon", 93, 20)
    ZONES = [z for z in ZONES if z[0] != "Allée du fronton"]
    for (eid, x, y) in (("pm_tunnel", 53, 7), ("pm_buisson_creux", 14, 23), ("pm_cabane_branches", 64, 37),
                        ("pm_roseaux", 66, 9)):
        retire(eid, x, y)


def retouches_v6():
    """v6 (sur la v4 ; la v5 reculait de 10 points en rapprochant une sortie du départ) : sorties plus
    loin du départ et des planques, au bout d'une approche à découvert : le portail des petits au coin
    sud-ouest (bac à sable et jeux à ressort écartés), la sortie de la mare au coin nord-est de la rive."""
    retire("pm_portillon", 17, 39)
    put(17, 40, 2, 1, "v")
    put(17, 39, 2, 1, ".")
    for (eid, x, y, nx, ny) in (("pm_ressort", 3, 38, 9, 35), ("pm_tunnel", 4, 37, 13, 36)):
        if (eid, x, y) in PLACES:
            bouge(eid, x, y, nx, ny)
    obj("pm_portillon", 2, 39)
    retire("pm_portillon", 71, 1)
    put(71, 1, 2, 1, "v")
    put(71, 2, 2, 1, ".")
    if ("pm_buisson", 79, 1) in PLACES:
        retire("pm_buisson", 79, 1)
    obj("pm_portillon", 77, 1)


# ------------------------------------------------------------------------------------------- mesures
def zone_of(x, y):
    for i, (_, zx, zy, zw, zh) in enumerate(ZONES):
        if zx <= x < zx + zw and zy <= y < zy + zh:
            return i
    return -1


def zname(i):
    return ZONES[i][0] if i >= 0 else "allées"


def zone_proche(x, y):
    """Zone de la case, ou la plus proche (sortie posée au bord, hors du rectangle de sa zone)."""
    if zone_of(x, y) >= 0:
        return zone_of(x, y)
    return min(range(len(ZONES)), key=lambda i: max(ZONES[i][1] - x, 0, x - (ZONES[i][1] + ZONES[i][3] - 1))
               + max(ZONES[i][2] - y, 0, y - (ZONES[i][2] + ZONES[i][4] - 1)))


def bfs(start, chars=WALK):
    d = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in d and g[n[1]][n[0]] in chars:
                d[n] = d[(x, y)] + 1
                q.append(n)
    return d


def exit_groups():
    tiles = {(x, y) for y in range(H) for x in range(W) if g[y][x] == "E"}
    groups = []
    while tiles:
        t = tiles.pop()
        grp, q = [t], [t]
        while q:
            x, y = q.pop()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in tiles:
                    tiles.remove(n)
                    grp.append(n)
                    q.append(n)
        groups.append(sorted(grp))
    return sorted(groups)


def culs_de_sac():
    """Cases de sol retirées par élagage des cases à un seul voisin : bras sans seconde issue."""
    walk = {(x, y) for y in range(H) for x in range(W) if g[y][x] in WALK}
    deg = {}
    for (x, y) in walk:
        deg[(x, y)] = sum((n in walk) for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    todo = [c for c in walk if deg[c] <= 1]
    out = set()
    while todo:
        c = todo.pop()
        if c in out:
            continue
        out.add(c)
        x, y = c
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n in walk and n not in out:
                deg[n] -= 1
                if deg[n] <= 1:
                    todo.append(n)
    return out


def ray_len(x, y, ang, cap=25.0):
    dx, dy = math.cos(ang), math.sin(ang)
    t = 0.0
    while t < cap:
        t += 0.25
        cx, cy = int(x + 0.5 + dx * t), int(y + 0.5 + dy * t)
        if not (0 <= cx < W and 0 <= cy < H) or g[cy][cx] in OCCLUDE:
            return t
    return cap


def check(verbose=True):
    ok = True
    start = next((x, y) for y in range(H) for x in range(W) if g[y][x] == "S")
    d = bfs(start)
    bad = [(x, y) for y in range(H) for x in range(W) if g[y][x] in WALK and (x, y) not in d]
    hides = [(x, y) for y in range(H) for x in range(W) if g[y][x] == "H"]
    free = {h: sum((n in d) for n in ((h[0] + 1, h[1]), (h[0] - 1, h[1]), (h[0], h[1] + 1), (h[0], h[1] - 1))) for h in hides}
    lone = [h for h in hides if free[h] == 0]
    if bad or lone:
        ok = False
    # Objets : chaque case non marchable d'une zone appartient à un seul objet posé, du même caractère
    # (sauf l'eau et les haies du labyrinthe, en tuiles) ; chaque objet posé porte bien son caractère.
    owner = {}
    mism = []
    for (eid, x, y) in PLACES:
        el = CAT[eid]
        w, h = el["taille"]
        if el.get("type") == "decal":
            continue
        for j in range(h):
            for i in range(w):
                c = (x + i, y + j)
                if c in owner:
                    mism.append(("chevauchement", eid, owner[c], c))
                owner[c] = eid
                if g[c[1]][c[0]] != el["car"]:
                    mism.append(("caractère", eid, c, g[c[1]][c[0]]))
    for yy in range(H):
        for xx in range(W):
            ch = g[yy][xx]
            z = zone_of(xx, yy)
            if z < 0 or ch in WALK or ch == "~" or (xx, yy) in owner:
                continue
            if ch == "v" and ZONES[z][0] == "Labyrinthe de haies":
                continue
            mism.append(("sans objet", ch, zname(z), (xx, yy)))
    if mism:
        ok = False
    dead = culs_de_sac()
    groups = exit_groups()
    if verbose:
        n_walk = len(d)
        print(f"carte {W}×{H}, sol atteignable {n_walk} cases, isolées {len(bad)}, cachettes {len(hides)} "
              f"(inaccessibles {len(lone)}, un seul côté libre {sum(1 for h in hides if free[h] == 1)})")
        if bad:
            print("  cases isolées :", bad[:12])
        if lone:
            print("  cachettes inaccessibles :", lone)
        for m in mism:
            print("  objet sans image à sa taille :", m)
        if dead:
            print(f"  culs-de-sac : {len(dead)} cases", sorted(dead)[:30])
        per = {}
        for h in hides:
            per.setdefault(zname(zone_of(*h)), []).append(h)
        print("  zones sans cachette :", [z[0] for z in ZONES if z[0] not in per])
        cents = []
        for grp in groups:
            c = (sum(t[0] for t in grp) / len(grp), sum(t[1] for t in grp) / len(grp))
            cents.append(c)
            appro = len({zone_of(*n) for t in grp for n in ((t[0] + 2, t[1]), (t[0] - 2, t[1]), (t[0], t[1] - 2), (t[0], t[1] + 2))})
            print(f"  sortie « {zname(zone_proche(*grp[0]))} » : {min(d.get(t, 9999) for t in grp)} cases du départ")
        for i in range(len(cents)):
            for j in range(i + 1, len(cents)):
                dd = math.dist(cents[i], cents[j])
                print(f"  écart sorties {i}-{j} : {dd:.0f} {'(jamais ensemble, < 40)' if dd < 40 else ''}")
        # Lignes de vue : rayon moyen et part des cases d'où un rayon file à 15 cases et plus.
        print("  zone : sol, cachettes, rayon moyen, part ≥ 15 cases")
        for i, (zn, zx, zy, zw, zh) in enumerate(ZONES):
            cells = [(x, y) for y in range(zy, zy + zh) for x in range(zx, zx + zw) if g[y][x] in WALK]
            if not cells:
                continue
            rs, far = [], 0
            for (x, y) in cells:
                lens = [ray_len(x, y, k * math.pi / 8) for k in range(16)]
                rs.append(sum(lens) / 16)
                far += max(lens) >= 15
            print(f"    {zn:22s} {len(cells):4d}  {len(per.get(zn, [])):2d}  {sum(rs) / len(rs):5.1f}  {100 * far / len(cells):3.0f} %")
    return ok


# ------------------------------------------------------------------------------------------- décor
def decor_index():
    """Index du décor de la carte (GkDecor, index par carte) : chaque objet posé sur ses cases."""
    port = json.load(open(os.path.join(DECOR, "index.json"), encoding="utf-8"))["elements"]
    els = {}
    for eid, el in CAT.items():
        e = {"nom": el["nom"], "caractere": el["car"], "taille_cases": list(el["taille"]),
             "debord_haut_cases": el.get("deb", 0), "categorie": el["cat"]}
        if el.get("reprise"):
            src = port[eid]
            e.update({k: src[k] for k in ("type", "fichiers", "ombre", "ombre_decalage", "animation") if k in src})
            e["fichiers"] = ["res://assets/gordeka/decor/" + f for f in e["fichiers"]]
            if "ombre" in e:
                e["ombre"] = "res://assets/gordeka/decor/" + e["ombre"]
            e["nom"] = src["nom"]
            e["reprise_du_port"] = True
        else:
            e["type"] = el.get("type", "objet")
            sub = "sols" if e["type"] == "tuile_sol" else "objets"
            e["fichiers"] = [f"{sub}/{eid}.png"]
            e["placeholder"] = True
            if el.get("anim"):
                e["animation"] = {"description": el["anim"]}
        if el.get("bloque_vue") is not None:
            e["bloque_vue"] = el["bloque_vue"]
        if el.get("hors_jeu"):
            continue
        if e["type"] == "tuile_sol":
            e["zones"] = el["zones"]
        else:
            ps = [(x, y) for (i, x, y) in PLACES if i == eid]
            e["zones"] = []                    # posé seulement là où zones.json → objets le dit
            e["poses"] = len(ps)
        els[eid] = e
    return {"_doc": "Décor du Parc Mazon (tools/gordeka/make_parc_mazon.py), lu par src/gordeka/gk_decor.gd "
                    "(décor propre à la carte). Placeholders dessinés par tools/gordeka/placeholders_parc.py, à remplacer "
                    "par les images du backlog « Carte : Parc Mazon » ; poses dans ../zones.json → objets.",
            "carte": MAP_ID, "elements": els}


def apercu(path):
    from PIL import Image, ImageDraw
    k = 12
    col = {"#": (59, 66, 83), "v": (63, 120, 60), "c": (160, 112, 62), "t": (201, 168, 115), "r": (214, 120, 160),
           "~": (47, 127, 184), ":": (230, 207, 152), "=": (150, 110, 70), "H": (224, 138, 46), "E": (60, 220, 120),
           "S": (240, 60, 60), ".": (215, 210, 195)}
    im = Image.new("RGB", (W * k, H * k), (0, 0, 0))
    dr = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            ch = g[y][x]
            c = col.get(ch, (255, 0, 255))
            if ch == "." and zone_of(x, y) < 0:
                c = (190, 180, 160)
            dr.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1], fill=c)
    for (zn, zx, zy, zw, zh) in ZONES:
        dr.rectangle([zx * k, zy * k, (zx + zw) * k - 1, (zy + zh) * k - 1], outline=(255, 255, 255))
        dr.text((zx * k + 3, zy * k + 2), zn, fill=(0, 0, 0))
    for (eid, x, y) in PLACES:
        w, h = CAT[eid]["taille"]
        dr.rectangle([x * k, y * k, (x + w) * k - 1, (y + h) * k - 1], outline=(20, 20, 40))
    im.save(path)
    print("aperçu :", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apercu", default="")
    ap.add_argument("--sans-images", action="store_true", help="n'écrit pas les placeholders")
    ap.add_argument("--variante", default="", help="écrit assets/maps/<variante>/ (décor de parc_mazon), pour les A/B")
    ap.add_argument("--sortie-sud", action="store_true", help="4e sortie : portail sud de la fontaine")
    ap.add_argument("--version", type=int, default=VERSION, help="version du plan (journal dans SPEC-GORDEKA §8)")
    opts = ap.parse_args()
    build(opts)
    out_id = opts.variante or MAP_ID
    out = os.path.join(ROOT, "assets", "maps", out_id)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(row) for row in g) + "\n")
    zones = [{"name": n, "rect": [x, y, w, h]} for (n, x, y, w, h) in ZONES]
    exits = [{"zone": zname(zone_proche(*grp[0])), "tiles": [list(t) for t in grp]} for grp in exit_groups()]
    objets = []
    for (eid, x, y) in PLACES:
        el = CAT[eid]
        if el.get("type") == "tuile_sol":
            continue
        w, h = el["taille"]
        objets.append({"element": eid, "rect": [x, y, w, h]})
    zj = {"name": "Parc Mazon", "version": opts.version, "zones": zones, "exits": exits, "objets": objets}
    if opts.variante:
        zj["decor"] = MAP_ID
    with open(os.path.join(out, "zones.json"), "w") as fh:
        json.dump(zj, fh, ensure_ascii=False, indent=1)
    ok = check()
    if not opts.variante:
        idx = decor_index()
        os.makedirs(OWN, exist_ok=True)
        with open(os.path.join(OWN, "index.json"), "w", encoding="utf-8") as fh:
            json.dump(idx, fh, ensure_ascii=False, indent=1)
        if not opts.sans_images:
            sys.path.insert(0, HERE)
            import placeholders_parc
            placeholders_parc.dessine_tout(CAT, OWN)
    if opts.apercu:
        apercu(opts.apercu)
    print(os.path.join(out, "map.txt"))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
