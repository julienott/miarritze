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

## 2026-10-21 : carte Plage de la Côte des Basques (`tools/gordeka/make_plage.py`, SPEC-GORDEKA §8)

Outil : `ab_tension.py run <essai> --map plage[_<variante>]` (variantes : `make_plage.py --variante=<nom>`), chassés
« normal », 6 joueurs, règles retenues du port (détection progressive, frisson, mouvement, gâteaux, mouettes,
chatouille, délivrance). Diagnostic des zones : `analyse_carte.py plage --ab <essai>`. Les essais d'écrémage ont 64
rounds (erreur type ±6 points sur « chasseur gagne ») ; les essais complets 120 rounds par niveau (±4 à 5).

**Attention** : `ab_tension.py` arrête tout au bout de `--timeout` (3600 s par défaut). Avec la machine chargée
(plusieurs cartes mesurées en même temps), v2 et la première série de la carte retenue ont été coupées avant la fin
du niveau malin : il faut passer `--timeout 30000` pour les séries complètes.

| essai | rounds (F / N / M) | chasseur gagne % (erreur type) | trouvés % | sortis % | vu-perdu | frôlements < 2 | cases/min | en mouvement % | entrées en cachette |
|---|---|---|---|---|---|---|---|---|---|
| v1 : premier jet (écrémage) | 30 / – / – | 37 / – / – (±9 / – / –) | 37 / – / – | 63 / – / – | 4.1 / – / – | 0.3 / – / – | 140 / – / – | 49 / – / – | 5.0 / – / – |
| v2 : tunnels au palier du milieu de l'escalier et de la rampe, canot au bout d'un ponton | 120 / 120 / 33 | 40 / 51 / 55 (±4 / ±5 / ±9) | 44 / 50 / 50 | 56 / 50 / 50 | 4.0 / 4.2 / 3.1 | 0.4 / 0.4 / 0.5 | 133 / 131 / 133 | 46 / 46 / 46 | 4.7 / 4.7 / 4.5 |
| v2 + abris sur le sable et 2 cachettes | 57 / – / – | 19 / – / – (±5 / – / –) | 30 / – / – | 70 / – / – | 4.5 / – / – | 0.4 / – / – | 136 / – / – | 47 / – / – | 5.4 / – / – |
| v2 sans tunnel vers l'escalier, Basta plus bas | 64 / – / – | 22 / – / – (±5 / – / –) | 34 / – / – | 66 / – / – | 4.8 / – / – | 0.4 / – / – | 137 / – / – | 47 / – / – | 5.1 / – / – |
| idem + rampe sans tunnel | 64 / – / – | 36 / – / – (±6 / – / –) | 43 / – / – | 56 / – / – | 4.4 / – / – | 0.3 / – / – | 140 / – / – | 49 / – / – | 4.7 / – / – |
| v2 avec 14 cachettes | 64 / – / – | 25 / – / – (±5 / – / –) | 35 / – / – | 65 / – / – | 3.8 / – / – | 0.4 / – / – | 136 / – / – | 47 / – / – | 5.2 / – / – |
| v2 avec 12 cachettes | 64 / – / – | 30 / – / – (±6 / – / –) | 36 / – / – | 64 / – / – | 3.9 / – / – | 0.2 / – / – | 131 / – / – | 45 / – / – | 5.6 / – / – |
| v2 + talus (les montées se voient d'en bas) | 64 / 64 / – | 36 / 47 / – (±6 / ±6 / –) | 38 / 45 / – | 62 / 55 / – | 3.5 / 4.4 / – | 0.3 / 0.3 / – | 133 / 132 / – | 46 / 46 / – | 4.9 / 5.0 / – |
| talus + bande du bord de l'eau rattachée aux plages | 64 / 64 / – | 47 / 62 / – (±6 / ±6 / –) | 47 / 56 / – | 53 / 44 / – | 3.9 / 4.2 / – | 0.3 / 0.4 / – | 131 / 135 / – | 46 / 47 / – | 4.6 / 3.9 / – |
| zones + moins de cabines et de gros rochers | 32 / 64 / – | 53 / 66 / – (±9 / ±6 / –) | 52 / 57 / – | 48 / 43 / – | 4.5 / 4.4 / – | 0.4 / 0.3 / – | 137 / 135 / – | 48 / 47 / – | 4.0 / 4.1 / – |
| idem, première série complète (coupée) | 54 / 42 / – | 54 / 74 / – (±7 / ±7 / –) | 48 / 64 / – | 52 / 36 / – | 4.3 / 4.3 / – | 0.4 / 0.4 / – | 129 / 133 / – | 45 / 46 / – | 4.5 / 3.5 / – |
| **retenue** (idem + correctifs de zones et du ponton) | 120 / 120 / 120 | **40 / 56 / 78** (±4 / ±5 / ±4) | 45 / 52 / 68 | 55 / 48 / 32 | 4.3 / 4.4 / 3.2 | 0.4 / 0.3 / 0.4 | 134 / 131 / 129 | 46 / 45 / 45 | 4.7 / 4.5 / 3.8 |
| forte (avant correctifs) sans tunnel vers l'escalier | – / 64 / – | – / 62 / – (– / ±6 / –) | – / 58 / – | – / 42 / – | – / 4.4 / – | – / 0.4 / – | – / 132 / – | – / 46 / – | – / 4.5 / – |
| retenue + gros rochers du Basta bas | 120 / 38 / – | 43 / 61 / – (±5 / ±8 / –) | 46 / 60 / – | 54 / 40 / – | 4.4 / 4.2 / – | 0.5 / 0.3 / – | 132 / 129 / – | 46 / 45 / – | 4.7 / 3.8 / – |
| idem + rochers du Port-Vieux bas | – / 64 / – | – / 59 / – (– / ±6 / –) | – / 52 / – | – / 48 / – | – / 4.0 / – | – / 0.3 / – | – / 132 / – | – / 46 / – | – / 4.6 / – |
| pour comparer : Port des Pêcheurs v2 (série « carte_v2 ») | 120 / 120 / 120 | 52 / 71 / 76 (±5 / ±4 / ±4) | 51 / 62 / 65 | 49 / 38 / 35 | 2.6 / 3.0 / 2.3 | 0.4 / 0.4 / 0.3 | 150 / 153 / 146 | 52 / 53 / 51 | 3.9 / 3.8 / 3.5 |
| retenue avec grottes sombres (`idee_grottes:1`) | – / 120 / – | – / 52 / – (– / ±5 / –) | – / 53 / – | – / 46 / – | – / 3.9 / – | – / 0.3 / – | – / 133 / – | – / 46 / – | – / 4.6 / – |

Ce que disent les essais :
- **Les sorties décident du round** : comme au port, presque tous les chassés encore libres à 90 s s'échappent ; le
  chasseur gagne s'il en a trouvé trois avant. Au premier jet, un chassé sur deux à deux sur trois s'échappait par les
  sorties du haut (escalier, rampe), que les tunnels rendaient sûres.
- **Plus d'abris ou moins de cachettes, c'est pire pour le chasseur** : sans cachette, les chassés ne restent pas
  enfermés 20 s loin des sorties, ils filent ; plus d'abris sur le sable, ils s'échappent de la vue plus souvent.
- **Ce qui a aidé le chasseur** : rattacher la bande de sable mouillé aux plages (il n'y a plus une zone « Bord de
  l'eau » de 79 cases sans abri que la ronde du chasseur IA allait inspecter), moins de cabines et de gros rochers
  (le haut d'un objet masque un chassé caché derrière : moins de planques à 2 cases près).
- **Les écrémages à 64 rounds trompent** : les meilleurs (forte 66 %, rochers 70 % au normal) retombent sur 120 rounds
  (56 %, 61 %). Seuls les écarts de plus de ~12 points s'y lisent.
- **Le reste est dans le bruit** : talus (visibilité des montées), sans tunnel vers l'escalier, rochers bas au Basta ou
  au Port-Vieux. Trois itérations sans gain de suite : arrêt, carte « retenue » fixée.

### Carte retenue (à valider par Julien)

Plan et contenu : SPEC-GORDEKA §8 (« Plage de la Côte des Basques »). Séries complètes : 120 rounds par niveau (le malin dans une série à part, la première ayant été coupée à 78 rounds : 67 %).

- **Ordre des niveaux** respecté : le chasseur gagne 40 % des rounds en facile, 56 % en normal, 78 % en malin (port : 52 / 71 / 76).
- **Le chasseur reste en dessous de l'objectif** (2 rounds sur 3 au normal) : 56 % contre 71 % au port. Le
  sable laisse filer plus de chassés vers les sorties ; quand les deux sorties du haut (escalier et rampe) sont
  ouvertes ensemble, le chasseur ne gagne que 51 % des rounds (tous niveaux), contre 55 à 64 % avec une sortie du bas.
  Pistes si Julien veut un chasseur plus fort ici : une sortie du haut de moins (la rampe sans sortie, une
  autre en bas), ou des réglages par carte (ouverture des sorties plus tard sur la plage), à mesurer.
- **Presque trouvés** : 4,4 vu-perdu par round au normal (3,0 au port), 0,3 frôlement à moins de 2 cases ; les
  chassés bougent un peu moins qu'au port (131 cases/min, 45 % du temps en mouvement, contre 153 et 53 %).
- **Aucune zone morte** (`analyse_carte.py`) ; les 18 cachettes servent toutes (0,2 à 0,3 entrée par round chacune) ;
  les 4 sorties servent (par ouverture : escalier 1,4 chassé, rampe 1,1, digue 0,9, ponton 0,8).
- **Grottes sombres** (`idee_grottes:1`, vue du chasseur à 4 cases dans les grottes et tunnels), 120 rounds au
  normal : le chasseur gagne 52 % au lieu de 56 % (dans le bruit), 3,9 vu-perdu au lieu de 4,4 ; elle ne change pas l'équilibre. Laissée désactivée (à essayer en jouant : c'est surtout un frisson de plus).

## 2026-10-21 : Parc Mazon (nouvelle carte, `tools/gordeka/make_parc_mazon.py --version N`)

`ab_tension.py run … --map <variante>`, 6 joueurs, chassés « normal », chasseur facile / normal / malin, 120 manches
par niveau (sauf mention) ; instantané du projet pour toutes les mesures. Le port mesuré avec le même code et les
mêmes règles sert de référence. Erreur type : ±4 à 5 points sur « chasseur gagne ».

| essai | changement | sol (cases) | cachettes | chasseur gagne % | trouvés % | sortis % | vu-perdu | cases/min |
|---|---|---|---|---|---|---|---|---|
| port (référence) | — | 2 035 | 16 | 59 / 58 / 80 | 54 / 54 / 70 | 46 / 46 / 30 | 3,0 / 2,9 / 2,3 | 151 / 149 / 144 |
| v1 | premier plan : 15 zones, massifs fins, sorties au gardien, au potager, aux petits | 2 771 | 26 | 32 / 43 / 58 | 35 / 43 / 52 | 65 / 57 / 48 | 3,0 / 2,9 / 2,4 | 133 / 136 / 132 |
| v2 | sorties exposées (rive nord de la mare au bout du pont, coin des platanes), labyrinthe aéré | 2 795 | 26 | 32 / 45 (75 manches) / – | 39 / 47 / – | 61 / 52 / – | 3,1 / 3,4 / – | 138 / 131 / – |
| v3 | abords des sorties dégagés (arbres et cachettes à plus de 6 cases) | 2 796 | 26 | 27 (117 manches) / – / – | 35 | 65 | 3,0 | 135 | 
| **v4 (retenue)** | chaque zone rend son bord d'une case aux massifs : carte de la taille du port, de vraies allées entre les zones | 2 066 | 26 | **38 / 54 / 58** | 44 / 50 / 56 | 56 / 50 / 44 | 2,8 / 3,1 / 2,0 | 142 / 140 / 139 |
| v5 | v4 + sortie au bord est de la pelouse (au lieu des platanes), allée du fronton hors zones, 4 cachettes de moins | 2 071 | 22 | 32 / 44 (61 manches) / – | 40 / 45 | 60 / 55 | 2,8 / 2,8 | 137 / 142 |
| v6 | v4 + sorties poussées aux coins (portail des petits au sud-ouest, mare au nord-est) | 2 065 | 26 | 35 / 18 (17 manches) / – | 42 | 58 | 2,7 | 143 |
| **final** (v4, deux cachettes coincées par le nouveau bord déplacées) | | 2 066 | 26 | **35 / 49 / 63** | 41 / 51 / 56 | 59 / 49 / 44 | 3,1 / 2,9 / 2,2 | 143 / 140 / 137 |

- **La taille compte le plus** : à 2 800 cases de sol (37 % de plus que le port), le chasseur reste au centre (terrain,
  kiosque, allée du fronton : 37 % de son temps) et ne voit presque jamais les salles du pourtour (potager 2 %, platanes
  2 %) où les chassés attendent l'ouverture des sorties. Ramenée à la taille du port (v4), la carte gagne ~10 points.
- **Personne ne reste caché jusqu'au bout** (0 par manche, au port comme au parc) : tout chassé non trouvé finit par
  sortir, le chasseur gagne en attrapant sur le chemin des sorties. Une sortie près d'une zone où l'on se cache
  (labyrinthe, bosquet) laisse filer 1,8 chassé par ouverture ; au bout du pont de la mare, à découvert, 1,1.
- v3, v5, v6 n'apportent rien (dans le bruit ou en recul) : arrêt après deux essais sans gain, v4 retenue. v3, v5 et
  v6 ont été arrêtés avant 120 manches par niveau, nettement derrière v4.
- **Objectif non atteint** : au niveau normal le chasseur gagne 49 % (port : 58 %), loin des 2/3 ; le chasseur facile
  est bien plus faible qu'au port (35 % contre 59 %). Les niveaux restent dans l'ordre. Leviers hors carte, à essayer
  sur les deux cartes : `exits_open_at`, `extract_hold`.
- Usage (essai final, 360 manches) : les 26 cachettes servent toutes (39 à 66 entrées chacune), toutes les zones sont
  visitées (buvette et potager le moins, 2 à 3 % du temps des chassés), les captures et les « vu puis perdu » ont lieu
  d'abord dans les allées entre les zones (168 et 169), puis l'aire des grands, le labyrinthe et la grande pelouse.
- Statistiques : les portillons sont posés sur le bord rendu aux massifs, hors du rectangle de leur zone ; le jeu note
  donc ces sorties « ? » dans `sorties_lieux` (sans effet sur le jeu).

## 2026-10-21 : carte v3 du Port des Pêcheurs (demande de Julien : « une meilleure map »)

Demande : zones moins vides, mieux segmentées par des couloirs, déco plus riche et vivante, le tout bien
balancé ; itérer jusqu'à ce que deux essais de suite n'apportent plus rien de net. Grille de lecture : Among Us
(salles reliées par des couloirs étroits, pas de cul-de-sac, lignes de vue coupées aux entrées, une boucle et des
raccourcis, un repère et une raison d'y aller par salle) et jeux d'extraction (sorties visibles mais exposées,
plusieurs approches, zones calmes et chaudes, tension qui monte avec le temps, récompense au risque).

Outils :
- `tools/gordeka/analyse_carte.py <carte> [--ab <variantes>] [--png <dossier>]` : vides (aucun objet à 2 ou
  3 cases), lignes de vue (rayon moyen sur 16 directions, part des cases d'où un rayon file à 15 cases, part
  visible du disque de 7 cases), cachettes et objets hauts par zone, graphe des zones (liaisons, boucles,
  culs-de-sac, ponts), largeur des couloirs, sorties (distance, approches, exposition) ; avec `--ab`, où se
  jouent les rounds (temps des chassés et du chasseur, captures, vu-perdu, frôlements par zone), entrées par
  cachette, sorties prises, zones mortes, et cartes de chaleur en PNG.
- `--gk-stats` journalise aussi la carte : présence par case (une fois par seconde), entrées par cachette,
  lieux des vu-perdu, des frôlements et des sorties.
- `tools/gordeka/make_port_v3.py` : la v2 (avec sa tension) plus des passes au choix (ruelles, salles,
  cachettes, sorties, liaisons, entrées, densité, ornements) ; `ab_tension.py run … --map <carte>`.
- Mesures : 120 rounds par niveau du chasseur (chassés normaux), 6 joueurs, comme plus haut. La machine était
  très chargée cette nuit-là (jusqu'à 60 Godot en parallèle avec les essais du Parc et de la Plage) : ça ne
  change pas les chiffres (pas de temps fixe), seulement la durée.
- **Bruit** : sur 120 rounds, l'erreur type sur « chasseur gagne » est de ±4 à 5 points. La même carte v2,
  mesurée deux fois à deux heures d'écart, a donné 71 puis 62 % au normal ; seuls les écarts de 10 points ou
  plus comptent. La référence de ce tableau est la seconde mesure (`carte_v2_bis`, même instantané du code que
  les variantes).

### Diagnostic de la v2 (`analyse_carte.py port_v2 --ab carte_v2_bis`)

- **Vide** : 25 % du sol sans aucun objet à 2 cases, 11 % à 3 cases. Les vides sont surtout le long des murs
  (les masses entre zones étaient des blocs gris nus) et dans les couloirs (78 % de leurs cases sans rien autour).
- **Lignes de vue longues** : rayon moyen 5,3 cases, et d'une case sur deux (53 %) un rayon file à 15 cases :
  jetée 92 %, bassin 94 %, place 78 %, criée 66 %, atelier 61 %. Les crampottes, à l'inverse, ferment tout
  (rayon 2,5).
- **Chemins** : 14 zones, 25 liaisons, 12 boucles indépendantes, aucun cul-de-sac ni pont ; couloirs larges de 3
  cases (2 à 6), en lignes droites.
- **Où se jouent les rounds** : les couloirs font 11 % du sol mais 34 % des captures et 27 % du temps du
  chasseur (la rue des pêcheurs et le quai nord sont des autoroutes nues) ; le quai nord fait 30 % des
  frôlements. Zones calmes : cale, terrasse, lavoir, escalier, jetée (chasseur 1,5 à 4 % du temps, 1 à 3 % des
  captures). Pas de zone morte ; les 16 cachettes servent (0,2 à 0,3 entrée par round chacune) ; les 4 sorties
  aussi (0,4 à 0,7 chassé par round).

### Journal des essais

| essai | ce qui change | chasseur gagne % (facile / normal / malin) | vu-perdu (normal) | cases/min | verdict |
|---|---|---|---|---|---|
| v2 (référence) | — | 52 / 62 / 78 | 2,9 | 155 | — |
| 1a « déco » | objets le long des murs (barriques, pots, casiers), ornements, toits et façades | 48 / 56 / – (162 rounds au normal) | 3,0 | 151 | joli, chasseur un peu affaibli |
| 1b « structure » | ruelles en baïonnette, salles coupées (crampotte sur la jetée, platanes, cloison de la criée…), 8 cachettes de plus, raccourcis | 38 / 46 / – (81) | 3,6 | 147 | **trop favorable aux chassés** (sortis 52 %) |
| 1c tout | 1a + 1b | 42 / 53 / – (53) | 3,5 | 149 | idem |
| 2 v3b | tout, + barriques derrière chaque porte, − raccourci chapelle → escalier (il menait tout droit à une sortie) | 37 / 40 / – (112 / 25) | 2,8 | 146 | toujours trop favorable aux chassés |
| 3 **v3d** | v3b + **abords des sorties dégagés** (pas d'objet à 7 cases, pas de cachette à 8 cases) | 33 / 60 / 71 | 3,2 | 143 | normal et malin revenus ; le chasseur facile s'effondre (33 %) |
| 4a v3e | v3d plus légère : pas de cachettes en plus, peu d'objets hauts | – / 51 / – (104) | 3,2 | 144 | rien de mieux |
| 4b v3f | v3d + boucle du sud (terrasse ↔ lavoir ↔ atelier) | – / 41 / – (77) | 3,8 | 141 | plus de tension, mais chassés trop forts : écartée |
| 5 v3d + sorties à 110 s | réglage propre à la carte : `exits_open_at` 90 → 110 (zones.json → regles) | 64 / 69 / 74 | 3,4 | 144 | équilibre retrouvé, plus de tension ; mouvement −7 % |
| 6 v3g | 5 avec moins d'objets hauts (20 % au lieu de 45 %) | 62 (52) / 66 / – | 3,6 | 144 | mouvement inchangé : rien de net |
| 7 **v3d + sorties à 110 s + 6 gâteaux** | 5 + `gateaux_nombre` 4 → 6 sur cette carte (récompense au risque) | **51 / 71 / 77** | **3,4** | **150** | **retenue** : l'écart entre niveaux de la v2, mouvement presque rattrapé |

### Tableau final (120 rounds par niveau ; chassés normaux, chasseur facile / normal / malin)

| | v2 | v3d, sorties à 110 s (essai 5) | **v3 retenue** (essai 7 : + 6 gâteaux) |
|---|---|---|---|
| chasseur gagne % | 52 / 62 / 78 | 64 / 69 / 74 | **51 / 71 / 77** |
| chassés trouvés % | 52 / 56 / 64 | 56 / 62 / 65 | 49 / 62 / 63 |
| chassés sortis % | 48 / 44 / 36 | 44 / 37 / 34 | 50 / 38 / 36 |
| vu-perdu par round | 3,1 / 2,9 / 2,3 | 3,4 / 3,4 / 2,8 | **3,6 / 3,4 / 2,6** |
| frôlements < 2 cases | 0,37 / 0,30 / 0,33 | 0,49 / 0,53 / 0,28 | **0,60 / 0,47 / 0,40** |
| frôlements < 3 cases | 0,65 / 0,63 / 0,55 | 1,10 / 1,07 / 0,76 | 1,14 / 0,89 / 0,87 |
| « ? » qui retombent | 1,2 / 1,0 / 0,8 | 1,5 / 1,3 / 0,8 | 1,5 / 1,1 / 0,9 |
| cases/min (chassés) | 154 / 155 / 150 | 141 / 144 / 142 | 148 / 150 / 148 |
| en mouvement % | 54 / 54 / 52 | 49 / 50 / 49 | 51 / 52 / 51 |
| changements de planque | 9,4 / 8,9 / 8,1 | 12,7 / 11,3 / 10,7 | **13,4 / 10,6 / 10,9** |
| entrées en cachette | 4,1 / 3,8 / 3,7 | 5,0 / 5,1 / 4,9 | 6,2 / 5,0 / 5,0 |
| gâteaux mangés | 4,5 | 4,5 | 7,4 à 8,9 |
| captures en pleine course | 3,4 / 3,6 / 3,9 | 3,6 / 3,8 / 3,9 | 3,3 / 3,8 / 3,8 |
| durée du round (s) | 121 / 120 / 117 | 135 / 136 / 132 | 142 / 135 / 136 |

Carte (`analyse_carte.py port_pecheurs`) : vide à 2 cases 25 → 13 %, à 3 cases 11 → 3 % ; rayon moyen 5,3 →
4,9 cases, rayons à 15 cases 53 → 42 % (bassin 94 → 87 %, place 78 → 55 %, criée 66 → 52 %) ; objets hauts
33 → 56, objets bas 27 → 48, cachettes 16 → 23 ; captures dans les couloirs 34 → 33 %, place 9 → 6 % (rounds de la v3 retenue). Toujours
aucune zone morte, toutes les cachettes servent (0,19 à 0,29 entrée par round), les 4 sorties aussi (0,47 à
0,58 chassé par round, mieux réparties qu'en v2 où le phare dominait) ; les couloirs font 29 % des frôlements
(7 % en v2) : ce sont devenus les lieux de rencontre.

Constats :
- **Toute couverture ajoutée profite aux chassés**, surtout par les sorties : avec plus d'abris, ils tiennent
  jusqu'à leur ouverture puis filent. Le chasseur facile, qui fouille peu et ne garde pas les sorties, en
  souffre le plus (52 → 33 %).
- **Le levier qui marche est la sortie**, pas le décor : abords des sorties dégagés (essai 3), puis ouverture à
  110 s sur cette carte (essai 5). Les chassés qui tiennent plus longtemps rendent les rounds plus tendus
  (+15 % de vu-perdu, +60 % de frôlements au normal) et ils durent 15 s de plus.
- **Mouvement** : les essais 1 à 6 perdent tous 5 à 8 % de cases parcourues (plus d'obstacles, plus de bonnes
  planques) ; moins d'objets hauts (essai 6) n'y change rien. **Six gâteaux au lieu de quatre** (essai 7,
  récompense au risque des jeux d'extraction) le rattrapent presque (148-150 cases/min contre 150-155), font
  manger deux fois plus de gâteaux, et ramènent le chasseur facile à son niveau de la v2 (51 %).
- **Arrêt** : après l'essai 7, l'écart restant avec la v2 (mouvement −3 %) est dans le bruit ; les leviers qui
  resteraient sont dans l'IA (`mouvement_relocate`), pas dans la carte.
- Zones calmes : terrasse et lavoir (moins de 1 % des captures) ; ce sont des poches au bout de la rue, voulues
  calmes (la boucle du sud, essai 4b, les rendait chaudes mais déséquilibrait).

Principes appliqués : couloirs étroits en baïonnette avec niches (rencontres et frôlements, Among Us), lignes de
vue coupées aux entrées des salles (barrique décalée derrière chaque porte), un repère par salle gardé et des
raisons d'y aller (cachettes dans chaque salle et dans les niches de la rue, gâteaux, mouettes), aucun
cul-de-sac (13 boucles indépendantes), sorties visibles et exposées sans abri ni cachette à leurs abords,
plusieurs approches (2 à 5 zones voisines), zones calmes et chaudes, tension qui monte (ouverture plus tardive),
récompense au risque (plus de gâteaux, que le chasseur voit aussi).
Écartés : raccourcis qui mènent droit à une sortie, boucle du sud.
