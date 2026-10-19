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

## 2026-10-19 (soir) : réglages appliqués (accord de Julien), 100 rounds

Changements :
- onde de 14 cases, et flèche vers le chassé le plus proche quand le rayon est vide ;
- sorties ouvertes à 90 s, 4 s pour sortir ; capture en 0,5 s ;
- IA retravaillée :
  - pièges en embuscade sur le chemin de la planque, et pendant une fuite ;
  - fouilles là où un chassé a disparu, jamais la même cachette deux fois de suite ;
  - onde lancée là où l'on peut se cacher (malin) ;
  - garde des sorties ;
  - temps de réaction et mémoire des indices selon le niveau ;
  - vitesse du chasseur IA : 0,9 / 1 / 1,07 ;
  - chassés malins plus patients.

| chassés / chasseur | trouvés | sortis | restés cachés | ondes utiles | pièges posés / pris par round |
|---|---|---|---|---|---|
| normal / chasseur facile | 66 % | 24 % | 10 % | 24 % | 1,4 / 0,7 |
| normal / chasseur normal | 70 % | 23 % | 7 % | 25 % | 1,7 / 1,0 |
| normal / chasseur malin | 76 % | 21 % | 3 % | 25 % | 1,7 / 1,1 |
| chassés faciles / chasseur normal | 78 % | 19 % | 3 % | 28 % | 1,9 / 1,0 |
| chassés malins / chasseur normal | 74 % | 21 % | 5 % | 25 % | 1,7 / 0,9 |

- **Le chasseur** respecte maintenant l'ordre des niveaux (66 → 76 %), dans deux séries de suite.
- **Les chassés** : le « facile » se fait bien trouver plus souvent ; l'écart entre « normal » et « malin » reste dans le
  bruit (±10 points).
- **Contre un humain**, l'écart ressenti tiendra surtout à la vitesse et à la réaction du chasseur IA, à vérifier en
  jouant.

## 2026-10-20 (nuit) : idées de gameplay testées en A/B

Chaque idée a son drapeau `idee_*` dans `data/gordeka/rules.json` (1 = active), réglable en A/B par
`--gk-rules=idee_x:1`. 80 rounds par variante (deux séries de 40), chassés et chasseur « normal », 6 joueurs.
`bilan_stats.py` donne maintenant aussi la part de rounds gagnés par le chasseur, le plus long « chou blanc »
(plus longue période sans capture), l'attente d'un trouvé et le compte de chaque idée.

**Correctif au passage** : le chasseur « malin » refouillait sans fin une cachette vide (il prenait le
tremblement de fin de sa propre fouille pour un indice) : 24 fouilles par round, dont 99 % vides. Corrigé dans
`gk_ai.gd`. Avec le correctif, le malin redevient le plus fort : 73 % de trouvés au lieu de 64 %.

Situation de départ (normal / normal, 120 rounds) : 67 % trouvés, 30 % sortis, 3 % restés cachés ; **le
chasseur gagne 78 % des rounds** ; 1,4 évasion par round ; plus long chou blanc 59 s (médiane) ; un trouvé
attend 62 s en fantôme sans rien pouvoir faire.

| idée (drapeau) | ce que c'est | trouvés | chasseur gagnant | autre effet | verdict |
|---|---|---|---|---|---|
| départ | — | 67 % | 78 % | évasions 1,4/round | — |
| **chatouille** (`idee_chatouille`) | un fantôme qui touche le chasseur le fait rire : 60 % de vitesse pendant 1,5 s ; chaque fantôme une fois par 15 s, et le chasseur a 8 s de répit entre deux ; +1 point au fantôme | 66 % | 72 % | 6,5 chatouilles/round : les trouvés ont enfin quelque chose à faire | **retenue** (neutre pour l'équilibre, enlève le temps mort des fantômes) |
| ↳ sans répit | | 66 % | 78 % | 9 chatouilles/round : harcèlement | répit ajouté |
| **délivrance** (`idee_delivrance`) | un chassé libre et hors de vue qui reste 3 s près d'un fantôme le ramène en jeu ; **une seule par round** ; +2 points au sauveur | 56 % | 59 % | évasions 1,8/round ; 1 délivrance/round | **retenue** (rééquilibre en faveur des chassés, très « cache-cache de cour ») |
| ↳ sans limite, 2 s | | 26 % | 16 % | 3,2 délivrances/round ; 26 rounds sur 80 sans aucun trouvé | trop fort : limitée à 1 |
| ↳ 1 par round, 2 s | | 62 % | 69 % | | 3 s gardées (anneau plus lisible) |
| **gâteaux basques** (`idee_gateaux`) | 4 gâteaux au sol, dans des coins dégagés : +1 point et sprint (130 %) 4 s pour le chassé qui le ramasse ; le chasseur les voit aussi | 67 % | 76 % | 2,4 gâteaux/round : on sort de sa planque, prise de risque | **retenue** (neutre, donne des buts aux chassés) |
| **mouettes** (`idee_mouettes`) | 6 groupes de mouettes ; un chassé qui passe trop près les fait s'envoler en criant « kaio ! » (vu de tous, entendu par le chasseur IA à 12 cases) ; elles reviennent après 20 s | 61 % | 75 % | 3,2 envols/round ; le chasseur IA court après des indices déjà périmés | **retenue** (indice sonore lisible et drôle, légèrement favorable aux chassés) |
| cachette qui grince (`idee_grince`) | après 8 s dedans, la cachette craque toutes les 3 s (« crac ! », entendu à 9 cases) | 68 % | 79 % | fouilles réussies 26 % au lieu de 15 % | **écartée** : aide le chasseur, déjà gagnant |
| ↳ chassés IA qui sortent quand ça grince | | 72 % | 89 % | sortir expose davantage | écartée aussi (code retiré) |
| chasseur bredouille (`idee_bredouille`) | sans capture depuis 30 s, le chasseur a « le vent dans le dos » : 112 % de vitesse | 71 % | 85 % | chou blanc 49 s au lieu de 59 s | **écartée** : raccourcit les temps morts mais déséquilibre |

Sur 80 rounds, l'écart d'une série à l'autre est d'environ ±4 points sur les trouvés et ±6 points sur les
rounds gagnés par le chasseur.

### Réglage retenu : chatouille + délivrance (1 par round, 3 s) + gâteaux + mouettes

| chassés / chasseur | trouvés avant → après | chasseur gagnant avant → après | évasions/round | plus long chou blanc | temps fantôme/round |
|---|---|---|---|---|---|
| normal / normal (120 rounds) | 67 % → **61 %** | 78 % → **67 %** | 1,4 → 1,9 | 59 s → 58 s | 229 s → 190 s |
| normal / chasseur facile | 60 % → 52 % | 65 % → 58 % | 1,6 → 1,5 | 62 s → 69 s | |
| normal / chasseur malin (corrigé) | 73 % → 68 % | 90 % → 75 % | 0,7 → 0,7 | 54 s → 51 s | |
| facile / facile | 66 % → 59 % | 70 % → 62 % | 1,6 → 1,4 | 56 s → 61 s | |
| malin / malin (corrigé) | 77 % → 62 % | 88 % → 78 % | 0,9 → 1,0 | 52 s → 54 s | |
| 4 joueurs, normal / normal | 56 % → 52 % | 62 % → 52 % | 0,9 → 1,0 | 74 s → 66 s | 101 s → 83 s |

- L'ordre des niveaux du chasseur est gardé (52 → 61 → 68 % de trouvés).
- Le chasseur reste favori (2 rounds sur 3), mais moins écrasant : chaque chassé a plus d'une chance sur trois
  de gagner son round.
- Les trouvés ne se contentent plus de regarder : ils chatouillent (5/round) et un trouvé sur quatre environ revient en jeu.
- À vérifier avec Louis : si la chatouille est perçue comme gênante par l'enfant chasseur, monter
  `chatouille_repit`.
