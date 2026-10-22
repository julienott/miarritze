#!/usr/bin/env python3
"""Port des Pêcheurs v3 (GDD-BLACKOUT.md, revue de carte du 2026-10-20, demande de Julien : « une meilleure
map », zones moins vides, mieux segmentées par des couloirs, déco plus riche, le tout bien balancé).

Part de la carte v2 (make_port_v2.py, avec sa passe « tension ») et applique des passes au choix :

  ruelles     couloirs en baïonnette : la rue des pêcheurs et le quai nord ne sont plus des lignes droites
              (avancées de maisons, niches, chicanes), petits passages en plus (raccourcis) ;
  salles      grandes salles coupées : crampottes sur le terre-plein de la jetée, platanes sur la place,
              cloison de la criée, piles de l'atelier, de la cale et de l'escalier ;
  densite     objets le long des murs (barriques qui cachent, pots, casiers, bittes qui ne cachent pas),
              jamais devant une porte, en laissant toujours 2 cases de passage ;
  cachettes   cachettes en plus dans les couloirs (niches de la rue) et dans les grandes salles ;
  liaisons    boucle du sud : terrasse, lavoir et atelier reliés entre eux ;
  sorties     abords des sorties dégagés, pas de cachette tout près ;
  entrees     une barrique décalée juste derrière chaque porte : la ligne de vue est coupée à l'entrée ;
  ornements   décor sans effet de jeu (decor.json) : lanternes, bouées, filets, fanions, linge, fumée…

  make_port_v3.py [--passes ruelles,salles,cachettes,sorties,entrees,densite,ornements] [--id port_pecheurs]
                  [--graine 7] [--pas 5] [--hauts 0.45] [--regles exits_open_at:110,gateaux_nombre:6]

Sans option : la carte retenue (essai v3d du 2026-10-21), écrite dans assets/maps/port_pecheurs, carte par
défaut du jeu. La v2 d'avant reste générée à part par make_port_v2.py (assets/maps/port_v2) pour l'A/B.

Écrit assets/maps/<id>/map.txt, zones.json (« decor » : port_pecheurs, le décor en images est partagé)
et decor.json (objets imposés et ornements, lus par src/blackout/bk_decor.gd). Vérifie que tout est
atteignable, sans passage d'une seule case créé par les passes. Mesures : tools/blackout/analyse_carte.py,
parties : tools/blackout/ab_tension.py run <variante> --map <id>. Journal des essais :
archive/2026-10-22-docs-gordeka/GORDEKA_EQUILIBRAGE.md (revue de carte).
"""
import argparse
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.argv_v2 = sys.argv
import make_port_v2 as v2  # noqa: E402   (grille v2.g, put, ZONES, bfs, exit_groups, zone_of)

ROOT = v2.ROOT
W, H = v2.W, v2.H
g = v2.g
put = v2.put
ZONES = [list(z) for z in v2.ZONES]
OBJ = "cBHtv~E"          # objets (et sorties) qu'on ne colle pas
DECOR = {"objets": {}, "ornements": []}


def at(x, y):
    return g[y][x] if 0 <= x < W and 0 <= y < H else "#"


def zone_of(x, y):
    for i, (_, zx, zy, zw, zh) in enumerate(ZONES):
        if zx <= x < zx + zw and zy <= y < zy + zh:
            return i
    return -1


def zname(x, y):
    i = zone_of(x, y)
    return ZONES[i][0] if i >= 0 else ""


# ------------------------------------------------------------------ passes de forme

def ruelles():
    """Couloirs en baïonnette : avancées et niches, raccourcis."""
    # Rue des pêcheurs (y 27-28, x 33-58) : on l'élargit d'une rangée au sud (y 29) puis on y pose des
    # avancées de maisons alternées : la rue serpente sur 2 cases et laisse des niches.
    put(35, 29, 5, 1, ".")
    put(42, 29, 15, 1, ".")
    for (x, y, w, h) in ((37, 27, 3, 1), (44, 29, 3, 1), (50, 27, 2, 1), (53, 29, 2, 1)):
        put(x, y, w, h, "#")
    # Avancée au milieu du tronçon ouest (x 20-33, y 30-31) : passage en S par la rangée 29.
    put(21, 29, 11, 1, ".")
    put(24, 31, 3, 1, "#")
    put(29, 29, 2, 1, "#")
    # Quai nord (y 9-11) : abri de pêcheurs (« txoko ») et piles qui coupent la ligne droite.
    put(40, 11, 2, 1, "c")                      # pile de caisses contre le mur sud, la ligne y 11 est coupée
    put(30, 9, 1, 1, "t")                       # bitte d'amarrage côté eau
    put(57, 11, 2, 1, "c")
    # Raccourci crampottes → cale (ruelle étroite de 2 entre les maisons).
    put(13, 26, 2, 2, ".")
    # (Essai 1 : raccourci chapelle → escalier par l'est, en x 92-93 : il menait tout droit à la sortie de
    # la porte de la ville, les chassés s'échappaient bien plus ; retiré.)


def salles():
    """Grandes salles coupées en sous-espaces, lignes de vue plus courtes."""
    # Jetée : une crampotte sur le terre-plein, la ligne y 7-9 est cassée ; passage par y 10-11.
    put(9, 7, 4, 3, "#")
    # Place du fronton : quatre platanes (ils cachent), en quinconce autour de la fontaine.
    for (x, y) in ((40, 16), (48, 17), (41, 22), (53, 18)):
        put(x, y, 1, 1, "v")
    # Criée : cloison (mur du bureau de la criée) entre les deux halles, deux portes.
    put(69, 9, 1, 1, "c")
    # Cale sèche : pile de bois entre les deux coques.
    put(9, 30, 2, 2, "c")


def cachettes():
    """Cachettes en plus, dans les niches des couloirs et les grandes salles (une seule personne
    chacune, toujours au moins deux côtés libres pour en ressortir)."""
    # Niches creusées dans le mur de la rue (on y entre depuis la rue, comme une bouche d'aération).
    for (x, y) in ((41, 26), (48, 26), (22, 32)):
        if at(x, y) == "#":
            put(x, y, 1, 1, "H")
            # Niche de deux cases : la cachette garde deux côtés libres (on en ressort par le côté).
            ouv = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if at(x + dx, y + dy) in ".ES"]
            if len(ouv) == 1:
                dx, dy = ouv[0]
                for lx, ly in ((x + dy, y + dx), (x - dy, y - dx)):
                    if at(lx, ly) == "#" and at(lx + dx, ly + dy) in ".ES":
                        put(lx, ly, 1, 1, ".")
                        break
    for (x, y) in ((47, 11), (66, 2), (63, 21), (16, 36)):
        if at(x, y) == ".":
            put(x, y, 1, 1, "H")


def sorties():
    """Sorties visibles et exposées (jeux d'extraction) : rien qui cache à leurs abords, pas de cachette
    à moins de 8 cases (on n'attend pas l'ouverture caché à côté)."""
    put(92, 30, 2, 2, ".")                      # escalier : les caisses derrière le mur cachaient l'approche
    put(92, 8, 1, 1, ".")                       # phare : le coffre à cordages était à 5 cases de l'échelle
    put(84, 1, 1, 1, "H")                       # … il passe à l'entrée du phare, côté criée


def liaisons():
    """Boucle du sud (Among Us : pas de salle à une seule entrée, une grande boucle et des raccourcis) :
    terrasse ↔ lavoir ↔ atelier se touchent, les salles du bas deviennent des passages."""
    put(39, 36, 2, 2, ".")                      # terrasse → lavoir, par le fond du bar
    put(56, 35, 3, 2, ".")                      # lavoir → atelier


# ------------------------------------------------------------------ densité le long des murs

def portes():
    """Cases de sol au contact d'une autre zone ou d'un couloir (entrées des salles)."""
    out = set()
    for y in range(H):
        for x in range(W):
            if at(x, y) not in ".ES":
                continue
            z = zone_of(x, y)
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if at(nx, ny) in ".ES" and zone_of(nx, ny) != z:
                    out.add((x, y))
    return out


def pres_sortie(x, y, r=7):
    """Près d'une sortie : on n'y pose rien (les sorties restent exposées, Among Us / jeux d'extraction)."""
    return any(at(a, b) == "E" for a in range(x - r, x + r + 1) for b in range(y - r, y + r + 1))


def densite(graine, pas, hauts):
    """Objets le long des murs : barriques (hautes) et objets bas, pas plus d'un tous les `pas`
    cases, à 3 cases au moins des portes et des autres objets, en gardant 2 cases de passage."""
    rng = random.Random(graine)
    doors = portes()
    cells = [(x, y) for y in range(1, H - 1) for x in range(1, W - 1) if at(x, y) == "."]
    rng.shuffle(cells)
    placed = []
    for (x, y) in cells:
        walls = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if at(x + dx, y + dy) == "#"]
        if len(walls) != 1:
            continue
        dx, dy = walls[0]
        nx, ny = -dx, -dy
        # Deux cases libres devant (passage de 2 au moins) et sur les côtés.
        if at(x + nx, y + ny) != "." or at(x + 2 * nx, y + 2 * ny) not in ".ES":
            continue
        side = [(x + dy, y + dx), (x - dy, y - dx)]
        if any(at(sx, sy) != "." for sx, sy in side):
            continue
        if any(abs(x - a) <= 2 and abs(y - b) <= 2 for a, b in doors) or pres_sortie(x, y):
            continue
        near = False
        for yy in range(y - 2, y + 3):
            for xx in range(x - 2, x + 3):
                if at(xx, yy) in OBJ:
                    near = True
        if near or any(abs(x - a) < pas and abs(y - b) < pas for a, b in placed):
            continue
        z = zname(x, y)
        if z in ("Lavoir",) and rng.random() < 0.5:
            continue
        ch = "c" if rng.random() < hauts else "t"
        avant = atteint()
        local = {c for c in etroits() if abs(c[0] - x) <= 2 and abs(c[1] - y) <= 2}
        g[y][x] = ch
        apres = {c for c in etroits() if abs(c[0] - x) <= 2 and abs(c[1] - y) <= 2}
        if atteint() < avant - 1 or apres - local:
            g[y][x] = "."
            continue
        placed.append((x, y))
        if rng.random() < 0.5:
            DECOR["objets"][f"{x},{y}"] = {"miroir": True}
    return placed


def entrees(graine):
    """Lignes de vue coupées aux entrées des salles (Among Us) : juste derrière chaque porte, une barrique
    décalée d'un côté, à 2 cases du seuil ; on entre en la contournant et le chasseur qui arrive ne voit
    pas toute la salle d'un coup."""
    rng = random.Random(graine + 2)
    doors = sorted(portes())
    faits = []
    for (x, y) in doors:
        z = zone_of(x, y)
        if z < 0:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if zone_of(x - dx, y - dy) == z or at(x - dx, y - dy) not in ".ES":
                continue
            # (dx, dy) : direction vers l'intérieur de la salle.
            for side in ((dy, dx), (-dy, -dx)) if rng.random() < 0.5 else ((-dy, -dx), (dy, dx)):
                px, py = x + 2 * dx + side[0], y + 2 * dy + side[1]
                if any(abs(px - a) <= 3 and abs(py - b) <= 3 for a, b in faits):
                    break
                ok = at(px, py) == "." and zone_of(px, py) == z and not pres_sortie(px, py) and all(
                    at(px + i, py + j) not in OBJ for i in (-1, 0, 1) for j in (-1, 0, 1))
                if not ok:
                    continue
                avant = atteint()
                local = {c for c in etroits() if abs(c[0] - px) <= 2 and abs(c[1] - py) <= 2}
                g[py][px] = "c"
                apres = {c for c in etroits() if abs(c[0] - px) <= 2 and abs(c[1] - py) <= 2}
                if atteint() < avant - 1 or apres - local:
                    g[py][px] = "."
                    continue
                faits.append((px, py))
                break
    return faits


def formes_caisses():
    """Les groupes de caisses doivent avoir une forme d'image existante (1×1 barriques, 2×1, 1×2, 2×2)."""
    seen, bad = set(), []
    for y in range(H):
        for x in range(W):
            if at(x, y) != "c" or (x, y) in seen:
                continue
            comp, q = [], [(x, y)]
            seen.add((x, y))
            while q:
                a, b = q.pop()
                comp.append((a, b))
                for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                    if n not in seen and at(*n) == "c" and zone_of(*n) == zone_of(x, y):
                        seen.add(n)
                        q.append(n)
            w = max(c[0] for c in comp) - min(c[0] for c in comp) + 1
            h = max(c[1] for c in comp) - min(c[1] for c in comp) + 1
            if (w, h) not in ((1, 1), (2, 1), (1, 2), (2, 2)) or len(comp) != w * h:
                bad.append((min(c[0] for c in comp), min(c[1] for c in comp), w, h))
    return bad


def atteint():
    start = next((x, y) for y in range(H) for x in range(W) if at(x, y) == "S")
    return len(v2.bfs(start))


# ------------------------------------------------------------------ ornements (decor.json)

def variantes():
    """Crampottes variées : une sur deux aux volets verts, une sur trois en miroir (decor.json)."""
    seen = set()
    k = 0
    for y in range(H):
        for x in range(W):
            if at(x, y) != "#" or (x, y) in seen or zname(x, y) not in ("Crampottes", "Jetée"):
                continue
            comp, q = [], [(x, y)]
            seen.add((x, y))
            while q:
                a, b = q.pop()
                comp.append((a, b))
                for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                    if n not in seen and at(*n) == "#" and zone_of(*n) == zone_of(x, y):
                        seen.add(n)
                        q.append(n)
            x0, y0 = min(c[0] for c in comp), min(c[1] for c in comp)
            ent = {"miroir": k % 3 == 1}
            if k % 2 == 1:
                ent["id"] = "maison_crampotte_verte"
            DECOR["objets"][f"{x0},{y0}"] = ent
            k += 1


def ornements(graine):
    variantes()
    rng = random.Random(graine + 1)
    orn = DECOR["ornements"]
    facades = [(x, y) for y in range(1, H - 1) for x in range(W) if at(x, y) == "#" and at(x, y + 1) in ".ESHtc"
               and zone_of(x, y) < 0]
    rng.shuffle(facades)
    used = []

    def libre(x, y, r):
        return not any(abs(x - a) < r and abs(y - b) < r for a, b in used)

    for (x, y) in facades:
        z = zname(x, y + 1)
        if not libre(x, y, 4):
            continue
        r = rng.random()
        if z in ("Jetée", "Bassin", "Quai des chalutiers", "Cale sèche"):
            kind = "bouee_murale" if r < 0.35 else ("filet_suspendu" if r < 0.6 else "lanterne_murale")
        elif z in ("Hangar à filets", "Atelier", "Criée"):
            kind = "filet_suspendu" if r < 0.45 else "lanterne_murale"
        elif z == "":
            kind = "lanterne_murale" if r < 0.7 else "filet_suspendu"
        else:
            kind = "lanterne_murale" if r < 0.8 else "bouee_murale"
        orn.append({"id": kind, "x": x + 0.5, "y": y + 1.0, "miroir": rng.random() < 0.5})
        used.append((x, y))
    # Réverbères au pied des façades du quai nord, de la place et de l'escalier.
    for (x, y) in ((28, 12), (36, 12), (54, 12), (35, 25), (52, 25), (80, 39), (90, 25)):
        if at(x, y) == "#" and at(x, y - 1) in ".":
            orn.append({"id": "lampadaire_port", "x": x + 0.5, "y": float(y)})
    # Fumée sur les toits (loin du bord de la carte), mouettes posées sur les faîtes.
    roofs = [(x, y) for y in range(2, H - 2) for x in range(2, W - 2) if at(x, y) == "#" and zone_of(x, y) < 0
             and all(at(x + dx, y + dy) == "#" for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
    rng.shuffle(roofs)
    smoke = []
    for (x, y) in roofs:
        if len(smoke) >= 9:
            break
        if all(abs(x - a) > 8 or abs(y - b) > 5 for a, b in smoke):
            smoke.append((x, y))
            orn.append({"id": "fumee_cheminee", "x": x + 0.5, "y": y + 0.8})
    gulls = 0
    for (x, y) in roofs[::-1]:
        if gulls >= 7:
            break
        if all(abs(x - a) > 3 or abs(y - b) > 3 for a, b in smoke):
            orn.append({"id": "mouette_posee", "x": x + 0.5, "y": y + 0.7, "miroir": gulls % 2 == 1})
            gulls += 1
    # Fanions au-dessus des rues et de la place (tendus d'un mur à l'autre), linge près du lavoir et
    # dans les crampottes, drapeaux au bout de la jetée et au phare, chat, ancre, cordages.
    for (x0, x1, y) in ((46, 56, 14.6), (34, 46, 27.4), (47, 57, 27.4), (20, 33, 30.4), (80, 94, 12.5),
                        (79, 95, 25.4), (24, 36, 9.3)):
        orn.append({"id": "fanions_basques", "x": (x0 + x1) / 2.0, "y": y, "l": float(x1 - x0), "h": 1.2})
    for (x, y, l) in ((43.5, 34.8, 3.0), (51.5, 38.6, 3.0), (2.5, 18.8, 2.0), (13.0, 14.8, 2.0)):
        orn.append({"id": "linge_seche", "x": x, "y": y, "l": l, "h": 1.0})
    for (x, y) in ((4.5, 2.4), (91.5, 9.6)):
        orn.append({"id": "drapeau_mat", "x": x, "y": y})
    for (x, y) in ((31.5, 37.6), (8.5, 25.4)):
        orn.append({"id": "chat_du_port", "x": x, "y": y})
    for (x, y) in ((25.5, 11.8), (60.5, 11.8), (19.5, 7.6)):
        orn.append({"id": "ancre_decor", "x": x, "y": y})
    for (x, y) in ((33.5, 9.7), (45.5, 9.7), (6.5, 7.6), (21.5, 14.8)):
        orn.append({"id": "cordage_enroule", "x": x, "y": y})
    # Petit bazar au sol, dans les coins dégagés des salles (paniers, filets étendus, cordages) : à 2 cases
    # au moins des objets et des portes, pour ne pas faire croire à une cachette.
    sols = {"panier_poissons": ("Criée", "Quai des chalutiers", "Bassin", "Jetée"),
            "filet_au_sol": ("Hangar à filets", "Jetée", "Quai des chalutiers", "Cale sèche"),
            "cordage_enroule": ("Cale sèche", "Atelier", "Quai des chalutiers")}
    doors = portes()
    pris = [(o["x"], o["y"]) for o in orn]
    for oid, zs in sols.items():
        for z in zs:
            cells = [(x, y) for y in range(H) for x in range(W) if zname(x, y) == z and at(x, y) == "."
                     and all(at(x + i, y + j) == "." for i in (-1, 0, 1) for j in (-1, 0, 1))
                     and not any(abs(x - a) <= 2 and abs(y - b) <= 2 for a, b in doors)]
            rng.shuffle(cells)
            n = 0
            for (x, y) in cells:
                if n >= 2:
                    break
                if any(abs(x + 0.5 - a) < 4 and abs(y + 1 - b) < 4 for a, b in pris):
                    continue
                orn.append({"id": oid, "x": x + 0.5 + (0.5 if oid == "filet_au_sol" else 0.0), "y": y + 0.9,
                            "miroir": rng.random() < 0.5})
                pris.append((x + 0.5, y + 1))
                n += 1


# ------------------------------------------------------------------ vérifications

def etroits():
    """Passages d'une case : sol bouché à gauche et à droite mais ouvert en haut et en bas (ou
    l'inverse), c'est-à-dire un vrai goulet, pas un recoin."""
    s = set()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if at(x, y) in ".ES":
                w = lambda a, b: at(a, b) in ".ES"   # noqa: E731
                hb = not w(x - 1, y) and not w(x + 1, y) and w(x, y - 1) and w(x, y + 1)
                vb = not w(x, y - 1) and not w(x, y + 1) and w(x - 1, y) and w(x + 1, y)
                if hb or vb:
                    s.add((x, y))
    return s


def largeur_un(avant):
    """Goulets d'une case créés par les passes (absents de `avant`)."""
    return sorted(etroits() - avant)


def main():
    ap = argparse.ArgumentParser()
    # Variante retenue (essai « v3d » du 2026-10-21, archive/2026-10-22-docs-gordeka/GORDEKA_EQUILIBRAGE.md) : carte par défaut du jeu.
    ap.add_argument("--passes", default="ruelles,salles,cachettes,sorties,entrees,densite,ornements")
    ap.add_argument("--id", default="port_pecheurs")
    ap.add_argument("--graine", type=int, default=7)
    ap.add_argument("--pas", type=int, default=5)
    ap.add_argument("--hauts", type=float, default=0.45)
    # Sorties ouvertes à 110 s (essai 5 du 2026-10-21 : plus riche, la carte avantage les chassés) et 6 gâteaux
    # au lieu de 4 (essai 7 : les chassés bougent autant qu'en v2).
    ap.add_argument("--regles", default="exits_open_at:110,gateaux_nombre:6",
                    help="réglages propres à la carte (zones.json → regles), k:v,… (« » : aucun)")
    a = ap.parse_args()
    passes = [p for p in a.passes.split(",") if p]
    v2.build()
    v2.tension()
    avant = etroits()
    if "ruelles" in passes:
        ruelles()
    if "salles" in passes:
        salles()
    if "cachettes" in passes:
        cachettes()
    if "sorties" in passes:
        sorties()
    if "liaisons" in passes:
        liaisons()
    if "entrees" in passes:
        entrees(a.graine)
    if "densite" in passes:
        densite(a.graine, a.pas, a.hauts)
    if "ornements" in passes:
        ornements(a.graine)
    out = os.path.join(ROOT, "assets", "maps", a.id)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(r) for r in g) + "\n")
    zones = [{"name": n, "rect": [x, y, w, h]} for (n, x, y, w, h) in ZONES]
    exits = [{"zone": ZONES[zone_of(*grp[0])][0], "tiles": [list(t) for t in grp]} for grp in v2.exit_groups()]
    regles = {kv.split(":")[0]: float(kv.split(":")[1]) for kv in a.regles.split(",") if ":" in kv}
    json.dump({"name": "Port des Pêcheurs", "version": 3, "decor": "port_pecheurs", "passes": passes,
               "regles": regles, "zones": zones, "exits": exits}, open(os.path.join(out, "zones.json"), "w"), ensure_ascii=False, indent=1)
    json.dump({"_doc": "Placement du décor propre à cette carte (tools/blackout/make_port_v3.py), lu par "
                       "src/blackout/bk_decor.gd : objets imposés ou en miroir, ornements sans effet de jeu.",
               **DECOR}, open(os.path.join(out, "decor.json"), "w"), ensure_ascii=False, indent=1)
    ok = v2.check()
    for y in range(H):
        for x in range(W):
            if at(x, y) == "H" and sum(at(x + dx, y + dy) in ".ES" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) < 2:
                print("  cachette avec un seul côté libre :", (x, y))
    for b in formes_caisses():
        print("  groupe de caisses sans image à sa forme :", b)
    un = largeur_un(avant)
    if un:
        print("  passages d'une case créés :", un)
    print(f"  {a.id} : passes {passes}, ornements {len(DECOR['ornements'])}, objets en miroir {len(DECOR['objets'])}")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
