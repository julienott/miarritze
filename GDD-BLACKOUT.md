# Miarritze Blackout — document de conception (GDD)

> **Ce document fait foi pour tout le projet** : règles, personnages, boss, style, cartes, menus,
> réseau, pipeline d'images. En cas de doute ou de contradiction avec un autre fichier, **il prime**.
> Les autres documents ne sont que des procédures techniques (comment lancer un outil, une API) qui
> renvoient ici ; aucune décision de conception ne vit ailleurs. Toute nouvelle décision de Julien est
> écrite ici, datée, et les documents qui la contredisent sont corrigés ou archivés le jour même.
>
> Version du **22/10/2026** : fusion de l'ancienne spec (`archive/2026-10-22-docs-gordeka/SPEC-GORDEKA.md`), du GDD généré par
> IA que Julien a joint, du style Party Hard (`docs/STYLE_PARTY_HARD.md`) et des réponses de Julien
> au questionnaire du 22/10. Ce qui est marqué *à équilibrer* se règle en jouant ; tout le reste est
> décidé.

---

## 1. Pitch et piliers

**Miarritze Blackout** est un cache-cache asymétrique en temps réel, de nuit, dans Biarritz, en pixel
art vu de dessus façon *Party Hard*. À chaque round, un joueur tiré au sort devient **le chasseur** ;
les autres sont **les chassés**. Le chasseur voit devant lui, dans un cône que les murs et les objets
coupent, et l'ombre le gêne. Chaque personnage a **deux coups spéciaux** : un quand il est chassé, un
quand il est chasseur. La partie se termine par le **round du boss** : une créature de la mythologie
basque, jouée par l'IA, chasse tout le monde.

**Piliers**
1. **Lisible en une seconde.** Le cône rouge du chasseur se voit au sol chez les chassés. Un enfant de
   9 ans comprend sans tutoriel : « s'il me voit dans la lumière, je suis trouvé ».
2. **Contrôles simples.** Se déplacer, plus **un seul bouton** (coup spécial, entrer/sortir d'une
   cachette, fouiller, actionner).
3. **Jamais punitif, jamais violent.** Personne n'est blessé : on est *trouvé* et on devient un
   fantôme. Aucun effet ne bloque un joueur plus de 3 s (§4.3). Vocabulaire léger (§5).
4. **Entre copains, sans risque.** Salons en ligne publics ou privés par code, ou seul contre l'IA.
   Aucun texte libre entre joueurs, **zéro donnée personnelle** (pseudo seulement).
5. **Biarritz la nuit.** Lieux de la ville, personnages et boss du Pays basque.

## 2. Boucle de jeu

### 2.1 Une partie
`Qui joue ? (profil) → Accueil → (Partie rapide : réglages | En ligne : salons → salon) →
[tirage → versus → round → scores] × N rounds → round du boss → podium → retour accueil ou salon`.

- **N rounds** : par défaut le nombre de joueurs (chacun chasse une fois grâce au tirage en sac),
  réglable de 3 à 12. L'admin (ou le joueur en partie rapide) peut arrêter plus tôt pendant les scores.
- **Round du boss** : clôt chaque partie. Option « Boss final » dans la création de partie, **activée
  par défaut** (§5).

### 2.2 Un round
| Phase | Durée (données) | Ce qui se passe |
|---|---|---|
| Tirage | 3 s | Une roulette désigne le chasseur : « Tu es le CHASSEUR » / « Cache-toi ! ». |
| Versus | 5 s | Écran de suspense : à gauche le chasseur en grand (portrait, pseudo, icône de son coup de chasseur), à droite les chassés (portrait, pseudo, icône de leur coup de chassé), « VS » au centre avec une secousse, compte à rebours 5→1. |
| Cachette | 15 s | Le chasseur compte, écran voilé et immobile (« Bat, bi, hiru… »). Les chassés se cachent. |
| Chasse | 180 s | Le chasseur cherche. Coups spéciaux actifs. Sorties ouvertes à 90 s. |
| Fin | 6 s | Le round finit quand plus aucun chassé n'est libre, ou au chrono. Victoires individuelles : chaque chassé extrait ou libre au chrono gagne ; le chasseur gagne s'il en a trouvé plus de la moitié. Révélation des cachettes, puis scores. |

- **Tirage en sac** : chacun est chasseur une fois avant qu'un joueur le redevienne ; jamais deux
  rounds de suite le même.
- **Joueurs** : 2 à 8, **un seul chasseur** ; des IA complètent (au moins 4 joueurs).
- **Points de sortie** : 2 par carte, fixes et connus, dans des zones exposées. Ils s'ouvrent à 90 s
  de chasse ; un chassé qui y reste **4 s** sans être vu est **extrait** (il a gagné son round et
  devient spectateur).
- **Départs** : chasseur qui quitte → round arrêté sans points ; chassé qui quitte → il disparaît ;
  si l'admin l'a activé, une IA reprend la place au round suivant ; un joueur coupé garde sa place
  60 s.

### 2.3 Score
Cumulé sur la partie, affiché entre les rounds et au podium. Pas de classement en ligne.

| Action | Points |
|---|---|
| Chassé : par tranche de 10 s non trouvé | +1 |
| Chassé : encore libre à la fin du round | +5 |
| Chassé : extrait par un point de sortie | +8 |
| Chassé : délivrer un copain (§3.6) | +2 |
| Chassé : coup spécial qui touche le chasseur | +2 |
| Chasseur : chassé trouvé | +3 |
| Chasseur : tous trouvés avant la fin | +5 |
| Round du boss : par tranche de 5 s non trouvé | +1 |
| Round du boss : dernier survivant | +5 |

## 3. Règles

### 3.1 Vision du chasseur
- **Cône** de 90°, portée 7 cases, plus un cercle de 1,5 case tout autour de lui. Il suit la direction
  de marche (rotation lissée). Pas de second stick.
- Le cône est **coupé par les murs pleins et les objets hauts**. Les **éléments traversables**
  (fenêtres, grilles, rambardes) laissent passer la vue mais pas le passage.
- Hors de sa vue, l'écran du chasseur est assombri ; le décor reste visible pour s'orienter ; les
  chassés hors vue sont invisibles pour lui. Son client ne reçoit pas leur position (anti-triche).

### 3.2 Lumière et ombre (*décidé le 22/10*)
- La carte est de nuit. Des **sources de lumière fixes** (lampadaires, projecteurs, vitrines, phare)
  éclairent des zones ; le reste est dans l'**ombre**.
- **Dans le cône, un chassé éclairé** est détecté à la vitesse normale (§3.3). **Dans l'ombre**, la
  jauge monte **3 fois moins vite**, et le chasseur ne voit de lui qu'une **silhouette sombre**
  (shader monochrome), pas son sprite.
- **Disjoncteur** : un boîtier par secteur. Un chassé qui l'actionne (bouton, 1 s) éteint toutes les
  lumières du secteur pendant **15 s**. Le chasseur IA va le réparer ; un chasseur joueur peut le
  rallumer de la même façon. Cooldown du boîtier 30 s.
- Les chassés voient la carte entière, éclairée normalement, avec les zones de lumière bien visibles.
- Réglages dans `data/blackout/rules.json` (`ombre_facteur`, `disjoncteur_*`).

### 3.3 Être trouvé : détection progressive
- Quand un chassé est dans la vue du chasseur, une **jauge** se remplit : 0,3 s tout près, 1 s au bout
  du cône, plus lentement s'il n'est vu qu'en partie, 3 fois plus lentement dans l'ombre. Elle
  redescend doucement hors de vue (0,6 par seconde).
- Au-dessus du chasseur, **vus de tous** : une petite jauge jaune → rouge, un « ? » dès 30 %, un « ! »
  à la capture. Le chassé qui s'en tire souffle « ouf ! ».
- **Frisson du chassé** : pour le joueur chassé seulement, battement de cœur, vignette rouge sombre et
  vibration qui montent quand le chasseur approche (sous 8 cases), au plus fort quand il est vu ;
  « Il fouille à côté ! » quand le chasseur fouille une cachette à moins de 6 cases.

### 3.4 Cachettes
- Dans des objets (cabines, poubelles, casiers, coffres). Près d'une cachette, le bouton d'un chassé
  devient **Entrer**, puis **Sortir**. Une personne par cachette ; dedans on est invisible et on voit
  autour de soi. Pas de coup spécial depuis une cachette, sauf ceux qui le disent.
- **20 s au plus** dedans, puis éjection et cachette fermée 10 s.
- Près d'une cachette, le bouton du chasseur devient **Fouiller** (1 s) : s'il y a quelqu'un, il est
  trouvé. Fouille vide sans pénalité. L'objet tremble quand quelqu'un y entre.

### 3.5 Objets de la carte
- **Gâteaux basques = recharges** : posés au sol dans des coins dégagés. Un joueur (chassé ou chasseur)
  qui en ramasse un **recharge son coup spécial tout de suite**. Un gâteau mangé réapparaît ailleurs
  12 s plus tard, loin du chasseur. Y aller expose : ça crée du mouvement.
- **Mouettes** : groupes posés. Un chassé qui passe trop près les fait s'envoler en criant « kaio ! »,
  visible de tous : un indice pour le chasseur. Elles reviennent après 20 s.
- **Disjoncteurs** : §3.2.

### 3.6 Fantômes et délivrance
- Le chassé trouvé crie un « Trouvé ! » rigolo, joue l'animation **d'envol** (`lift`, il clignote en
  s'élevant) puis devient un **fantôme**.
- **Seuls les fantômes voient les fantômes** : ni le chasseur ni les chassés ne les voient. Un fantôme
  se déplace librement, traverse les murs, voit toute la carte.
- **Délivrance** : quand un fantôme est à 1,5 case d'un chassé libre, un **halo** apparaît autour du
  chassé (lui seul le voit) ; s'ils restent **3 s** ensemble hors de la vue du chasseur, le fantôme
  revient en jeu à cet endroit. Une fois par round et par fantôme ; +2 points au sauveur. Pas de
  délivrance pendant le round du boss.

### 3.7 Vitesses (données)
| | Vitesse |
|---|---|
| Chassé | 100 % |
| Chasseur | 115 % |
| Fantôme | 120 % |
| Boss | 110 % au départ, +5 % toutes les 20 s (§5.1) |

Pas de sprint ni d'endurance (*décidé le 22/10*) : les effets « endurance » des fiches deviennent des
bonus ou malus de vitesse. Tous les persos ont la même vitesse et la même empreinte au sol.

## 4. Coups spéciaux

*Décidé le 22/10 : ils remplacent les pièges et les détections.* La liste qui fait foi est celle de
Julien (§4.4).

### 4.1 Activation
- **Un seul bouton.** L'icône du bouton montre le coup du moment et se remplit pendant la recharge.
- **Recharge avec le temps** : environ **25 s** pour un coup de chassé, **20 s** pour un coup de
  chasseur (*à équilibrer*, par perso dans les données).
- **Recharge immédiate** en ramassant un gâteau basque (§3.5).
- Les coups « réflexes » (Maïa, Peio) se déclenchent quand on appuie au bon moment ; appuyés à vide,
  ils partent quand même et repartent en recharge.

### 4.2 Visée et déclenchement
- Les coups qui se lancent (pelote, ligne, bouée, pierre, pot de piment, faisceau) partent **droit
  devant, dans la direction de marche**, avec un **aimant de ±20°** vers une cible visible.
- Un chassé **dans une cachette** n'est pas touché, sauf par les coups faits pour ça (geysers
  d'Itsaso).
- Les coups de zone sont centrés sur le lanceur sauf mention contraire.
- Les chassés voient qu'un coup de chasseur a été lancé (icône au-dessus du chasseur), pour garder le
  jeu juste.

### 4.3 Garde-fous (enfants de 9 ans)
- **Aucun effet qui gêne les commandes ou la vue ne dure plus de 3 s** (figé, renversé, collé,
  commandes inversées, écran noir, ralenti). Les effets qui ne gênent personne (bonus de vitesse,
  mur, traces, révélation) peuvent durer plus.
- Après un effet subi, **2 s de protection** contre tout nouvel effet (pas d'enchaînement).
- Commandes inversées : **2 s** au plus.
- Écran noir ou masqué : le joueur voit toujours **sa propre silhouette**.

### 4.4 Les coups par personnage
Durées *à équilibrer* ; elles respectent déjà §4.3. `(c)` = case.

| Perso | Chassé | Chasseur |
|---|---|---|
| **Louis** | **Passe-Muraille** : saute par-dessus un obstacle d'une case (muret, haie, barrière) ou traverse une cloison fine devant lui ; il casse la ligne de vue, le chasseur doit faire le tour. | **Cache-Cache !** : « 1, 2, 3… j'arrive ! ». Pendant 5 s, les pas du chassé le plus proche clignotent au sol (piste qui s'estompe). |
| **Txomin** | **Fil d'Ariane** : lance sa bouée rouge vers un chassé en détresse à 6 c au plus (jauge de détection au-dessus de 30 % ou sous un effet) ; la bouée le tracte jusqu'à Txomin, puis une gerbe d'eau masque l'écran du chasseur 3 s s'il est à 4 c. | **Coup de sifflet de vigie** : tous les chassés qui **bougent** à 8 c ou moins sont figés 2 s ; les immobiles ne subissent rien. |
| **Patxi** | **Appât de sardines** : jette un seau derrière lui ; zone de 3 c pendant 4 s ; le chasseur qui la traverse voit de fausses traces de pas et des mouettes fantômes pendant 3 s. | **La prise au vol** : lance sa ligne droit devant (8 c) ; s'il accroche un chassé, il le tire de 4 c vers lui. |
| **Maïa** | **Le canard** : plonge au ras du sol ; 1,5 s invisible et intouchable (sa jauge ne monte pas), elle avance de 2 c et peut passer dans le dos du chasseur. | **Take-off foudroyant** : surfe sur un courant d'eau, +80 % de vitesse pendant 4 s. |
| **Xabi** | **Rebond d'urgence** : dash de 3 c, à l'opposé du mur le plus proche s'il est collé à un mur, sinon droit devant ; il traverse les persos. | **Le tir crayon** : pelote qui ricoche 3 fois sur les murs (12 c en tout) ; le chassé touché est collé 2 s et révélé 3 s. |
| **Mattin** | **Endurance du harrijasotzaile** : 4 s insensible à tous les effets ; s'il est trouvé pendant ce temps, il repousse le chasseur d'une case et la capture est annulée (une fois par round). | **La pierre traqueuse** : pose une pierre qui roule vers le chassé visible le plus proche (8 c) ; touché, il est renversé 2,5 s. |
| **Amaia** | **Mutxiko** : 4 s de pas de danse, +30 % de vitesse, insensible aux effets au sol (zones, flaques, racines), sans traces ni bruit de pas. | **Sonnerie du makila** : frappe le sol ; les chassés **immobiles** depuis plus de 2 s à 8 c tintent et brillent 2 s. |
| **Kaio** | **Battement de plumes** : vole 3 s par-dessus les obstacles bas (murets, buissons, rochers) et peut atteindre les cachettes en hauteur. | **Cri strident** : chassés à 5 c : commandes inversées 2 s ; s'ils bougent pendant ce temps, ils perdent des plumes qui les révèlent 3 s. |
| **Karramarro** | **L'enfouissement** : s'enfonce dans le sol meuble (sable, terre, herbe) ; invisible et indétectable tant qu'il ne bouge pas, 8 s au plus ; s'il bouge, il ressort avec un bruit de sable. | **Débordement crabe** : glissade latérale très rapide de 4 c dans sa dernière direction, pour jaillir d'un angle mort. |
| **Ramuntxo** | **Gâteau basque du partage** : pose un gâteau ; le chasseur qui passe à 1,5 c s'arrête pour le humer 1,5 s ; un chassé qui passe gagne +30 % de vitesse 3 s. Disparaît après 15 s ou un usage. | **Pot de piment d'Espelette** : lancé devant (6 c), nuage rouge de 2 c pendant 4 s ; les chassés dedans toussent 3 s, et la toux les révèle à travers les murs. |
| **Itsaso** | **Bâtisse éclair** : fait jaillir un muret de pierre de 3 c derrière elle, qui bloque la vue et le passage 4 s. | **Courant des laminak** : 3 geysers jaillissent près des cachettes à 10 c ; un chassé caché touché est éjecté de sa cachette et révélé 2 s par une éclaboussure. |
| **Peio** | **Feinte de passe** : pas de côté instantané de 2 c ; si sa jauge de détection dépasse 70 %, elle retombe à 0 et il gagne +30 % de vitesse 2 s. | **Troisième mi-temps** : cri de guerre ; chassés à 7 c ralentis de 30 % 3 s ; Peio voit leurs traces de pas 3 s. |
| **Itsasargi** | **Feu à occultation** : flash ; si le chasseur est à 6 c et regarde vers lui, son écran devient noir 2 s (il voit sa silhouette). | **Éclat révélateur** : faisceau droit devant (10 c) ; les chassés touchés, même derrière un buisson ou un muret, sont révélés à travers les murs 3 s et ralentis de 30 % 3 s. |

### 4.5 Effets communs (catalogue)
Les effets subis sont **les mêmes pour tous les persos** et **faits par le code**, posés sur n'importe
quel sprite : la matrice persos × effets se réduit à 13 + 10 éléments.

| Effet | Rendu (placeholder puis final) |
|---|---|
| Figé | contour bleu clair, petites étoiles |
| Renversé | sprite couché (rotation 90°), étoiles |
| Collé | flaque de résine sous les pieds |
| Ralenti | traits bleus derrière, sprite qui oscille |
| Révélé | contour lumineux visible à travers les murs (pour le chasseur) |
| Commandes inversées | plumes qui tournent au-dessus de la tête |
| Aveuglé / masqué | écran noir ou bleu d'eau, silhouette du joueur seule |
| Tracté | corde ou ligne tendue, glissade |
| Insensible | halo doré |
| Invisible / enfoui | sprite à 30 % pour son joueur seulement, rien pour les autres |

### 4.6 Animation des coups (*recommandation retenue*)
- Chaque perso a **2 animations de lancement** : un clip Quaternius pour son coup de chassé, un pour
  son coup de chasseur. **Pour l'instant : placeholders** (pose figée + flash + icône), affinés au fur
  et à mesure.
- Ce qui est lancé ou posé (pelote, bouée, pierre, gâteau, nuage, muret, geysers) : **formes simples
  en placeholder**, remplacées plus tard par de petits sprites pixelforge.
- Les effets subis : §4.5, par le code.

## 5. Le round du boss

### 5.1 Règles
- Dernier round de chaque partie (option « Boss final », activée par défaut).
- **Tout le monde est chassé**. Le chasseur est un **boss tiré au hasard**, contrôlé par l'IA.
- **Pas de sorties, pas de délivrance.** Il faut tenir le plus longtemps possible ; les coups de chassé
  restent actifs.
- Le boss part à 110 % de vitesse et accélère de +5 % toutes les 20 s : tout le monde finit par être
  trouvé. Il utilise ses deux pouvoirs en IA (recharge ~15 s).
- Points : +1 par tranche de 5 s, +5 au dernier survivant (§2.3).
- **Ambiance** : lune rouge, brume, lumières qui vacillent ; musique propre (quand le son reviendra).
- Les boss sont **plus gros** (64 px, §8.1) et un peu plus rapides ; plus tard, ils font fuir les PNJ.
- Vocabulaire léger : personne n'est blessé, mangé ni pétrifié. On est *trouvé*, *figé*, *délogé*.

### 5.2 Fiches des boss
Source : [lurkaia.com/fr/criaturas](https://lurkaia.com/fr/criaturas), choix de Julien. D'autres
viendront.

**Basajaun — le seigneur de la forêt**
- *Visuel* : colosse couvert d'une épaisse fourrure brune et d'une barbe de mousse ; mains comme des
  racines ; s'appuie sur un tronc sculpté.
- *Animation* : démarche lourde (l'écran tremble légèrement) ; immobile, il se confond avec les
  arbres ; quand il repère quelqu'un, il pousse un cri et accélère d'une foulée simiesque.
- *Murmure des bois* : 5 s, toutes les cachettes végétales (buissons, arbres) occupées brillent en vert.
- *Étreinte racinaire* : frappe le sol avec son tronc ; des racines immobilisent le chassé le plus
  proche (8 c) pendant 3 s.

**Intxixuk — les lutins des grottes**
- *Visuel* : **trio** de petits êtres bossus à la peau grise comme la roche, vêtus de peaux, coiffés de
  mousse sèche, yeux jaunes qui brillent. **Trois sprites de 32 px**.
- *Animation* : frénétiques et désarticulés, ils sautent partout en ricanant ; ils se relaient : l'un
  court au sol, les autres guettent.
- *Cercle de cromlech* : des pierres levées enferment un chassé repéré dans une petite arène pendant 3 s.
- *Farce de pierraille* : rafale de galets ; le chassé touché est ralenti de 40 % pendant 3 s.

**Tartalo — l'ogre cyclope glouton**
- *Visuel* : géant trapu avec **un seul gros œil au milieu du front**, peau tannée, grosse massue de
  bois.
- *Animation* : démarche asymétrique, renifle l'air sans arrêt ; quand il charge, il baisse la tête.
- *Regard du cyclope* : son œil projette un cône de lumière rouge à longue portée ; un chassé pris
  dedans est figé 2 s.
- *Broyage de cachette* : frappe le sol de sa massue ; toutes les cachettes légères à 15 c sont
  ouvertes et leurs occupants délogés.

**Herensuge — le dragon-serpent**
- *Visuel* : long serpent ailé à **trois têtes**, écailles couleur bronze et soufre.
- *Animation* : il ondule au-dessus du sol, ses têtes bougent chacune de leur côté pour scruter les
  angles morts.
- *Souffle de flammes* : une tête souffle sur une zone (4 c) ; les cachettes de la zone s'allument
  comme des braises et leurs occupants doivent sortir (aucun dégât).
- *Grande inspiration* : ouvre ses gueules et inspire ; les chassés dans un large cône devant lui sont
  lentement attirés vers lui et ralentis de 40 % pendant 3 s.

**Zezengorri — le taureau rouge**
- *Visuel* : taureau massif au pelage rouge vif, yeux brillants, cornes entourées de flammes magiques,
  fumée aux naseaux.
- *Animation* : gratte le sol du sabot, puis fonce ; laisse une traînée de braises.
- *Charge infernale* : fonce en ligne droite sur un chassé visible, trop vite pour l'esquiver à pied ;
  il faut se mettre derrière un élément solide (rocher, mur) : il s'y cogne et reste étourdi 3 s.
- *Souffle de soufre* : nuage autour de lui (3 c, 4 s) qui cache la vue ; les chassés immobiles dedans
  toussent et sont révélés.

## 6. Contrôles

| | Déplacement | Bouton | Menu |
|---|---|---|---|
| Tactile (iPhone, paysage) | joystick virtuel flottant à gauche | gros bouton à droite | petit bouton en haut à droite |
| Manette (et Steam Deck) | stick gauche ou croix | A | Start |
| Clavier | flèches ou ZQSD | Espace | Échap |

- Le bouton unique fait, par ordre de priorité : Entrer/Sortir (cachette) ou Fouiller, Actionner
  (disjoncteur), sinon le coup spécial.
- Les personnages **se traversent** : personne ne bloque personne.
- Le personnage regarde là où il va. Vibration courte quand on est trouvé ou touché par un effet.
- **Pas d'emotes** (*retirées le 22/10*).

## 7. Modes et menus

Tous les écrans se pilotent au toucher, à la manette et au clavier, en paysage, avec de gros boutons.
Aucun texte libre entre joueurs.

### 7.1 Écrans
1. **Qui joue ?** : jusqu'à 4 profils par appareil ; créer, choisir, supprimer (avec confirmation).
2. **Accueil** : Partie rapide, En ligne, Mon profil, Réglages, avec le portrait animé du profil actif.
3. **Mon profil** : choix du **personnage** (les 13) et du **pseudo** (2 à 15 caractères, filtre
   anti-gros-mots du serveur et hors ligne, rappel « pas ton vrai nom ! »). **Rien d'autre** : pas de
   couleur, pas de cosmétique, pas d'âge. Les joueurs se reconnaissent à leur **pseudo** affiché
   au-dessus de la tête. Deux joueurs peuvent prendre le même perso.
4. **Réglages** : vibration, aide. Les curseurs Musique et Sons sont **masqués** tant que le jeu n'a pas
   de son.
5. **Versus** avant chaque round, **Scores** entre les rounds, **Podium** à la fin.
6. **Pas de round guidé** au premier lancement (*retiré le 22/10*) ; des bulles d'aide en jeu suffisent.

### 7.2 Partie rapide (contre l'IA, en local)
- Hors ligne, sans compte, de 4 à 8 joueurs. « Jouer » lance avec les défauts : 6 joueurs, IA Normal,
  carte par défaut, rounds = nombre de joueurs, boss final activé.
- Réglages repliés : nombre de joueurs, difficulté des IA (Facile, Normal, Malin), carte, rounds (3 à
  12), boss final, options de gameplay validées (`data/blackout/options_partie.json`).
- **Menu debug (temporaire, jalon actuel)** : choisir son perso, son rôle (chassé, chasseur) et le boss,
  sur la carte bac à sable, sans chrono si on veut ; touche pour afficher les formes du décor et les
  zones de lumière.

### 7.3 En ligne : salons
- **Liste des salons publics** : nom automatique (« Salon de Léa »), carte, places, état, portraits.
  En haut : **Créer un salon** et **J'ai un code**.
- **Salon privé** : invisible dans la liste, rejoint avec un **code de 4 lettres** sans caractères
  ambigus, saisi au clavier de lettres à l'écran.
- **Places** : 4 à 8 (6 par défaut). Dans le salon, chacun change son perso librement (pas de « Prêt »).
- **L'admin** (créateur du salon) règle places, IA, rounds, boss final, options (et la carte),
  avant le lancement et entre deux rounds ; il lance (au moins 2 humains, IA en complément jusqu'à 4) ;
  il peut exclure un joueur et terminer la partie pendant les scores. Un humain arrivé en cours de
  partie regarde en fantôme puis **remplace une IA** au round suivant.
- **Si l'admin quitte**, le plus ancien humain devient admin (et hôte, §11). Une IA n'est jamais admin.
- Coupure : place gardée 60 s. Salon sans partie depuis 10 min : fermé.

### 7.4 Pas de jeu à plusieurs sur un même écran
La vision limitée du chasseur n'a pas de sens si tout le monde regarde le même écran.

## 8. Personnages

### 8.1 Échelle et éléments (*décidé les 21 et 22/10*)
- Persos de **32 px** de haut dans une **case de 64×64** (pieds à y=60) : la marge sert aux sauts et aux
  coups. Dessinés en **HD 256×256** par le moteur A de pixelforge, puis réduits ×4 en pixel art par le
  moteur B. Boss : **64 px** dans une case de 128×128 (HD 512) ; Intxixuk : trois sprites de 32 px.
- **Aucune personnalisation** : ni couleur de joueur, ni masque de tenue, ni cosmétique.
- Tout est de **profil tourné vers la droite** ; la gauche est le miroir.
- **Éléments par perso** :

| Élément | Rôle | Clip Quaternius |
|---|---|---|
| `profile` | sprite de référence | — |
| `portrait` | buste de **trois-quarts face**, 64×64 (HD 256), pour menus, versus, podium | — |
| `idle` | immobile | Idle_Loop |
| `idle_long` | pose d'inactivité propre au perso (§8.2) | par perso |
| `run` | course | Sprint_Loop |
| `jump_hide` | saut vers la cachette (la sortie = à l'envers) | Jump_Start |
| `lift` | envol avant de devenir fantôme, couleurs normales ; le **code fait clignoter** le perso | LiftAir_Idle_Loop |
| `ghost` | fantôme, **sans ailes** | Swim_Idle_Loop |
| `cast_chasse`, `cast_chasseur` | lancement des coups spéciaux (§4.6) | placeholders pour l'instant |

- Clips : **uniquement Quaternius**, nommés explicitement ; pixelforge a les bibliothèques UAL1 et
  **UAL2** depuis le 22/10 (182 clips, liste : `GET /v2/motions`).

### 8.2 Les 13 personnages
Les prompts sont volontairement **simples** : une description et une signature (ce qui doit se lire de
loin), sans négation. Les défauts de rendu (ombre, blanc entre les jambes, halos, flashs) sont à
corriger **chez pixelforge**, pas dans les prompts (Julien, 21/10).

**Bibliothèque de prompts v2 (22/10)** — copie machine : `data/blackout/style_party_hard.json`
(`persos`, `idle_long`) ; script de rejeu : `tools/blackout/party_hard_v2.py` (mêmes paramètres,
graine 7, chaîne moteur A → moteur B). Toute modification se fait ici d'abord, puis dans le JSON.

| Perso | Description (prompt) | Signature | idle_long : geste — clip |
|---|---|---|---|
| Louis — l'enfant du pays | a little Basque boy with blond hair, a red beret, a white short-sleeved shirt, a red belt and navy rolled-up trousers | a red Basque beret on blond hair | folds his arms and taps his foot, glancing around — Idle_FoldArms_Loop |
| Txomin — maître-nageur | a Basque lifeguard boy with dark brown skin and short black curly hair, a red cap, black sunglasses, a yellow tank top and red swim shorts, barefoot | a red cap and a yellow tank top | talks into his walkie-talkie held at his mouth — Idle_TalkingPhone_Loop |
| Patxi — pêcheur | a bearded Basque fisherman with a blue beanie, a yellow raincoat, light blue trousers and yellow rubber boots | a bright yellow raincoat and yellow boots | casts a fishing rod and waits for a bite — Fish_Cast_Idle_Loop |
| Maïa — surfeuse | a young Basque surfer girl with a brown ponytail, a turquoise wetsuit with a navy panel, a small yellow surfboard strapped upright on her back, barefoot | a small yellow surfboard upright on her back | chats cheerfully with big hand gestures — Idle_Talking_Loop |
| Xabi — pelotari | a little Basque jai alai player with short dark brown hair, a white polo shirt, plain white trousers, a red sash, red espadrilles and a long curved wicker chistera on his right hand pointing forward | a long curved wicker chistera pointing forward | practises a chistera swing — Sword_Attack |
| Mattin — leveur de pierre | a short stocky Basque stone lifter with a broad muscular chest, a black beard, a red beret, a red and white horizontally striped shirt, navy trousers and brown shoes | red and white horizontal stripes on a broad chest | lifts a heavy round stone — PickUp_Table |
| Amaia — dantzari | a Basque folk dancer girl with a red headscarf, a green vest over a white blouse, a red skirt, simple white shoes and a wooden makila stick on her back | a red headscarf and a red skirt | dances a few Basque folk steps — Dance_Loop |
| Kaio — goéland | a cheeky upright seagull with a white head and belly, light grey wings used as arms, a big yellow beak with a red dot and orange webbed feet | a big yellow beak and orange webbed feet | screams with his beak wide open — Idle_Rail_Call |
| Karramarro — crabe | a cheerful orange cartoon crab standing on six thin pointed crab legs, two big raised pincers, eyes on stalks, a yellow belly and a big happy open mouth | two big raised orange pincers and eyes on stalks | scratches his head with a pincer — Zombie_Scratch |
| Ramuntxo — chef des Halles | a jolly Basque chef with a small brown mustache, a tall white chef hat, a white chef jacket, a red neck scarf, plain red trousers and black shoes | a tall white chef hat | tastes a sauce from a wooden spoon — Consume |
| Itsaso — esprit de l'écume | a mythical girl made of sea water with pale cyan skin, long wavy aqua hair and a dress of deep blue waves edged with bright white foam, barefoot | long flowing aqua hair and a white foam hem | swirls a small wave between her hands — Spell_Simple_Shoot |
| Peio — rugbyman | a sturdy young Basque rugby player with medium brown skin and short black hair, a red and white hooped jersey, black shorts, white socks, black boots and an oval rugby ball under his arm | a brown oval rugby ball under his arm | spins his rugby ball in his hands — Interact |
| Itsasargi — gardien du phare | an old lighthouse keeper with a white beard, a captain cap, a navy pea coat and a big glowing brass lantern held firmly by its handle in front of him | a big glowing yellow lantern held forward | raises his lantern and peers into the dark — Idle_Lantern_Loop |

Changements du 22/10 (retours de Julien sur le run du 21/10) : Txomin sans palmes, casquette rouge ;
Patxi sans canne (elle n'apparaît que dans son idle_long), pantalon bleu clair et bottes jaunes ; Xabi
pantalon blanc uni, chistera vers l'avant ; Mattin plus petit, torse musclé ; Amaia chaussures blanches
simples ; Kaio et Karramarro sans foulard, Karramarro sur pattes de crabe ; Ramuntxo pantalon rouge
uni et chaussures noires ; Itsaso écume blanche ; Itsasargi lanterne plus grosse, bien tenue. Louis,
Maïa et Peio inchangés.

### 8.3 Boss
Même pipeline, en 64 px (§8.1). Prompts tirés des fiches §5.2 (visuel), écrits au moment de les
générer et ajoutés ici.

## 9. Direction artistique

Référence : **Party Hard 1** (analyse détaillée, mesures et captures : `docs/STYLE_PARTY_HARD.md`).
- **Pixel art pur** : résolution logique **640×360**, affichée ×2 (1280×720), filtre plus proche voisin.
  **1 case = 32 px = 1 perso.** Caméra qui **suit le joueur** (nos cartes font plusieurs écrans).
- **Vue de dessus oblique « maison de poupée »** : sol vu d'en haut, murs du fond montrant leur face,
  autres murs réduits à une arête sombre de 5–6 px ; meubles « dessus + face » alignés sur la grille ;
  pas de toit.
- **Persos** : ~32 px, ~5 têtes, sans contour noir, lisibles à leur silhouette et à 2–3 aplats ; 6 à 10
  couleurs vives et contrastées. Animation sobre : poses tenues 100 ms, course en 4 poses, rebond 1 px.
- **Nuit** : grandes surfaces sombres et désaturées (bleu nuit, violet), couleurs franches réservées
  aux persos, aux lumières et aux objets interactifs. **Lumière additive** saturée et chaude : halos
  jaunes des lampadaires, néons rose et cyan, faisceau du phare, rouge de Tartalo. L'ombre est une
  vraie zone de jeu (§3.2).
- **Pays basque** : maisons labourdines blanchies à la chaux, colombages et volets rouges, toits de
  tuiles, crampottes, barques peintes, quais de pierre, lauburu et linge basque par touches, gâteaux
  basques, piments d'Espelette, chisteras.
- **Sols à motif** par zone, peu contrastés. **HUD minimal** en police pixel.
- **Jamais inquiétant pour un enfant** : même les boss restent des créatures de conte.

## 10. Cartes

### 10.1 Jalon actuel : la carte « bac à sable »
*Décidé le 22/10 : on fait tourner le jeu et on affine personnages et gameplay avant le level design.*
- Cases de 32 px, **placeholders** (aplats et formes simples).
- Contenu : pièces et couloirs, **murets d'une case** (Louis, Kaio), **cloisons fines** (Louis),
  **grilles et fenêtres** (vue oui, passage non), **sol meuble** (Karramarro), **cachettes**, objets
  hauts et bas, **lampadaires** et zones d'ombre, **un disjoncteur** par secteur, gâteaux basques,
  mouettes, 2 points de sortie.
- Menu debug pour tester chaque coup avec chaque perso, chaque rôle et chaque boss (§7.2).
- Les anciennes cartes (Port des Pêcheurs, plage de la Côte des Basques, parc Mazon), en cases de 64 px
  et sans lumière, sont **archivées** ; elles serviront de références de lieux.

### 10.2 Règles du décor
- Chaque objet a une **forme d'occlusion** (bloque la vue) et une **forme de collision** (bloque le
  passage), souvent identiques ; données dans `assets/maps/<id>/map.json`.
- Les éléments **traversables** (fenêtres, grilles, rambardes) ne bloquent que le passage ; les objets
  **bas** (murets, buissons) bloquent le passage mais pas la vue d'un perso debout.
- Un objet haut placé devant un perso le masque à moitié : un chassé masqué n'est vu qu'à courte
  portée, ses coéquipiers voient l'objet en transparence. Les masques et emprises des objets viennent de
  pixelforge quand ils existent, sinon d'un calcul sur l'alpha de l'image (procédure :
  `docs/TEST_DECOR.md`).
- **Masques du décor : en suspens** (*Julien, 22/10*). Deux pistes étudiées, aucune lancée :
  volume déclaré par objet et masques calculés par pixelforge (`docs/RECHERCHE_MASQUES_DECOR.md`, spec
  mise en pause : Julien doute qu'il faille écrire un volume par objet) ; modèle dédié entraîné chez
  pixelforge, sans token par objet (`docs/RECHERCHE_MODELE_MASQUES.md`, recommandé par la recherche,
  « pas maintenant »). On y revient après le jalon 1 : la carte bac à sable n'a pas de décor en image.
- Taille visée d'une carte finale : environ 14 zones reliées par des couloirs, ~5 écrans de large.

### 10.3 Cartes à venir (après le jalon)
Lieux de Biarritz : Port des Pêcheurs, Grande Plage, Les Halles, Parc Mazon, Côte des Basques, puis
Phare (annexe A.2), Aquarium, Rocher de la Vierge, Fronton.

## 11. IA
- **Chassés IA** : choisir une cachette à l'abri des grands axes et dans l'ombre, différente des
  autres ; surveiller le cône, fuir dès que leur jauge monte, changer de cachette dans le dos du
  chasseur, utiliser leur coup quand c'est pertinent, actionner un disjoncteur.
- **Chasseur IA** : patrouiller entre les zones, regarder derrière les gros objets, réagir aux indices
  (mouettes, toux, traces), lancer son coup au bon moment, réparer un disjoncteur.
- **Boss** : chasseur IA plus rapide, qui accélère, avec ses deux pouvoirs (§5).
- **Difficultés** : Facile (chasseur lent à tourner la tête, chassés qui bougent trop), Normal, Malin
  (fouille méthodique, chassés qui changent de cachette dans son dos).
- Navigation : `NavigationRegion2D` générée depuis la carte.

## 12. Réseau
- **Hôte-autorité** : l'appareil de l'admin fait tourner la partie, IA comprises. Les autres envoient
  leurs entrées 20 fois par seconde ; l'hôte renvoie l'état 20 fois par seconde ; interpolation
  ~100 ms côté client. Pas de simulation déterministe ni de rollback ; « trouvé » est décidé par
  l'hôte seul.
- **Anti-triche** : un client chasseur ne reçoit pas la position des chassés hors de sa vue ; personne
  ne reçoit la position des fantômes sauf les fantômes.
- **Transport** : WebRTC en étoile (hôte relié à chacun), signalisation PHP par polling, STUN et relais
  TURN Cloudflare, extension WebRTC native pour le Steam Deck.
- **Hôte qui part** : le plus ancien humain devient admin et hôte ; le round en cours est annulé sans
  points et la partie reprend au round suivant avec l'état du salon (joueurs, scores, réglages).
- **Serveur PHP** : salons (public/privé, code, liste, places, état, admin, exclusions, purge),
  présence, signalisation. API : `docs/ONLINE.md`. Routes et tables gardent leur préfixe historique
  `gk_` (données en prod).

## 13. Plateformes et technique
- Godot 4.7, GDScript typé, renderer Compatibility, export web threadé. **v1 : web (navigateur et
  iPhone en paysage) et Steam Deck** (export natif à refaire ; Recalbox abandonné).
- Code : `src/blackout/` (préfixe `bk_`), données `data/blackout/`, outils `tools/blackout/`,
  tests `tests/bk_tests.gd`. Tout réglage de jeu est une donnée (`data/blackout/rules.json`) : durées,
  vitesses, cône, lumière, recharges, effets, points.
- Backend PHP + SQLite, même origine `/api`. Outils Python (`.venv/`), Playwright (`tests/web/`).
- **Son** : aucun pour l'instant (l'audio de Borroka a été supprimé le 22/10). Plan : annexe A.1.
- Tests : règles en headless (vision, ombre, détection, coups, fin de round, tirage), IA contre IA sur
  la carte, salons à deux navigateurs.
- Déploiement : à la main, seulement sur décision de Julien.

## 14. Pipeline d'images (pixelforge)
- **Moteur A** `pf_px__character_set` : perso et animations en pixel art HD (256 px de case).
  **Moteur B** `pf_px__reduce` : réduction ×4 en 32 px (palette verrouillée, couleurs vives et
  contrastées, selout, pieds stables). Chaînés à la mise en file (`then`).
- **Les jobs passent par la file de pixelforge** (API), jamais par un message. Les messages à
  pixelforge servent aux demandes de capacité.
- **Prompts simples** (§8.2) ; pixelforge corrige ses défauts lui-même.

### 14.1 Contrat persos avec pixelforge (*22/10*)
Référence côté pixelforge : la description publiée des styles (`GET /v2/styles`, `pf_px__character_set`
et `pf_px__reduce`). Ce qui suit est ce que **nous** attendons ; tout écart se règle par message à
pixelforge, jamais par un traitement de notre côté.

**Ce que nous envoyons** (un job par perso, `tools/blackout/party_hard_v2.py`) : le prompt (description +
signature, §8.2), `colors`, la graine, et la liste `extras`. Rien d'autre : ni palette, ni retouche.

**Ce que pixelforge livre**, chaîne A (HD, case 256, pieds à 240) → B (32 px, case 64, pieds à 60) :
- éléments fixes : `profile`, `portrait` (buste de trois-quarts face), `idle` (Idle_Loop), `run`
  (4 poses, Sprint_Loop), `jump_hide` (Jump_Start), `lift` (LiftAir_Idle_Loop), `ghost` (Swim_Idle_Loop) ;
- **plusieurs extras** dans le même set : chacun `{name, motion, action, object, loop, fps, frames,
  anchor}`, même palette, même cadrage, même ligne de pieds. Aujourd'hui un seul (`idle_long`) ; demain
  aussi les lancements des coups spéciaux (§4.6) ;
- `set.json` : cadence, boucle, calage, ligne des pieds, palette, contrôles.

**Animation ajoutée à un perso déjà validé** (*question de Julien, 22/10, demandée à pixelforge*) :
mode « extras seuls » de `pf_px__character_set`. Référence = le perso validé : sa tâche si elle existe
encore, sinon son `profile_hd.png` et son `set.json`, que nous gardons dans `assets/blackout/persos/<id>/hd/`
(les tâches sont purgées après 48 h).
**Perso validé = conservé des deux côtés** (*Julien, 22/10*) : quand Julien valide un perso en QA, ses tâches
A et B sont marquées « à garder » chez pixelforge (jamais purgées ; conservation exposée dans l'API,
demandée le 22/10) et sa référence est committée chez nous (`hd/profile_hd.png`, `hd/set.json` et le
dossier `px32/`). Tous les éléments fixes sont sautés, et la nouvelle animation garde
la même palette, le même cadrage, la même ligne des pieds et la même échelle. En B, la réduction reprend la
palette 32 px du set d'origine. Les éléments déjà validés ne sont jamais régénérés.

**Clip absent de sa banque** : uniquement des clips Quaternius nommés (21/10). Un clip inconnu doit être
**refusé au dépôt** avec les clips les plus proches, pas ignoré en silence ; je soumets le remplaçant à
Julien. Une nouvelle bibliothèque se demande par message, avec l'accord de Julien. Pas de clip sur mesure.

**Qualité due par pixelforge** (Julien : « Nous devons faire des prompts, pixelforge nous livrer des
images de qualité. C'est à lui de faire les traitements corrects. ») :
1. aucune ombre au sol ; fond enfermé transparent (entre les jambes, entre la main et un objet), blanc
   des vêtements gardé ;
2. pas de halo de bord ; palette simplifiée pour la réduction (aucune nuance jumelle) ;
3. chaque zone garde sa couleur d'une image à l'autre, en se référant au profil (aucun clignotement) ;
4. course fluide : les 4 phases clés (contact, passage, contact, passage), tête stable à 1 px près ;
5. portrait et animations fidèles au profil, sans détail inventé ;
6. objet de l'action réellement dessiné ;
7. pieds sur la ligne, rien qui sorte de la case.

**Défauts ouverts** (Louis v2, 22/10) : 1 (ombre et blanc entre les jambes sur `profile_hd`), 2 (palette
de 20 couleurs avec rouges jumeaux), 3 (pantalon bordeaux sur une image de la course HD), 4 (course
irrégulière), 5 (étoile jaune inventée sur le béret du portrait). Run v2 suspendu jusqu'à leur
correction ; on relancera Louis seul d'abord.

- **Décor** : masques en suspens (§10.2).
- Méthode de travail : on intègre chaque rendu tel quel, **Julien tranche en QA** sur /producer
  (procédure : `docs/PRODUCER.md`).

## 15. Jalons et travail à faire
1. **Jalon actuel — jouable sur carte nue** : carte bac à sable, lumière et ombre, coups spéciaux en
   placeholders (13 × 2), effets communs, recharges, fantômes invisibles et délivrance, round du boss
   avec un boss placeholder, menu debug, pseudo seul, sans emotes. Échelle 640×360 et cases de 32 px.
2. **Persos v2** : run pixelforge avec la bibliothèque v2 et les corrections de pixelforge, puis QA.
3. **Boss** : 5 boss en 64 px (Intxixuk en trio).
4. **Équilibrage** : rounds IA contre IA, puis tests avec Louis.
5. **Level design** : première vraie carte de Biarritz.
6. **En ligne** : salons branchés sur le jeu (signalisation `/room/signal`).
7. **Finitions** : son et musique, écran « tourne ton appareil », icônes et PWA, export Steam Deck.

## 16. Journal des décisions
- **19/10** : pivot du jeu de combat Borroka vers un cache-cache (« Gordeka »).
- **20/10** : salons publics et privés à la place des groupes ; menus, versus, podium.
- **21/10** : style Party Hard (pixel art, persos 32 px, caméra qui suit, aucune personnalisation) ;
  ancien visuel archivé (`archive/2026-10-21-flat-cartoon/`) ; clips Quaternius uniquement ; fantôme
  sans ailes ; 6e élément idle_long.
- **22/10** : Borroka supprimé du dépôt (restent réseau, client pixelforge, backend des salons) ;
  le jeu devient **Miarritze Blackout** ; ce GDD fait foi ; code renommé (`bk_`, `src/blackout/`) ;
  lumière et ombre dans les règles ; coups spéciaux (liste de Julien) à la place des pièges et
  détections ; recharge temps + gâteaux ; visée droit devant avec aimant ; garde-fous de 3 s ;
  vocabulaire adouci ; round du boss en fin de partie, sans délivrance ; boss 64 px ; fantômes
  visibles des seuls fantômes ; délivrance par halo ; emotes, chatouille, round guidé, couleurs de
  joueur et progression cosmétique retirés ; pas de sprint ; portrait de trois-quarts ; case de 64 ;
  canne de Patxi retirée ; carte bac à sable ; web, iPhone et Steam Deck ; UAL2 chez pixelforge : Louis garde
  Idle_FoldArms_Loop (Idle_LookAround n'existe pas), Itsaso prend Spell_Simple_Shoot.

---

## Annexe A — Plus tard (idées retenues, hors jalon)

### A.1 Son et musique
- Ambiance : ressac, vent sur la falaise, goélands au loin.
- Musique : synthwave rythmée par une **txalaparta** électronique, deux arrangements synchronisés :
  patrouille (percussions, basse sourde) et chasse (synthés saturés, tempo pressant), en fondu
  enchaîné quand le chasseur repère quelqu'un. Prompts de musique : `docs/PROMPTS_MUSIQUE.md`.
- Sons : pas feutrés, « Bat, bi, hiru… », « Trouvé ! », toux, sifflet, cris des coups.

### A.2 Niveau du Phare de Biarritz
- 40 % d'espaces ouverts (danger), 60 % cloisonnés (infiltration).
- Esplanade centrale circulaire balayée par le faisceau du phare (360°) ; maison du gardien (petites
  pièces, fenêtres) ; sentiers de la falaise (buissons denses, cul-de-sac au bord du vide).

### A.3 Caisses à pousser
Piles de caisses de poisson ou de bois : les pousser quand le chasseur passe le fait trébucher (étourdi
2 s).

### A.4 PNJ de la fête
Une foule de PNJ façon Party Hard, que les boss font fuir.
