# Équilibrage des combattants (2026-10-18)

Demande de Julien : « équilibrer les combats selon le personnage (vitesse, coups, garde, engagement) ».
But : une identité de jeu nette par perso (SPEC §5.1) **et** des matchs équilibrés, paire par paire.
Contraintes : SPEC §5.2 (marche et PV à ±10 % de Louis, ±20 % pour Mattin et Kaio), sim inchangée.

## 1. Outils

| Commande | Rôle |
|---|---|
| `python3 tools/balance/matrix.py --n 200 --ai 80` | Matrice IA contre IA : 66 paires × n matchs, côtés alternés, graines brassées, 9 processus Godot headless (≈ 3 min pour n = 200). Affiche la matrice, les paires hors 40/60, et par perso : dégâts/s, touches/s, % de coups gardés, garde, spéciaux, projectiles, projections, distance, coups qui font les dégâts. |
| `… --only kaio:ramuntxo --detail kaio:ramuntxo` | Une paire seule, avec le détail par côté (dégâts par coup, coups dans le vide). |
| `.venv/bin/python tools/balance/tune.py --ai 50,80` | Réglage fin de `damage_pct`, **seulement dans les bornes de l'archétype** (`_equilibrage.damage_pct` de la fiche), moyenné sur deux niveaux d'IA. |
| `python3 tools/balance/archetypes.py` | Profil statique (vitesses, saut, allonge, dégâts, avantage à la garde, projectiles) lu dans les `data.json`. |
| `python3 tools/balance/heatmap.py` | Heatmap PNG de `tests/out/balance.csv`. |

Le moteur est `tests/balance_sim.gd` (la sim et l'IA telles qu'en jeu, sans rendu).
Après chaque changement de fiche : `.venv/bin/python tools/sprites/build_fighter.py --all` (données seules, les images ne sont que lues).

## 2. Ce que la mesure a montré

1. **L'IA ne frappait presque jamais au contact.** Ses seuils de distance (contact 60 px, mi-distance 130 px) dataient des boîtes de poussée de 22 px ; mesurées sur les sprites, elles font 30 à 54 px. Deux persos collés restaient « à mi-distance » : pas de coups normaux, pas de coups favoris (Karramarro : aucun). L'ancien équilibrage (`damage_pct` seul) avait été réglé contre cette IA-là. Corrigé dans `ai_brain.gd` (`gap_px`, `REF_PUSH_PX = 44`), test `test_ai_contact_normals`.
2. **L'allonge venait du dessin.** La boîte de coup d'un normal est l'union de la boîte du sprite et de celle de `_common` : elle dépassait la référence de 0 px (Kaio) à 55 px (Mattin, Karramarro). Avec l'IA corrigée, cette allonge décidait des matchs (Karramarro 76 %, Patxi 35 %). `build_fighter.py` la borne désormais : référence + 8 px minimum (tolérance enfant), + 24 px maximum, plus l'`allonge` d'archétype de la fiche.
3. **La boîte de poussée de Karramarro (54 px) polarisait ses matchs** (de 23 % à 77 % selon l'allonge adverse) : ramenée à 44 px.
4. **Un match est une course aux dégâts très peu aléatoire** : 5 % de dégâts/s ou de PV en plus donnent environ 60/40. Les PV et `damage_pct` sont donc des leviers fins, à petites touches.
5. **Les graines consécutives du xorshift32 sont corrélées** : sans brassage, deux séries de graines différaient de plus de 10 points sur une même paire. L'outil les brasse (murmur3) ; n = 200 donne ± 3,5 points (1 σ) par paire.

## 3. Archétypes et leviers

`damage_pct` multiplie tous les dégâts du perso ; il reste dans les bornes de l'archétype (colonne « bornes »).

| Perso | Archétype | Leviers d'identité | damage_pct (bornes) |
|---|---|---|---|
| Louis | équilibré (référence) | Toutes les valeurs communes : marche 640, PV 1000, frame data de `_common`. Espadrille boomerang, charge, uppercut invulnérable. | 96 (90–110) |
| Maïa | rapide, rushdown | Marche 700 / course 1250 (les plus rapides), poings en 3 frames, +2 de blockstun sur P et P,P (avantage à la garde : 0 au lieu de −2), récupération −1. Portée courte. | 96 (80–100) |
| Patxi | lutteur, contrôle | Lent (580), 1040 PV, projection la plus forte du jeu (136 en jeu, 96 à 132 pour les autres), hameçon qui ramène, filet qui immobilise, sardines. Frappes moins fortes. | 85 (80–115) |
| Xabi | zoneur | 4 projectiles (17 projectiles/min mesurés, le plus haut du jeu), 950 PV. | 120 (85–120) |
| Mattin | lourd | Le plus lent (512 / 900), 1100 PV, poings en 7 frames, +3/+4 de récupération sur tous les normaux (punissable), Bélier à armure 14 frames ; allonge +8 px ; ses gros coups sont ses spéciaux (Soulevé 130, pierre 110). | 101 (95–125) |
| Amaia | technique, coups de pied | Coups de pied plus rapides et plus forts (75/85), spéciaux à plusieurs touches, saut plus haut, 970 PV. | 106 (90–115) |
| Txomin | contrôle, étourdissement | Moyen en vitesse et PV ; sifflet qui étourdit, palme, pavillon qui ralentit. | 118 (90–120) |
| Kaio | aérien, harcèlement | Saut le plus haut et le plus long (50 frames, 152 px), coups sautés 70/80, piqué, fiente en cloche, IA plus zoneuse (0,6). Petits poings au sol, 1000 PV. | 108 (90–125) |
| Karramarro | défensif, armure | Lent (576), 1100 PV, grandes pinces (allonge +8 px), carapace qui contre, poussée 44 px. Ses coups font peu de dégâts : il gagne à l'usure (le plus faible en dégâts/s, 21,8). | 89 (70–95) |
| Ramuntxo | polyvalent, pièges | Moyen partout ; gâteau piège, jambon à grande portée, poêle qui renvoie. | 103 (90–110) |
| Itsaso | mystique, téléportation | La moins endurante (950 PV), téléportation, perle qui ralentit, piège de marée, geyser. | 120 (95–120) |
| Peio | puissant, charges | 1080 PV, course 1200, charges qui renversent, plaquage lent. | 104 (100–120) |

Le boss (Itsasargi) reçoit une `allonge` de 16 px pour garder sa portée ; Hondar ne change pas de rôle.

### Profil mesuré (après)

Statique (`archetypes.py`) :

| perso | PV | marche px/s | course px/s | saut (f) | allonge px | P,P,P dégâts/s | K gardé (f) | projectiles |
|---|---|---|---|---|---|---|---|---|
| louis | 1000 | 150 | 258 | 38 | 64 | 238 | −2 | 1 |
| maia | 1000 | 164 | 293 | 38 | 64 | 253 | 0 | 1 |
| patxi | 1040 | 136 | 234 | 38 | 76 | 216 | −2 | 3 |
| xabi | 950 | 145 | 258 | 38 | 76 | 298 | −2 | 4 |
| mattin | 1100 | 120 | 211 | 35 | 84 | 169 | −6 | 2 |
| amaia | 970 | 155 | 258 | 40 | 68 | 264 | −2 | 0 |
| txomin | 1000 | 150 | 258 | 38 | 64 | 293 | −2 | 2 |
| kaio | 1000 | 141 | 281 | 50 | 76 | 269 | −2 | 1 |
| karramarro | 1100 | 135 | 258 | 35 | 83 | 221 | −2 | 1 |
| ramuntxo | 1020 | 150 | 258 | 38 | 75 | 255 | −2 | 1 |
| itsaso | 950 | 145 | 258 | 38 | 64 | 298 | −2 | 2 |
| peio | 1080 | 141 | 281 | 38 | 64 | 259 | −2 | 1 |

En combat (IA 80, 13 200 matchs) : Xabi 16,8 projectiles/min et 90 px de distance moyenne (zoneur) ; Karramarro 21,8 dégâts/s (le plus bas) et 55 % de garde (le plus haut) ; Mattin 0,29 touche/s (le plus bas) mais ses spéciaux font 32 % de ses dégâts ; Maïa 0,43 touche/s et 67 % du temps au contact ; Patxi 0,48 touche/s, 11 projectiles/min.

## 4. Matrices

Taux de victoire (%) de la ligne contre la colonne, 200 matchs par paire, mêmes graines.
En gras : hors 40/60.

### Avant (IA d'origine, fiches d'origine), IA 80

| | louis | maia | patxi | xabi | matti | amaia | txomi | kaio | karra | ramun | itsas | peio | total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| louis | · | 55 | 44 | 40 | **62** | **64** | 53 | **36** | **96** | 48 | **36** | **63** | 54.4 |
| maia | 45 | · | **34** | 43 | 50 | 50 | **64** | **63** | **62** | 57 | **61** | 55 | 52.9 |
| patxi | 56 | **66** | · | 48 | **30** | **63** | 49 | **74** | 48 | 44 | **37** | **62** | 52.4 |
| xabi | 60 | 57 | 52 | · | 48 | **68** | **68** | 49 | 53 | 55 | 49 | **64** | 56.6 |
| mattin | **38** | 50 | **70** | 52 | · | **32** | **60** | 56 | **70** | 50 | 57 | 56 | 53.7 |
| amaia | **36** | 50 | **37** | **32** | **68** | · | 58 | **40** | **72** | 57 | 53 | 60 | 51.2 |
| txomin | 47 | **36** | 51 | **32** | **40** | 42 | · | **64** | 50 | **38** | 42 | **60** | 45.7 |
| kaio | **64** | **37** | **26** | 51 | 44 | **60** | **36** | · | **64** | **62** | **22** | **80** | 49.7 |
| karramarro | **4** | **38** | 52 | 47 | **30** | **28** | 50 | **36** | · | 50 | 52 | **25** | 37.4 |
| ramuntxo | 52 | 43 | 56 | 45 | 50 | 43 | **62** | **38** | 50 | · | **34** | **61** | 48.6 |
| itsaso | **64** | **39** | **63** | 51 | 43 | 47 | 58 | **78** | 48 | **66** | · | **78** | 57.6 |
| peio | **37** | 45 | **38** | **36** | 44 | 40 | **40** | **20** | **75** | **39** | **22** | · | 39.8 |

35 paires sur 66 hors 40/60 (Louis bat Karramarro 96 %).

### Après, IA 80

| | louis | maia | patxi | xabi | matti | amaia | txomi | kaio | karra | ramun | itsas | peio | total |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| louis | · | 48 | 50 | 54 | 53 | 57 | 52 | 59 | 54 | 46 | 54 | 54 | 52.9 |
| maia | 52 | · | **37** | 50 | 54 | **64** | 60 | 58 | 52 | 49 | 46 | 60 | 52.9 |
| patxi | 50 | **63** | · | **39** | 47 | 58 | 48 | **60** | 51 | 49 | 55 | 60 | 52.5 |
| xabi | 46 | 50 | **61** | · | 49 | 46 | 48 | 52 | 55 | 50 | 50 | 49 | 50.6 |
| mattin | 47 | 46 | 53 | 51 | · | 48 | 51 | 58 | 52 | 46 | 54 | 50 | 50.5 |
| amaia | 43 | **36** | 42 | 54 | 52 | · | 51 | 48 | 40 | 48 | 44 | 50 | 46.1 |
| txomin | 48 | 40 | 52 | 52 | 49 | 49 | · | 47 | 52 | 50 | 52 | 50 | 49.4 |
| kaio | 41 | 42 | **40** | 48 | 42 | 52 | 53 | · | 44 | **64** | 42 | 49 | 47.0 |
| karramarro | 46 | 48 | 49 | 45 | 48 | 60 | 48 | 56 | · | 52 | 54 | 49 | 50.5 |
| ramuntxo | 54 | 51 | 51 | 50 | 54 | 52 | 50 | **36** | 48 | · | 56 | 58 | 50.8 |
| itsaso | 46 | 54 | 45 | 50 | 46 | 56 | 48 | 58 | 46 | 44 | · | 50 | 49.3 |
| peio | 46 | 40 | 40 | 51 | 50 | 50 | 50 | 51 | 51 | 42 | 50 | · | 47.4 |

5 paires sur 66 hors 40/60 (dont deux à 60–61 %), aucune au-delà de 64/36.

### Résumé (taux global par perso)

| perso | avant, IA 80 | avant, IA 50 | IA corrigée seule, IA 80 | après, IA 80 | après, IA 50 |
|---|---|---|---|---|---|
| louis | 54.4 | 50.1 | 50.0 | 52.9 | 47.6 |
| maia | 52.9 | 59.2 | 52.9 | 52.9 | 53.0 |
| patxi | 52.4 | 35.1 | 34.5 | 52.5 | 45.9 |
| xabi | 56.6 | 56.8 | 49.0 | 50.6 | 46.4 |
| mattin | 53.7 | 64.1 | 40.3 | 50.5 | 50.9 |
| amaia | 51.2 | 59.5 | 46.0 | 46.1 | 57.6 |
| txomin | 45.7 | 32.2 | 44.3 | 49.4 | 52.1 |
| kaio | 49.7 | 64.5 | 62.9 | 47.0 | 52.6 |
| karramarro | 37.4 | 30.0 | 76.1 | 50.5 | 49.2 |
| ramuntxo | 48.6 | 49.8 | 49.7 | 50.8 | 48.2 |
| itsaso | 57.6 | 51.0 | 57.7 | 49.3 | 44.9 |
| peio | 39.8 | 47.7 | 36.5 | 47.4 | 51.5 |
| **paires hors 40/60** | **35/66** | **40/66** | **33/66** | **5/66** (max 64) | **7/66** (max 67) |

Restent à surveiller : Kaio > Ramuntxo (64 % à l'IA 80, 67 % à l'IA 50), Patxi > Maïa (63 %), Maïa > Amaia (64 %). Amaia est plus forte contre une IA qui garde moins (57,6 % à l'IA 50, 46,1 % à l'IA 80).

## 5. Limites

- **Biais de l'IA.** L'IA est générique : elle n'utilise le projectile que s'il est en spécial neutre, le spécial bas que s'il est « favori », ne punit qu'en Expert. Les zoneurs et contrôleurs (Xabi, Itsaso, Txomin) ont donc besoin de `damage_pct` hauts (118–120, en butée) pour tenir contre elle ; un humain qui sait zoner sera plus fort avec eux. Mesuré à deux niveaux (50 et 80), même niveau des deux côtés.
- **Refonte graphique.** Les boîtes de coups et de corps viennent des sprites (`anims.json`). L'allonge des normaux est maintenant bornée, mais les hurtboxes et la hauteur des boîtes suivront les nouveaux dessins : relancer `matrix.py` (et `tune.py`) après chaque perso refait. Persos les plus sensibles : Karramarro (pinces, poussée), Mattin (bras), Patxi (canne), Kaio (petit gabarit).
- **Karramarro** : poussée 54 → 44 px. En phase 8 elle avait été élargie pour le ressenti (sprites qui se chevauchent) ; la capture `docs/captures/equilibrage_karramarro_maia.png` ne montre pas de chevauchement gênant, à vérifier en jeu.
- Les icônes « puissance / vitesse / portée » de l'écran de sélection (`stats`) n'ont pas été modifiées.
- L'équilibrage IA contre IA ne dit rien du ressenti d'un enfant contre l'IA Facile : à jouer.

Captures : `docs/captures/equilibrage_*.png`.
