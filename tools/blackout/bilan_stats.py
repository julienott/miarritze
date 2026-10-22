#!/usr/bin/env python3
"""Bilan des rounds IA contre IA (lignes « [bk-stats] {…} » de bk_game avec --bk-stats).

  bilan_stats.py <journal.log> [<journal.log> …]

Regroupe par (niveau des chassés, niveau du chasseur) et affiche les moyennes utiles à
l'équilibrage : part des chassés trouvés, comment (vue, fouille), coups spéciaux, cachettes,
sorties, durée.
"""
import json
import sys
from collections import defaultdict


def main() -> None:
    groupes = defaultdict(list)
    for chemin in sys.argv[1:]:
        for ligne in open(chemin, encoding="utf-8"):
            if ligne.startswith("[bk-stats] "):
                r = json.loads(ligne[len("[bk-stats] "):])
                groupes[(r["niveau"], r["niveau_chasseur"])].append(r)
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


if __name__ == "__main__":
    main()
