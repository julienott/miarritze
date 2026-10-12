#!/usr/bin/env python3
"""Équilibrage automatique (SPEC §5.2, §14.4).

Boucle : matrice IA Expert contre IA Expert (tests/balance_sim.gd) → taux
de victoire par perso → ajustement de `damage_pct` dans tools/fighters/<id>.json
(borné 75–130 %) → reconstruction des data.json. S'arrête quand tous les
persos sont dans [40 %, 60 %] ou après N itérations.
Usage : balance_tune.py [--iters 6] [--n 10]
"""
import csv, json, os, subprocess, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
PY = sys.executable


def run_matrix(n):
    subprocess.run(["godot", "--headless", "--path", ROOT, "--script",
                    "res://tests/balance_sim.gd", "--", f"--n={n}"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    rows = list(csv.reader(open(os.path.join(ROOT, "tests", "out", "balance.csv"))))
    return {r[0]: float(r[-1]) for r in rows[1:]}


def main():
    iters = int(sys.argv[sys.argv.index("--iters") + 1]) if "--iters" in sys.argv else 6
    n = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else 10
    for it in range(iters):
        rates = run_matrix(n)
        print(f"itération {it}: " + ", ".join(f"{k} {v:.0f}" for k, v in sorted(rates.items(), key=lambda x: x[1])))
        if all(40 <= v <= 60 for v in rates.values()):
            print("équilibré")
            return rates
        for fid, rate in rates.items():
            path = os.path.join(ROOT, "tools", "fighters", f"{fid}.json")
            data = json.load(open(path))
            pct = int(data.get("damage_pct", 100))
            step = round((50 - rate) * 0.5)
            data["damage_pct"] = max(75, min(130, pct + step))
            json.dump(data, open(path, "w"), indent=1, ensure_ascii=False)
        subprocess.run([PY, os.path.join(ROOT, "tools", "sprites", "build_fighter.py"), "--all"],
                       check=True, stdout=subprocess.DEVNULL)
    rates = run_matrix(n)
    print("final: " + ", ".join(f"{k} {v:.0f}" for k, v in sorted(rates.items(), key=lambda x: x[1])))
    return rates


if __name__ == "__main__":
    main()
