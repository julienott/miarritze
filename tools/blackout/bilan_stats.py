#!/usr/bin/env python3
"""Bilan des rounds IA contre IA (lignes « [bk-stats] {…} » de bk_game avec --bk-stats).

  bilan_stats.py <journal.log> [<journal.log> …]

Regroupe par (niveau des chassés, niveau du chasseur) et affiche les moyennes utiles à
l'équilibrage : part des chassés trouvés, comment (vue, fouille), coups spéciaux, cachettes,
sorties, durée. Puis, tous niveaux confondus : taux de trouvés par perso du chasseur, et lancers et
effets qui ont pris par coup (coups jamais lancés signalés).
"""
import json
import sys
from collections import defaultdict


def main() -> None:
    groupes = defaultdict(list)
    tous = []
    for chemin in sys.argv[1:]:
        for ligne in open(chemin, encoding="utf-8"):
            if ligne.startswith("[bk-stats] "):
                r = json.loads(ligne[len("[bk-stats] "):])
                groupes[(r["niveau"], r["niveau_chasseur"])].append(r)
                tous.append(r)
    for (niv, nivc), rs in sorted(groupes.items()):
        n = len(rs)
        tot = lambda k: sum(r.get(k, 0) for r in rs)
        chasses = tot("chasses")
        trouves = tot("trouves")
        t = [x for r in rs for x in r["t_trouves"]]
        print(f"\n== chassés {niv} / chasseur {nivc} : {n} rounds ==")
        print(f"  trouvés {trouves}/{chasses} ({100 * trouves / max(chasses, 1):.0f} %), "
              f"sortis {tot('sorties')} ({100 * tot('sorties') / max(chasses, 1):.0f} %), "
              f"restés cachés {tot('restes_caches')} ({100 * tot('restes_caches') / max(chasses, 1):.0f} %)")
        rafle = sum(1 for r in rs if r["trouves"] == r["chasses"])
        vide = sum(1 for r in rs if r["trouves"] == 0)
        print(f"  rounds où le chasseur trouve tout le monde : {rafle} ; personne : {vide} ; "
              f"durée moyenne {sum(r['duree'] for r in rs) / n:.0f} s")
        if t:
            t.sort()
            print(f"  instant des captures : médiane {t[len(t) // 2]:.0f} s, premier quart {t[len(t) // 4]:.0f} s")
        print(f"  par la vue {tot('vue')}, par une fouille {tot('fouille')} ; "
              f"fouilles réussies {tot('fouille_ok')} / {tot('fouille_ok') + tot('fouille_vide')}")
        print(f"  coups spéciaux : chasseur {tot('coups_chasseur')} ({tot('coups_chasseur') / n:.1f}/round), "
              f"chassés {tot('coups_chasse')}, chasseur touché {tot('coups_touche')}, "
              f"trouvés < 10 s après un coup du chasseur {tot('trouves_apres_coup')}")
        print(f"  entrées en cachette {tot('entrees_cachette')}, éjections (20 s) {tot('ejections_cachette')}, "
              f"trouvés en cachette {tot('trouves_en_cachette')}")
        print(f"  évasions (jauge entamée puis perdue) {tot('evasions_de_vue')} ({tot('evasions_de_vue') / n:.1f}/round)")
        # Plaisir de jeu : rounds gagnés par le chasseur, temps morts (plus longue période sans
        # capture, attente des fantômes).
        gagnes = sum(1 for r in rs if r["trouves"] * 2 > r["chasses"])
        trous = []
        for r in rs:
            ts = sorted(r["t_trouves"])
            bornes = [0.0] + ts + [r["duree"]]
            trous.append(max(b - a for a, b in zip(bornes, bornes[1:])))
        trous.sort()
        attente = [r["duree"] - x for r in rs for x in r["t_trouves"]]
        print(f"  chasseur gagnant {gagnes}/{n} ({100 * gagnes / n:.0f} %) ; plus long chou blanc : "
              f"médiane {trous[len(trous) // 2]:.0f} s ; attente moyenne d'un trouvé "
              f"{sum(attente) / max(len(attente), 1):.0f} s"
              + (f" (temps fantôme mesuré {tot('fantome_s') / n:.0f} s/round)" if tot('fantome_s') else ""))
        idees = [(k, tot(k)) for k in ("chatouilles", "delivres", "grincements", "gateaux", "mouettes",
                                       "trouves_apres_bruit") if tot(k)]
        if idees:
            print("  idées : " + ", ".join(f"{k} {v} ({v / n:.1f}/round)" for k, v in idees)
                  + (f", vent dans le dos {tot('elan_s') / n:.0f} s/round" if tot('elan_s') else ""))
        if tot("captures_annulees"):
            print(f"  captures annulées (Endurance) {tot('captures_annulees')}")
    par_perso_et_coup(tous)


def par_perso_et_coup(rs: list) -> None:
    """Taux de trouvés par perso chasseur ; lancers et effets qui ont pris par coup."""
    persos = defaultdict(lambda: [0, 0, 0])
    lancers = defaultdict(int)
    touches = defaultdict(int)
    for r in rs:
        p = persos[r.get("chasseur_perso", "?")]
        p[0] += 1
        p[1] += r["trouves"]
        p[2] += r["chasses"]
        for k, v in r.get("coups_par", {}).items():
            lancers[k] += v
        for k, v in r.get("touches_par", {}).items():
            touches[k] += v
    n = max(len(rs), 1)
    print(f"\n== par perso chasseur ({len(rs)} rounds) ==")
    for nom, (k, t, c) in sorted(persos.items(), key=lambda x: -x[1][1] / max(x[1][2], 1)):
        print(f"  {nom:<11} {k:>3} rounds  trouvés {t:>3}/{c:<3} ({100 * t / max(c, 1):3.0f} %)")
    try:
        d = json.load(open("data/blackout/coups.json", encoding="utf-8"))
        ids = [(c["id"], role) for p in d["persos"].values() for role, c in p.items()]
    except OSError:
        ids = [(k, "?") for k in lancers]
    print("\n== par coup (lancers, effets qui ont pris ; /round joué par ce rôle) ==")
    for cid, role in sorted(ids, key=lambda x: -lancers.get(x[0], 0)):
        print(f"  {cid:<20} {role:<8} lancés {lancers.get(cid, 0):>4}  pris {touches.get(cid, 0):>4}"
              + ("   ← jamais lancé" if not lancers.get(cid) else ""))
    print(f"  total : {sum(lancers.values())} lancers ({sum(lancers.values()) / n:.1f}/round)")


if __name__ == "__main__":
    main()
