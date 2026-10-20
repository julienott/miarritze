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

## 2026-10-20 : tension et mouvement (demande de Julien : « plus tendu, beaucoup de near miss, beaucoup de mouvements »)

Outil : `python3 tools/gordeka/ab_tension.py run <variante> [--rules k:v,…] [--niveaux …] [--rounds 80]`
(Godot headless en `--fixed-fps 60` : même pas de temps qu'en jeu, aussi vite que le processeur ; 9 processus en
parallèle, ~8 min pour 3 × 80 rounds), puis `ab_tension.py tableau <variantes…>`. Journaux et `bilan.json` dans
`tests/out/gordeka_ab/<variante>/`. 6 joueurs, chiffres par round : **moyenne ± écart-type [± erreur type]**.

Nouvelles mesures (`--gk-stats`, `GkGame.tension_keys`) :
- **frôlement** : le chasseur passe à moins de 2 (ou 3) cases d'un chassé qu'il ne trouve pas (épisode refermé au-delà
  de 2,5 cases) ;
- **vu-perdu** : un chassé entre dans la vue du chasseur puis en sort 0,4 s sans être trouvé ;
- **mouvement** : cases parcourues par minute et par chassé ; part du temps en mouvement, immobile, en cachette ;
  **changements de planque** (immobile 3 s à plus de 4 cases de la planque d'avant) ; sorties de cachette en fuite ;
- **captures au dernier moment** : en pleine course, moins de 15 s après une évasion, dans les 30 dernières s.

### Leviers essayés (80 rounds par niveau ; chassés « normal », chasseur facile / normal / malin)

| variante | chasseur gagne % | trouvés % | frôlements < 2 | vu-perdu | cases/min | en mouvement % |
|---|---|---|---|---|---|---|
| **départ** (base) | 42 / 62 / 72 | 49 / 57 / 66 | 0,3 / 0,3 / 0,1 | 1,9 / 2,2 / 0,9 | 100 / 99 / 91 | 35 / 35 / 32 |
| a. détection progressive (0,35 s → 1,4 s) | 31 / 44 / 69 | 38 / 48 / 59 | 0,3 / 0,2 / 0,2 | **3,7 / 3,1 / 2,4** | 101 / 100 / 98 | 35 / 35 / 34 |
| a'. détection plus vive (0,3 s → 1,0 s) | 34 / 68 / 62 | 42 / 56 / 58 | 0,2 / 0,3 / 0,3 | **2,3 / 3,4 / 1,9** | 98 / 97 / 94 | 34 / 34 / 33 |
| c. mouvement | 56 / 65 / 72 | 54 / 57 / 63 | 0,4 / 0,3 / 0,1 | 1,9 / 2,5 / 0,8 | **149 / 143 / 141** | **52 / 50 / 49** |
| d. carte | 51 / 56 / 75 | 48 / 54 / 63 | **0,6 / 0,5 / 0,2** | 2,0 / 2,4 / 0,8 | 99 / 99 / 97 | 35 / 35 / 34 |
| d + ronde du chasseur derrière les objets | 46 / 56 / 61 | 47 / 56 / 56 | 0,4 / 0,4 / 0,2 | 1,9 / 2,2 / 0,9 | 103 / 97 / 99 | 36 / 34 / 34 |
| a + c + d | 35 / 56 / 71 | 41 / 52 / 61 | 0,4 / 0,3 / 0,4 | 3,6 / 3,3 / 2,7 | 151 / 153 / 152 | 53 / 53 / 53 |
| a' + c + d + ronde | 41 / 61 / 68 | 42 / 58 / 59 | 0,6 / 0,6 / 0,2 | 2,8 / 3,1 / 2,5 | 147 / 151 / 153 | 51 / 53 / 53 |

Erreur type sur 80 rounds : ±5 à 6 points sur « chasseur gagne », ±3 sur « trouvés », ±0,1 sur les frôlements,
±0,2 à 0,3 sur vu-perdu, ±2 cases/min. b (frisson) ne change rien aux IA : pas de ligne.

Constats :
- **Les frôlements à moins de 2 cases restent rares** (moins d'un par round) : à moins de 1,9 case, le chasseur voit
  tout autour de lui, un frôlement suppose donc un mur entre les deux. La carte les double (0,3 → 0,6) sans les rendre
  fréquents. **Le « presque trouvé » que l'on vit vraiment, c'est le vu-perdu** : la détection progressive le
  multiplie par 1,5 à 3, et chaque fois tout le monde le voit (« ? » au-dessus du chasseur, « ouf ! »).
- **La détection lente (1,4 s au bout du cône) affaiblit trop le chasseur** (62 → 44 % au normal). À 0,3 s / 1,0 s,
  l'équilibre revient.
- **Le levier mouvement fait bouger** : +50 % de cases parcourues, la moitié du temps en mouvement au lieu d'un tiers,
  deux fois plus d'entrées en cachette et de gâteaux ; il rend les chassés un peu plus faciles à trouver par le
  chasseur facile.
- **La ronde derrière les objets** n'apporte ni frôlements ni captures (le malin devient même moins bon) : écartée.
- Les sorties restent la grande porte de victoire des chassés (40 à 50 % des chassés sortent) ; un levier simple si
  le chasseur doit regagner : `exits_open_at` ou `extract_hold`.

### Combinaison retenue (à valider par Julien) : détection 0,3 s → 1,0 s + frisson + mouvement + carte, 120 rounds

| chassés / chasseur | chasseur gagne % (départ → retenu) | trouvés % | frôlements < 2 | vu-perdu | cases/min | en mouvement % | entrées en cachette |
|---|---|---|---|---|---|---|---|
| normal / facile | 42 → 56 | 49 → 53 | 0,3 → 0,4 | 1,9 → **3,1** | 100 → **153** | 35 → **53** | 2,6 → 3,9 |
| normal / normal | 62 → **59** | 57 → 59 | 0,3 → 0,4 | 2,2 → **3,3** | 99 → **149** | 35 → **52** | 2,3 → 3,9 |
| normal / malin | 72 → 73 | 66 → 61 | 0,1 → 0,4 | 0,9 → **2,7** | 91 → **149** | 32 → **52** | 2,4 → 3,8 |
| facile / facile | 57 → 60 | 55 → 54 | 0,3 → 0,4 | 2,0 → 2,7 | 128 → 174 | 45 → 61 | 3,7 → 4,3 |
| malin / malin | 66 → 59 | 58 → 56 | 0,1 → 0,2 | 0,8 → **2,9** | 69 → **123** | 24 → **43** | 1,7 → 2,8 |

- Au niveau normal, le chasseur gagne toujours environ 3 rounds sur 5 (62 → 59 %, dans le bruit) ; il reste le
  favori, l'objectif de 2 sur 3 est à peine en dessous, comme avant.
- Les « presque trouvés » visibles (vu-perdu) passent de ~2 à ~3 par round, et triplent chez les malins.
- Les chassés bougent 1,5 fois plus et passent la moitié du temps en mouvement.
- **À surveiller** : l'écart facile / normal du chasseur s'est réduit (56 / 59 %, contre 42 / 62 %) ; si Louis
  trouve le chasseur facile trop fort, baisser `ai.facile.hunter_speed` (0,9) ou monter `hunter_react`.

## 2026-10-20 (soir) : poursuite (question de Julien, `idee_poursuite`, désactivée)

« Est-ce que ça servirait à la tension si, quand un chasseur détecte un chassé, le chasseur et le chassé avaient une
vitesse ×1,2 ? », avec la précision « valable pour tous les chassés visibles ». Mesure sur la combinaison retenue,
120 rounds par niveau (chassés normaux, chasseur facile / normal / malin). Déclenchement au « ? » (jauge à 30 %),
3 s, sauf « tant que vu » (rechargé tant que le chasseur le voit, puis 1 s).

| variante | chasseur gagne % | trouvés % | vu-perdu | poursuites / round | durée moyenne (s) | finies en capture / round | cases/min | en mouvement % |
|---|---|---|---|---|---|---|---|---|
| sans poursuite (retenu) | 56 / 59 / 73 | 53 / 59 / 61 | 3,1 / 3,3 / 2,7 | – | – | – | 153 / 149 / 149 | 53 / 52 / 52 |
| ×1,2 les deux, tous les chassés vus | 46 / 55 / 71 | 48 / 52 / 64 | 3,1 / 3,2 / 2,3 | 4,2 / 4,4 / 4,5 | 1,2 / 1,2 / 0,9 | 3,3 / 3,5 / 4,0 | 149 / 152 / 151 | 52 |
| ×1,2 les deux, chassé repéré seul | 50 / 62 / 72 | 49 / 57 / 62 | 3,1 / 3,3 / 2,3 | 4,3 / 4,7 / 4,5 | 1,2 / 1,2 / 0,8 | 3,3 / 3,7 / 4,0 | 152 / 147 / 151 | 52 |
| ×1,2 les deux, tant que vu (tous) | 49 / 65 / 63 | 51 / 58 / 59 | 2,9 / 3,1 / 2,0 | 4,4 / 4,7 / 4,2 | 0,8 / 0,8 / 0,7 | 3,4 / 3,7 / 3,7 | 153 / 151 / 149 | 52 |
| ×1,2 chassés seulement (tous) | 48 / 52 / 77 | 46 / 52 / 64 | 3,2 / 3,0 / 2,2 | 4,2 / 4,4 / 4,5 | 1,2 / 1,1 / 0,9 | 3,1 / 3,5 / 4,1 | 152 / 153 / 153 | 53 |
| chasseur ×1,15, chassés ×1,25 (tous) | 52 / 49 / 80 | 50 / 48 / 66 | 3,1 / 2,7 / 2,2 | 4,4 / 4,2 / 4,7 | 1,2 / 1,1 / 0,9 | 3,4 / 3,3 / 4,2 | 152 / 149 / 147 | 51 |

Erreur type : ±4 à 5 points sur « chasseur gagne », ±0,2 sur vu-perdu et sur les poursuites.

- **La poursuite ne crée presque pas de vraies courses** : environ 4,5 par round, mais elles durent ~1 s et 3 sur 4
  finissent en capture. Au « ? », la jauge est déjà au tiers et se remplit en moins d'une seconde de plus : l'élan
  arrive trop tard pour changer l'issue. Les poursuites dont on s'échappe restent ~1 par round, comme avant.
- **Le vu-perdu ne monte pas** (et baisse un peu chez les malins), les cases parcourues et le temps en mouvement ne
  bougent pas.
- **Équilibre** : « chassé repéré seul » est la seule variante neutre (62 % au normal) ; « tous les chassés vus »
  coûte ~4 points au chasseur normal (dans le bruit) et 10 au facile ; les variantes asymétriques désordonnent les
  niveaux (normal 49-52 %, malin 77-80 %).
- Verdict : **pas de gain de tension mesurable, à ne pas activer en l'état.** Pour qu'une poursuite existe vraiment, il
  faudrait la déclencher plus tôt (`poursuite_seuil` bas) avec une capture plus lente (`detection_temps_loin`), à
  essayer en jouant : l'IA ne rend pas le plaisir d'une course.
