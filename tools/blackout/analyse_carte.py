#!/usr/bin/env python3
"""Diagnostic chiffré d'une carte de Blackout (GDD-BLACKOUT.md, revue de carte du 2026-10-20).

  analyse_carte.py <id de carte> [--ab <variante>[,<variante>…]] [--png <dossier>] [--json <fichier>]

Mesures statiques (map.txt, zones.json), par zone et au total :
- vide : part des cases de sol sans aucun objet (caisse, bateau, cachette, objet bas, bâtiment posé dans la
  zone ; les murs d'enceinte et l'eau ne comptent pas) à 2 cases (et à 3 cases) autour ;
- lignes de vue : longueur moyenne des rayons (16 directions, arrêtés par « #cBHvR », plafond 25 cases),
  part des cases d'où un rayon file à 15 cases ou plus, part visible du disque de 7 cases (portée du cône) ;
- densité : cachettes et objets hauts (groupes de « c », « B », « # » posés dans la zone) pour 100 cases ;
- chemins : graphe des zones (reliées par un couloir ou directement), degré, culs-de-sac, nombre de
  boucles indépendantes (E − V + 1), largeur des couloirs ;
- sorties : distance au départ et nombre de zones voisines (approches).
Avec --ab (journaux de tools/blackout/ab_tension.py, tous niveaux confondus) : part du temps des chassés et
du chasseur par zone, captures, vu-perdu, frôlements, entrées par cachette, sorties prises ; zones mortes.
--png : carte de la carte (vides en rouge), des lignes de vue, et cartes de chaleur des parties.
"""
import argparse
import json
import math
import os
import sys
from collections import deque

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WALK = ".ES"
OCCLUDE = "#cBHvR"
TALL = "cB#vR"


def charger(mid):
    d = os.path.join(ROOT, "assets", "maps", mid)
    g = [l for l in open(os.path.join(d, "map.txt"), encoding="utf-8").read().split("\n") if l.strip()]
    z = json.load(open(os.path.join(d, "zones.json"), encoding="utf-8"))
    return g, z


class Carte:
    def __init__(self, mid):
        self.id = mid
        self.g, self.zj = charger(mid)
        self.H = len(self.g)
        self.W = len(self.g[0])
        self.zones = [(z["name"], *z["rect"]) for z in self.zj["zones"]]
        self.zgrid = [[self._zone(x, y) for x in range(self.W)] for y in range(self.H)]
        self.occ = [[ch in OCCLUDE for ch in row] for row in self.g]

    def at(self, x, y):
        if 0 <= x < self.W and 0 <= y < self.H:
            return self.g[y][x]
        return "#"

    def _zone(self, x, y):
        for i, (_, zx, zy, zw, zh) in enumerate(self.zones):
            if zx <= x < zx + zw and zy <= y < zy + zh:
                return i
        return -1

    def walk(self, x, y):
        return self.at(x, y) in WALK

    def cells(self):
        return [(x, y) for y in range(self.H) for x in range(self.W) if self.walk(x, y)]

    def ray(self, x, y, ang, cap=25.0):
        dx, dy = math.cos(ang) * 0.4, math.sin(ang) * 0.4
        px, py = x + 0.5, y + 0.5
        occ, W, H = self.occ, self.W, self.H
        for i in range(1, int(cap / 0.4) + 1):
            cx, cy = int(px + dx * i), int(py + dy * i)
            if cx < 0 or cy < 0 or cx >= W or cy >= H or occ[cy][cx]:
                return i * 0.4
        return cap

    def visible(self, x, y, x2, y2):
        n = int(max(abs(x2 - x), abs(y2 - y)) * 2) + 1
        occ, W, H = self.occ, self.W, self.H
        for i in range(1, n):
            t = i / n
            cx = int(x + 0.5 + (x2 - x) * t)
            cy = int(y + 0.5 + (y2 - y) * t)
            if cx < 0 or cy < 0 or cx >= W or cy >= H or occ[cy][cx]:
                return False
        return True


def statique(c):
    cells = c.cells()
    per = {i: {"sol": 0, "vide2": 0, "vide3": 0, "ray": 0.0, "long": 0, "disque": 0.0, "n": 0}
           for i in range(-1, len(c.zones))}
    obj = set()
    # Objets hauts et cachettes par zone (groupes contigus).
    seen = set()
    tall = {i: 0 for i in per}
    hides = {i: 0 for i in per}
    low = {i: 0 for i in per}
    for y in range(c.H):
        for x in range(c.W):
            ch = c.at(x, y)
            if (x, y) in seen or ch not in "cBHt#~vR":
                continue
            comp, q = [(x, y)], [(x, y)]
            seen.add((x, y))
            while q:
                a, b = q.pop()
                for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                    if n not in seen and 0 <= n[0] < c.W and 0 <= n[1] < c.H and c.at(*n) == ch:
                        seen.add(n)
                        comp.append(n)
                        q.append(n)
            zs = {c.zgrid[b][a] for a, b in comp}
            if ch == "#" and (len(zs) > 1 or -1 in zs or len(comp) > 60):
                continue          # masse entre zones, pas un objet
            z = c.zgrid[comp[0][1]][comp[0][0]]
            if ch != "~" or (len(comp) <= 40 and len(zs) == 1 and -1 not in zs):
                obj.update(comp)          # l'eau d'un bassin posé dans une zone est un objet, pas la mer
            if ch == "H":
                hides[z] += 1
            elif ch in TALL:
                tall[z] += 1
            elif ch == "t":
                low[z] += 1
    vide, rays = {}, {}
    for (x, y) in cells:
        z = c.zgrid[y][x]
        p = per[z]
        p["sol"] += 1

        def libre(r):
            return not any((x + dx, y + dy) in obj for dy in range(-r, r + 1) for dx in range(-r, r + 1))
        v2 = libre(2)
        v3 = v2 and libre(3)
        p["vide2"] += v2
        p["vide3"] += v3
        vide[(x, y)] = 2 if v3 else (1 if v2 else 0)
        rs = [c.ray(x, y, k * math.pi / 8) for k in range(16)]
        m = sum(rs) / len(rs)
        rays[(x, y)] = m
        p["ray"] += m
        p["long"] += max(rs) >= 15
        # Disque de 7 cases : part des cases (non murs) visibles depuis ici (échantillon 1 case sur 2).
        tot = vis = 0
        for dy in range(-7, 8, 2):
            for dx in range(-7, 8, 2):
                if dx * dx + dy * dy > 49 or c.at(x + dx, y + dy) == "#":
                    continue
                tot += 1
                vis += c.visible(x, y, x + dx, y + dy)
        p["disque"] += vis / max(tot, 1)
    out = {}
    for i, p in per.items():
        if p["sol"] == 0:
            continue
        n = p["sol"]
        nom = c.zones[i][0] if i >= 0 else "(couloirs)"
        out[nom] = {"sol": n, "vide2": round(100 * p["vide2"] / n), "vide3": round(100 * p["vide3"] / n),
                    "ray": round(p["ray"] / n, 1), "long": round(100 * p["long"] / n),
                    "disque": round(100 * p["disque"] / n), "cachettes": hides[i], "hauts": tall[i], "bas": low[i],
                    "hauts_100": round(100 * tall[i] / n, 1), "cach_100": round(100 * hides[i] / n, 1)}
    n = len(cells)
    tot = {"sol": n, "vide2": round(100 * sum(v >= 1 for v in vide.values()) / n),
           "vide3": round(100 * sum(v >= 2 for v in vide.values()) / n),
           "ray": round(sum(rays.values()) / n, 1),
           "long": round(100 * sum(p["long"] for p in per.values()) / n),
           "disque": round(100 * sum(p["disque"] for p in per.values()) / n),
           "cachettes": sum(hides.values()), "hauts": sum(tall.values()), "bas": sum(low.values())}
    return out, tot, vide, rays


def graphe(c):
    """Zones reliées (couloir commun ou contact direct), couloirs et leur largeur."""
    lab = {}
    corr = []
    for (x, y) in c.cells():
        if c.zgrid[y][x] != -1 or (x, y) in lab:
            continue
        k = len(corr)
        comp, q = [], deque([(x, y)])
        lab[(x, y)] = k
        while q:
            a, b = q.popleft()
            comp.append((a, b))
            for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                if n not in lab and c.walk(*n) and c.zgrid[n[1]][n[0]] == -1:
                    lab[n] = k
                    q.append(n)
        corr.append(comp)
    edges = set()
    corr_info = []
    for k, comp in enumerate(corr):
        zs = set()
        for (a, b) in comp:
            for n in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                if c.walk(*n) and c.zgrid[n[1]][n[0]] >= 0:
                    zs.add(c.zgrid[n[1]][n[0]])
        zs = sorted(zs)
        widths = []
        for (a, b) in comp:
            h = 1
            while c.walk(a - h, b):
                h += 1
            h2 = 1
            while c.walk(a + h2, b):
                h2 += 1
            v = 1
            while c.walk(a, b - v):
                v += 1
            v2 = 1
            while c.walk(a, b + v2):
                v2 += 1
            widths.append(min(h + h2 - 1, v + v2 - 1))
        widths.sort()
        corr_info.append({"cases": len(comp), "zones": [c.zones[z][0] for z in zs],
                          "largeur": widths[len(widths) // 2] if widths else 0})
        for i in range(len(zs)):
            for j in range(i + 1, len(zs)):
                edges.add((zs[i], zs[j]))
    for (x, y) in c.cells():
        z = c.zgrid[y][x]
        if z < 0:
            continue
        for n in ((x + 1, y), (x, y + 1)):
            if c.walk(*n) and c.zgrid[n[1]][n[0]] >= 0 and c.zgrid[n[1]][n[0]] != z:
                edges.add(tuple(sorted((z, c.zgrid[n[1]][n[0]]))))
    deg = {i: 0 for i in range(len(c.zones))}
    for a, b in edges:
        deg[a] += 1
        deg[b] += 1
    # Ponts (une liaison dont la coupure isole des zones).
    ponts = []
    for e in edges:
        rest = edges - {e}
        vu, q = {0}, [0]
        while q:
            u = q.pop()
            for a, b in rest:
                for s, t in ((a, b), (b, a)):
                    if s == u and t not in vu:
                        vu.add(t)
                        q.append(t)
        if len(vu) < len(c.zones):
            ponts.append(e)
    return {"liaisons": len(edges), "boucles": len(edges) - len(c.zones) + 1,
            "degre": {c.zones[i][0]: d for i, d in deg.items()},
            "culs_de_sac": [c.zones[i][0] for i, d in deg.items() if d <= 1],
            "ponts": [(c.zones[a][0], c.zones[b][0]) for a, b in ponts],
            "couloirs": corr_info, "_edges": edges}


def sorties(c, edges):
    start = next((x, y) for y in range(c.H) for x in range(c.W) if c.at(x, y) == "S")
    d = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n not in d and c.walk(*n):
                d[n] = d[(x, y)] + 1
                q.append(n)
    out = []
    for e in c.zj.get("exits", []):
        ts = [tuple(t) for t in e["tiles"]]
        z = c.zgrid[ts[0][1]][ts[0][0]]
        # Exposition : part visible du disque de 7 cases depuis la sortie.
        x, y = ts[0]
        tot = vis = 0
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                if dx * dx + dy * dy > 49 or not c.walk(x + dx, y + dy):
                    continue
                tot += 1
                vis += c.visible(x, y, x + dx, y + dy)
        out.append({"zone": e["zone"], "distance": min(d.get(t, 9999) for t in ts),
                    "approches": sum(1 for a, b in edges if z in (a, b)), "exposition": round(100 * vis / max(tot, 1))})
    return out


def parties(c, variantes):
    rs = []
    for v in variantes:
        dossier = os.path.join(ROOT, "tests", "out", "blackout_ab", v)
        for nom in sorted(os.listdir(dossier)):
            if nom.endswith(".log"):
                for l in open(os.path.join(dossier, nom), encoding="utf-8"):
                    if l.startswith("[bk-stats] "):
                        rs.append(json.loads(l[11:]))
    heat, hheat = {}, {}
    caps, vp, fro = {}, {}, {}
    cach, sorti = {}, {}
    for r in rs:
        for k, n in r.get("chaleur", {}).items():
            heat[k] = heat.get(k, 0) + n
        for k, n in r.get("chaleur_chasseur", {}).items():
            hheat[k] = hheat.get(k, 0) + n
        for lst, dst in ((r.get("lieux_trouves", []), caps), (r.get("lieux_vu_perdu", []), vp),
                         (r.get("lieux_frolements", []), fro)):
            for x, y in lst:
                dst[f"{x},{y}"] = dst.get(f"{x},{y}", 0) + 1
        for k, n in r.get("cachettes_entrees", {}).items():
            cach[k] = cach.get(k, 0) + n
        for z in r.get("sorties_lieux", []):
            sorti[z] = sorti.get(z, 0) + 1
    def parzone(d):
        out = {}
        for k, n in d.items():
            x, y = map(int, k.split(","))
            z = c.zgrid[y][x] if 0 <= y < c.H and 0 <= x < c.W else -1
            nom = c.zones[z][0] if z >= 0 else "(couloirs)"
            out[nom] = out.get(nom, 0) + n
        return out
    tot = {}
    for nom, d in (("chasses", heat), ("chasseur", hheat), ("captures", caps), ("vu_perdu", vp), ("frolements", fro)):
        pz = parzone(d)
        s = max(sum(pz.values()), 1)
        tot[nom] = {k: round(100.0 * v / s, 1) for k, v in pz.items()}
    hides = [(x, y) for y in range(c.H) for x in range(c.W) if c.at(x, y) == "H"]
    cach_list = {f"{x},{y}": cach.get(f"{x},{y}", 0) for (x, y) in hides}
    return {"rounds": len(rs), "par_zone": tot, "cachettes": cach_list, "sorties": sorti,
            "_heat": heat, "_hheat": hheat, "_caps": caps, "_vp": vp}


COUL = {"#": (59, 66, 83), "c": (160, 112, 62), "B": (232, 238, 242), "H": (224, 138, 46), "t": (201, 168, 115),
        "~": (47, 127, 184), "E": (60, 200, 90), "S": (240, 220, 60), ".": (217, 210, 195)}


def png(c, dossier, vide, rays, ab):
    from PIL import Image, ImageDraw
    os.makedirs(dossier, exist_ok=True)
    k = 12

    def base():
        im = Image.new("RGB", (c.W * k, c.H * k))
        dr = ImageDraw.Draw(im)
        for y in range(c.H):
            for x in range(c.W):
                dr.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1], fill=COUL.get(c.at(x, y), (255, 0, 255)))
        for (n, zx, zy, zw, zh) in c.zones:
            dr.rectangle([zx * k, zy * k, (zx + zw) * k - 1, (zy + zh) * k - 1], outline=(30, 30, 30))
            dr.text((zx * k + 3, zy * k + 2), n, fill=(20, 20, 20))
        return im, dr
    im, dr = base()
    for (x, y), v in vide.items():
        if v:
            col = (235, 120, 110) if v == 1 else (200, 40, 40)
            dr.rectangle([x * k + 2, y * k + 2, x * k + k - 3, y * k + k - 3], fill=col)
    im.save(os.path.join(dossier, f"{c.id}_vides.png"))
    im, dr = base()
    for (x, y), m in rays.items():
        t = min(m / 12.0, 1.0)
        dr.rectangle([x * k + 1, y * k + 1, x * k + k - 2, y * k + k - 2],
                     fill=(int(60 + 195 * t), int(200 - 150 * t), int(90 - 60 * t)))
    im.save(os.path.join(dossier, f"{c.id}_lignes_de_vue.png"))
    if ab:
        for nom, d, col in (("chasses", ab["_heat"], (40, 90, 230)), ("chasseur", ab["_hheat"], (220, 40, 40))):
            im, dr = base()
            mx = max(d.values()) if d else 1
            for kk, n in d.items():
                x, y = map(int, kk.split(","))
                t = math.sqrt(n / mx)
                dr.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1],
                             fill=tuple(int(255 * (1 - t) + col[i] * t) for i in range(3)))
            for kk in ab["_caps"]:
                x, y = map(int, kk.split(","))
                dr.ellipse([x * k + 3, y * k + 3, x * k + k - 4, y * k + k - 4], outline=(0, 0, 0))
            for kk, n in ab["cachettes"].items():
                x, y = map(int, kk.split(","))
                dr.text((x * k, y * k), str(n), fill=(0, 0, 0))
            im.save(os.path.join(dossier, f"{c.id}_chaleur_{nom}.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("carte")
    ap.add_argument("--ab", default="")
    ap.add_argument("--png", default="")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    c = Carte(a.carte)
    zs, tot, vide, rays = statique(c)
    gr = graphe(c)
    so = sorties(c, gr["_edges"])
    print(f"## Carte {a.carte} ({c.W}×{c.H}, {tot['sol']} cases de sol)\n")
    print("| zone | sol | vide 2 % | vide 3 % | rayon moyen | rayon ≥ 15 % | disque 7 visible % | cachettes | hauts | bas | hauts/100 | cachettes/100 | liaisons |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for nom, v in zs.items():
        print(f"| {nom} | {v['sol']} | {v['vide2']} | {v['vide3']} | {v['ray']} | {v['long']} | {v['disque']} | "
              f"{v['cachettes']} | {v['hauts']} | {v['bas']} | {v['hauts_100']} | {v['cach_100']} | {gr['degre'].get(nom, '–')} |")
    print(f"| **total** | {tot['sol']} | {tot['vide2']} | {tot['vide3']} | {tot['ray']} | {tot['long']} | {tot['disque']} | "
          f"{tot['cachettes']} | {tot['hauts']} | {tot['bas']} | | | |")
    print(f"\nliaisons {gr['liaisons']}, boucles indépendantes {gr['boucles']}, culs-de-sac {gr['culs_de_sac']}, "
          f"ponts {gr['ponts']}")
    lw = [x["largeur"] for x in gr["couloirs"]]
    print(f"couloirs : {len(gr['couloirs'])}, largeur médiane {sorted(lw)[len(lw) // 2] if lw else 0} "
          f"(min {min(lw) if lw else 0}, max {max(lw) if lw else 0})")
    for s in so:
        print(f"sortie {s['zone']} : {s['distance']} cases du départ, {s['approches']} zones voisines, "
              f"exposition {s['exposition']} %")
    ab = None
    if a.ab:
        ab = parties(c, a.ab.split(","))
        print(f"\n### Parties ({ab['rounds']} rounds)\n")
        print("| zone | sol % | temps chassés % | temps chasseur % | captures % | vu-perdu % | frôlements % |")
        print("|---|---|---|---|---|---|---|")
        for nom, v in zs.items():
            pz = ab["par_zone"]
            print(f"| {nom} | {round(100 * v['sol'] / tot['sol'])} | {pz['chasses'].get(nom, 0)} | {pz['chasseur'].get(nom, 0)} | "
                  f"{pz['captures'].get(nom, 0)} | {pz['vu_perdu'].get(nom, 0)} | {pz['frolements'].get(nom, 0)} |")
        n = max(ab["rounds"], 1)
        jamais = [k for k, v in ab["cachettes"].items() if v == 0]
        print(f"\ncachettes : entrées par round {', '.join(f'{k}:{v / n:.2f}' for k, v in sorted(ab['cachettes'].items()))}")
        print(f"cachettes jamais prises : {jamais}")
        print(f"sorties prises (par round) : {', '.join(f'{k} {v / n:.2f}' for k, v in sorted(ab['sorties'].items()))}")
        mortes = [nom for nom, v in zs.items() if nom != "(couloirs)"
                  and ab["par_zone"]["chasses"].get(nom, 0) < 0.35 * 100 * v["sol"] / tot["sol"]
                  and ab["par_zone"]["captures"].get(nom, 0) < 1.0]
        print(f"zones mortes (temps des chassés < 35 % de leur part du sol et moins de 1 % des captures) : {mortes}")
    if a.png:
        png(c, a.png, vide, rays, ab)
    if a.json:
        res = {"zones": zs, "total": tot, "graphe": {k: v for k, v in gr.items() if not k.startswith("_")},
               "sorties": so}
        if ab:
            res["parties"] = {k: v for k, v in ab.items() if not k.startswith("_")}
        json.dump(res, open(a.json, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    sys.exit(main())
