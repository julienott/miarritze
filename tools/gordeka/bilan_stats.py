#!/usr/bin/env python3
"""Bilan des rounds IA contre IA (lignes « [gk-stats] {…} » de gk_game avec --gk-stats).

  bilan_stats.py <journal.log> [<journal.log> …]

Regroupe par (niveau des chassés, niveau du chasseur) et affiche les moyennes utiles à
l'équilibrage : part des chassés trouvés, comment (vue, fouille), utilité des ondes, des pièges
et des cachettes, sorties, durée.
"""
import json
import sys
from collections import defaultdict


def main() -> None:
    groupes = defaultdict(list)
    for chemin in sys.argv[1:]:
        for ligne in open(chemin, encoding="utf-8"):
            if ligne.startswith("[gk-stats] "):
                r = json.loads(ligne[len("[gk-stats] "):])
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
        print(f"  ondes {tot('ondes')} ({tot('ondes') / n:.1f}/round), utiles {tot('ondes_utiles')} "
              f"({100 * tot('ondes_utiles') / max(tot('ondes'), 1):.0f} %), chassés montrés {tot('montres')}, "
              f"trouvés < 12 s après une onde {tot('trouves_apres_onde')}")
        print(f"  pièges posés {tot('pieges_poses')}, pris {tot('pieges_pris')}, "
              f"captures < 8 s après un piège pris {tot('trouves_apres_piege')}")
        print(f"  entrées en cachette {tot('entrees_cachette')}, éjections (20 s) {tot('ejections_cachette')}, "
              f"trouvés en cachette {tot('trouves_en_cachette')}")
        print(f"  évasions (jauge entamée puis perdue) {tot('evasions_de_vue')}")


if __name__ == "__main__":
    main()
