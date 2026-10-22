#!/usr/bin/env python3
"""Port des Pêcheurs v2 (GDD-BLACKOUT.md, revue de level design du 2026-10-19).

Même taille que v1 (96 × 40, taille de The Skeld), mais façon Among Us : salles de formes et de
tailles variées reliées par des couloirs, une boucle (objet dont on fait le tour) et un repère
basque par zone, une cachette par zone, 5 sorties possibles dont 2 tirées au sort par round.

Écrit assets/maps/port_v2/map.txt et zones.json (zones nommées + sorties possibles ; la carte par défaut,
port_pecheurs, est la v3 depuis le 2026-10-21 : tools/blackout/make_port_v3.py),
vérifie que tout est atteignable et affiche quelques mesures (liaisons, distances aux sorties).

Légende : . sol   # mur/bâtiment   c caisse   B bateau   (pleins, cachent la vue)
          t objet bas (bloque le passage, pas la vue)   ~ eau (idem)
          H cachette   E sortie possible   S départ
Usage : make_port_v2.py [--sans-tension] [--id port_v2]

Tension (2026-10-20, archive/2026-10-22-docs-gordeka/GORDEKA_EQUILIBRAGE.md) : caisses qui coupent les longues lignes de vue
(place, criée, jetée, escalier, atelier), coffres au milieu du quai nord, cachettes déplacées des
recoins vers les passages, avec plusieurs côtés libres pour en ressortir. `--sans-tension` redonne
la carte d'avant (A/B). Le décor suit tout seul : BkDecor pose l'image de chaque objet d'après son
caractère, sa zone et sa taille (caisses 2 × 2, cachettes 1 × 1, comme les images existantes).
"""
import json
import os
import sys
from collections import deque

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# Depuis la carte v3 (2026-10-21, make_port_v3.py écrit port_pecheurs), la v2 s'écrit à part, pour l'A/B :
# assets/maps/port_v2 (`--id <carte>` pour un autre dossier ; « decor » : port_pecheurs, même décor).
_ID = sys.argv[sys.argv.index("--id") + 1] if "--id" in sys.argv else "port_v2"
OUT = os.path.join(ROOT, "assets", "maps", _ID)
W, H = 96, 40
g = [["#"] * W for _ in range(H)]
TENSION = "--sans-tension" not in sys.argv


def put(x, y, w, h, ch):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 < xx < W - 1 and 0 < yy < H - 1:
                g[yy][xx] = ch


def ring(x, y, w, h, ch):
    """Contour d'un rectangle (objet dont on fait le tour : fontaine, bassin)."""
    put(x, y, w, 1, ch)
    put(x, y + h - 1, w, 1, ch)
    put(x, y, 1, h, ch)
    put(x + w - 1, y, 1, h, ch)


# Zones nommées : (nom, x, y, w, h) — rectangles intérieurs, utilisés par l'IA (patrouille) et
# les messages. Les couloirs n'appartiennent à aucune zone.
ZONES = [
    ("Jetée", 1, 1, 22, 11),
    ("Bassin", 24, 1, 34, 11),
    ("Criée", 62, 1, 18, 11),
    ("Phare", 82, 1, 13, 9),
    ("Crampottes", 1, 14, 16, 12),
    ("Quai des chalutiers", 19, 14, 13, 11),
    ("Place du fronton", 34, 14, 22, 11),
    ("Hangar à filets", 58, 14, 18, 10),
    ("Chapelle des marins", 80, 12, 15, 10),
    ("Cale sèche", 1, 28, 19, 11),
    ("Terrasse", 22, 34, 17, 5),
    ("Lavoir", 41, 34, 15, 5),
    ("Atelier", 59, 27, 17, 12),
    ("Escalier de la ville", 79, 25, 16, 14),
]


def build():
    # ------------------------------------------------ bande du haut : la mer, la jetée, le quai nord
    put(1, 1, 57, 8, "~")                       # la mer et le bassin
    put(2, 3, 24, 2, ".")                       # la jetée, longue et exposée
    put(1, 2, 4, 4, ".")                        # le musoir au bout
    put(1, 2, 2, 3, "E")                        # sortie : la barque au bout de la jetée
    put(1, 7, 22, 5, ".")                       # terre-plein de la jetée
    put(5, 8, 2, 2, "c")
    put(13, 9, 3, 1, "t")
    put(20, 7, 1, 1, "t")                       # bitte d'amarrage
    put(9, 10, 1, 1, "H")                       # casier à homards
    put(24, 9, 36, 3, ".")                      # quai nord (couloir le long du bassin)
    put(23, 3, 4, 6, ".")                       # racine de la jetée → quai
    put(31, 2, 6, 2, "B")
    put(42, 4, 7, 2, "B")                       # barques au mouillage
    put(51, 2, 4, 2, "B")
    put(38, 10, 1, 1, "t")
    put(50, 10, 1, 1, "t")                      # bittes d'amarrage
    put(44, 9, 1, 1, "H")                       # coffre de quai
    # Criée : grande halle, deux rangées d'étals dont on fait le tour, chambre froide.
    put(62, 1, 18, 11, ".")
    put(60, 9, 2, 3, ".")                       # porte depuis le quai
    for y in (3, 7):
        put(64, y, 5, 1, "t")
        put(71, y, 5, 1, "t")                   # étals
    put(76, 1, 4, 4, "#")                       # chambre froide
    put(75, 2, 1, 1, "H")                       # caisse à glace devant
    put(63, 10, 2, 1, "c")
    # Phare (feu du port) : repère tout en haut à droite, sortie derrière.
    put(82, 1, 13, 9, ".")
    put(80, 5, 2, 2, ".")                       # passage depuis la criée
    ring(86, 3, 5, 5, "#")                      # la tour (on en fait le tour)
    put(87, 4, 3, 3, "#")
    put(93, 1, 2, 3, "E")                       # sortie : l'échelle derrière le phare
    put(83, 8, 2, 1, "c")
    put(92, 8, 1, 1, "H")
    # ------------------------------------------------ bande du milieu
    # Crampottes : petites maisons serrées, ruelles en baïonnette.
    put(1, 14, 16, 12, ".")
    for (x, y, w, h) in ((2, 15, 4, 3), (8, 14, 4, 3), (13, 16, 3, 3), (2, 20, 3, 4), (7, 19, 4, 3),
                         (12, 21, 4, 3), (6, 24, 4, 2)):
        put(x, y, w, h, "#")
    put(11, 18, 1, 1, "H")                      # poubelle de ruelle
    put(6, 12, 3, 2, ".")                       # ruelle vers la jetée
    put(17, 17, 2, 3, ".")                      # ruelle vers le quai des chalutiers
    # Quai des chalutiers : un gros chalutier à quai dont on fait le tour.
    put(19, 14, 13, 11, ".")
    put(22, 17, 7, 4, "B")
    put(26, 12, 3, 2, ".")                      # couloir vers le quai nord
    put(20, 23, 2, 1, "c")
    put(30, 15, 1, 2, "c")
    put(19, 21, 1, 1, "H")
    put(32, 20, 2, 3, ".")                      # passage vers la place
    # Place du fronton : le fronton (mur) au nord, fontaine au centre, bancs.
    put(34, 14, 22, 11, ".")
    put(36, 14, 10, 1, "#")                     # le fronton
    put(43, 18, 4, 4, "t")                      # la fontaine (bas : on voit par-dessus)
    put(37, 22, 3, 1, "t")
    put(50, 16, 3, 1, "t")                      # bancs
    put(52, 21, 2, 2, "c")
    put(44, 16, 2, 1, "S")
    put(48, 12, 3, 2, ".")                      # couloir vers le quai nord
    put(35, 24, 1, 1, "H")
    put(56, 16, 2, 3, ".")                      # couloir vers le hangar
    # Hangar à filets : rayonnages décalés (pas de grille), filets étendus.
    put(58, 14, 18, 10, ".")
    for (x, y, w, h) in ((60, 15, 2, 4), (64, 17, 2, 5), (68, 14, 2, 4), (68, 20, 2, 3), (72, 16, 2, 5)):
        put(x, y, w, h, "#")
    put(61, 21, 2, 1, "t")
    put(74, 22, 1, 1, "H")
    put(70, 12, 3, 2, ".")                      # couloir vers la criée
    put(76, 18, 4, 2, ".")                      # couloir vers la chapelle
    # Chapelle des marins : nef avec bancs, autel au fond (repère).
    put(80, 12, 15, 10, ".")
    put(82, 10, 2, 2, ".")                      # couloir vers le phare
    for y in (14, 16, 18):
        put(83, y, 4, 1, "t")
        put(89, y, 4, 1, "t")                   # bancs
    put(87, 20, 2, 2, "#")                      # l'autel
    put(93, 13, 1, 1, "H")                      # confessionnal
    # ------------------------------------------------ bande du bas
    # Rue des pêcheurs : couloir sinueux qui relie tout le bas.
    put(20, 30, 14, 2, ".")
    put(33, 28, 2, 4, ".")
    put(33, 27, 26, 2, ".")
    put(45, 25, 3, 2, ".")                      # descente depuis la place
    put(57, 27, 2, 4, ".")
    put(40, 29, 2, 5, ".")                      # vers le lavoir
    put(28, 32, 2, 2, ".")                      # vers la terrasse
    # Cale sèche : coques sur cales, sortie par la barque à l'eau.
    put(1, 28, 19, 11, ".")
    put(3, 30, 6, 3, "B")
    put(11, 33, 6, 3, "B")
    put(1, 34, 3, 3, "~")
    put(1, 37, 2, 2, "E")                       # sortie : la barque de la cale
    put(14, 29, 3, 1, "t")
    put(7, 26, 3, 2, ".")                       # couloir vers les crampottes
    put(18, 37, 1, 1, "H")
    # Terrasse du bar : tables dont on fait le tour, comptoir.
    put(22, 34, 17, 5, ".")
    for x in (24, 28, 32):
        put(x, 36, 2, 1, "t")
    put(36, 34, 3, 2, "#")                      # le comptoir
    put(23, 38, 1, 1, "H")
    # Lavoir : bassin couvert dont on fait le tour (repère).
    put(41, 34, 15, 5, ".")
    ring(45, 35, 6, 3, "~")
    put(46, 36, 4, 1, "~")
    put(54, 37, 1, 1, "H")
    # Atelier : établis et coque en chantier.
    put(59, 27, 17, 12, ".")
    put(61, 29, 5, 1, "t")
    put(61, 33, 5, 1, "t")                      # établis
    put(68, 30, 5, 4, "B")                      # coque en chantier (on en fait le tour)
    put(73, 36, 2, 2, "c")
    put(60, 37, 1, 1, "H")
    put(66, 24, 3, 3, ".")                      # couloir vers le hangar
    put(76, 32, 3, 2, ".")                      # couloir vers l'escalier
    # Escalier de la ville : grands escaliers vers la ville, sortie en haut à droite.
    put(79, 25, 16, 14, ".")
    put(86, 22, 3, 3, ".")                      # couloir vers la chapelle
    for y in (28, 31, 34):
        put(81, y, 6, 1, "t")                   # marches (bas)
    put(89, 27, 2, 8, "#")                      # mur de soutènement
    put(92, 36, 2, 2, "E")                      # sortie : la porte de la ville
    put(83, 37, 2, 1, "c")
    put(93, 26, 1, 1, "H")


def tension():
    """Lignes de vue plus courtes et cachettes près des passages (voir l'en-tête)."""
    put(38, 18, 2, 2, "c")                      # place : caisses de part et d'autre de la fontaine
    put(49, 20, 2, 2, "c")
    put(35, 24, 1, 1, ".")
    put(55, 19, 1, 1, "H")                      # malle à pelotes : contre le couloir du hangar
    put(69, 4, 2, 2, "c")                       # criée : caisses entre les étals
    put(35, 10, 1, 1, "H")
    put(53, 10, 1, 1, "H")                      # quai nord : deux coffres de plus au milieu du quai
    put(16, 10, 2, 2, "c")                      # jetée : caisses sur le terre-plein
    put(92, 30, 2, 2, "c")                      # escalier : caisses derrière le mur de soutènement
    put(93, 26, 1, 1, ".")
    put(85, 25, 1, 1, "H")                      # cabine : au pied du couloir de la chapelle
    put(60, 37, 1, 1, ".")
    put(74, 31, 1, 1, "H")                      # atelier : caisse à voiles au bord de la coque
    put(63, 36, 2, 2, "c")
    put(93, 13, 1, 1, ".")
    put(81, 13, 1, 1, "H")                      # confessionnal : à l'entrée de la chapelle
    put(74, 22, 1, 1, ".")
    put(75, 20, 1, 1, "H")                      # tas de filets : près du couloir de la chapelle


def walkable(ch):
    return ch in ".ESH"


def bfs(start):
    d = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in d and g[n[1]][n[0]] in ".ES":
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


def zone_of(x, y):
    for i, (_, zx, zy, zw, zh) in enumerate(ZONES):
        if zx <= x < zx + zw and zy <= y < zy + zh:
            return i
    return -1


def check():
    start = next((x, y) for y in range(H) for x in range(W) if g[y][x] == "S")
    d = bfs(start)
    bad = [(x, y) for y in range(H) for x in range(W) if g[y][x] in ".E" and (x, y) not in d]
    hides = [(x, y) for y in range(H) for x in range(W) if g[y][x] == "H"]
    lone = [h for h in hides if not any((h[0] + dx, h[1] + dy) in d for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    print(f"carte {W}×{H}, sol atteignable {len(d)} cases, isolées {len(bad)}, cachettes {len(hides)} "
          f"(inaccessibles {len(lone)})")
    if bad:
        print("  cases isolées :", bad[:12])
    if lone:
        print("  cachettes inaccessibles :", lone)
    # Cachettes par zone, liaisons entre zones, distances.
    per = {}
    for h in hides:
        per[zone_of(*h)] = per.get(zone_of(*h), 0) + 1
    print("  zones sans cachette :", [ZONES[i][0] for i in range(len(ZONES)) if i not in per])
    for grp in exit_groups():
        z = ZONES[zone_of(*grp[0])][0]
        print(f"  sortie possible « {z} » : {min(d.get(t, 9999) for t in grp)} cases du départ")
    return not bad and not lone


def main():
    build()
    if TENSION:
        tension()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(row) for row in g) + "\n")
    zones = [{"name": n, "rect": [x, y, w, h]} for (n, x, y, w, h) in ZONES]
    exits = [{"zone": ZONES[zone_of(*grp[0])][0], "tiles": [list(t) for t in grp]} for grp in exit_groups()]
    with open(os.path.join(OUT, "zones.json"), "w") as fh:
        json.dump({"name": "Port des Pêcheurs", "version": 2, "decor": "port_pecheurs", "zones": zones, "exits": exits}, fh,
                  ensure_ascii=False, indent=1)
    ok = check()
    print(os.path.join(OUT, "map.txt"))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
