#!/usr/bin/env python3
"""Réglage fin de `damage_pct` dans les bornes de l'archétype (SPEC §5.2, §14.4).

L'identité d'un perso est portée par ses leviers propres (vitesse, PV, frame
data, portée, spéciaux) ; `damage_pct` ne sert qu'au réglage fin, et seulement
dans les bornes `_equilibrage.damage_pct` de sa fiche (un lourd reste au-dessus
de 100 %, un rapide en dessous). Boucle : matrice (matrix.py) → taux global par
perso → pas amorti vers 50 % → reconstruction des data.json (build_fighter.py,
données seules). S'arrête quand tous les persos sont dans [45 %, 55 %].

Usage : .venv/bin/python tools/balance/tune.py [--iters 5] [--n 60] [--ai 80] [--gain 0.35]
"""
import argparse, json, os, subprocess, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
FIGHTERS = os.path.join(ROOT, "tools", "fighters")
TARGET_LOW, TARGET_HIGH = 45.0, 55.0


def rebuild():
    # Même interpréteur (le .venv : build_fighter.py lit les sprites avec numpy/Pillow
    # pour la boîte de poussée ; sans eux, data.json changerait).
    try:
        import numpy, PIL  # noqa: F401
    except ImportError:
        sys.exit("lancer avec le .venv (numpy et Pillow requis par build_fighter.py)")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sprites", "build_fighter.py"), "--all"],
                   check=True, stdout=subprocess.DEVNULL)


def totals(args):
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "balance", "matrix.py"),
                    "--n", str(args.n), "--ai", str(args.ai)], check=True, stdout=subprocess.DEVNULL)
    m = json.load(open(os.path.join(ROOT, "tests", "out", "balance.json")))
    out = {}
    for fid in m["ids"]:
        w = d = g = 0
        for p in m["pairs"]:
            if fid in (p["a"], p["b"]):
                w += p["wins_a"] if p["a"] == fid else p["wins_b"]
                d += p["draws"]
                g += p["games"]
        out[fid] = 100.0 * (w + 0.5 * d) / max(g, 1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=5)
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--ai", type=int, default=80)
    ap.add_argument("--gain", type=float, default=0.35, help="points de damage_pct par point d'écart")
    args = ap.parse_args()
    for it in range(args.iters + 1):
        rates = totals(args)
        print(f"itération {it} : " + ", ".join(f"{k} {v:.0f}" for k, v in sorted(rates.items(), key=lambda x: x[1])))
        if all(TARGET_LOW <= v <= TARGET_HIGH for v in rates.values()) or it == args.iters:
            break
        for fid, rate in rates.items():
            path = os.path.join(FIGHTERS, f"{fid}.json")
            data = json.load(open(path))
            lo, hi = data.get("_equilibrage", {}).get("damage_pct", [75, 130])
            pct = int(data.get("damage_pct", 100))
            new = max(lo, min(hi, pct + round((50.0 - rate) * args.gain)))
            if new != pct:
                print(f"  {fid}: damage_pct {pct} -> {new}" + (" (borne)" if new in (lo, hi) else ""))
                data["damage_pct"] = new
                with open(path, "w") as f:
                    json.dump(data, f, indent=1, ensure_ascii=False)
        rebuild()


if __name__ == "__main__":
    main()
