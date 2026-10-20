# Miarritze Gordeka — spécification

> Cache-cache en ligne pour enfants, façon *Among Us*, dans les décors de Biarritz.
> Brouillon du 2026-10-19 (pivot décidé par Julien). Remplace `SPEC-BORROKA.md` (jeu de combat),
> gardée en archive. Les points **[À trancher]** attendent une décision de Julien.

---

## 1. Pitch et piliers

À chaque round, un joueur tiré au sort devient **le chasseur**. Les autres sont **les chassés** : ils
ont quelques secondes pour se cacher derrière les cabines de plage, les étals des Halles ou les
bateaux du port. Le chasseur voit seulement devant lui, dans un cône que les objets bloquent. Un
chassé qui entre dans ce cône est **trouvé**. Les chassés voient toute la carte, y compris le cône du
chasseur : tout le jeu consiste à rester hors de vue. Chacun a un pouvoir, un **piège** quand il est
chassé et une **détection** quand il est chasseur. Les rounds s'enchaînent jusqu'à ce qu'on quitte la
partie.

**Piliers**
1. **Lisible en une seconde.** Le cône rouge du chasseur se voit sur le sol, chez tout le monde.
   Un enfant de 9 ans comprend sans tutoriel : « s'il me voit, je suis trouvé ».
2. **Contrôles simples.** Se déplacer, plus un seul bouton de pouvoir. Le même bouton pose un piège
   ou lance une détection selon le rôle.
3. **Jamais punitif.** Personne n'est « tué » : on est *trouvé*. Un joueur trouvé devient un petit
   fantôme qui continue de regarder et d'encourager, et le round suivant arrive vite (2 à 3 min).
4. **Entre copains.** On joue en salon avec son groupe, ou seul contre l'IA. Pas de joueurs inconnus,
   pas de chat libre.
5. **Biarritz.** Les cartes sont des lieux de la ville, les personnages viennent de Miarritze Borroka.

## 2. Boucle de jeu

### 2.1 Une partie
`Accueil → choix du personnage et de la couleur → (solo : réglages IA | en ligne : salon) →
round → scores du round → round suivant … → quitter → scores de la partie`.

### 2.2 Un round
| Phase | Durée (données) | Ce qui se passe |
|---|---|---|
| Tirage | 3 s | Une roulette désigne le chasseur. Il voit « Tu es le CHASSEUR », les autres « Cache-toi ! ». |
| Cachette | 15 s | Le chasseur compte, écran voilé et immobile (« Bat, bi, hiru… » en basque). Les chassés courent se cacher. |
| Chasse | 180 s | Le chasseur cherche. Pouvoirs actifs. Sorties ouvertes à 90 s. |
| Fin | 6 s | Le round finit quand plus aucun chassé n'est libre, ou au chrono. **Victoires individuelles** : chaque chassé extrait ou encore libre au chrono gagne ; le chasseur gagne s'il en a trouvé plus de la moitié. Révélation des cachettes, puis scores. |

- **Points d'extraction** (demande de Julien) : chaque carte a un ou plusieurs points de sortie
  difficiles à atteindre (bout de jetée, échelle du phare, barque, porte de la chambre froide).
  - Un chassé qui l'atteint et y reste **4 s** sans être vu est **extrait** : il a gagné son round,
    marque des points et devient spectateur.
  - Les points s'**ouvrent** après 90 s de chasse (*équilibrage du 2026-10-19 : à 60 s, un chassé sur trois
    s'échappait*), pour que tout le monde ne file pas dès le départ.
    Chaque carte en a **2, fixes et connues**, qui s'ouvrent ensemble (*décidé le 2026-10-19*).
  - Ils sont placés dans des zones exposées : longues lignes droites, peu d'objets. Le chasseur peut
    les garder, mais il laisse alors le reste de la carte libre.
- **Tirage du chasseur** : au hasard, mais en « sac ». Chacun est chasseur une fois avant qu'un
  joueur le redevienne. Jamais deux rounds de suite le même.
- **Joueurs** : 2 à 8 par salon, toujours **un seul chasseur** ; des IA complètent si besoin
  (*décidé le 2026-10-19*).
- Le round suivant démarre seul après les scores. Un bouton « Quitter » est toujours accessible.
- **Fin de partie** : il n'y a pas de nombre de rounds. Quand l'hôte quitte (ou le joueur, en solo),
  un **podium** du cumul des points s'affiche (or, argent, bronze), puis on revient au menu.
- **Départs** :
  - si le chasseur quitte, le round s'arrête sans points et le suivant démarre ;
  - si un chassé quitte, il disparaît et le round continue ;
  - si l'hôte l'a activé, une IA prend la place libre au round suivant.

### 2.3 Score
Les scores sont cumulés sur la partie, affichés entre les rounds et à la fin. Ils ne servent qu'à
s'amuser, sans classement en ligne en v1.

| Action | Points |
|---|---|
| Chassé : par tranche de 10 s non trouvé | +1 |
| Chassé : encore caché à la fin du round | +5 |
| Chassé : extrait par un point de sortie | +8 |
| Chassé : piège qui ralentit le chasseur | +2 |
| Chasseur : chassé trouvé | +3 |
| Chasseur : tous trouvés avant la fin | +5 |

## 3. Rôles et règles

### 3.1 Vision
- **Chasseur**
  - Vision limitée à un **cône** de 90°, d'une portée de 7 cases, plus un petit cercle de 1,5 case
    tout autour de lui, pour qu'on ne puisse pas le frôler impunément.
  - Le cône est **bloqué par les objets** : murs, cabines, étals, bateaux. Hors de sa vision,
    l'écran est assombri, mais le décor reste visible pour qu'il puisse s'orienter. Les chassés hors
    vue sont invisibles pour lui.
- **Chassés**
  - Vision **illimitée** : ils voient toute la carte, les autres chassés, le chasseur et **son cône
    dessiné au sol en rouge translucide**.
  - **Pas de mini-carte** (*décidé le 2026-10-19*). Quand le chasseur est hors champ, une flèche au
    bord de l'écran indique sa direction.
- **Caméra identique pour tous**, qui suit son joueur, au zoom d'Among Us : l'écran montre environ
  une zone, et un personnage fait environ 1/9 de la hauteur d'écran.

### 3.2 Être trouvé
- Un chassé est trouvé quand son corps reste **0,5 s** dans la zone de vision (*0,3 s jusqu'au 2026-10-19 : être vu
  voulait presque toujours dire être trouvé*) du chasseur (cône ou
  cercle), sans objet entre les deux. Une petite jauge se remplit au-dessus de lui et se vide dès qu'il
  sort de la vue. C'est plus juste en ligne (~100 ms de retard) et ça permet des fuites de justesse.
  *Décidé le 2026-10-19.*
- **Emotes** (*remplacé le 2026-10-19, validé par Julien*) : 6 gestes du perso (`emote_salut`,
  `emote_rire`, `emote_danse`, `emote_pouce`, `emote_chut`, `emote_langue`, `GkGame.EMOTES`) avec
  une bulle d'icône dessinée, sans texte, au-dessus de la tête pendant 1,5 s (`emote_duration`).
  Elles sont permises seulement **hors de l'action** : au tirage, sur le podium, et pour un fantôme ou
  un échappé ; jamais en jeu actif, ni pour tricher ni pour gêner la cachette. Commandes : un petit
  bouton au-dessus du bouton d'action qui ouvre un éventail de 6 bulles, les touches 1 à 6, ou LB/RB
  à la manette puis la croix et A. Les IA en font rarement, au tirage et au podium. Pas encore de
  synchro réseau (le mode en ligne de Gordeka n'existe pas encore). Sans planche, le profil fixe
  reste affiché le temps de l'emote.
- Le chassé trouvé crie un « Trouvé ! » rigolo et devient un **fantôme** translucide, simple
  spectateur (*décidé le 2026-10-19*). Il se déplace
  librement, traverse les murs, voit tout, mais ne peut plus rien faire ni être vu par le chasseur.
  Il peut envoyer les emotes prédéfinies.
  *TEMPORAIRE (2026-10-20, génération des fantômes arrêtée)* : les persos sans planches ghost/ghost_move
  volent avec leurs idle/walk (vol stationnaire, ombre au sol) et des ailes blanches dessinées par code
  (`tools/gordeka/dessine_ailes.py`) ; ceux qui ont leurs planches gardent leurs ailes, avec le même vol.
- ~~Un chassé ne peut pas « sauver » un autre en v1.~~ **Délivrance** (*essai A/B du 2026-10-20, à
  valider par Julien*) : un chassé libre et hors de vue qui reste 3 s près d'un fantôme le ramène en jeu
  (anneau vert sur le fantôme), **une seule fois par round**, +2 points au sauveur.
- **Chatouille** (*même essai*) : un fantôme qui touche le chasseur le fait rire (« hi hi ! ») et le
  ralentit à 60 % pendant 1,5 s ; une fois par 15 s et par fantôme, 8 s de répit pour le chasseur, +1 point.
  Le fantôme voit en bas de l'écran ce qu'il peut faire.

### 3.3 Vitesses (données)
| | Vitesse |
|---|---|
| Chassé | 100 % |
| Chasseur | 115 % |
| Fantôme | 120 % |
| Chasseur dans un piège de ralentissement | 50 % pendant la durée du piège |

## 4. Pouvoirs

Un seul bouton **Pouvoir** pour tout le monde. Son effet dépend du rôle et du personnage.
L'icône du bouton montre le pouvoir du moment et se remplit pendant le cooldown.

### 4.1 Règles communes (données, par personnage)
- **Piège** (quand on est chassé)
  - Posé aux pieds du chassé ou lancé un peu devant lui.
  - Cooldown 20 s. 2 pièges actifs au plus par joueur ; le plus ancien disparaît.
  - Les chassés voient les pièges. Le chasseur ne voit un piège que dans son cône et seulement à
    moins de 2 cases : il peut l'éviter s'il est attentif.
  - Un piège se déclenche une fois, sur le chasseur uniquement.
- **Détection** (quand on est chasseur)
  - Cooldown 15 s : la carte est grande, le chasseur a besoin d'indices souvent.
  - Donne une **indication**, jamais une capture directe : une silhouette, une flèche, des traces ou
    une onde, pendant 2 à 4 s.
  - Les chassés voient qu'une détection a été lancée (son et icône), pour garder le jeu juste.
  - Détection de base (en attendant les pouvoirs par perso) : onde de **14 cases** qui montre les
    chassés 2 s ; si personne n'est dans le rayon, **flèche vers le chassé le plus proche** pendant 3 s
    (*équilibrage du 2026-10-19 : à 8 cases, 95 % des ondes ne montraient rien*). Bilans :
    `docs/GORDEKA_EQUILIBRAGE.md`.

### 4.2 Par personnage (premières idées, à équilibrer en test)
| Perso | Piège (chassé) | Détection (chasseur) |
|---|---|---|
| Louis — l'enfant du pays | **Copain en carton** : un leurre à son image ; si le chasseur le « trouve », il est étourdi 1 s | **Pelote** : lancée tout droit, elle rebondit sur les murs et révèle les chassés qu'elle frôle |
| Maïa — surfeuse | **Flaque de wax** : le chasseur glisse, direction imprécise 2 s | **Vague** : onde circulaire de 5 cases qui révèle les silhouettes 1 s, même derrière les objets |
| Peio — rugbyman | **Plots** : barrière de plots qui bloque un passage 5 s | **Coup d'œil de l'ailier** : flèche vers le chassé le plus proche 3 s |
| Karramarro — crabe | **Pince** : immobilise 1,5 s | **Pas de côté** : vision à travers les objets 2 s |
| Kaio — goéland | **Fiente** : ralentit 3 s | **Vue du ciel** : portée du cône ×2 pendant 3 s |
| Patxi — pêcheur | **Filet** : immobilise 2 s | **Sonar** : les chassés apparaissent 2 s sur la mini-carte |
| Mattin — leveur de pierre | **Pierre** : rocher qui bloque un passage 6 s | **Secousse** : les chassés à moins de 6 cases laissent des traces de pas 4 s |
| Amaia — dantzari | **Ruban** : le chasseur tourne sur lui-même 1 s | **Makila** : frappe le sol ; onde de 4 cases qui révèle 1,5 s |
| Itsaso — esprit de l'écume | **Écume** : nuage qui bloque la vision du chasseur 4 s | **Perle** : roule vers le chassé le plus proche et l'éclaire 2 s |
| Ramuntxo — chef des Halles | **Gâteau collant** : ralentit 4 s | **Odorat** : traces de tous les chassés des 5 dernières secondes, pendant 3 s |
| Xabi — pelotari | **Chistera** : renvoie le chasseur 2 cases en arrière | **Rebond** : sa pelote suit les murs et s'arrête près d'un chassé caché |
| Txomin — maître-nageur | **Bouée** : le chasseur coincé dans une bouée, ralenti 3 s | **Sifflet** : les chassés qui **bougent** dans 6 cases sont révélés 2 s |

Familles d'effets à garder équilibrées entre elles :
- pour les pièges : ralentir, immobiliser court, bloquer un passage, brouiller la vue, leurrer ;
- pour les détections : onde, direction, traces, vision élargie.

### 4.3 Petits plus du port (*essai A/B du 2026-10-20, à valider par Julien*)
Retenus après des rounds IA contre IA (`docs/GORDEKA_EQUILIBRAGE.md`), chacun derrière un drapeau
`idee_*` de `rules.json` :
- **Gâteaux basques** : 4 au sol, dans des coins dégagés. Le chassé qui en ramasse un marque 1 point et
  file à 130 % pendant 4 s. Le chasseur les voit aussi : y aller est un risque.
- **Mouettes** : 6 groupes posés. Un chassé qui passe trop près les fait s'envoler en criant « kaio ! »,
  visible de tous : un indice sonore pour le chasseur. Elles reviennent après 20 s.
- Essayées et écartées (drapeau à 0) : cachette qui grince après 8 s, chasseur plus rapide après 30 s
  bredouille ; toutes deux renforçaient un chasseur déjà gagnant.

## 5. Contrôles

| | Déplacement | Pouvoir | Emote / menu |
|---|---|---|---|
| Tactile (iPhone, paysage) | joystick virtuel à gauche, flottant là où le pouce se pose | gros bouton à droite | petit bouton en haut à droite |
| Manette | stick gauche ou croix | A | Y / Start |
| Clavier | flèches ou ZQSD | Espace | E / Échap |

- Les personnages **se traversent**, comme dans Among Us : personne ne bloque ni ne coince personne.
- Le personnage regarde **là où il va**. Le cône du chasseur suit donc sa direction de marche, avec
  une rotation lissée et rapide. Pas de second stick pour viser.
- Vibration courte sur iPhone et manette quand on est trouvé ou quand on déclenche un piège.

## 6. Modes

### 6.1 Solo contre l'IA
- Hors ligne, sans compte.
- Réglages : nombre de joueurs (4 à 8, complétés par des IA), difficulté (Facile, Normal, Malin),
  carte (ou au hasard). Par défaut : **6 joueurs (toi et 5 IA), Normal, Port des Pêcheurs**.
- Le joueur est chasseur à son tour comme les autres, grâce au sac du tirage.
- **Visite de debug, TEMPORAIRE** (*Julien, 2026-10-20*) : « Visite : chassé » et « Visite : chasseur »
  dans le menu (ou `--gk-visite=chasse|chasseur`, web `#scene=gk_game&visite=…`) : carte complète,
  ni chrono ni fin de manche, personne d'autre, F montre les formes du décor, C change de perso. À
  retirer une fois les collisions, masques et décor mis au point.

### 6.2 Salon entre copains (en ligne)
- **Créer un salon** : l'hôte choisit la carte et le nombre de places (4 à 8).
- **Compléter par des IA** (Julien, 2026-10-19) : entre deux rounds, l'hôte peut ajouter ou retirer
  des IA, avec leur difficulté. L'option « compléter automatiquement » remplit les places vides
  jusqu'au nombre choisi à chaque round, y compris les places laissées par ceux qui partent.
  Les IA ont un pseudo du roster suivi de « (IA) » et sont tirées comme chasseur à leur tour.
- **On ne joue qu'entre membres du groupe.** Les « Salons actifs » servent seulement à demander à
  entrer dans un groupe (un membre accepte), jamais à rejoindre directement une partie d'inconnus.
- **Rejoindre** : depuis le groupe, avec la liste des copains connectés et des salons ouverts du
  groupe. On reprend le système existant :
  - code de groupe, « Créer un groupe », « J'ai un code » ;
  - « Salons actifs » avec demande acceptée par un membre.
- Arriver pendant un round : on attend en fantôme et on joue au round suivant.
- L'hôte quitte : la partie s'arrête pour tous, avec un message gentil. **[Plus tard]** Un autre
  joueur reprend le rôle d'hôte.

### 6.3 Pas de jeu à plusieurs sur un même écran
La vision limitée du chasseur n'a pas de sens si tout le monde regarde le même écran. Les copains
dans la même pièce jouent chacun sur leur appareil, en salon.

## 7. Personnages et couleurs

- On choisit **un personnage du roster** : les 12 de Miarritze Borroka, redessinés dans le nouveau
  style (*décidé le 2026-10-19*). **Personnages cartoon propres d'après ceux de Borroka** (leur
  silhouette, leur tête, leur tenue), et non des capsules façon Among Us, mais **dessinés en 2D flat
  cartoon dans le style d'Among Us** (cf. `docs/GORDEKA_STYLE_2D.md`), avec une `tenue` recolorable dans la couleur du joueur
  (masque). ~~Générés en 3D par pixelforge.~~
- ~~**Bâtiments** : un kit de pièces 3D~~ : en 2D, objets et bâtiments vus de dessus en léger 3/4
  (`pf_hd__prop`).
- On choisit **sa couleur** parmi 12, qui teinte la tenue principale (palette). Dans un salon, chaque
  couleur est unique, comme dans Among Us ; la couleur sert à se reconnaître de loin.
- Le profil garde le pseudo, le personnage favori, la couleur favorite et l'emote. On reprend
  l'existant : pseudo, code de groupe, aucune donnée personnelle.
- Le personnage ne change que l'apparence et les pouvoirs. Pas de différence de vitesse ni de taille
  de hitbox : tous ont la même empreinte au sol.

### 7.1 Progression légère (*décidé le 2026-10-19*)
- Tous les personnages et pouvoirs sont disponibles dès le début.
- En jouant, on débloque des **chapeaux**, des **couleurs spéciales** et des **emotes** : txapela,
  béret, bob, couronne en château de sable, couleurs à motifs (rayé Biarritz, écume…).
- Les déblocages viennent de défis simples : être extrait 3 fois, trouver 10 chassés, poser 20
  pièges… Ils sont enregistrés dans le profil local et synchronisés avec le groupe, comme les stats
  actuelles.

### 7.2 Premier lancement (*décidé le 2026-10-19*)
Un **round guidé contre l'IA**, sur le Port des Pêcheurs. On joue une fois chassé, puis une fois
chasseur, avec des bulles d'aide : « cache-toi derrière le bateau », « évite le cône rouge »,
« appuie pour poser un piège », « entre dans le casier ». On peut le refaire depuis le menu.

## 8. Cartes

Vue **de dessus en 3/4**, comme Among Us : le sol vu d'en haut, les personnages et les objets
légèrement de face. **Taille de The Skeld** (*décidé le 2026-10-19*) : environ 14 zones reliées par
des couloirs, soit environ 5 écrans de large sur 3,5 de haut. C'est une estimation à partir du jeu,
à vérifier sur le prototype. D'où une chasse de 3 min, un chasseur plus rapide et des détections
fréquentes.

**Première carte : Port des Pêcheurs** (*décidé le 2026-10-19*), pour le prototype gris puis le
style final.

| Carte (v1) | Zones | Objets qui cachent | Sorties |
|---|---|---|---|
| Port des Pêcheurs | quais, crampottes, bateaux à sec, rampe | bateaux, filets, casiers, caisses, crampottes | bout de la jetée, barque au pied de la rampe |
| Grande Plage | sable, promenade, cabines, poste de secours | cabines rayées, parasols, rochers, châteaux de sable | poste du maître-nageur, escalier du casino |
| Les Halles | allées d'étals, chambre froide, terrasse | étals, caisses, piles de cagettes, comptoirs | porte de la chambre froide, quai de livraison |

À venir : Aquarium (bassins, tunnel), Phare (escalier en colimaçon, plusieurs étages), Rocher de la
Vierge, Fronton.

- Chaque objet a une **forme d'occlusion** (polygone) qui bloque la vision et une **forme de
  collision** qui bloque le passage. Elles sont souvent identiques. Les données sont dans
  `assets/maps/<id>/map.json`.
- **Forme des objets du décor en images** (*2026-10-20, retour de Julien : « on doit pouvoir se
  cacher derrière le mur d'une maison, la coque d'un bateau »*). Elle n'est plus le rectangle des cases :
  le jeu la calcule au chargement depuis l'alpha de l'image (`src/gordeka/gk_decor.gd`, `_shape`),
  une fois par image, avec les réglages de `data/gordeka/rules.json` :
  1. silhouette à 4 px près, dont on retire les parties plus fines que `decor_finesse_px`
     (ouverture morphologique : mât, pieds, perche, corde ne bloquent pas) ;
  2. **enveloppe basse** : pour chaque colonne, le point le plus bas de l'objet, là où il touche le sol ;
  3. le dessus de l'**empreinte au sol** s'en déduit par **symétrie centrale** : un rectangle vu de
     face, le losange d'un objet vu en coin, le fuseau d'une coque, le disque d'une fontaine sont
     tous symétriques par leur centre. Le centre est à la hauteur des coins gauche et droit, et au
     moins à `decor_profondeur_min`/2 au-dessus du point le plus bas (objet vu de face). L'empreinte ne
     dépasse jamais la silhouette ni les cases de l'objet ;
  4. on bute sur l'empreinte et la vue du chasseur s'y arrête (objets bas : le passage seulement).
     Le reste de l'image (toit, face haute, mât) passe devant un perso qui est derrière et le masque :
     un chassé masqué n'est vu qu'à `masque_vue_portee` cases, et ses coéquipiers voient l'objet en
     transparence.

  **Masques de pixelforge prioritaires** (*2026-10-20, Julien : le calcul sur la silhouette « ne va
  pas »*) : quand `assets/gordeka/decor/masques/<id>/masks.json` existe (`tools/gordeka/masques_pf.py`),
  le jeu prend son emprise (`polygons`), sa ligne de tri (`baseline_y` : pieds au-dessus = perso
  derrière l'objet), `blocks_view` et `occluder.png` pour le masquage. Le calcul ci-dessus n'est plus
  qu'un repli : objet sans masques, confiance sous `decor_masques_pf_confiance_min`, ou emprise de plus
  de `decor_masques_pf_part_max` de la silhouette ; `decor_masques_pf` = 0 l'impose partout.

  Contrôle : `tools/gordeka/masques_decor.py` exporte, avec le code du jeu, la forme effectivement
  utilisée par objet (bandeau : pixelforge ou repli et pourquoi ; empreinte en vert, zone qui masque en
  violet, ligne de tri en rouge) dans `tools/gordeka/masques/jeu/`, à côté des aperçus de pixelforge
  (`tools/gordeka/masques/<id>.png`) ; les deux sont visibles sur /producer.
- **Cachettes dans les objets dès la v1** (*décidé le 2026-10-19*) : cabines, poubelles, casiers,
  coffres de bateau, comme les bouches d'aération d'Among Us.
  - Près d'une cachette, le bouton Pouvoir d'un chassé devient **Entrer**, puis **Sortir** une fois
    dedans.
  - Une seule personne par cachette. Dedans, on est invisible et on voit autour de soi. On ne peut
    pas poser de piège depuis une cachette.
  - On reste **20 s au plus** dedans ; ensuite on est éjecté et la cachette est fermée 10 s, pour
    qu'on ne puisse pas camper.
  - Près d'une cachette, le bouton du chasseur devient **Fouiller** : 1 s d'animation, et s'il y a
    quelqu'un dedans, il est trouvé. Une fouille vide ne coûte que cette seconde, sans cooldown. Ailleurs, le bouton reste la détection.
  - L'objet tremble légèrement quand quelqu'un y entre. C'est un indice si le chasseur regarde.

## 9. Direction artistique

- **Cartoon propre** : formes rondes, gros contours, aplats de couleur avec une ombre douce,
  personnages trapus et expressifs. Même esprit qu'Among Us et Fall Guys : mignon, lisible de loin,
  jamais inquiétant.
- **HD lisse façon Among Us** (*décidé le 2026-10-19*) : fin du pixel art et de la résolution
  384×216. Résolution logique 1280×720, filtre lissé.
- **Abandonné le 2026-10-19 (Julien : « pas content du tout du résultat »)** : repli sur le **style
  d'Among Us en 2D flat cartoon, légèrement en perspective**, persos de profil. Observations,
  liste des animations et pipeline pixelforge : `docs/GORDEKA_STYLE_2D.md`, qui remplace ce
  point et les parties 3D du §16.
- ~~**Rendu en 3D**~~ (*décidé puis abandonné le 2026-10-19*) : même vue de dessus en 3/4,
  mais des modèles 3D plutôt que des illustrations détourées (détourages peu précis). **Le rendu
  reste celui de l'intention d'origine** : cartoon propre façon Among Us et Fall Guys.
  - Ombrage simple (« toon »), aplats vifs, contours sombres et épais, formes rondes.
  - Ni réalisme ni textures photo ; des textures peintes simples, générées à plat (crépi, tuiles,
    pavés, bois).
  - Les règles restent en 2D (carte, collisions, vision) ; seul l'affichage passe en 3D. Le cône du
    chasseur devient une lampe torche avec de vraies ombres.
- **Architecture et décor du Pays basque** (Julien, 2026-10-19) : tous les bâtiments, éléments
  d'architecture **et objets de décor** doivent ressembler à ce qu'on trouve au Pays basque (Biarritz, Labourd) :
  - maisons labourdines et crampottes du port, aux murs blanchis à la chaux ;
  - colombages et volets rouge basque (parfois vert), toits de tuiles rouges à deux pentes
    asymétriques ;
  - quais et murs en pierre ou en grès, garde-corps du front de mer ;
  - barques basques peintes ;
  - par petites touches : lauburu, ikurriña, linge basque, fronton ;
  - objets : tonneaux de cidre, jambons de Bayonne et piments d'Espelette sur les étals, gâteaux
    basques, nappes en linge basque, chaises rouges ;
  - mobilier vert foncé du front de mer, hortensias, cabines et parasols rayés, pelotes et
    chisteras.
- Animations courtes et simples (vue de dessus) : immobile, marche (4 directions, gauche et droite
  en miroir), pouvoir, trouvé (surprise), fantôme, victoire.
- Le cône de vision et l'assombrissement sont faits par shader, avec les occulteurs 2D de Godot
  (`LightOccluder2D`).
- Son : pas feutrés, « Bat, bi, hiru… » au début, petit jingle de panique quand le chasseur
  approche (chassés à moins de 4 cases), « Trouvé ! » rigolo. Musique : *Hegoak* au menu, airs
  originaux pendant les rounds, de plus en plus pressants dans les 20 dernières secondes.

## 10. IA

- **Chassés IA**
  - Pendant la cachette : choisir une cachette (point derrière un objet, à l'abri des grands axes),
    différente de celles des autres.
  - Pendant la chasse : surveiller le cône, fuir dès qu'il approche, changer de cachette quand le
    chasseur s'éloigne, poser un piège sur le chemin du chasseur quand c'est pertinent.
- **Chasseur IA**
  - Patrouiller entre les zones, regarder derrière les gros objets, réagir aux sons des pièges, et
    utiliser sa détection au bon moment, puis aller vers l'indice obtenu.
- **Difficultés**
  - Facile : chasseur lent à tourner la tête, chassés qui bougent trop.
  - Malin : chasseur qui fouille méthodiquement, chassés qui changent de cachette dans son dos.
- Navigation : graphe de navigation Godot, `NavigationRegion2D`, généré depuis la carte.

## 11. Réseau

- **Modèle hôte-autorité** : l'appareil qui crée le salon fait tourner la vraie partie, y compris
  les IA. Les autres envoient leurs entrées, 20 fois par seconde ; l'hôte renvoie l'état
  (positions, rôles, pièges, chrono), 20 fois par seconde. Chaque client lisse les positions par
  interpolation (~100 ms).
- **Pas de simulation déterministe ni de rollback.** Le cache-cache tolère la latence ; la règle
  « trouvé » est décidée **uniquement par l'hôte**.
- **Triche limitée** : un client chasseur ne reçoit pas la position des chassés hors de sa vue. On
  ne peut donc pas « voir à travers » en trafiquant son client.
- **Transport** : WebRTC en étoile, l'hôte relié à chacun (2 à 8 joueurs). On réutilise :
  - la signalisation PHP par polling ;
  - les serveurs STUN et le relais TURN Cloudflare ;
  - l'extension WebRTC native (Steam Deck, Mac, Recalbox) et le diagnostic d'échec.
- **Serveur PHP** : groupes, présence, salons (création, liste, places), invitations, demandes
  d'entrée, signalisation. Pas de partie côté serveur.

## 12. Plateformes et technique

- Godot 4.7, GDScript typé. v1 : **web (navigateur et iPhone en paysage) et Steam Deck**, Mac en
  bonus (même build). Recalbox plus tard, si le cône se lit bien sur une télé (*décidé le
  2026-10-19*).
- Résolution et rendu : selon la décision du §9.
- Tout réglage de jeu est une donnée : durées, vitesses, cône, cooldowns, effets des pouvoirs,
  points. Fichiers `data/rules.json` et `data/characters/<id>.json`.
- Tests :
  - règles en headless : vision et occlusion, capture, pièges, fin de round, tirage en sac ;
  - IA contre IA sur chaque carte (un round se termine, pas de blocage de navigation) ;
  - deux navigateurs Playwright pour le salon en ligne (comme `tests/web/online_two.mjs`).

## 13. Ce qu'on garde de Miarritze Borroka, ce qu'on laisse

| On garde | On laisse (archivé) |
|---|---|
| Projet Godot, autoloads (profils, API, entrées, audio, navigation entre écrans, QA, mise à jour Steam Deck) | La simulation de combat déterministe, le rollback, les hitboxes |
| Pad virtuel et manettes (à simplifier : joystick + 1 bouton) | Les feuilles de sprites de combat (37 animations par personnage) |
| Backend PHP : groupes, présence, invitations, salons actifs, signalisation, TURN, limites de débit | Pyramide, entraînement, combat rapide, équilibrage des coups |
| Lien WebRTC, extension native, diagnostics réseau | Spéciaux, super, finish |
| Les 12 personnages, leur caractère et leurs couleurs (à redessiner) | |
| Les lieux de Biarritz (photos de référence, décors comme inspiration) | |
| Déploiement (GitHub Actions, web, paquet Steam Deck), *Hegoak* | |
| Kit d'interface, profils (pseudo, carte de joueur, emotes) | |

## 14. Jalons

**Où** : même dépôt. Borroka est archivé sur la branche `borroka`, et Gordeka se développe sur
`main`. Le site garde le Borroka actuel ; le déploiement web de Gordeka n'est activé que quand le
prototype plaît à Julien (*décidé le 2026-10-19*). **Prototype gris d'abord**, sans aucune image
avant l'avis de Louis.


1. **Prototype gris (fun d'abord)**
   - Une carte en blocs, des personnages en capsules de couleur.
   - Cône de vision avec occlusion, capture, rounds enchaînés, tirage en sac.
   - Un chasseur IA et des chassés IA, au clavier et au tactile.
   - Test avec Louis : **est-ce que c'est drôle ?**
2. **Pouvoirs** : 2 pièges et 2 détections génériques, cooldowns, scores, sons de base.
3. **Style final sur une carte** : Port des Pêcheurs et 4 personnages dans la direction choisie (§9).
4. **En ligne** : salon jusqu'à 8, hôte-autorité, IA de remplissage, test à deux navigateurs, puis
   iPhone contre Steam Deck.
5. **Contenu v1** : 12 personnages et leurs pouvoirs, 3 cartes, IA Facile, Normal et Malin,
   finitions (menus, musique, vibrations).

## 15. Décisions prises (2026-10-19)

Plus rien n'est à trancher avant le prototype. L'équilibrage des pouvoirs, le comportement des IA
et les détails du réseau se règleront en jouant.

- **Jeu** : *Miarritze Gordeka* ; web, iPhone et Steam Deck d'abord ; même dépôt (Borroka archivé en
  branche) ; prototype gris d'abord, testé par Louis.
- **Style** : HD lisse façon Among Us ; les 12 du roster redessinés, couleur au choix ; progression
  légère (chapeaux, couleurs, emotes).
- **Round** :
  - 15 s pour se cacher, puis 180 s de chasse ;
  - 2 sorties fixes ouvertes à 90 s (4 s pour sortir) ;
  - victoires individuelles ;
  - rounds sans limite, podium en quittant ;
  - règles de départ (§2.2).
- **Joueurs** : 2 à 8, un seul chasseur ; on peut compléter par des IA ; on ne joue qu'entre membres
  du groupe ; solo par défaut à 6 joueurs en Normal.
- **Règles** :
  - capture après 0,5 s dans le cône ; un chassé trouvé devient fantôme spectateur ;
  - le cône suit la marche ; les personnages se traversent ;
  - chasseur à 115 % ; détection toutes les 15 s ;
  - cachettes dans les objets dès la v1 (20 s au plus, fouille de 1 s) ; pas de piège depuis une
    cachette.
- **Vue** : même caméra pour tous, au zoom d'Among Us ; carte de la taille de The Skeld ; pas de
  mini-carte ; emotes seulement (6 au départ, les fantômes peuvent en envoyer).
- **Premier lancement** : round guidé ; première carte, le Port des Pêcheurs.

## 16. Pipeline d'images et de modèles

> **Mis à jour le 2026-10-19** : la 3D est abandonnée, voir `docs/GORDEKA_STYLE_2D.md` (styles
> `pf_2d__cutout` et `pf_2d__anim` demandés à pixelforge). Le principe reste : tout est généré par
> les outils de pixelforge.
>
> ~~**Décidé le 2026-10-19** : en 3D~~, **tout est généré par les outils de pixelforge**, exposés dans
> son API et intégrés à sa CI :
> - textures peintes sans couture (`pf_hd__texture`) ;
> - objets, bâtiments et personnages en modèles 3D (GLB texturés, low-poly), avec un matériau
>   `tenue` recolorable et un squelette simple pour les personnages.
>
> Les modèles faits en code dans `gk_view3d.gd` ne sont que des remplaçants. Les sections
> ci-dessous décrivent l'approche 2D d'avant, qui reste vraie pour les textures.

Les outils actuels (pixelforge, Retro Diffusion) sont faits pour le **pixel art**. Pour le style
retenu, il faut un modèle qui produit du **dessin cartoon lisse** : contours épais réguliers, aplats et
ombre douce, fond transparent. Il doit aussi garder un personnage identique d'une image à l'autre.

- **Demande à pixelforge** (Julien, 2026-10-19 : « faire évoluer son modèle ou en trouver un plus
  adapté ») :
  - un style `cartoon_clean` : même modèle d'édition guidée, sans pixellisation, avec une LoRA ou un
    modèle « flat cartoon / vector » ;
  - sortie en 512 px ou plus, détourée, avec des **couleurs par zones** pour pouvoir teinter la tenue
    (la couleur choisie par le joueur) ;
  - l'animation guidée par silhouette (mannequin) qui marche déjà en pixel art, en vue de dessus 3/4.
- **Besoins par personnage** (bien plus légers que pour le combat) :
  - une fiche de face en 3/4 et un portrait ;
  - 6 animations : immobile, marche, pouvoir, trouvé, victoire, fantôme ;
  - 2 directions (gauche en miroir) ;
  - les icônes de piège et de détection.
- **Décors** : cartes vues de dessus en 3/4. Les objets sont des sprites séparés (pour l'occlusion et
  l'ordre d'affichage), le sol est une grande image peinte.
- **Teinte par couleur** : la tenue est dessinée dans une couleur repère, puis recolorée par shader
  (12 couleurs). Les autres zones (peau, cheveux, accessoires) gardent leur couleur.
- **Prototype** (jalon 1) : aucune image nécessaire, des capsules de couleur suffisent. Le pipeline
  se met en place pendant le jalon 3.


### 16.1 Méthode retenue pour les persos (2026-10-19)

- **Méthode pixelforge du 2026-10-19** (validée par Julien, « super résultat »).
- Deux étapes, toutes deux par l'API `/v2/inferences` :
  1. `pf_2d__character` dessine le perso entier, de profil vers la droite. Julien choisit une
     variante.
  2. `pf_2d__animate` anime la variante choisie. Le mouvement vient des animations Quaternius
     (CC0, `GET /v2/motions`) et le dessin est fait par Wan Animate.
- Le jeu joue les planches telles quelles :
  - `GkPerso` lit `assets/gordeka/persos/<id>/<anim>.png`, `_tenue.png` et `.json` ;
  - le masque `_tenue` recolore la tenue dans la couleur du joueur ;
  - la marche et la course sont accélérées selon la vitesse réelle du perso.
  - pieds qui glissent (2026-10-20) : `tools/gordeka/pieds.py` (appelé par `import_perso.py`) mesure
    les pieds posés et écrit dans le `.json` un recalage par image `frame_offsets` (sur place : pieds
    fixes, sur ceux de l'idle) et un `stride_px` (déplacement : cadence = vitesse / stride, bornée à
    ×3 du fps) ; PNG intacts.
- Import : `tools/gordeka/import_perso.py <id> tools/gordeka/taches_<id>.json`.
- Prompts d'animation (2026-10-20) : `tools/gordeka/prompts_anims.json`, envoyés par `tools/gordeka/anime_perso.py`.
  Le squelette (`motion`) fait le mouvement du corps ; l'exagération passe par les réglages du mannequin
  (`exaggerate`, `bounce`, `arms`), les objets tenus par `hold`, et le mouvement de chaque accessoire
  est décrit animation par animation dans `action`. Repli en jeu : profil fixe (`modele.png`).
- Fantôme : le même perso avec de petites ailes d'ange (idée de Julien), à moitié transparent et
  flottant dans le jeu.

### 16.2 Historique des prompts par perso

But : pouvoir refaire un perso à l'identique. On note **chaque** génération retenue (style,
prompt, graine, image d'entrée, tâche). Les tâches pixelforge sont purgées au bout de 48 h : seuls
ces paramètres permettent de les relancer.

#### Louis (validé le 2026-10-19)
| Étape | Style | Entrée | Prompt / paramètres | Graine | Tâche |
|---|---|---|---|---|---|
| Esquisse (candidat n° 3 retenu) | `pf_hd__character` | — | « Clean flat 2D vector cartoon game character in the exact art style of Among Us: thick uniform dark navy outline, flat colors with one darker cel-shadow tone, tiny white highlight, no gradient, no texture. Full body side view facing right, standing calmly, arms relaxed along the body, feet flat on the ground. A cheerful 9 year old Basque boy: blond hair, red Basque beret, white shirt with rolled sleeves, red sash belt, navy trousers, rope espadrilles, big happy smile. Very chunky cute chibi proportions: big round head, short round body, short stubby legs, simple mitten hands, about 2.5 heads tall. Plain white background, no shadow on the ground. » (768 px) | 4102 | — |
| Retouche de profil (« A ») | `pf_hd__edit` | l'esquisse | « Turn this boy to a pure side profile view facing right, standing, arms relaxed. Keep exactly the same character, face, hair, beret, clothes and colors. Restyle as a flat 2D cartoon like the game Among Us: thick uniform dark navy outline, flat colors with one hard darker shadow tone, no gradients. Make him chunkier: big round head, short round body, short stubby legs. Plain white background. » | 5200 | — |
| **Modèle** (variante 3 sur 3 retenue) | `pf_2d__character` | la retouche A (fond blanc) | « a little Basque boy, red beret, blond hair, white short-sleeved shirt, red belt, navy rolled-up trousers, brown gloves and shoes », `num_images` 3 → `image_02.png` | 1 | `affc36bd90aa4e25ba350ee139b2fdc5` |
| Fantôme (variante 1 sur 2 retenue) | `pf_2d__character` | le modèle (fond blanc) | « the same little Basque boy, red beret, blond hair, white short-sleeved shirt, red belt, navy rolled-up trousers, brown gloves and shoes, with small white feathered angel wings on his back », `num_images` 2 → `image_00.png` | 7 | `0beeee88db1e43639247bacf45c794a6` |
| 13 animations | `pf_2d__animate` | le modèle (`image_02.png`) | `motion` = idle, walk, run_scared, hide_in, hide_out, found, trap, trapped, search, detect, extract, victory, sad ; `tenue` « shirt » ; `description` « a little Basque boy with a red beret » ; expressions par défaut des préréglages | défaut | `tools/gordeka/taches_louis.json` |
| ghost, ghost_move | `pf_2d__animate` | le fantôme | `motion` idle / walk ; `tenue` « shirt » ; `expression` « mischievous sly smile » ; `description` « a little Basque boy with a red beret and small white angel wings on his back, the wings flapping » | défaut | `tools/gordeka/taches_louis.json` |

À revoir sur Louis :
- « found » et « victory » sont un peu timides ;
- les ailes du fantôme bougent peu (le jeu le fait flotter).

#### Txomin (profil validé le 2026-10-19, animations à faire)
| Étape | Style | Entrée | Prompt / paramètres | Graine | Tâche |
|---|---|---|---|---|---|
| Essai écarté | `pf_2d__character` | `tools/rd/out/txomin/neutral_256.png` (pixel art Borroka, fond blanc, 512 px) | « a Basque lifeguard boy with dark brown skin and short black curly hair, black sunglasses, yellow tank top, red swim shorts, a silver whistle on a cord around his neck, a pair of blue swim fins hanging from his belt at his hip, barefoot, cheerful confident smile », `num_images` 3. Rendu pixelisé, casquette inventée : **ne pas partir d'un sprite pixel art.** | 1 | `13c35937f92b463fa794eb7f794ea95c` |
| **Modèle** (variante 2 sur 3 retenue par Julien → `image_01.png`) | `pf_2d__character` | aucune (description seule) | le même prompt + « bare head with no hat and no cap, smooth clean cartoon, no pixel art », `num_images` 3 | 1 | `149ffc0a84eb4d12b713216d6731ff32` |

#### Profils des 10 autres persos (run du 2026-10-19, `tools/gordeka/profils_persos.py`, choix de Julien attendus)
`pf_2d__character`, description seule, `num_images` 3, graine 1 ; à chaque prompt s'ajoute « , smooth clean cartoon, no pixel art ».

| Perso | Prompt | Tâche | Remarques |
|---|---|---|---|
| maia | « a young Basque surfer girl with wet brown hair in a ponytail, deep turquoise wetsuit with a navy panel, a small yellow surfboard strapped flat on her back, barefoot, hands empty, confident cheerful smile » | `b5c2e32aba454898a8c6233c6b95fdc3` | planche portée en travers du corps et non sur le dos (les 3) |
| patxi | « a bearded Basque fisherman, blue beanie, yellow raincoat, navy trousers, black boots, a fishing rod strapped on his back, hands empty, friendly smile » | `11e6f30a41564ff78fb939228778e3f1` | **variante 1 retenue** (`image_00.png`) ; animations en attente (Julien : profils d'abord) |
| xabi | « a Basque pelota player boy, white shirt and white trousers, red sash belt, a long curved wicker chistera basket glove on his hand, cheerful smile » | `7d011045d17848868609879d9a914277` | chistera mal rendue (panier rond) ; variante 2 à tête grise de mannequin |
| mattin | « a strong Basque stone lifter man, black mustache, red beret, red and white horizontally striped shirt, navy trousers, big muscular arms, friendly smile » | `fcb50f5c24ff41b992860791e5e90888` | **variante 1 retenue** (`image_00.png`), pieds à uniformiser : `pf_hd__edit` « both feet wear the same brown leather shoes », tâche `f3c384cfdc6e4ceb9e8a98942788d575` |
| amaia | « a Basque folk dancer girl, red headscarf, green vest over a white blouse, red skirt, white espadrilles, a wooden makila walking stick slung on her back, hands empty, cheerful smile » | `455ca52c6cb64e7f9b0836ad7e0f3fa9` | **variante 1 retenue** (`image_00.png`) |
| kaio | « a cheeky anthropomorphic seagull standing upright on two orange webbed feet, big yellow beak with a red dot, white head and belly, light grey wings used as arms with feathered fingertips, small grey tail, mischievous grin » | `bc43a467a3e6467eaf358ee113c97bc9` | **variante 2 retenue** (`image_01.png`) |
| karramarro | « a cheerful orange cartoon crab standing on its eight thin legs, two big orange pincers raised, eyes on stalks, yellow belly, big happy open mouth » | `3b9c8d989c5d46fcb647acf38ee2291f` | de face plutôt que de profil |
| ramuntxo | « a jolly Basque chef, tall white chef hat, white chef jacket, red neck scarf, checkered trousers, a frying pan hanging from his belt, hands empty, big smile » | `04b332683de44715960e433426fbfd26` | peau grise sur les 3 variantes : préciser la couleur de peau |
| itsaso | « a girl made of sea water, pale cyan skin, long wavy aqua hair, a dress of deep blue waves edged with white sea foam, barefoot, gentle smile » | `38bbce7c1da34d97882c78fcf0e5145d` | interrompu (arrêt de pixelforge) : à relancer |
| peio | « a sturdy young Basque rugby player with dark brown skin and short black hair, red and white hooped rugby jersey, black shorts, white socks, black boots, hands empty, no logo, big cheerful smile » | `d02476411bac480abdee501ed42a3ca1` | interrompu (arrêt de pixelforge) : à relancer |

#### Profils retenus le 2026-10-20 (`assets/gordeka/persos/<id>/modele.png`, graine 1)
Patxi : variante 1 ; Amaïa : variante 1 ; Kaio : variante 2 (tâches ci-dessus). Leçon : `pf_hd__edit` sait changer une couleur ou retirer un détail, mais déplace mal un objet ou une pose ; pour ajouter un objet porté, régénérer le perso avec l'objet dans le prompt.

| Perso | Choix | Style | Entrée | Prompt | Tâche |
|---|---|---|---|---|---|
| Maïa | variante 1 | `pf_2d__character` | — | « a young Basque surfer girl with wet brown hair in a ponytail, deep turquoise wetsuit with a navy panel, a small yellow surfboard carried upright behind her back with two shoulder straps, only its edge visible behind her shoulder, nothing in front of her body, barefoot, hands empty, confident cheerful smile, smooth clean cartoon, no pixel art » | `9b92d04a41a54ca6b10dd03af90301c5` |
| Itsaso | variante 1 ; aux animations, sa robe doit onduler comme des vagues (créature mythique) | `pf_2d__character` | — | « a girl made of sea water, pale cyan skin, long wavy aqua hair, a dress of deep blue waves edged with white sea foam, barefoot, gentle smile, smooth clean cartoon, no pixel art » | `90f5be1274a54c7fbd74f5c4afa1de1c` |
| Mattin | variante 1 + retouche des pieds n° 1 | `pf_hd__edit` | variante 1 du profil (fcb50f5c…) | « Keep this exact character, pose, colors and cartoon style. Only fix the feet: both feet wear the same brown leather shoes, identical color, no bare skin on the feet. Plain white background. » | `f3c384cfdc6e4ceb9e8a98942788d575` |
| Karramarro | variante 2 + retouche des yeux n° 1, trace verte effacée à la main | `pf_hd__edit` | variante 2 du profil (f536fa8d…) | « Keep this exact crab character, pose, colors and cartoon style. Only fix the eyes: both eyes on the stalks are plain white eyeballs with round black pupils and a tiny white highlight, no orange spot inside the eyes. Plain white background. » | `24663d9d743a4d0e915cab1e10f84d33` |
| Xabi (profil) | 3e essai, variante 3 | `pf_2d__character` | — | « a little Basque jai alai player boy, short dark brown hair, light peach skin, rosy cheeks, white polo shirt, white trousers, red sash belt, red espadrilles, cheerful smile. On his right hand he wears a jai alai cesta: a long curved wicker basket glove, as long as his whole arm, shaped like a big curved scoop or a long claw, light tan woven wicker, attached to his hand by a leather glove, held down at his side, smooth clean cartoon, no pixel art » | `60e424df5bd74e969541ed7be60b9b57` |
| Xabi (gant) | retouche n° 2 : gant retiré, main nue sur la chistera (option A de Julien) | `pf_hd__edit` | variante 3 ci-dessus | « Keep this exact boy, pose, colors and cartoon style. Only change his right hand: remove the separate brown leather glove; his hand slides directly into the open end of the long curved wicker chistera basket, the wicker sheath wraps around his hand and wrist as one single piece with the basket, tied at the wrist with a thin red cord. Plain white background. » | `c03cb85d38b14a3692c15b373e6b9072` |
| Ramuntxo | retouche n° 1 (moustache) ; écusson du tablier effacé et ikurriña collée sur la toque par `tools/gordeka/ramuntxo_drapeau.py` | `pf_hd__edit` | variante 1 du profil (8d41bc97…) | « Keep this exact chef: same big open smile, same face, apron, frying pan, pose, colors and cartoon style; the apron stays plain white with nothing printed on it. Add only: (1) a small thin dark brown mustache just above his smiling mouth, the smile still visible; (2) on the horizontal band at the bottom of his tall white chef hat, a tiny Basque flag patch: red rectangle with a green diagonal X cross and a white upright plus cross on top. Nothing else changes. Plain white background. » | `5c50f386be284f99be3fe87f1467b52c` |
| Peio | régénéré avec le ballon, variante 1 (les retouches `pf_hd__edit` ne mettaient pas le ballon sous le bras) | `pf_2d__character` | — | « a sturdy young Basque rugby player with medium brown skin and short black hair, red and white hooped rugby jersey, black shorts, white socks, black boots, no logo, big cheerful smile. He carries a brown oval rugby ball tucked tightly under his near arm against his ribs, elbow bent over the ball, the ball horizontal and pointing forward, his other arm relaxed, smooth clean cartoon, no pixel art » | `0e35624765f94c35a3facd35639d8760` |
