#!/usr/bin/env python3
"""Plage de la Côte des Basques (SPEC-GORDEKA §8, carte « à valider par Julien », 2026-10-21).

Demande de Julien : « une autre [carte] sur une plage avec des rochers, des cavernes sous la falaise,
des tunnels, des cabanes de plage, des restaurants ». Biarritz : la falaise de la Côte des Basques en
haut, creusée de trois grottes reliées par des tunnels sombres (raccourcis parallèles à la plage), deux
restaurants adossés à la falaise (terrasse, comptoir, cuisine creusée dans la roche qui donne sur une
grotte), le poste de secours, les cabines rayées, le chaos de rochers du Basta, la grande plage
structurée (parasols, transats, paravents, kiosque à glaces, château de sable), les bateaux tirés au sec,
le Port-Vieux et sa digue, la ligne d'eau en bas (non marchable).

Écrit assets/maps/plage/ : map.txt, zones.json (zones, sorties, cases sombres, « objets » : l'élément
du décor de chaque objet posé) et decor/ (index.json + images provisoires dessinées ici, formes simples
« base au sol + haut qui masque » ; les images communes qui conviennent sont reprises en res://).
Vérifie que tout est atteignable et affiche le diagnostic de la carte (liaisons, culs-de-sac, boucles,
lignes de vue, vides, sorties).

Légende (BkMap) : .  sol (sable, planches, carrelage selon la zone)
                  R  falaise (masse)      v  pied de falaise (face rocheuse, posé tout seul)
                  #  bord de carte        c  objet haut (cabine, rocher, paravent, kiosque, façade…)
                  B  bateau tiré au sec   t  objet bas (parasol, transat, table, douche : on voit par-dessus)
                  r  rocher bas, talus    ~  eau (mer, flaques : on ne passe pas, on voit par-dessus)
                  :  sable mouillé        =  planches du ponton
                  H  cachette             E  sortie possible       S  départ
Usage : .venv/bin/python make_plage.py [--variante=<nom>] [--sans-images]
Variantes (essais A/B, écrites dans assets/maps/plage_<nom>/ avec le décor de « plage ») : voir VARIANTES.

Essais retenus (tools/blackout/ab_tension.py, docs/GORDEKA_EQUILIBRAGE.md, 2026-10-21) : tunnels qui arrivent
au palier du milieu de l'escalier et de la rampe, canot des sauveteurs au bout d'un ponton ; talus entre les
volées (la montée se voit d'en bas) ; plus de zone « Bord de l'eau » (bande de sable mouillé rattachée aux
plages) ; moins de cabines et de gros rochers (moins de planques derrière). Écartés : plus d'abris sur le sable,
moins de cachettes, sans tunnel vers les sorties du haut, rochers plus bas.
"""
import json
import math
import os
import sys
from collections import deque

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
W, H = 96, 40
ARGS = [a for a in sys.argv[1:]]
VARIANTE = next((a.split("=", 1)[1] for a in ARGS if a.startswith("--variante=")), "")
MAP_ID = "plage" + (f"_{VARIANTE}" if VARIANTE else "")
OUT = os.path.join(ROOT, "assets", "maps", MAP_ID)
DECOR_OUT = os.path.join(ROOT, "assets", "maps", "plage", "decor")
WALK = ".ES:="
OCCLUDE = "#cBHRv"
LOW = "t~r"

g = [["R"] * W for _ in range(H)]
placed = []        # (element, x, y, w, h)
dark_rects = []    # cases sombres hors zones (tunnels, bouches)


def put(x, y, w, h, ch):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 < xx < W - 1 and 0 < yy < H - 1:
                g[yy][xx] = ch


def obj(el, x, y, w=None, h=None):
    """Pose un objet du décor : son caractère sur ses cases et l'élément qui le dessine."""
    e = ELEMENTS[el]
    w = w or e["taille"][0]
    h = h or e["taille"][1]
    put(x, y, w, h, e["car"])
    placed.append((el, x, y, w, h))


def tunnel(x, y, w, h):
    put(x, y, w, h, ".")
    dark_rects.append([x, y, w, h])


# ---------------------------------------------------------------- éléments du décor
# car : caractère de la grille ; taille : cases (largeur, profondeur au sol) ; haut : débord vers le haut
# (cases) ; cat : catégorie (index.json) ; fichier : image commune reprise (sinon provisoire dessiné ici) ;
# anim : animation à prévoir ; prompt : description proposée pour pixelforge (positive, sans négation).
ELEMENTS = {
    # Cabines et plage
    "cabine_rayee": dict(nom="Cabine de plage rayée", car="c", taille=(1, 1), haut=1.3, cat="batiment",
                         prompt="A small wooden Biarritz beach changing cabin with bold blue and white vertical stripes, a narrow closed door, a little triangular roof with a white ridge, standing on the sand."),
    "cabine_rayee_rouge": dict(nom="Cabine de plage rayée rouge", car="c", taille=(1, 1), haut=1.3, cat="batiment",
                               prompt="A small wooden Biarritz beach changing cabin with bold red and white vertical stripes, a narrow closed door, a little triangular roof with a white ridge, standing on the sand."),
    "cachette_cabine": dict(nom="Cabine de plage (cachette)", car="H", taille=(1, 1), haut=1.3, cat="cachette",
                            prompt="A small wooden Biarritz beach changing cabin with blue and white vertical stripes and a bright orange door, a little triangular roof, clearly a hiding spot, slightly bigger than the cabins around it."),
    "parasol": dict(nom="Parasol rayé", car="t", taille=(1, 1), haut=1.1, cat="objet_bas", anim="parasol qui ondule au vent (boucle)",
                    prompt="A round beach umbrella with wide red and white stripes on a thin wooden pole planted in the sand, seen from above at a slight angle, the canopy round and generous."),
    "parasol_bleu": dict(nom="Parasol rayé bleu", car="t", taille=(1, 1), haut=1.1, cat="objet_bas", anim="parasol qui ondule au vent (boucle)",
                         prompt="A round beach umbrella with wide turquoise and white stripes on a thin wooden pole planted in the sand, seen from above at a slight angle, the canopy round and generous."),
    "transat": dict(nom="Transat en toile", car="t", taille=(2, 1), haut=0.2, cat="objet_bas",
                    prompt="A wooden folding deck chair with a striped green and white canvas, lying long and low on the sand, a folded beach towel on it."),
    "douche": dict(nom="Douche de plage", car="t", taille=(1, 1), haut=1.2, cat="objet_bas",
                   prompt="A simple outdoor beach shower: a tall blue metal post with a round shower head and a small wooden duckboard at its foot, drops of water."),
    "paravent": dict(nom="Paravent de plage (brise-vent)", car="c", taille=(2, 1), haut=0.5, cat="objet", anim="toile qui se gonfle au vent",
                     prompt="A colorful striped beach windbreak made of canvas stretched between wooden poles, planted in the sand in a straight line, yellow, orange and blue stripes."),
    "planches_surf": dict(nom="Râtelier de planches de surf", car="c", taille=(1, 1), haut=1.0, cat="objet",
                          prompt="A wooden rack standing on the sand holding four upright surfboards in bright colors (yellow, turquoise, coral, white), rounded noses on top."),
    "kiosque_glaces": dict(nom="Kiosque à glaces", car="c", taille=(2, 2), haut=1.4, cat="repere",
                           prompt="A small round beach ice cream kiosk with a pink and white striped awning, a counter window, and a giant ice cream cone sculpture on its roof, a landmark visible from far away."),
    "chateau_sable": dict(nom="Château de sable géant", car="t", taille=(2, 2), haut=0.6, cat="repere",
                          prompt="A big sand castle with four round towers, little walls and a moat, a small Basque flag on the top tower, golden sand with darker wet sand details."),
    "filet_volley": dict(nom="Filet de beach-volley", car="t", taille=(4, 1), haut=0.8, cat="objet_bas",
                         prompt="A beach volleyball net between two wooden posts planted in the sand, a white net with a blue band on top, a ball resting at the foot of a post."),
    "cachette_tente": dict(nom="Tente de plage (cachette)", car="H", taille=(1, 1), haut=0.6, cat="cachette",
                           prompt="A small dome beach sun tent in orange and turquoise fabric with a round open entrance, pegged in the sand, clearly a hiding spot."),
    "cachette_glaciere": dict(nom="Glacière géante (cachette)", car="H", taille=(1, 1), haut=0.0, cat="cachette",
                              fichier="objets/cachette_caisse_glace.png", ombre="objets/cachette_caisse_glace_ombre.png",
                              prompt="(image commune reprise : caisse à glace du port)"),
    "cachette_coffre_plage": dict(nom="Coffre à jouets de plage (cachette)", car="H", taille=(1, 1), haut=0.0, cat="cachette",
                                  fichier="objets/cachette_coffre_quai.png", ombre="objets/cachette_coffre_quai_ombre.png",
                                  prompt="(image commune reprise : coffre de quai du port)"),
    "bouee_poteau": dict(nom="Poteau à bouée", car="t", taille=(1, 1), haut=1.0, cat="objet_bas",
                         prompt="A short wooden post planted in the sand holding a red and white ring buoy, a coiled rope at its foot."),
    # Rochers
    "rocher": dict(nom="Rocher", car="c", taille=(1, 1), haut=0.4, cat="rocher",
                   prompt="A rounded golden-grey coastal rock of the Basque coast, smooth chunky shape with a flat lighter top and a darker front, a little green seaweed at its foot."),
    "rocher_large": dict(nom="Gros rocher", car="c", taille=(2, 1), haut=0.6, cat="rocher",
                         prompt="A wide rounded golden-grey coastal rock, smooth chunky shape with a flat lighter top and a darker front, a few barnacles and a little green seaweed at its foot."),
    "grand_rocher": dict(nom="Grand rocher", car="c", taille=(2, 2), haut=0.9, cat="rocher",
                         prompt="A big tall golden-grey coastal rock of Biarritz with layered strata, a flat top with a tuft of grass, a darker front face, seaweed and small shells at its foot."),
    "rocher_geant": dict(nom="Rocher géant (repère)", car="c", taille=(3, 2), haut=1.3, cat="repere",
                         prompt="A huge golden-grey sea rock shaped like an arch with layered strata, a small natural tunnel through its middle, a tuft of grass on top, a landmark of the Basque coast."),
    "rocher_bas": dict(nom="Rochers bas", car="r", taille=(1, 1), haut=0.0, cat="objet_bas",
                       prompt="A cluster of low flat rocks covered with green seaweed and small mussels, barely above the sand."),
    "rocher_bas_large": dict(nom="Banc de rochers bas", car="r", taille=(2, 1), haut=0.0, cat="objet_bas",
                             prompt="A wide low shelf of flat rocks covered with green seaweed and small mussels, barely above the sand."),
    "flaque": dict(nom="Flaque de marée", car="~", taille=(2, 1), haut=0.0, cat="objet_bas", anim="reflets qui scintillent",
                   prompt="A small tide pool in a ring of low rocks, clear turquoise water, a starfish and a little crab inside, seen from above."),
    "flaque_grande": dict(nom="Grande flaque de marée", car="~", taille=(3, 2), haut=0.0, cat="objet_bas", anim="reflets qui scintillent",
                          prompt="A big tide pool in a ring of low rocks, clear turquoise water, starfish, sea anemones and a little crab inside, seen from above."),
    "cachette_creux_rocher": dict(nom="Creux de rocher (cachette)", car="H", taille=(1, 1), haut=0.6, cat="cachette",
                                  prompt="A chunky golden-grey rock with a dark round hollow at its front big enough for a child, an orange starfish stuck on it as a marker, clearly a hiding spot."),
    # Grottes et tunnels
    "rocher_grotte": dict(nom="Rocher de grotte", car="c", taille=(1, 1), haut=0.6, cat="rocher",
                          prompt="A dark blue-grey cave rock pillar, rounded and chunky, wet shiny highlights, a few glowing turquoise drops of water."),
    "rocher_grotte_large": dict(nom="Bloc de grotte", car="c", taille=(2, 1), haut=0.7, cat="rocher",
                                prompt="A wide dark blue-grey cave boulder, rounded and chunky, wet shiny highlights, small pale stalagmites on top."),
    "tonneau": dict(nom="Tonneau des contrebandiers", car="c", taille=(1, 1), haut=0.4, cat="objet",
                    prompt="A sturdy old wooden barrel with dark iron hoops standing upright, a coiled rope around its foot, a smugglers cave feeling, cute and friendly."),
    "caisses": dict(nom="Pile de caisses", car="c", taille=(2, 2), haut=1.0, cat="objet",
                    fichier="objets/caisses_poisson.png", ombre="objets/caisses_poisson_ombre.png",
                    prompt="(image commune reprise : caisses de poisson du port)"),
    "cachette_coffre_contrebandiers": dict(nom="Coffre des contrebandiers (cachette)", car="H", taille=(1, 1), haut=0.0,
                                           cat="cachette", fichier="objets/cachette_coffre_cordages.png",
                                           ombre="objets/cachette_coffre_cordages_ombre.png",
                                           prompt="(image commune reprise : coffre à cordages du phare)"),
    "lanterne_grotte": dict(nom="Lanterne posée", car="t", taille=(1, 1), haut=0.5, cat="objet_bas", anim="flamme qui vacille",
                            prompt="An old brass lantern standing on a flat rock, a warm yellow flame inside, a small circle of warm light on the ground."),
    # Restaurants
    "facade_resto_rouge": dict(nom="Façade du restaurant Itsasoa", car="c", taille=(3, 1), haut=1.6, cat="batiment",
                               prompt="The front wall of a small Basque beach restaurant built against a cliff, white walls with dark red timber beams, a wide window with red shutters and a striped red and white awning above it."),
    "facade_resto_vert": dict(nom="Façade du Txiringito", car="c", taille=(3, 1), haut=1.6, cat="batiment",
                              prompt="The front wall of a small wooden beach bar shack built against a cliff, pale wood planks, dark green shutters, a striped green and white awning and a few hanging shell garlands."),
    "comptoir": dict(nom="Comptoir de bar", car="c", taille=(3, 2), haut=1.0, cat="batiment",
                     fichier="objets/comptoir_bar.png", ombre="objets/comptoir_bar_ombre.png",
                     prompt="(image commune reprise : comptoir du bar du port)"),
    "table_terrasse": dict(nom="Table de terrasse", car="t", taille=(2, 1), haut=0.0, cat="objet_bas",
                           fichier="objets/table_terrasse.png", ombre="objets/table_terrasse_ombre.png",
                           prompt="(image commune reprise : table de terrasse du port)"),
    "jardiniere": dict(nom="Jardinière d'hortensias", car="t", taille=(3, 1), haut=0.4, cat="objet_bas",
                       prompt="A long low white wooden planter box full of blue and pink hydrangeas, edging a restaurant terrace."),
    "cachette_sous_terrasse": dict(nom="Dessous de la terrasse (cachette)", car="H", taille=(1, 1), haut=0.0, cat="cachette",
                                   prompt="The front edge of a raised wooden terrace deck with a lattice skirt and a dark opening under it with a little orange curtain, big enough for a child to crawl under, clearly a hiding spot."),
    "fourneau": dict(nom="Fourneau de cuisine", car="c", taille=(2, 1), haut=0.7, cat="objet", anim="fumée et vapeur des casseroles",
                     prompt="A big restaurant kitchen stove in dark iron with copper pots and a pan of grilled sardines, little puffs of steam."),
    "plan_travail": dict(nom="Plan de travail", car="t", taille=(3, 1), haut=0.2, cat="objet_bas",
                         prompt="A long stainless steel kitchen worktable with a wooden chopping board, a bowl of piperade peppers, a basket of bread and a ladle."),
    "cachette_frigo": dict(nom="Grand frigo de la cuisine (cachette)", car="H", taille=(1, 1), haut=1.1, cat="cachette",
                           prompt="A tall rounded retro restaurant fridge in pale turquoise with a big chrome handle and an orange magnet on the door, clearly a hiding spot."),
    "cachette_poubelle": dict(nom="Poubelle de la cuisine (cachette)", car="H", taille=(1, 1), haut=0.3, cat="cachette",
                              fichier="objets/cachette_poubelle_ruelle.png", ombre="objets/cachette_poubelle_ruelle_ombre.png",
                              prompt="(image commune reprise : poubelle de ruelle du port)"),
    # Poste de secours
    "poste_secours": dict(nom="Poste de secours", car="c", taille=(4, 2), haut=2.2, cat="repere", anim="drapeaux qui claquent au vent (vert, jaune, rouge)",
                          prompt="A small white lifeguard station on wooden stilts with a red roof, a lookout balcony, a red cross sign shape, a tall flag pole with a green flag, landmark of the beach."),
    "chaise_surveillance": dict(nom="Chaise haute du maître-nageur", car="t", taille=(1, 1), haut=1.6, cat="objet_bas",
                                prompt="A tall white wooden lifeguard chair with a ladder and a small red parasol on top, standing on the sand."),
    "rack_sauvetage": dict(nom="Planches de sauvetage", car="c", taille=(2, 1), haut=0.6, cat="objet",
                           prompt="A wooden rack holding two long yellow rescue boards and a red rescue tube, standing on the sand."),
    "cachette_coffre_sauveteur": dict(nom="Coffre du sauveteur (cachette)", car="H", taille=(1, 1), haut=0.2, cat="cachette",
                                      prompt="A big red wooden lifeguard chest with a white cross shape on its lid and a coiled rope on top, clearly a hiding spot with an orange latch."),
    # Bateaux
    "barque_retournee": dict(nom="Barque retournée", car="B", taille=(3, 2), haut=0.4, cat="bateau",
                             prompt="A wooden rowing boat lying upside down on the sand, its curved hull painted Basque red and white, two oars resting against it."),
    "barque_retournee_verte": dict(nom="Barque retournée verte", car="B", taille=(3, 2), haut=0.4, cat="bateau",
                                   prompt="A wooden rowing boat lying upside down on the sand, its curved hull painted dark Basque green and white, a fishing net draped over it."),
    "bateau_remorque": dict(nom="Bateau de pêche sur sa remorque", car="B", taille=(4, 2), haut=1.0, cat="bateau",
                            coque=True,
                            prompt="A small Basque fishing boat (txalupa) resting upright on a wooden beach trailer, red and white hull with a green stripe, a little cabin at the back."),
    "canoe": dict(nom="Canoës empilés", car="B", taille=(3, 1), haut=0.3, cat="bateau",
                  prompt="Two bright yellow and orange sea kayaks stacked on the sand with their paddles."),
    "cachette_annexe": dict(nom="Petite barque retournée (cachette)", car="H", taille=(1, 1), haut=0.2, cat="cachette",
                            prompt="A tiny wooden dinghy turned upside down on the sand, propped up on one side by a stone so a child can crawl under, an orange stripe on its hull, clearly a hiding spot."),
    # Port-Vieux et digue
    "banc": dict(nom="Banc du front de mer", car="t", taille=(3, 1), haut=0.0, cat="objet_bas",
                 fichier="objets/banc_vert.png", ombre="objets/banc_vert_ombre.png",
                 prompt="(image commune reprise : banc vert du port)"),
    "bitte": dict(nom="Bitte d'amarrage", car="t", taille=(1, 1), haut=0.0, cat="objet_bas",
                  fichier="objets/bitte_amarrage.png", ombre="objets/bitte_amarrage_ombre.png",
                  prompt="(image commune reprise : bitte d'amarrage du port)"),
    "cachette_casier": dict(nom="Casier à homards (cachette)", car="H", taille=(1, 1), haut=0.0, cat="cachette",
                            fichier="objets/cachette_casier_homards.png", ombre="objets/cachette_casier_homards_ombre.png",
                            prompt="(image commune reprise : casier à homards du port)"),
    "cabine_blanche": dict(nom="Cabine du Port-Vieux", car="c", taille=(1, 1), haut=1.3, cat="batiment",
                           prompt="A small white wooden bathing cabin of the old port of Biarritz with a turquoise door and a flat little roof, a towel hanging on a hook."),
    "longue_vue": dict(nom="Longue-vue du belvédère", car="t", taille=(1, 1), haut=0.8, cat="objet_bas",
                       prompt="A coin-operated seaside telescope on a short green cast iron post, pointing toward the sea, a landmark of the cliff walk of Biarritz."),
    "club_plage": dict(nom="Club de plage des enfants", car="c", taille=(3, 2), haut=1.4, cat="repere",
                       anim="fanions qui flottent au vent",
                       prompt="A big square beach club tent for children in blue and yellow stripes with a scalloped edge, a rope of colorful pennants on top, a little slide next to it, a landmark of the beach."),
    "pile_transats": dict(nom="Pile de transats", car="c", taille=(2, 1), haut=0.6, cat="objet",
                          prompt="A neat stack of six folded wooden deck chairs with striped canvas leaning together on the sand, tied with a rope."),
    "lampadaire": dict(nom="Lampadaire de la digue", car="t", taille=(1, 1), haut=1.6, cat="objet_bas",
                       prompt="An old cast iron seaside street lamp painted dark green with a round white globe, on a stone pier."),
    # Sorties (à plat : on marche dessus)
    "sortie_escalier": dict(nom="Sortie : haut de l'escalier de la falaise", car="E", taille=(2, 2), haut=0, cat="sortie", type="decal",
                            anim="petit fanion vert qui flotte quand la sortie est ouverte",
                            prompt="The top landing of a stone staircase climbing a cliff, a little wooden gate open toward the town, seen from above, flat on the ground."),
    "sortie_rampe": dict(nom="Sortie : haut de la rampe du Port-Vieux", car="E", taille=(2, 2), haut=0, cat="sortie", type="decal",
                         anim="petit fanion vert qui flotte quand la sortie est ouverte",
                         prompt="The top of a paved ramp along a cliff with a little white railing and a lamp post, the road toward the town, seen from above, flat on the ground."),
    "sortie_digue": dict(nom="Sortie : bout de la digue", car="E", taille=(3, 2), haut=0, cat="sortie", type="decal",
                         anim="la barque qui attend tangue sur l'eau",
                         prompt="The round end of a stone pier with a small iron ladder going down to a red and white rowboat waiting on the water, seen from above."),
    "sortie_canot": dict(nom="Sortie : canot des sauveteurs", car="E", taille=(3, 1), haut=0, cat="sortie", type="decal",
                         anim="le canot tangue dans l'écume",
                         prompt="An orange inflatable rescue boat waiting on the wet sand at the edge of the waves, a rope and a paddle, seen from above."),
}

# Sols (tuile_sol, 2 × 2 cases par tuile) : zone(s) → texture.
FLOORS = {
    "sable": dict(nom="Sable doré", car=".", zones=["Cabines rayées", "Grande plage", "Bateaux au sec", "Port-Vieux",
                                                    "Poste de secours", "Rochers du Basta"],
                  prompt="Soft golden beach sand seen straight from above, gentle ripples drawn by the wind, a few tiny shells and pebbles, warm light beige."),
    "sable_mouille": dict(nom="Sable mouillé (bord de l'eau)", car=":", zones=["Rochers du Basta", "Grande plage", "Bateaux au sec", "Port-Vieux", "Digue"], anim="l'écume qui monte et descend sur le sable",
                          prompt="Wet shiny beach sand at the edge of the sea seen straight from above, slightly darker golden brown, little foam lines and reflections of the sky."),
    "planches": dict(nom="Planches de la terrasse", car=".", zones=["Restaurant Itsasoa", "Restaurant Txiringito"],
                     fichier="sols/sol_planches_terrasse.png", prompt="(image commune reprise : planches de la terrasse du port)"),
    "carrelage": dict(nom="Carrelage de la cuisine", car=".", zones=["Cuisine de l'Itsasoa", "Cuisine du Txiringito"],
                      fichier="sols/sol_carrelage_criee.png", prompt="(image commune reprise : carrelage de la criée)"),
    "sol_grotte": dict(nom="Sol de la grotte", car=".", zones=["Grotte des contrebandiers", "Grotte aux sirènes",
                                                               "Grotte de la marée", "tunnels (hors zones)"],
                       anim="gouttes qui tombent et ronds dans les flaques",
                       prompt="The floor of a sea cave seen straight from above, dark blue-grey wet rock with smooth worn shapes, small shallow puddles reflecting turquoise light, a few pebbles."),
    "marches": dict(nom="Marches de pierre", car=".", zones=["Escalier de la falaise", "Rampe du Port-Vieux"],
                    prompt="Wide old sandstone stair steps seen straight from above, horizontal steps with a slightly darker edge on each step, warm golden stone."),
    "ponton": dict(nom="Planches du ponton", car="=", zones=["Grande plage"], fichier="sols/sol_planches_terrasse.png",
                   prompt="(image commune reprise : planches de la terrasse du port)"),
    "digue": dict(nom="Dalles de la digue", car=".", zones=["Digue"], fichier="sols/sol_dalles_quai.png",
                  prompt="(image commune reprise : dalles de quai du port)"),
    "talus": dict(nom="Talus de la falaise (herbes et rochers bas)", car="r", zones=["Escalier de la falaise", "Rampe du Port-Vieux"],
                  prompt="A steep grassy slope at the foot of a sandstone cliff seen from above: tufts of sea grass, tamarisk bushes, small pink flowers and low golden rocks, calm colours."),
    "falaise": dict(nom="Falaise (dessus)", car="R", zones=["*"],
                    prompt="The top of an ochre and golden sandstone sea cliff seen straight from above, layered rock with soft cracks, tufts of green grass and little pink flowers on top."),
    "falaise_face": dict(nom="Pied de falaise (face rocheuse)", car="v", zones=["*"],
                         prompt="The front face of an ochre sandstone sea cliff, horizontal layered strata, darker at the bottom where it meets the sand, a few tufts of grass in the cracks."),
}

# Animés sans place fixe sur la grille (assets à créer, posés par le jeu ou en ornement).
ANIMES = {
    "vagues_ecume": dict(nom="Vagues et écume du bord de mer", taille=(2, 1),
                         prompt="Gentle rolling sea waves breaking on a golden beach, white foam lines, turquoise and navy water, seen from above with a slight tilt, horizontally seamless strip, loop of 6 frames."),
    "eau_mer_plage": dict(nom="Mer de la Côte des Basques (tuile animée)", taille=(2, 2),
                          prompt="Open sea seen from above, turquoise near the beach turning navy, soft wave crests, seamless tileable texture, loop of 6 frames."),
    "drapeaux_poste": dict(nom="Drapeaux de baignade du poste de secours", taille=(1, 2),
                           prompt="A tall white flag pole with a green bathing flag flapping in the wind, loop of 6 frames; variants with a yellow flag and a red flag."),
    "mouettes": dict(nom="Mouettes de la plage", taille=(1, 1),
                     prompt="A cute white and grey seagull standing on the sand, then flapping its wings and taking off, loop of 8 frames."),
    "fumee_cuisine": dict(nom="Fumée de la cuisine", taille=(1, 2),
                          prompt="Soft white puffs of cooking smoke rising and curling from a small chimney pipe, loop of 8 frames, transparent background."),
    "enseigne_itsasoa": dict(nom="Enseigne du restaurant Itsasoa", taille=(2, 1),
                             prompt="A hanging wooden restaurant sign shaped like a fish, painted red and white, swinging gently in the wind, loop of 6 frames."),
    "enseigne_txiringito": dict(nom="Enseigne du Txiringito", taille=(2, 1),
                                prompt="A wooden beach bar sign shaped like a surfboard, painted green and yellow, with shell garlands swinging gently in the wind, loop of 6 frames."),
    "parasols_vent": dict(nom="Parasols au vent", taille=(1, 1),
                          prompt="A red and white striped beach umbrella whose canopy ripples in the wind, loop of 6 frames."),
    "goutte_grotte": dict(nom="Gouttes dans la grotte", taille=(1, 1),
                          prompt="A drop of water falling from the cave ceiling into a small puddle, turquoise ripples spreading, loop of 8 frames."),
}

# Zones : (nom, x, y, w, h, sombre)
ZONES = [
    ("Escalier de la falaise", 1, 1, 12, 21, False),
    ("Grotte des contrebandiers", 15, 2, 13, 7, True),
    ("Grotte aux sirènes", 39, 2, 12, 6, True),
    ("Grotte de la marée", 62, 2, 12, 6, True),
    ("Rampe du Port-Vieux", 84, 1, 11, 12, False),
    ("Cuisine de l'Itsasoa", 35, 9, 11, 4, False),
    ("Cuisine du Txiringito", 63, 9, 10, 4, False),
    ("Cabines rayées", 13, 13, 18, 9, False),
    ("Restaurant Itsasoa", 31, 13, 16, 9, False),
    ("Poste de secours", 47, 13, 12, 9, False),
    ("Restaurant Txiringito", 59, 13, 16, 9, False),
    ("Port-Vieux", 75, 13, 20, 17, False),
    ("Rochers du Basta", 1, 22, 24, 17, False),
    ("Grande plage", 25, 22, 34, 17, False),
    ("Bateaux au sec", 59, 22, 16, 17, False),
    ("Digue", 75, 30, 12, 9, False),
]


def build():
    # ------------------------------------------------ bande du bas : la mer
    put(1, 34, 94, 5, "~")
    put(75, 30, 20, 4, "~")
    put(1, 32, 74, 2, ".")                      # bord de l'eau (sable mouillé)
    # ------------------------------------------------ la plage
    put(13, 13, 62, 19, ".")                    # sable, des cabines aux bateaux
    put(75, 13, 20, 17, ".")                    # Port-Vieux
    put(1, 22, 12, 10, ".")                     # rochers du Basta, sous l'escalier
    # ------------------------------------------------ escalier de la falaise (lacets, exposé)
    put(2, 18, 11, 4, ".")                      # palier du bas, ouvert sur la plage
    put(2, 12, 2, 6, ".")                       # volée A
    put(2, 10, 10, 2, ".")                      # palier du milieu
    put(10, 6, 2, 4, ".")                       # volée B
    put(2, 4, 10, 2, ".")                       # palier du haut (le tunnel y arrive)
    put(2, 1, 2, 3, ".")                        # volée C
    obj("sortie_escalier", 2, 1)
    # Talus d'herbes et de rochers bas entre les volées (on ne passe pas, on voit par-dessus) : la montée vers
    # la sortie se voit d'en bas, comme sur la vraie falaise (essai A/B « talus », 2026-10-21).
    put(4, 12, 9, 6, "r")
    put(4, 6, 6, 4, "r")
    obj("longue_vue", 6, 4)
    obj("banc", 5, 10)
    obj("rocher", 12, 21)                       # coupe la vue du palier du bas
    obj("douche", 7, 20)
    # ------------------------------------------------ grottes et tunnels (sombres)
    # Les tunnels entrent et sortent des grottes à des hauteurs différentes et font un coude : pas de
    # ligne de vue d'un bout à l'autre ; ce sont les raccourcis sombres, parallèles à la plage.
    # Grotte des contrebandiers : tonneaux, caisses, le coffre ; bouche sur les cabines.
    put(15, 2, 13, 7, ".")
    # Le tunnel part du palier du MILIEU : les dernières volées jusqu'à la sortie restent à découvert.
    tunnel(12, 10, 3, 2)
    tunnel(14, 7, 1, 4)
    tunnel(20, 9, 2, 4)                         # bouche vers les cabines
    obj("tonneau", 16, 2)
    obj("tonneau", 17, 2)
    obj("caisses", 24, 2)
    obj("rocher_grotte_large", 18, 5)
    obj("rocher_grotte", 25, 6)
    obj("cachette_coffre_contrebandiers", 22, 5)
    obj("lanterne_grotte", 15, 8)
    obj("tonneau", 26, 8)
    # Tunnel vers la grotte aux sirènes : part en haut, descend, arrive au milieu.
    tunnel(28, 2, 4, 2)
    tunnel(30, 2, 2, 5)
    tunnel(32, 5, 7, 2)
    # Grotte aux sirènes : la grande flaque, des blocs ; porte sur la cuisine de l'Itsasoa.
    put(39, 2, 12, 6, ".")
    obj("flaque_grande", 43, 3)
    obj("rocher_grotte", 42, 5)
    obj("rocher_grotte", 48, 2)
    obj("rocher_grotte_large", 46, 6)
    obj("cachette_creux_rocher", 49, 5)
    obj("lanterne_grotte", 39, 2)
    tunnel(40, 8, 2, 1)                         # porte de la cuisine
    # Tunnel vers la grotte de la marée, avec une faille qui descend sur le poste de secours.
    tunnel(51, 2, 7, 2)
    tunnel(56, 2, 2, 11)                        # faille du poste de secours
    tunnel(58, 6, 4, 2)
    # Grotte de la marée : blocs, flaque, lanterne ; porte sur la cuisine du Txiringito.
    put(62, 2, 12, 6, ".")
    obj("rocher_grotte_large", 64, 4)
    obj("rocher_grotte", 70, 2)
    obj("rocher_grotte", 67, 6)
    obj("flaque", 70, 5)
    obj("cachette_creux_rocher", 63, 2)
    obj("lanterne_grotte", 73, 7)
    tunnel(68, 8, 2, 1)                         # porte de la cuisine
    # Tunnel vers le milieu de la rampe du Port-Vieux (la fin de la montée reste à découvert).
    tunnel(74, 2, 4, 2)
    tunnel(76, 2, 2, 9)
    tunnel(78, 9, 6, 2)
    # ------------------------------------------------ rampe du Port-Vieux (exposée)
    put(84, 4, 10, 3, ".")                      # palier du haut, exposé
    put(92, 1, 2, 3, ".")
    obj("sortie_rampe", 92, 1)
    put(84, 7, 2, 6, ".")                       # rampe vers la plage (le tunnel y arrive à mi-hauteur)
    obj("lampadaire", 88, 6)
    obj("lampadaire", 90, 4)
    put(86, 7, 8, 6, "r")                       # talus sous le palier : la montée se voit de l'anse
    # ------------------------------------------------ restaurant Itsasoa (rouge)
    put(35, 9, 11, 4, ".")                      # cuisine creusée dans la falaise
    obj("fourneau", 36, 9)
    obj("plan_travail", 41, 11)
    obj("cachette_frigo", 45, 10)
    # Façade entre la cuisine et la terrasse : deux portes et le comptoir.
    obj("facade_resto_rouge", 34, 13)
    obj("comptoir", 39, 13)
    obj("facade_resto_rouge", 44, 13)
    for (x, y) in ((32, 16), (36, 17), (44, 16), (40, 19)):
        obj("table_terrasse", x, y)
    obj("parasol", 35, 15)
    obj("parasol", 42, 17)
    obj("jardiniere", 31, 20)
    obj("jardiniere", 44, 20)
    obj("cachette_sous_terrasse", 36, 20)
    # ------------------------------------------------ poste de secours
    obj("poste_secours", 49, 14)
    obj("chaise_surveillance", 48, 19)
    obj("rack_sauvetage", 53, 17)
    obj("cachette_coffre_sauveteur", 51, 18)
    obj("bouee_poteau", 57, 20)
    # ------------------------------------------------ restaurant Txiringito (vert)
    put(63, 9, 10, 4, ".")
    obj("fourneau", 70, 9)
    obj("plan_travail", 64, 11)
    obj("cachette_frigo", 63, 9)
    obj("facade_resto_vert", 62, 13)
    obj("comptoir", 66, 13)
    obj("facade_resto_vert", 71, 13)
    for (x, y) in ((60, 16), (64, 18), (72, 16), (68, 17)):
        obj("table_terrasse", x, y)
    obj("parasol_bleu", 63, 16)
    obj("parasol_bleu", 71, 18)
    obj("jardiniere", 59, 20)
    obj("jardiniere", 72, 20)
    obj("cachette_glaciere", 67, 20)
    # ------------------------------------------------ cabines rayées (rangées en quinconce)
    for x in (14, 15, 17, 18, 23, 24, 27, 28):
        obj("cabine_rayee" if x % 2 else "cabine_rayee_rouge", x, 14)
    obj("rocher_large", 19, 16)                 # coupe la vue de la bouche de la grotte
    obj("cachette_cabine", 16, 17)              # rangée du milieu : la cabine-cachette seule (moins de planques derrière)
    for x in (15, 16, 19, 20, 25, 26):
        obj("cabine_rayee" if x % 2 else "cabine_rayee_rouge", x, 20)
    obj("cachette_cabine", 28, 20)
    obj("douche", 21, 20)
    # ------------------------------------------------ rochers du Basta (chaos, flaques)
    obj("rocher_geant", 3, 24)
    obj("rocher_bas_large", 9, 23)
    obj("rocher_large", 14, 23)
    obj("flaque", 6, 27)
    obj("rocher", 2, 29)
    obj("rocher_bas_large", 12, 27)
    obj("rocher_bas_large", 17, 26)
    obj("rocher", 20, 24)
    obj("flaque_grande", 18, 29)
    obj("rocher_bas", 9, 30)
    obj("rocher_large", 22, 27)
    obj("cachette_creux_rocher", 8, 26)
    obj("cachette_creux_rocher", 16, 29)
    # ------------------------------------------------ grande plage (structurée)
    obj("kiosque_glaces", 41, 25)
    put(41, 28, 2, 1, "S")
    obj("club_plage", 52, 23)
    obj("paravent", 30, 23)
    obj("paravent", 46, 24)
    obj("paravent", 35, 28)
    obj("paravent", 47, 29)
    obj("planches_surf", 56, 27)
    obj("planches_surf", 27, 27)
    obj("pile_transats", 33, 25)
    obj("chateau_sable", 29, 25)
    for (x, y, k) in ((26, 23, "parasol"), (36, 23, "parasol_bleu"), (38, 30, "parasol"), (45, 27, "parasol_bleu"),
                      (52, 28, "parasol"), (57, 24, "parasol_bleu"), (29, 30, "parasol_bleu")):
        obj(k, x, y)
    for (x, y) in ((27, 24), (37, 24), (43, 29), (53, 29), (30, 30)):
        obj("transat", x, y)
    obj("cachette_tente", 38, 26)
    obj("cachette_coffre_plage", 49, 27)
    # ------------------------------------------------ bateaux tirés au sec
    obj("barque_retournee", 60, 23)
    obj("bateau_remorque", 66, 24)
    obj("barque_retournee_verte", 71, 22)
    obj("canoe", 61, 27)
    obj("barque_retournee", 69, 28)
    obj("caisses", 64, 29)
    obj("cachette_annexe", 65, 27)
    obj("cachette_annexe", 72, 26)
    # ------------------------------------------------ Port-Vieux (anse, cabines blanches) et digue
    for x in (77, 80, 88, 91):
        obj("cabine_blanche", x, 14)
    obj("banc", 77, 18)
    obj("douche", 81, 18)
    obj("grand_rocher", 91, 18)
    obj("rocher_large", 87, 21)
    obj("rocher", 76, 23)
    obj("rocher_large", 89, 26)
    obj("cachette_creux_rocher", 92, 23)
    obj("cachette_casier", 79, 21)
    put(82, 26, 3, 13, ".")                     # la digue, longue et exposée
    put(75, 32, 7, 2, ".")                      # passerelle de la digue au bord de l'eau (pas de cul-de-sac)
    obj("bitte", 82, 30)
    obj("bitte", 84, 34)
    obj("sortie_digue", 82, 37)
    # ------------------------------------------------ bord de l'eau (long, exposé : rochers et bouées)
    obj("rocher_large", 9, 32)
    obj("rocher_large", 19, 32)
    obj("rocher", 28, 33)
    obj("bouee_poteau", 40, 32)
    obj("rocher", 46, 33)
    obj("rocher", 62, 33)
    obj("rocher_bas_large", 69, 32)
    put(51, 34, 2, 3, "=")                      # ponton des sauveteurs (planches), à découvert dans les vagues
    obj("sortie_canot", 50, 37)
    # Bande de sable mouillé (« : ») : elle appartient aux plages du dessus (pas de zone à part, essai « zones »).
    for y in (32, 33):
        for x in range(1, 82):
            if g[y][x] == ".":
                g[y][x] = ":"


def unobj(x, y, ch="."):
    """Retire l'objet posé qui couvre la case (x, y) (variantes)."""
    for p in list(placed):
        el, px, py, w, h = p
        if px <= x < px + w and py <= y < py + h:
            placed.remove(p)
            put(px, py, w, h, ch)


def v_sans_tunnel_escalier():
    """Sans le tunnel de la grotte des contrebandiers au palier du milieu de l'escalier."""
    put(12, 10, 3, 2, "R")
    put(14, 7, 1, 4, "R")
    for r in ([12, 10, 3, 2], [14, 7, 1, 4]):
        dark_rects.remove(r)


def v_rochers():
    """Rochers du Basta et Port-Vieux moins sûrs : deux gros rochers du Basta et le grand rocher du Port-Vieux
    deviennent des rochers bas (on voit par-dessus)."""
    for (x, y) in ((14, 23), (22, 27)):
        unobj(x, y)
        obj("rocher_bas_large", x, y)
    unobj(91, 18)
    obj("rocher_bas_large", 91, 18)


def v_rochers_pv():
    """v_rochers, et les rochers du Port-Vieux bas aussi (sauf le creux-cachette)."""
    v_rochers()
    for (x, y, el) in ((87, 21, "rocher_bas_large"), (89, 26, "rocher_bas_large"), (76, 23, "rocher_bas")):
        unobj(x, y)
        obj(el, x, y)


VARIANTES = {"sans_tunnel_escalier": v_sans_tunnel_escalier, "rochers": v_rochers, "rochers_pv": v_rochers_pv}


def faces():
    """Pied de falaise : une case de face rocheuse (v) au-dessus de chaque sol de la falaise."""
    for y in range(1, H - 1):
        for x in range(W):
            if g[y][x] == "R" and y + 1 < H and g[y + 1][x] not in "Rv#":
                g[y][x] = "v"


def border():
    for x in range(W):
        g[0][x] = "#"
        g[H - 1][x] = "#"
    for y in range(H):
        g[y][0] = "#"
        g[y][W - 1] = "#"


# ---------------------------------------------------------------- diagnostic

def walkable(ch):
    return ch in WALK


def bfs(start, chars=WALK):
    d = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in d and g[n[1]][n[0]] in chars:
                d[n] = d[(x, y)] + 1
                q.append(n)
    return d


def zone_of(x, y):
    for i, z in enumerate(ZONES):
        if z[1] <= x < z[1] + z[3] and z[2] <= y < z[2] + z[4]:
            return i
    return -1


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


EXIT_NAMES = {"sortie_escalier": "Haut de l'escalier", "sortie_rampe": "Haut de la rampe",
              "sortie_digue": "Bout de la digue", "sortie_canot": "Ponton des sauveteurs"}


def exit_name(grp):
    """Nom d'une sortie : celui de son objet (sinon sa zone)."""
    x, y = grp[0]
    for (el, px, py, w, h) in placed:
        if px <= x < px + w and py <= y < py + h and el in EXIT_NAMES:
            return EXIT_NAMES[el]
    return ZONES[zone_of(x, y)][0]


def zone_graph():
    """Liaisons entre zones : cases de sol voisines de deux zones, ou couloir (hors zones) commun."""
    links = set()
    for y in range(H):
        for x in range(W):
            if not walkable(g[y][x]):
                continue
            a = zone_of(x, y)
            for dx, dy in ((1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if nx < W and ny < H and walkable(g[ny][nx]):
                    b = zone_of(nx, ny)
                    if a != b and a >= 0 and b >= 0:
                        links.add((min(a, b), max(a, b)))
    # Couloirs : composantes de cases hors zones.
    seen = set()
    for y in range(H):
        for x in range(W):
            if (x, y) in seen or not walkable(g[y][x]) or zone_of(x, y) >= 0:
                continue
            comp, q, touch = [], [(x, y)], set()
            seen.add((x, y))
            while q:
                cx, cy = q.pop()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (cx + dx, cy + dy)
                    if not (0 <= n[0] < W and 0 <= n[1] < H) or not walkable(g[n[1]][n[0]]):
                        continue
                    z = zone_of(*n)
                    if z >= 0:
                        touch.add(z)
                    elif n not in seen:
                        seen.add(n)
                        q.append(n)
            t = sorted(touch)
            for i in range(len(t)):
                for j in range(i + 1, len(t)):
                    links.add((t[i], t[j]))
    return links


def rays(x, y, n=16, cap=25):
    out = []
    for k in range(n):
        a = 2 * math.pi * k / n
        dx, dy = math.cos(a), math.sin(a)
        L = 0.0
        while L < cap:
            L += 0.25
            cx, cy = int(x + 0.5 + dx * L), int(y + 0.5 + dy * L)
            if not (0 <= cx < W and 0 <= cy < H) or g[cy][cx] in OCCLUDE:
                break
        out.append(L)
    return out


def check(verbose=True):
    start = next((x, y) for y in range(H) for x in range(W) if g[y][x] == "S")
    d = bfs(start)
    bad = [(x, y) for y in range(H) for x in range(W) if g[y][x] in ".E" and (x, y) not in d]
    hides = [(x, y) for y in range(H) for x in range(W) if g[y][x] == "H"]
    lone = [h for h in hides if not any((h[0] + dx, h[1] + dy) in d for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    free_sides = {h: sum((h[0] + dx, h[1] + dy) in d for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) for h in hides}
    out = {"sol": len(d), "isolees": len(bad), "cachettes": len(hides), "cachettes_inaccessibles": len(lone)}
    if not verbose:
        return not bad and not lone, out
    print(f"carte {MAP_ID} {W}×{H}, sol atteignable {len(d)} cases, isolées {len(bad)}, cachettes {len(hides)} "
          f"(inaccessibles {len(lone)}, côtés libres moyens {sum(free_sides.values()) / max(len(hides), 1):.1f})")
    if bad:
        print("  cases isolées :", bad[:12])
    if lone:
        print("  cachettes inaccessibles :", lone)
    per = {}
    for h in hides:
        per.setdefault(zone_of(*h), []).append(h)
    links = zone_graph()
    deg = {i: 0 for i in range(len(ZONES))}
    for a, b in links:
        deg[a] += 1
        deg[b] += 1
    print(f"  liaisons entre zones : {len(links)}, boucles indépendantes : {len(links) - len(ZONES) + 1}")
    print("  culs-de-sac (une seule liaison) :", [ZONES[i][0] for i in deg if deg[i] == 1] or "aucun")
    print("  zones sans cachette :", [ZONES[i][0] for i in range(len(ZONES)) if i not in per])
    # Lignes de vue et vides par zone.
    print("  zone | cases | cachettes | liaisons | rayon moyen | part ≥ 15 cases | vides (rien à 2 cases)")
    tot = []
    for i, z in enumerate(ZONES):
        cells = [(x, y) for y in range(z[2], z[2] + z[4]) for x in range(z[1], z[1] + z[3])
                 if walkable(g[y][x]) and zone_of(x, y) == i]
        if not cells:
            continue
        rs = [rays(x, y) for (x, y) in cells]
        mean = sum(sum(r) / len(r) for r in rs) / len(rs)
        far = sum(1 for r in rs if max(r) >= 15) / len(rs)
        empty = 0
        for (x, y) in cells:
            near = False
            for yy in range(y - 2, y + 3):
                for xx in range(x - 2, x + 3):
                    if 0 <= xx < W and 0 <= yy < H and g[yy][xx] in "cBHtr~" and zone_of(xx, yy) == i:
                        near = True
            empty += 0 if near else 1
        tot.append((len(cells), mean, far, empty))
        print(f"  {z[0]:<26} | {len(cells):4} | {len(per.get(i, [])):2} | {deg[i]} | {mean:5.1f} | {100 * far:3.0f} % | "
              f"{100 * empty / len(cells):3.0f} %")
    n = sum(t[0] for t in tot)
    print(f"  TOTAL rayon moyen {sum(t[0] * t[1] for t in tot) / n:.1f}, part ≥ 15 cases "
          f"{100 * sum(t[0] * t[2] for t in tot) / n:.0f} %, vides {100 * sum(t[3] for t in tot) / n:.0f} %")
    for grp in exit_groups():
        print(f"  sortie possible « {exit_name(grp)} » : {min(d.get(t, 9999) for t in grp)} cases du départ")
    return not bad and not lone, out


# ---------------------------------------------------------------- écriture

def write():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(row) for row in g) + "\n")
    zones = []
    for (n, x, y, w, h, sombre) in ZONES:
        z = {"name": n, "rect": [x, y, w, h]}
        if sombre:
            z["sombre"] = True
        zones.append(z)
    exits = [{"zone": exit_name(grp), "tiles": [list(t) for t in grp]} for grp in exit_groups()]
    objets = [{"element": el, "rect": [x, y, w, h]} for (el, x, y, w, h) in placed]
    data = {"name": "Plage de la Côte des Basques", "version": 1, "zones": zones, "exits": exits,
            "sombres": dark_rects, "objets": objets}
    if VARIANTE:
        data["decor"] = "plage"
        data["variante"] = VARIANTE
    with open(os.path.join(OUT, "zones.json"), "w") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)


def main():
    build()
    if VARIANTE:
        VARIANTES[VARIANTE]()
    faces()
    border()
    write()
    ok, _ = check()
    if "--sans-images" not in ARGS and not VARIANTE:
        import plage_decor
        plage_decor.ecrit(DECOR_OUT, ELEMENTS, FLOORS, [z[0] for z in ZONES], placed,
                          lambda x, y: ZONES[zone_of(x, y)][0] if zone_of(x, y) >= 0 else "hors zones")
    print(os.path.join(OUT, "map.txt"))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
