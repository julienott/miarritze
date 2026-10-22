#!/usr/bin/env python3
"""Cartes de jeu fidèles à un lieu réel (Blackout, SPEC-GORDEKA §8).

Méthode (Port des Pêcheurs de Biarritz, 2026-10-19) :
  1. `telecharger` : l'orthophoto IGN (BD ORTHO, licence ouverte Etalab 2.0, ~0,22 m/px au zoom 19)
     et les tracés OpenStreetMap (© contributeurs OSM, ODbL) d'un rectangle lat/lon, plus une
     image des tracés OSM superposés pour se repérer. Pas de tuiles Google : leurs conditions
     interdisent de les télécharger pour en tirer un plan.
  2. On relève à la main, dans tools/blackout/cartes/<id>.json, les formes du lieu en pixels de
     l'orthophoto (eau, sol, jetées, rochers, sable, bâtiments, végétation), puis le gameplay en
     cases (objets, cachettes, sorties possibles, départ, zones nommées).
  3. `construire` : dessine le tracé, le superpose à la photo (relecture), le découpe en cases,
     pose le gameplay, vérifie (tout atteignable, une cachette par zone, distance aux sorties)
     et écrit assets/maps/<id>/map.txt + zones.json + un aperçu.

  carte_reelle.py telecharger <id> <lat_sud> <lon_ouest> <lat_nord> <lon_est> [--zoom 19]
  carte_reelle.py construire <id>

Fichiers de travail : tools/rd/out/cartes/<id>/ (ortho.jpg, osm.json, meta.json, osm_sur_ortho.jpg,
trace_sur_ortho.jpg, apercu.png).

Format de tools/blackout/cartes/<id>.json :
  {"nom": "…", "region": [x, y, w, h] (px ortho), "case_px": 16,
   "couches": [ {"classe": "eau|sol|jetee|rocher_haut|rocher_bas|sable|batiment|vegetation|hors",
                 "polygone": [[x, y], …]}  ou  {"classe": …, "ligne": [[x, y], …], "largeur": px}, … ],
   "fond": "eau",
   "objets": [["B"|"c"|"t"|"#", x, y, w, h], …]   (en cases ; posés sur la grille découpée),
   "cachettes": [[x, y], …], "depart": [x, y, w, h],
   "sorties": [{"zone": "…", "cases": [x, y, w, h]}, …],
   "zones": [{"nom": "…", "rect": [x, y, w, h]}, …]}
Les couches sont dessinées dans l'ordre (la dernière recouvre). Une case prend la classe
majoritaire de ses pixels, sauf les jetées (lignes fines) qui l'emportent dès 30 %.
"""
import io
import json
import math
import os
import sys
import urllib.parse
import urllib.request
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WORK = os.path.join(ROOT, "tools", "rd", "out", "cartes")
DESC = os.path.join(ROOT, "tools", "blackout", "cartes")
IGN = ("https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS"
       "&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg")
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
UA = {"User-Agent": "miarritze-blackout (carte de jeu)"}

CLASSES = ["hors", "sol", "eau", "jetee", "rocher_haut", "rocher_bas", "sable", "batiment", "vegetation"]
CHAR = {"hors": "#", "sol": ".", "eau": "~", "jetee": "=", "rocher_haut": "R", "rocher_bas": "r",
        "sable": ":", "batiment": "#", "vegetation": "v"}
RGB = {"hors": (30, 30, 30), "sol": (205, 205, 200), "eau": (47, 127, 184), "jetee": (150, 150, 150),
       "rocher_haut": (140, 100, 70), "rocher_bas": (170, 135, 100), "sable": (230, 205, 150),
       "batiment": (200, 90, 60), "vegetation": (90, 130, 70)}
TILE_RGB = {".": (215, 210, 195), "=": (175, 170, 160), ":": (230, 207, 152), "~": (47, 127, 184),
            "#": (59, 66, 83), "R": (140, 100, 70), "r": (170, 135, 100), "v": (95, 138, 74),
            "B": (232, 238, 242), "c": (160, 112, 62), "t": (201, 168, 115), "H": (224, 138, 46),
            "E": (80, 200, 110), "S": (230, 60, 60)}
WALK = ".ES:="


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
    return x, y


# ------------------------------------------------------------------ téléchargement

def telecharger(cid, s, w, n, e, z=19):
    out = os.path.join(WORK, cid)
    os.makedirs(out, exist_ok=True)
    x0, y0 = tile_xy(n, w, z)
    x1, y1 = tile_xy(s, e, z)
    X0, Y0, X1, Y1 = int(x0), int(y0), int(x1), int(y1)
    im = Image.new("RGB", ((X1 - X0 + 1) * 256, (Y1 - Y0 + 1) * 256), (40, 70, 90))
    manq = 0
    for x in range(X0, X1 + 1):
        for y in range(Y0, Y1 + 1):
            try:
                d = urllib.request.urlopen(urllib.request.Request(IGN.format(z=z, x=x, y=y), headers=UA), timeout=30).read()
                im.paste(Image.open(io.BytesIO(d)), ((x - X0) * 256, (y - Y0) * 256))
            except Exception:
                manq += 1
    im.save(os.path.join(out, "ortho.jpg"), quality=92)
    m_px = 156543.03 * math.cos(math.radians((s + n) / 2)) / 2 ** z
    meta = {"zoom": z, "tuile0": [X0, Y0], "bbox": [s, w, n, e], "m_par_px": round(m_px, 4), "taille": im.size,
            "sources": ["IGN BD ORTHO (licence ouverte Etalab 2.0)", "OpenStreetMap (ODbL)"]}
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
    q = f"[out:json][timeout:60];(way({s},{w},{n},{e}););out geom;"
    osm = None
    for url in OVERPASS:
        try:
            raw = urllib.request.urlopen(urllib.request.Request(url, urllib.parse.urlencode({"data": q}).encode(),
                                                                UA), timeout=90).read()
            osm = json.loads(raw)
            break
        except Exception as ex:
            print(f"Overpass {url} : {ex}")
    if osm:
        json.dump(osm, open(os.path.join(out, "osm.json"), "w"))
        _osm_sur_ortho(out, meta, osm)
    print(f"ortho {im.size[0]}×{im.size[1]} px ({m_px:.2f} m/px, dalles manquantes {manq}), "
          f"OSM {len(osm['elements']) if osm else 'indisponible'} ; {out}")


def _osm_sur_ortho(out, meta, osm):
    z = meta["zoom"]
    X0, Y0 = meta["tuile0"]

    def px(p):
        x, y = tile_xy(p["lat"], p["lon"], z)
        return ((x - X0) * 256, (y - Y0) * 256)
    im = Image.open(os.path.join(out, "ortho.jpg")).convert("RGB")
    d = ImageDraw.Draw(im, "RGBA")
    for el in osm["elements"]:
        t, g = el.get("tags", {}), el.get("geometry")
        if not g:
            continue
        col, w = None, 2
        if t.get("man_made") in ("pier", "breakwater", "groyne"):
            col, w = (255, 0, 255), 4
        elif t.get("natural") == "coastline":
            col, w = (0, 255, 255), 3
        elif "building" in t:
            col = (255, 80, 0)
        elif t.get("leisure") == "marina" or t.get("natural") == "water":
            col, w = (255, 255, 0), 3
        elif t.get("natural") in ("beach", "sand"):
            col = (255, 220, 120)
        elif t.get("natural") in ("bare_rock", "cliff"):
            col, w = (150, 90, 40), 3
        elif t.get("highway"):
            col, w = (120, 255, 120), 1
        if col:
            d.line([px(p) for p in g], fill=col + (230,), width=w)
    im.save(os.path.join(out, "osm_sur_ortho.jpg"), quality=88)


# ------------------------------------------------------------------ construction

def _classes(desc, size):
    im = Image.new("L", size, CLASSES.index(desc.get("fond", "eau")))
    d = ImageDraw.Draw(im)
    for c in desc["couches"]:
        k = CLASSES.index(c["classe"])
        if "polygone" in c:
            d.polygon([tuple(p) for p in c["polygone"]], fill=k)
        else:
            d.line([tuple(p) for p in c["ligne"]], fill=k, width=int(c["largeur"]), joint="curve")
    return np.array(im)


def construire(cid):
    out = os.path.join(WORK, cid)
    desc = json.load(open(os.path.join(DESC, cid + ".json"), encoding="utf-8"))
    ortho = Image.open(os.path.join(out, "ortho.jpg")).convert("RGB")
    cls = _classes(desc, ortho.size)
    rgb = np.zeros(cls.shape + (3,), np.uint8)
    for i, name in enumerate(CLASSES):
        rgb[cls == i] = RGB[name]
    rx, ry, rw, rh = desc["region"]
    T = float(desc["case_px"])
    Image.blend(ortho, Image.fromarray(rgb), 0.45).crop((rx, ry, rx + rw, ry + rh)).save(
        os.path.join(out, "trace_sur_ortho.jpg"), quality=88)
    cols, rows = int(rw / T), int(rh / T)
    jet = CLASSES.index("jetee")
    g = []
    for j in range(rows):
        row = []
        for i in range(cols):
            blk = cls[int(ry + j * T):int(ry + (j + 1) * T), int(rx + i * T):int(rx + (i + 1) * T)]
            counts = np.bincount(blk.ravel(), minlength=len(CLASSES))
            k = jet if counts[jet] >= 0.3 * blk.size else int(counts.argmax())
            row.append(CHAR[CLASSES[k]])
        g.append(row)
    _relier_diagonales(g)
    # Bordure fermée.
    for j in range(rows):
        g[j][0] = g[j][cols - 1] = "#"
    for i in range(cols):
        g[0][i] = g[rows - 1][i] = "#"

    def put(ch, x, y, w=1, h=1):
        # On ne pose rien hors du sol praticable (objet tombé à l'eau = coordonnées fausses).
        bad = [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)
               if not (0 < xx < cols - 1 and 0 < yy < rows - 1) or g[yy][xx] not in ".:="]
        if bad:
            print(f"  « {ch} » en ({x}, {y}, {w}, {h}) refusé : cases hors du sol {bad[:4]}")
            return
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                g[yy][xx] = ch
    for ch, x, y, w, h in desc.get("objets", []):
        put(ch, x, y, w, h)
    for x, y in desc.get("cachettes", []):
        put("H", x, y)
    for s in desc.get("sorties", []):
        put("E", *s["cases"])
    put("S", *desc["depart"])
    ok = _verifier(g, desc)
    os.makedirs(os.path.join(ROOT, "assets", "maps", cid), exist_ok=True)
    with open(os.path.join(ROOT, "assets", "maps", cid, "map.txt"), "w") as fh:
        fh.write("\n".join("".join(r) for r in g) + "\n")
    zones = [{"name": z["nom"], "rect": z["rect"]} for z in desc.get("zones", [])]
    exits = [{"zone": s["zone"], "tiles": [[x, y] for y in range(s["cases"][1], s["cases"][1] + s["cases"][3])
                                            for x in range(s["cases"][0], s["cases"][0] + s["cases"][2])]}
             for s in desc.get("sorties", [])]
    meta = json.load(open(os.path.join(out, "meta.json")))
    json.dump({"name": desc["nom"], "version": 3, "zones": zones, "exits": exits,
               "source": {"m_par_case": round(meta["m_par_px"] * T, 2), "bbox": meta["bbox"], "licences": meta["sources"]}},
              open(os.path.join(ROOT, "assets", "maps", cid, "zones.json"), "w"), ensure_ascii=False, indent=1)
    _apercu(g, desc, os.path.join(out, "apercu.png"))
    print(f"{cols}×{rows} cases ({meta['m_par_px'] * T:.1f} m par case) → assets/maps/{cid}/")
    return ok


def _relier_diagonales(g):
    """Une jetée tracée en biais donne des cases qui ne se touchent que par un coin : on ajoute
    une case de jetée pour que le chemin reste continu (déplacement en 4 directions)."""
    rows, cols = len(g), len(g[0])
    for y in range(rows - 1):
        for x in range(cols - 1):
            a, b, c, d = g[y][x], g[y][x + 1], g[y + 1][x], g[y + 1][x + 1]
            if a in WALK and d in WALK and b not in WALK and c not in WALK:
                g[y][x + 1] = "="
            elif b in WALK and c in WALK and a not in WALK and d not in WALK:
                g[y][x] = "="


def _verifier(g, desc):
    rows, cols = len(g), len(g[0])
    start = next((x, y) for y in range(rows) for x in range(cols) if g[y][x] == "S")
    d = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < cols and 0 <= n[1] < rows and n not in d and g[n[1]][n[0]] in WALK:
                d[n] = d[(x, y)] + 1
                q.append(n)
    walk = [(x, y) for y in range(rows) for x in range(cols) if g[y][x] in WALK]
    isol = [p for p in walk if p not in d]
    print(f"sol {len(walk)} cases, atteignables {len(d)}, isolées {len(isol)}" + (f" ex. {isol[:8]}" if isol else ""))
    for x, y in desc.get("cachettes", []):
        if not any((x + dx, y + dy) in d for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            print(f"  cachette ({x}, {y}) inaccessible")
    for z in desc.get("zones", []):
        zx, zy, zw, zh = z["rect"]
        n = sum(1 for x, y in desc.get("cachettes", []) if zx <= x < zx + zw and zy <= y < zy + zh)
        if n == 0:
            print(f"  zone sans cachette : {z['nom']}")
    for s in desc.get("sorties", []):
        x, y, w, h = s["cases"]
        dist = min((d.get((xx, yy), 9999) for yy in range(y, y + h) for xx in range(x, x + w)), default=9999)
        print(f"  sortie « {s['zone']} » : {dist} cases du départ")
    return not isol


def _apercu(g, desc, path, T=12):
    rows, cols = len(g), len(g[0])
    im = Image.new("RGB", (cols * T, rows * T))
    d = ImageDraw.Draw(im)
    for y in range(rows):
        for x in range(cols):
            d.rectangle([x * T, y * T, x * T + T - 1, y * T + T - 1], fill=TILE_RGB.get(g[y][x], (255, 0, 255)))
    for z in desc.get("zones", []):
        zx, zy, zw, zh = z["rect"]
        d.rectangle([zx * T, zy * T, (zx + zw) * T - 1, (zy + zh) * T - 1], outline=(255, 255, 255))
        d.text((zx * T + 3, zy * T + 2), z["nom"], fill=(0, 0, 0), stroke_width=2, stroke_fill=(255, 255, 255))
    im.save(path)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    if a[0] == "telecharger":
        z = int(a[a.index("--zoom") + 1]) if "--zoom" in a else 19
        telecharger(a[1], *map(float, a[2:6]), z=z)
    elif a[0] == "construire":
        raise SystemExit(0 if construire(a[1]) else 1)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
