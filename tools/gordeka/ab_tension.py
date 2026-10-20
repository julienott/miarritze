#!/usr/bin/env python3
"""Mesures A/B de la tension des rounds IA contre IA (docs/GORDEKA_EQUILIBRAGE.md, 2026-10-20).

  ab_tension.py run <variante> [--rules k:v,…] [--niveaux normal/facile,normal/normal,normal/malin]
                [--rounds 80] [--procs 8] [--players 6] [--projet <copie du projet>]
  ab_tension.py tableau <variante> [<variante> …] [--niveau normal/normal]

`run` lance `procs` Godot headless par niveau (« chassés/chasseur »), en temps fixe (--fixed-fps 60,
même pas de temps qu'en jeu, aussi vite que le processeur le permet), chacun pour sa part des rounds,
avec --gk-stats ; journaux et bilan dans tests/out/gordeka_ab/<variante>/. `tableau` compare des
variantes déjà mesurées : moyenne ± écart-type par round (± erreur type entre crochets pour les
indicateurs principaux).
"""
import argparse
import json
import math
import os
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "tests", "out", "gordeka_ab")
NIVEAUX = "normal/facile,normal/normal,normal/malin"


def lire(dossier, niveau=None):
    """Rounds (dict) des journaux d'une variante, filtrés par « chassés/chasseur »."""
    rs = []
    for nom in sorted(os.listdir(dossier)):
        if not nom.endswith(".log"):
            continue
        for ligne in open(os.path.join(dossier, nom), encoding="utf-8"):
            if ligne.startswith("[gk-stats] "):
                r = json.loads(ligne[len("[gk-stats] "):])
                if niveau is None or f"{r['niveau']}/{r['niveau_chasseur']}" == niveau:
                    rs.append(r)
    return rs


def par_round(r):
    """Indicateurs d'un round."""
    minutes = max(r["duree"], 1.0) / 60.0
    hider_min = max(r.get("chasse_s", 0.0), 1.0) / 60.0
    return {
        "trouves": 100.0 * r["trouves"] / max(r["chasses"], 1),
        "gagne": 100.0 if r["trouves"] * 2 > r["chasses"] else 0.0,
        "sortis": 100.0 * r["sorties"] / max(r["chasses"], 1),
        "fro2": r.get("frolements_2", 0),
        "fro3": r.get("frolements_3", 0),
        "fro2_min": r.get("frolements_2", 0) / minutes,
        "vus": r.get("vus", 0),
        "vu_perdu": r.get("vu_perdu", 0),
        "doutes": r.get("doutes", 0),
        "doutes_perdus": r.get("doutes_perdus", 0),
        "cases_min": r.get("cases_parcourues", 0.0) / hider_min,
        "bouge": 100.0 * r.get("bouge_s", 0.0) / max(r.get("chasse_s", 0.0), 1.0),
        "immobile": 100.0 * r.get("immobile_s", 0.0) / max(r.get("chasse_s", 0.0), 1.0),
        "cachette": 100.0 * r.get("cachette_s", 0.0) / max(r.get("chasse_s", 0.0), 1.0),
        "planques": r.get("changements_planque", 0),
        "entrees": r.get("entrees_cachette", 0),
        "fuites": r.get("sorties_fuite", 0),
        "cap_course": r.get("captures_course", 0),
        "cap_evasion": r.get("captures_apres_evasion", 0),
        "cap_fin": r.get("captures_fin", 0),
        "duree": r["duree"],
        "delivres": r.get("delivres", 0),
        "gateaux": r.get("gateaux", 0),
    }


def stats(valeurs):
    n = len(valeurs)
    if n == 0:
        return 0.0, 0.0, 0.0
    m = sum(valeurs) / n
    sd = math.sqrt(sum((v - m) ** 2 for v in valeurs) / max(n - 1, 1))
    return m, sd, sd / math.sqrt(n)


def bilan(rs):
    ind = [par_round(r) for r in rs]
    out = {"rounds": len(rs)}
    for k in (ind[0].keys() if ind else []):
        m, sd, se = stats([i[k] for i in ind])
        out[k] = {"m": round(m, 2), "sd": round(sd, 2), "se": round(se, 2)}
    return out


def run(args):
    dossier = os.path.join(OUT, args.variante)
    os.makedirs(dossier, exist_ok=True)
    for f in os.listdir(dossier):
        if f.endswith(".log"):
            os.remove(os.path.join(dossier, f))
    jobs = []
    part = math.ceil(args.rounds / args.procs)
    for niv in args.niveaux.split(","):
        chasses, chasseur = niv.split("/")
        for i in range(args.procs):
            cmd = ["godot", "--headless", "--path", args.projet, "--fixed-fps", "60", "--",
                   "--scene=gk_game", "--gk-bots-only", "--gk-stats", f"--gk-rounds={part}",
                   f"--gk-level={chasses}", f"--gk-hunter-level={chasseur}", f"--gk-players={args.players}"]
            if args.rules:
                cmd.append(f"--gk-rules={args.rules}")
            jobs.append((cmd, os.path.join(dossier, f"{chasses}_{chasseur}_{i}.log")))
    t0 = time.time()
    actifs = []
    while jobs or actifs:
        while jobs and len(actifs) < args.paralleles:
            cmd, log = jobs.pop(0)
            fh = open(log, "w")
            actifs.append((subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT), fh, log))
        time.sleep(0.5)
        for p, fh, log in list(actifs):
            if p.poll() is not None:
                fh.close()
                actifs.remove((p, fh, log))
            elif time.time() - t0 > args.timeout:
                p.kill()
    res = {"variante": args.variante, "rules": args.rules, "niveaux": {}}
    for niv in args.niveaux.split(","):
        res["niveaux"][niv] = bilan(lire(dossier, niv))
    with open(os.path.join(dossier, "bilan.json"), "w") as fh:
        json.dump(res, fh, ensure_ascii=False, indent=1)
    erreurs = 0
    for f in os.listdir(dossier):
        if f.endswith(".log"):
            erreurs += sum(1 for ligne in open(os.path.join(dossier, f), encoding="utf-8")
                           if "SCRIPT ERROR" in ligne or ligne.startswith("ERROR"))
    print(f"{args.variante} : {time.time() - t0:.0f} s, erreurs dans les journaux : {erreurs}")
    tableau([args.variante], None)


COLS = [("rounds", "rounds", None), ("gagne", "chasseur gagne %", 0), ("trouves", "trouvés %", 0),
        ("sortis", "sortis %", 0), ("fro2", "frôlements <2", 1), ("fro3", "frôl. <3", 1),
        ("vu_perdu", "vu-perdu", 1), ("vus", "vus", 1), ("doutes_perdus", "« ? » perdus", 1),
        ("cases_min", "cases/min", 1), ("bouge", "bouge %", 0), ("immobile", "immobile %", 0),
        ("cachette", "en cachette %", 0), ("planques", "chgts planque", 1), ("entrees", "entrées cachette", 1),
        ("fuites", "sorties en fuite", 1), ("cap_course", "captures en course", 1),
        ("cap_evasion", "captures après évasion", 1), ("cap_fin", "captures 30 dernières s", 1),
        ("delivres", "délivrances", 1), ("gateaux", "gâteaux", 1), ("duree", "durée s", 0)]
PRINCIPAUX = {"gagne", "fro2", "vu_perdu", "cases_min", "bouge"}


def tableau(variantes, niveau):
    print("| variante | chassés/chasseur | " + " | ".join(t for _, t, _ in COLS) + " |")
    print("|" + "---|" * (len(COLS) + 2))
    for v in variantes:
        b = json.load(open(os.path.join(OUT, v, "bilan.json"), encoding="utf-8"))
        for niv, d in b["niveaux"].items():
            if niveau and niv != niveau:
                continue
            cells = []
            for k, titre, dec in COLS:
                if k == "rounds":
                    cells.append(f"{d.get('rounds', 0)}")
                    continue
                x = d.get(k)
                if not x:
                    cells.append("–")
                    continue
                s = f"{x['m']:.{dec}f} ± {x['sd']:.{dec}f}"
                if k in PRINCIPAUX:
                    s += f" [±{x['se']:.{dec}f}]"
                cells.append(s)
            print(f"| {v} | {niv} | " + " | ".join(cells) + " |")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("variante")
    r.add_argument("--rules", default="")
    r.add_argument("--niveaux", default=NIVEAUX)
    r.add_argument("--rounds", type=int, default=80)
    r.add_argument("--procs", type=int, default=8, help="processus par niveau (chacun fait sa part des rounds)")
    r.add_argument("--paralleles", type=int, default=9, help="processus Godot en même temps")
    r.add_argument("--players", type=int, default=6)
    r.add_argument("--timeout", type=float, default=3600)
    r.add_argument("--projet", default=ROOT, help="copie du projet à lancer (instantané : le code peut changer pendant la mesure)")
    t = sub.add_parser("tableau")
    t.add_argument("variantes", nargs="+")
    t.add_argument("--niveau", default=None)
    args = ap.parse_args()
    if args.cmd == "run":
        run(args)
    else:
        tableau(args.variantes, args.niveau)


if __name__ == "__main__":
    sys.exit(main())
