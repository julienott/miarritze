# Gordeka : bilans d'équilibrage (IA contre IA)

Outil : `godot --headless --path . -- --scene=gk_game --gk-bots-only --speed=8 --gk-stats --gk-rounds=10
--gk-level=<niv> [--gk-hunter-level=<niv>] [--gk-rules=k:v,…]`, puis
`python3 tools/gordeka/bilan_stats.py <journaux>`. 6 joueurs (5 chassés), Port des Pêcheurs.

## 2026-10-19 : règles actuelles, 100 rounds

| chassés / chasseur | trouvés | sortis | restés cachés | ondes utiles | pièges posés / pris par round | entrées en cachette / round | trouvés en cachette |
|---|---|---|---|---|---|---|---|
| facile / facile | 64 % | 30 % | 6 % | 4 % | 0,7 / 0,25 | 1,8 | 2 (sur 34 fouilles) |
| normal / normal | 57 % | 38 % | 5 % | 6 % | 0,6 / 0,15 | 2,2 | 5 (sur 24) |
| malin / malin | 66 % | 28 % | 6 % | 6 % | 0,6 / 0,2 | 2,2 | 2 (sur 21) |
| normal / chasseur malin | 50 % | 42 % | 8 % | 3 % | 0,55 / 0,3 | 2,4 | 0 (sur 11) |
| normal / chasseur facile | 65 % | 28 % | 7 % | 4 % | 0,7 / 0,5 | 1,6 | 1 (sur 23) |

Constats :
- **Les niveaux d'IA ne changent presque rien** : le chasseur « malin » trouve même moins que le « normal ».
- **L'onde ne sert à rien** : 4 à 6 % des ondes montrent quelqu'un. Les chassés fuient dès 6 à 10 cases,
  donc presque toujours hors du rayon de 8.
- **Les pièges sont rares** : l'IA en pose moins d'un par round, et un sur trois environ est pris.
- **Les cachettes sont très sûres** : il y en a environ 2 par round, et 92 % des fouilles sont vides. Personne n'est
  éjecté au bout de 20 s.
- **Les sorties sont trop faciles** : un chassé sur trois s'échappe. La spec les veut difficiles.
- Rester caché jusqu'à la fin est rare (5 à 8 %) : on est trouvé, ou on sort.
- Une fois vu, on est presque toujours trouvé : environ 0,5 évasion par round, car la jauge de 0,3 s
  est très courte.

## Variantes (chassés et chasseur « normal », 20 rounds chacune)

| variante | trouvés | sortis | ondes utiles |
|---|---|---|---|
| règles actuelles | 57 % | 38 % | 6 % |
| `detect_radius` 14 | 70 % | 28 % | 17 % |
| sorties à 90 s, 4 s pour sortir | 75 % | 24 % | 9 % |
| les deux | 79 % | 18 % | 24 % |

Sur 20 rounds, l'écart d'un tirage à l'autre est d'environ ±10 points.
