#!/usr/bin/env python3
"""Carte « bac à sable » de Blackout (GDD-BLACKOUT.md §10.1, carte kanban #624).

Carte d'essai du jalon 1, en cases de 32 px : 60 × 24 cases, soit environ 3 × 2 écrans de 640×360.
Trois secteurs (un disjoncteur chacun) : la Maison à l'ouest (pièces, couloir, portes, fenêtres,
cloisons fines), la Place au centre (murets, buissons, jardin fermé de grilles, lampadaires) et la
Plage à l'est (sol meuble, rochers bas, cabines, barque, hangar). Tout est en placeholders : le jeu
dessine des aplats et des formes simples (BkMap).

Écrit assets/maps/bac_a_sable/map.txt (une lettre par case) et zones.json (zones et teinte de leur
sol, 2 sorties, secteurs, sources de lumière, disjoncteurs, places des gâteaux et des mouettes, réglages
propres à la carte), puis vérifie : tout le sol atteignable depuis le départ, chaque cachette avec
deux côtés libres, chaque type de case présent.

Légende (BkMap) :
  sol     .  sol de la zone     :  sol meuble (sable)   E  sortie   S  départ
  pleins  #  mur plein          c  objet haut (armoire, caisses)    B  barque   H  cachette
          |  cloison fine verticale    -  cloison fine horizontale
  bas     t  objet bas (table, banc)   m  muret d'une case   b  buisson
          g  grille (vue oui, passage non)   f  fenêtre dans un mur (idem)   r  rochers bas
Usage : make_bac_a_sable.py
"""
import json
import os
from collections import deque

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "maps", "bac_a_sable")
W, H = 60, 24
WALK = set(".ES:=")
BLOCK = set("#cBH|-tmbgfr~Rv")

grid = [["." for _ in range(W)] for _ in range(H)]


def put(x, y, ch, w=1, h=1):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            grid[yy][xx] = ch


def hline(x0, x1, y, ch):
    put(x0, y, ch, x1 - x0 + 1, 1)


def vline(x, y0, y1, ch):
    put(x, y0, ch, 1, y1 - y0 + 1)


# ---------------------------------------------------------------- enceinte
hline(0, W - 1, 0, "#")
hline(0, W - 1, H - 1, "#")
vline(0, 0, H - 1, "#")
vline(W - 1, 0, H - 1, "#")

# ---------------------------------------------------------------- secteur A : la Maison (x 1 à 19)
vline(20, 1, 22, "#")              # façade est de la maison
put(20, 5, ".", 1, 2)              # porte vers la Place (haut)
put(20, 17, ".", 1, 2)             # porte vers la Place (bas)
put(20, 2, "f")                    # fenêtres sur la Place
put(20, 13, "f")
put(20, 21, "f")
hline(1, 19, 9, "#")               # mur entre les pièces du haut et le couloir
put(4, 9, ".", 2, 1)               # porte du salon
put(15, 9, ".", 2, 1)              # porte de la cuisine
put(8, 9, "f")                     # fenêtre du salon sur le couloir
hline(1, 19, 12, "#")              # mur entre le couloir et les pièces du bas
put(6, 12, ".", 2, 1)              # porte de la chambre
put(14, 12, ".", 2, 1)             # porte de l'atelier
vline(10, 1, 8, "#")               # mur salon | cuisine
put(10, 5, "f")                    # passe-plat vitré
put(10, 2, ".")                    # petite porte salon ↔ cuisine
vline(10, 13, 22, "|")             # cloison fine chambre | atelier (Louis la traverse)
put(10, 18, ".", 1, 2)             # passage dans la cloison
# Salon : armoire-cachette, canapé (bas), bibliothèque (haut), table basse.
put(1, 1, "c", 3, 1)
put(7, 1, "H")
put(2, 5, "t", 3, 2)
put(7, 6, "c", 2, 1)
# Cuisine : étagères hautes, table, buffet-cachette, une cloison fine horizontale (garde-manger).
put(11, 1, "c", 1, 3)
put(13, 4, "t", 4, 2)
put(18, 1, "H")
hline(16, 18, 7, "-")
put(18, 8, "H")
# Couloir : un coffre-cachette au bout.
put(1, 10, "H")
# Chambre : lit (bas), armoire (haut), cachette sous le lit.
put(2, 14, "t", 3, 2)
put(1, 21, "c", 2, 1)
put(8, 15, "H")
put(6, 19, "c", 1, 2)
# Atelier : établi, caisses, grille (râtelier ajouré), cachette.
put(12, 14, "t", 4, 1)
put(17, 20, "c", 2, 2)
vline(15, 17, 20, "g")
put(18, 15, "H")
put(12, 21, "H")

# ---------------------------------------------------------------- secteur B : la Place (x 21 à 38)
# Jardin fermé de grilles (on voit au travers, on entre par le portail du bas).
hline(26, 33, 3, "g")
hline(26, 33, 8, "g")
vline(26, 3, 8, "g")
vline(33, 3, 8, "g")
put(29, 8, ".", 2, 1)              # portail
put(27, 4, "b", 2, 1)
put(31, 6, "b")
put(32, 4, "H")                    # cabane à outils (cachette)
# Murets d'une case et buissons, un kiosque (haut), des bancs (bas).
hline(23, 26, 16, "m")
hline(31, 34, 16, "m")
vline(23, 17, 19, "m")
put(36, 5, "b", 1, 2)
put(22, 9, "b")
put(37, 19, "b")
put(28, 18, "c", 2, 2)             # kiosque
put(25, 21, "t", 2, 1)             # banc
put(32, 21, "t", 2, 1)
put(22, 3, "H")                    # poubelle-cachette
put(35, 14, "H")
put(24, 7, "t")                    # fontaine basse
# Départ au centre de la place.
put(30, 12, "S")
# Sortie 1 : en haut de la place, à découvert.
put(36, 1, "E", 2, 2)

# ---------------------------------------------------------------- limite Place | Plage (x 39)
vline(39, 1, 22, "#")
put(39, 8, ".", 1, 2)              # passage
put(39, 10, "g", 1, 4)             # grille : on voit la plage
put(39, 14, ".", 1, 2)             # passage
put(39, 16, "m", 1, 4)             # muret
put(39, 20, ".", 1, 3)             # passage

# ---------------------------------------------------------------- secteur C : la Plage (x 40 à 58)
put(40, 1, ":", 19, 22)            # sable partout, le hangar le recouvre
# Hangar (sol dur) en haut à gauche.
put(40, 1, ".", 10, 7)
hline(40, 50, 8, "#")
vline(50, 1, 8, "#")
put(44, 8, ".", 2, 1)              # porte du hangar
put(50, 4, "f")                    # fenêtre sur la plage
put(41, 4, "t", 3, 1)              # établi
put(47, 1, "c", 2, 2)              # caisses
put(41, 1, "H")
put(48, 6, "H")
# Plage : rochers bas, barque (haute), cabines-cachettes, buissons de dune, parasol (bas).
put(53, 3, "B", 3, 2)
put(43, 12, "r", 2, 1)
put(52, 9, "r")
put(48, 19, "r", 3, 1)
put(46, 15, "H")
put(56, 12, "H")
put(43, 21, "H")
put(54, 14, "c", 1, 2)             # poste de secours (haut)
put(42, 17, "b", 2, 1)
put(57, 7, "b")
put(51, 13, "t")                   # parasol replié
# Sortie 2 : au bout de la plage, à découvert.
put(56, 20, "E", 2, 2)

# ---------------------------------------------------------------- zones.json
ZONES = [
    # Nom, rectangle (x, y, l, h), teinte du sol. Les plus petites d'abord (zone_of prend la première).
    ("Salon", [1, 1, 9, 8], "6b5a52"),
    ("Cuisine", [11, 1, 9, 8], "5b6670"),
    ("Couloir", [1, 10, 19, 2], "5a5560"),
    ("Chambre", [1, 13, 9, 10], "675870"),
    ("Atelier", [11, 13, 9, 10], "5c5f58"),
    ("Jardin", [27, 4, 6, 4], "4f6a48"),
    ("Place", [21, 1, 18, 22], "62677a"),
    ("Hangar", [40, 1, 10, 7], "585d66"),
    ("Plage", [40, 1, 19, 22], "a08a60"),
]
SECTEURS = [
    {"id": "A", "nom": "Maison", "rect": [0, 0, 21, 24]},
    {"id": "B", "nom": "Place", "rect": [21, 0, 18, 24]},
    {"id": "C", "nom": "Plage", "rect": [39, 0, 21, 24]},
]
LUMIERES = [
    # Sources de lumière fixes (GDD §3.2, §9) : case de la source, rayon de la zone éclairée (cases),
    # secteur (le disjoncteur du secteur les éteint), type (dessin et couleur par défaut : BkLumieres),
    # couleur facultative. Dans la maison : plafonniers ; dehors : lampadaires ; deux néons pour
    # l'ambiance (rose sur la façade de la maison, cyan sur le hangar), posés contre le mur `mur`.
    {"pos": [5, 3], "rayon": 3.0, "secteur": "A", "type": "plafonnier"},
    {"pos": [15, 10], "rayon": 2.5, "secteur": "A", "type": "plafonnier"},
    {"pos": [5, 17], "rayon": 3.0, "secteur": "A", "type": "plafonnier"},
    {"pos": [24, 5], "rayon": 3.5, "secteur": "B", "type": "lampadaire"},
    {"pos": [35, 10], "rayon": 3.5, "secteur": "B", "type": "lampadaire"},
    {"pos": [26, 20], "rayon": 3.5, "secteur": "B", "type": "lampadaire"},
    {"pos": [36, 21], "rayon": 3.0, "secteur": "B", "type": "lampadaire"},
    {"pos": [21, 14], "rayon": 2.5, "secteur": "B", "type": "neon", "couleur": "#ff4fb8", "mur": [-1, 0]},
    {"pos": [45, 3], "rayon": 3.0, "secteur": "C", "type": "plafonnier"},
    {"pos": [45, 11], "rayon": 3.5, "secteur": "C", "type": "lampadaire"},
    {"pos": [53, 17], "rayon": 3.5, "secteur": "C", "type": "lampadaire"},
    {"pos": [51, 2], "rayon": 2.5, "secteur": "C", "type": "neon", "couleur": "#3fe0ff", "mur": [-1, 0]},
]
DISJONCTEURS = [
    # Case où l'on se tient, et côté du mur qui porte le boîtier.
    {"pos": [12, 10], "mur": [0, -1], "secteur": "A"},
    {"pos": [30, 1], "mur": [0, -1], "secteur": "B"},
    {"pos": [43, 7], "mur": [0, 1], "secteur": "C"},
]
GATEAUX = [[5, 7], [17, 10], [3, 18], [29, 6], [23, 12], [34, 19], [47, 11], [57, 17], [42, 2]]
MOUETTES = [[32, 13], [26, 22], [45, 17], [55, 10], [53, 21]]
EXITS = [
    {"zone": "Place", "tiles": [[36, 1], [37, 1], [36, 2], [37, 2]]},
    {"zone": "Plage", "tiles": [[56, 20], [57, 20], [56, 21], [57, 21]]},
]


def check():
    rows = ["".join(r) for r in grid]
    start = next((x, y) for y in range(H) for x in range(W) if rows[y][x] == "S")
    seen = {start}
    todo = deque([start])
    while todo:
        x, y = todo.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and rows[n[1]][n[0]] in WALK:
                seen.add(n)
                todo.append(n)
    walk = {(x, y) for y in range(H) for x in range(W) if rows[y][x] in WALK}
    lost = sorted(walk - seen)
    assert not lost, "sol isolé : %s" % lost[:10]
    for y in range(H):
        for x in range(W):
            if rows[y][x] == "H":
                free = sum(rows[y + dy][x + dx] in WALK for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                assert free >= 2, "cachette (%d, %d) : %d côté(s) libre(s)" % (x, y, free)
    for ch in ".:ES#cBH|-tmbgfr":
        assert any(ch in r for r in rows), "case absente : %r" % ch
    for g in GATEAUX + MOUETTES + [l["pos"] for l in LUMIERES] + [d["pos"] for d in DISJONCTEURS]:
        assert rows[g[1]][g[0]] in WALK, "point sur une case pleine : %s (%r)" % (g, rows[g[1]][g[0]])
    for d in DISJONCTEURS + [l for l in LUMIERES if "mur" in l]:
        wx, wy = d["pos"][0] + d["mur"][0], d["pos"][1] + d["mur"][1]
        assert rows[wy][wx] == "#", "boîtier ou néon %s sans mur" % d
    for e in EXITS:
        for t in e["tiles"]:
            assert rows[t[1]][t[0]] == "E", "sortie %s" % t
    return rows, len(walk)


def main():
    rows, n = check()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "map.txt"), "w") as f:
        f.write("\n".join(rows) + "\n")
    info = {
        "name": "Bac à sable",
        "version": 1,
        "_doc": "Écrit par tools/blackout/make_bac_a_sable.py (GDD-BLACKOUT.md §10.1). Sources de lumière "
                "fixes (« lumieres », BkLumieres) et disjoncteurs, un par secteur (GDD §3.2).",
        "regles": {"exits_min_gap": 10.0},
        "zones": [{"name": z[0], "rect": z[1], "sol": "#" + z[2]} for z in ZONES],
        "exits": EXITS,
        "secteurs": SECTEURS,
        "lumieres": LUMIERES,
        "disjoncteurs": DISJONCTEURS,
        "gateaux": GATEAUX,
        "mouettes": MOUETTES,
    }
    with open(os.path.join(OUT, "zones.json"), "w") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("\n".join(rows))
    print("%d × %d cases, %d cases de sol, %d cachettes" % (W, H, n, sum(r.count("H") for r in rows)))


if __name__ == "__main__":
    main()
