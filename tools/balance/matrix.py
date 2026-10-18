#!/usr/bin/env python3
"""Matrice d'équilibrage IA contre IA en parallèle (SPEC §14.4).

Lance tests/balance_sim.gd en K processus Godot headless (une part des paires
chacun), fusionne et affiche :
  - la matrice des victoires (ligne contre colonne, en %) ;
  - le taux global par combattant et les paires hors de [40 %, 60 %] ;
  - par combattant : dégâts/s, touches/s, % de ses coups gardés, % des coups
    adverses qu'il garde, spéciaux/min, projectiles/min, durée moyenne ;
  - les coups qui font le plus de dégâts (détecter un coup dominant).
Écrit tests/out/balance.json, tests/out/balance.csv (heatmap) et, avec
--md FICHIER, un résumé Markdown.

Usage : matrix.py [--n 100] [--ai 80] [--seed 1000] [--jobs 9] [--boss]
                  [--ids a,b] [--only a:b,c:d] [--save NOM] [--md FICHIER] [--from FICHIER.json]
"""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tests", "out")
FPS = 60
LIMIT = 60  # % : au-delà, une paire est déséquilibrée (consigne : ~60/40)


def run(args):
    os.makedirs(OUT, exist_ok=True)
    procs, paths = [], []
    for s in range(args.jobs):
        path = os.path.join(OUT, f"balance_shard_{s}.json")
        paths.append(path)
        cmd = ["godot", "--headless", "--path", ROOT, "--script", "res://tests/balance_sim.gd", "--",
               f"--n={args.n}", f"--ai={args.ai}", f"--seed={args.seed}",
               f"--shard={s}/{args.jobs}", f"--out={path}"]
        if args.boss:
            cmd.append("--boss")
        if args.ids:
            cmd.append(f"--ids={args.ids}")
        if args.only:
            cmd.append(f"--only={args.only}")
        procs.append(subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE))
    for p in procs:
        _, err = p.communicate()
        if p.returncode != 0:
            sys.exit(err.decode(errors="replace"))
    merged = {"ai": args.ai, "n": args.n, "ids": None, "pairs": [], "fighters": {}}
    for path in paths:
        part = json.load(open(path))
        merged["ids"] = part["ids"]
        merged["pairs"] += part["pairs"]
        for fid, st in part["fighters"].items():
            acc = merged["fighters"].setdefault(fid, {})
            for k, v in st.items():
                if isinstance(v, dict):
                    sub = acc.setdefault(k, {})
                    for kk, vv in v.items():
                        sub[kk] = sub.get(kk, 0) + vv
                else:
                    acc[k] = acc.get(k, 0) + v
        os.remove(path)
    return merged


def winrate(pairs, a, b):
    for p in pairs:
        if p["a"] == a and p["b"] == b:
            return 100.0 * (p["wins_a"] + 0.5 * p["draws"]) / max(p["games"], 1)
        if p["a"] == b and p["b"] == a:
            return 100.0 * (p["wins_b"] + 0.5 * p["draws"]) / max(p["games"], 1)
    return None


def report(m):
    pairs, fs = m["pairs"], m["fighters"]
    ids = [i for i in m["ids"] if i in fs]  # --only : seulement les persos joués
    lines = []
    out = lines.append
    games = sum(p["games"] for p in pairs)
    out(f"IA {m['ai']} contre IA {m['ai']}, {m['n']} matchs par paire, {games} matchs")
    # Matrice.
    out("")
    out("| | " + " | ".join(i[:5] for i in ids) + " | total |")
    out("|---" * (len(ids) + 2) + "|")
    totals = {}
    for a in ids:
        w = sum(p["wins_a"] if p["a"] == a else p["wins_b"] for p in pairs if a in (p["a"], p["b"]))
        d = sum(p["draws"] for p in pairs if a in (p["a"], p["b"]))
        g = sum(p["games"] for p in pairs if a in (p["a"], p["b"]))
        totals[a] = 100.0 * (w + 0.5 * d) / max(g, 1)
        cells = []
        for b in ids:
            r = None if a == b else winrate(pairs, a, b)
            cells.append("·" if r is None else (f"**{r:.0f}**" if r > LIMIT or r < 100 - LIMIT else f"{r:.0f}"))
        out(f"| {a} | " + " | ".join(cells) + f" | {totals[a]:.1f} |")
    out("")
    bad = []
    for p in pairs:
        r = winrate(pairs, p["a"], p["b"])
        if r > LIMIT or r < 100 - LIMIT:
            bad.append((max(r, 100 - r), p["a"] if r >= 50 else p["b"], p["b"] if r >= 50 else p["a"]))
    bad.sort(reverse=True)
    spread = max(totals.values()) - min(totals.values())
    out(f"Global : {min(totals.values()):.1f} % ({min(totals, key=totals.get)}) à "
        f"{max(totals.values()):.1f} % ({max(totals, key=totals.get)}), écart {spread:.1f} points")
    out(f"Paires hors {100 - LIMIT}/{LIMIT} : {len(bad)} / {len(pairs)}"
        + ("" if not bad else " — " + ", ".join(f"{w} > {l} {r:.0f}" for r, w, l in bad[:12])))
    fight = sum(p["fight_frames"] for p in pairs)
    rounds = sum(p["rounds"] for p in pairs)
    tos = sum(p["timeouts"] for p in pairs)
    out(f"Durée moyenne d'un round : {fight / max(rounds, 1) / FPS:.1f} s ; "
        f"rounds au temps : {100.0 * tos / max(rounds, 1):.1f} %")
    # Par combattant.
    out("")
    out("| perso | victoires % | dégâts/s | touches/s | ses coups gardés % | garde % | "
        "spéciaux/min | projectiles/min | projections/min | contact % | distance px |")
    out("|---|---|---|---|---|---|---|---|---|---|---|")
    for a in ids:
        st = fs[a]
        ff = sum(p["fight_frames"] for p in pairs if a in (p["a"], p["b"]))
        close = sum(p["close"] for p in pairs if a in (p["a"], p["b"]))
        dist = sum(p["dist"] for p in pairs if a in (p["a"], p["b"]))
        sec = max(ff / FPS, 1)
        att = st["hits"] + st["blocked"]
        out(f"| {a} | {totals[a]:.1f} | {st['dmg'] / sec:.1f} | {st['hits'] / sec:.2f} | "
            f"{100.0 * st['blocked'] / max(att, 1):.0f} | {_guard_pct(a, m):.0f} | "
            f"{60 * st['specials'] / sec:.1f} | {60 * st['proj'] / sec:.1f} | "
            f"{60 * st['throws'] / sec:.1f} | {100.0 * close / max(ff, 1):.0f} | {dist / max(ff, 1):.0f} |")
    out("")
    out("Coups qui font le plus de dégâts (part des dégâts infligés) :")
    for a in ids:
        md = fs[a]["move_dmg"]
        tot = max(sum(md.values()), 1)
        top = sorted(md.items(), key=lambda kv: -kv[1])[:4]
        out(f"- {a} : " + ", ".join(f"{k} {100.0 * v / tot:.0f} %" for k, v in top))
    return "\n".join(lines), totals, bad


def pair_detail(m, a, b):
    """Détail d'une paire : par côté, dégâts/s, touches/s, coups gardés, dégâts par coup."""
    p = next((p for p in m["pairs"] if {p["a"], p["b"]} == {a, b}), None)
    if p is None or "stats_a" not in p:
        return f"{a}:{b} : pas de détail"
    sec = max(p["fight_frames"] / FPS, 1)
    lines = [f"{a} contre {b} : {winrate(m['pairs'], a, b):.0f} % sur {p['games']} matchs"]
    for fid, st in ((p["a"], p["stats_a"]), (p["b"], p["stats_b"])):
        md = st["move_dmg"]
        tot = max(sum(md.values()), 1)
        top = sorted(md.items(), key=lambda kv: -kv[1])[:6]
        lines.append(f"  {fid}: dégâts/s {st['dmg'] / sec:.1f}, touches/s {st['hits'] / sec:.2f}, "
                     f"gardés {100.0 * st['blocked'] / max(st['hits'] + st['blocked'], 1):.0f} %, "
                     f"garde {100.0 * st['blocks'] / max(st['blocks'] + st['hits_taken'], 1):.0f} %, "
                     f"projections {st['throws']}, spéciaux {st['move_use']}")
        lines.append("    dégâts : " + ", ".join(f"{k} {100.0 * v / tot:.0f} %" for k, v in top))
        wh = sorted(st.get("move_whiff", {}).items(), key=lambda kv: -kv[1])[:6]
        lines.append("    coups dans le vide : " + ", ".join(f"{k} {v}" for k, v in wh))
    return "\n".join(lines)


def _guard_pct(a, m):
    """% des coups reçus par a qu'il a gardés : ses gardes / (gardes + touches subies)."""
    st = m["fighters"][a]
    taken = st.get("hits_taken")
    if taken is None:
        return float("nan")
    return 100.0 * st["blocks"] / max(st["blocks"] + taken, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--ai", type=int, default=80)
    ap.add_argument("--seed", type=int, default=1000)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--boss", action="store_true")
    ap.add_argument("--ids", default="")
    ap.add_argument("--only", default="", help="paires a:b,c:d seules (vérifier des paires suspectes à grand n)")
    ap.add_argument("--detail", default="", help="détail des paires a:b,c:d")
    ap.add_argument("--save", default="", help="copie le résultat dans tests/out/balance_<NOM>.json")
    ap.add_argument("--md", default="", help="écrit le résumé Markdown dans ce fichier")
    ap.add_argument("--from", dest="src", default="", help="relit un JSON au lieu de simuler")
    args = ap.parse_args()
    t0 = time.time()
    m = json.load(open(args.src)) if args.src else run(args)
    text, totals, bad = report(m)
    print(text)
    for spec in filter(None, args.detail.split(",")):
        print(pair_detail(m, *spec.split(":")))
    if not args.src:
        print(f"\n({time.time() - t0:.0f} s)")
        json.dump(m, open(os.path.join(OUT, "balance.json"), "w"), indent=1)
        if args.save:
            json.dump(m, open(os.path.join(OUT, f"balance_{args.save}.json"), "w"), indent=1)
        ids = m["ids"]
        with open(os.path.join(OUT, "balance.csv"), "w") as f:
            f.write("id," + ",".join(ids) + ",total\n")
            for a in ids:
                row = []
                for b in ids:
                    if a == b:
                        row.append("")
                        continue
                    p = next((p for p in m["pairs"] if {p["a"], p["b"]} == {a, b}), None)
                    row.append("" if p is None else str(p["wins_a"] if p["a"] == a else p["wins_b"]))
                f.write(f"{a}," + ",".join(row) + f",{totals.get(a, 0.0):.1f}\n")
    if args.md:
        open(args.md, "w").write(text + "\n")


if __name__ == "__main__":
    main()
