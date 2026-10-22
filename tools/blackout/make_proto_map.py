#!/usr/bin/env python3
"""Carte du prototype gris de Gordeka : le Port des Pêcheurs en blocs (SPEC-GORDEKA §8).

15 zones (5 × 3) de 18 × 12 cases, séparées par des murs percés de passages ; taille de The
Skeld (~5 × 3,5 écrans). Écrit assets/maps/port_pecheurs/map.txt (une lettre par case) et
zones.json (nom et rectangle de chaque zone), puis vérifie que tout est atteignable.

Légende : . sol   # mur/bâtiment   c caisse   B bateau   (pleins, cachent la vue)
          t objet bas (table, filet : bloque le passage, pas la vue)   ~ eau (idem)
          H cachette (casier, poubelle)   E sortie   S départ
Usage : make_proto_map.py
"""
import json
import os
from collections import deque

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "maps", "port_pecheurs")
RW, RH = 18, 12                    # intérieur d'une zone
COLS, ROWS = 5, 3
W, H = COLS * (RW + 1) + 1, ROWS * (RH + 1) + 1     # 96 × 40

NAMES = [
    ["Jetée", "Bassin ouest", "Bassin est", "Rampe des barques", "Criée"],
    ["Crampottes", "Quai des chalutiers", "Place du port", "Quai des barques", "Hangar à filets"],
    ["Parking", "Cale sèche", "Rue des pêcheurs", "Terrasse", "Atelier"],
]
# Passages : (ligne, colonne) → voisin à droite / en bas, avec la position (en cases dans la zone)
# et la largeur de l'ouverture. Absents = mur plein (boucles et culs-de-sac voulus).
DOORS_RIGHT = {(0, 0): [(10, 3)], (0, 1): [(6, 3)], (0, 3): [(9, 3)],
               (1, 0): [(4, 3)], (1, 1): [(7, 3)], (1, 2): [(3, 3), (8, 3)], (1, 3): [(6, 3)],
               (2, 0): [(5, 3)], (2, 2): [(8, 3)], (2, 3): [(3, 3)]}
DOORS_DOWN = {(0, 0): [(2, 3)], (0, 1): [(13, 3)], (0, 2): [(8, 3)], (0, 3): [(4, 3)],
              (1, 0): [(12, 3)], (1, 1): [(5, 3)], (1, 2): [(7, 5)], (1, 4): [(9, 3)],
              (0, 4): [(14, 3)]}

grid = [["#"] * W for _ in range(H)]


def origin(r, c):
    return 1 + c * (RW + 1), 1 + r * (RH + 1)


def put(r, c, x, y, ch, w=1, h=1):
    ox, oy = origin(r, c)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < RW and 0 <= yy < RH:
                grid[oy + yy][ox + xx] = ch


def fill(r, c, ch):
    put(r, c, 0, 0, ch, RW, RH)


# ---------------------------------------------------------------- zones

def jetee(r, c):
    fill(r, c, "~")
    put(r, c, 0, 9, ".", RW, 3)          # terre-plein en bas
    put(r, c, 0, 3, ".", 3, 7)           # départ de la jetée
    put(r, c, 0, 3, ".", 17, 3)          # longue jetée exposée
    put(r, c, 14, 3, "E", 3, 3)          # sortie au bout
    put(r, c, 6, 2, "t", 1, 1)
    put(r, c, 11, 6, "t", 1, 1)          # bittes d'amarrage
    put(r, c, 5, 10, "c", 2, 2)
    put(r, c, 12, 10, "c", 2, 1)
    put(r, c, 9, 10, "H")


def bassin_ouest(r, c):
    fill(r, c, "~")
    put(r, c, 0, 5, ".", RW, 3)          # ponton
    put(r, c, 0, 8, ".", RW, 4)          # quai
    put(r, c, 3, 2, "B", 5, 2)
    put(r, c, 11, 1, "B", 4, 2)          # barques au mouillage
    put(r, c, 2, 9, "c", 2, 2)
    put(r, c, 8, 10, "t", 3, 1)
    put(r, c, 14, 9, "c", 2, 2)
    put(r, c, 6, 6, "H")


def bassin_est(r, c):
    fill(r, c, "~")
    put(r, c, 0, 5, ".", 12, 3)
    put(r, c, 6, 5, ".", 3, 7)           # descente vers la place
    put(r, c, 9, 1, "B", 6, 2)
    put(r, c, 2, 9, "B", 3, 2)
    put(r, c, 11, 6, "t", 1, 1)


def rampe(r, c):
    put(r, c, 12, 0, "~", 6, 7)          # l'eau en haut à droite
    put(r, c, 13, 2, "E", 3, 3)          # la barque au pied de la rampe
    put(r, c, 12, 1, ".", 1, 5)
    put(r, c, 16, 2, "~", 2, 3)
    put(r, c, 2, 2, "B", 4, 2)
    put(r, c, 2, 7, "B", 4, 2)           # barques sur remorque
    put(r, c, 8, 4, "c", 2, 2)
    put(r, c, 9, 9, "t", 4, 1)
    put(r, c, 1, 10, "H")


def criee(r, c):
    for y in (2, 6):
        put(r, c, 2, y, "t", 5, 1)
        put(r, c, 10, y, "t", 5, 1)      # étals (bas)
    put(r, c, 0, 0, "#", 4, 1)
    put(r, c, 14, 9, "#", 4, 3)          # chambre froide
    put(r, c, 7, 9, "c", 2, 2)
    put(r, c, 2, 9, "c", 2, 1)
    put(r, c, 16, 2, "H")
    put(r, c, 5, 10, "H")


def crampottes(r, c):
    for x in (1, 7, 13):
        put(r, c, x, 1, "#", 4, 3)
        put(r, c, x, 7, "#", 4, 3)       # petites maisons de pêcheurs
    put(r, c, 5, 5, "c")
    put(r, c, 11, 5, "H")
    put(r, c, 0, 11, "H")


def quai_chalutiers(r, c):
    put(r, c, 1, 1, "B", 8, 3)
    put(r, c, 10, 7, "B", 7, 3)          # chalutiers à quai
    put(r, c, 12, 1, "c", 2, 2)
    put(r, c, 3, 8, "c", 2, 2)
    put(r, c, 6, 6, "t", 2, 1)
    put(r, c, 16, 2, "H")


def place(r, c):
    put(r, c, 8, 3, "#", 2, 2)           # fontaine
    put(r, c, 3, 2, "t", 2, 1)
    put(r, c, 13, 2, "t", 2, 1)          # bancs
    put(r, c, 3, 9, "c", 1, 2)
    put(r, c, 14, 9, "c", 1, 2)
    put(r, c, 8, 7, "S", 2, 1)


def quai_barques(r, c):
    for x in (1, 6, 11):
        put(r, c, x, 2, "B", 4, 2)
    put(r, c, 3, 7, "t", 3, 1)
    put(r, c, 10, 7, "t", 3, 1)          # filets étendus
    put(r, c, 15, 9, "c", 2, 2)
    put(r, c, 1, 10, "H")


def hangar(r, c):
    for x in (2, 6, 10, 14):
        put(r, c, x, 2, "#", 2, 7)       # rayonnages
    put(r, c, 4, 10, "c", 2, 1)
    put(r, c, 9, 0, "H")
    put(r, c, 17, 10, "H")


def parking(r, c):
    for y in (1, 5, 9):
        for x in (1, 5, 9, 13):
            if (x, y) != (5, 5):
                put(r, c, x, y, "c", 3, 2)   # voitures
    put(r, c, 16, 5, "H")


def cale_seche(r, c):
    put(r, c, 2, 2, "B", 6, 3)
    put(r, c, 10, 6, "B", 6, 3)          # coques sur cales
    put(r, c, 11, 1, "t", 4, 1)
    put(r, c, 2, 8, "t", 3, 1)
    put(r, c, 15, 10, "c", 2, 2)
    put(r, c, 0, 0, "H")


def rue(r, c):
    put(r, c, 0, 0, "#", 7, 4)
    put(r, c, 11, 0, "#", 7, 4)
    put(r, c, 0, 8, "#", 6, 4)
    put(r, c, 12, 8, "#", 6, 4)          # maisons de la rue
    put(r, c, 8, 5, "c", 2, 1)
    put(r, c, 7, 0, "H")
    put(r, c, 11, 11, "H")


def terrasse(r, c):
    for y in (2, 5, 8):
        for x in (2, 6, 10):
            put(r, c, x, y, "t", 2, 1)   # tables
    put(r, c, 14, 1, "#", 3, 6)          # bar
    put(r, c, 14, 9, "c", 2, 2)
    put(r, c, 17, 0, "H")


def atelier(r, c):
    put(r, c, 2, 2, "t", 5, 1)
    put(r, c, 2, 6, "t", 5, 1)           # établis
    put(r, c, 10, 1, "c", 3, 3)
    put(r, c, 10, 7, "c", 2, 3)
    put(r, c, 15, 4, "#", 2, 5)
    put(r, c, 0, 11, "H")
    put(r, c, 14, 0, "H")


FURNISH = [
    [jetee, bassin_ouest, bassin_est, rampe, criee],
    [crampottes, quai_chalutiers, place, quai_barques, hangar],
    [parking, cale_seche, rue, terrasse, atelier],
]


def build():
    for r in range(ROWS):
        for c in range(COLS):
            fill(r, c, ".")
            FURNISH[r][c](r, c)
    # Passages : on perce le mur et on dégage 2 cases de chaque côté (sauf l'eau).
    for (r, c), doors in DOORS_RIGHT.items():
        ox, oy = origin(r, c)
        wx = ox + RW
        for (pos, width) in doors:
            for y in range(oy + pos, oy + pos + width):
                for x in range(wx - 2, wx + 3):
                    if grid[y][x] != "~" or x == wx:
                        grid[y][x] = "."
    for (r, c), doors in DOORS_DOWN.items():
        ox, oy = origin(r, c)
        wy = oy + RH
        for (pos, width) in doors:
            for x in range(ox + pos, ox + pos + width):
                for y in range(wy - 2, wy + 3):
                    if grid[y][x] != "~" or y == wy:
                        grid[y][x] = "."


def check():
    walk = set(".ESH")
    start = next((x, y) for y in range(H) for x in range(W) if grid[y][x] == "S")
    seen, q = {start}, deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and grid[n[1]][n[0]] in ".ES":
                seen.add(n)
                q.append(n)
    bad = [(x, y) for y in range(H) for x in range(W) if grid[y][x] in ".E" and (x, y) not in seen]
    hides = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == "H"]
    lone = [h for h in hides if not any((h[0] + dx, h[1] + dy) in seen
                                         for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    print(f"carte {W}×{H}, sol atteignable {len(seen)} cases, isolées {len(bad)}, "
          f"cachettes {len(hides)} (inaccessibles {len(lone)}), sorties "
          f"{sum(row.count('E') for row in grid)} cases")
    if bad:
        print("  cases isolées :", bad[:12])
    if lone:
        print("  cachettes inaccessibles :", lone)
    return not bad and not lone


def main():
    build()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(row) for row in grid) + "\n")
    zones = []
    for r in range(ROWS):
        for c in range(COLS):
            ox, oy = origin(r, c)
            zones.append({"name": NAMES[r][c], "rect": [ox, oy, RW, RH]})
    with open(os.path.join(OUT, "zones.json"), "w") as fh:
        json.dump({"name": "Port des Pêcheurs", "zones": zones}, fh, ensure_ascii=False, indent=1)
    ok = check()
    print(os.path.join(OUT, "map.txt"))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
