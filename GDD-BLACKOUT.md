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
- **Rendu (*Julien, 23/10*)** : le cône et le cercle de proximité forment **une seule forme**, sans
  bordure, en aplat de couleur, avec un léger dégradé d'opacité qui s'efface avec la distance. Sous le
  chasseur, un **halo rouge pixellisé** à la place de l'anneau.
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
- **Dans le noir, le chasseur voit moins loin** (*Julien, 23/10*) : regardé dans l'ombre, un chassé n'est
  vu qu'à **4 cases** au lieu de 7 (`ombre_portee`) ; le cercle de proximité reste. Un secteur coupé
  devient un vrai refuge.
- **Silhouette progressive** (*Julien, 23/10*) : un chassé dans l'ombre est une silhouette sombre au bout
  de la vue ; ses couleurs reviennent peu à peu quand le chasseur s'approche, et il est entier dans le
  cercle de proximité.
- La carte doit avoir **assez de lumières et de disjoncteurs** pour que l'ombre et les coupures comptent
  (retour de Julien sur le bac à sable : à augmenter).
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
- **Mouettes** (*devenues des PNJ oiseaux, §3.8*) : groupes posés. Un chassé qui passe trop près les fait s'envoler en criant « kaio ! »,
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

### 3.8 PNJ : la foule de la nuit (*Julien, 23/10*)
La carte est habitée par des **personnages non joueurs** (PNJ) qui vivent leur vie : ils remplissent la
carte, donnent l'ambiance de fête du soir à Biarritz, et offrent aux chassés un camouflage vivant.

**Qui** : des **humains** (15 à 25 par carte, réglable par carte) et, **en plus de ce quota**, des
**animaux** (6 à 12 : chats, chiens, goélands, pigeons). Tous tirés de la bibliothèque §8.4, sans jamais
reprendre un des 13 persos jouables. Les PNJ ne sont ni chassés ni chasseurs : on ne peut ni les trouver
ni les toucher, et ils ne bloquent pas le passage (on les traverse, comme les joueurs).

**Leur vie** (IA simple, jouée par l'hôte et synchronisée) :
- chaque carte a des **points d'activité** (banc, bar, terrasse, kiosque, quai, piste de danse…) ;
- un PNJ y fait une **activité** (parler, téléphoner, danser, écouter de la musique, lire le journal,
  boire un verre, s'asseoir…), **statique** quelques dizaines de secondes, puis **marche** vers un autre
  point et y fait une autre activité ; certains restent sur place tout le round ;
- les PNJ se **regroupent** : 2 à 4 se rejoignent sur un point et parlent ensemble un moment, puis se
  séparent ;
- un promeneur de chien est un **couple PNJ + animal** : le chien suit son maître en laisse ;
- les animaux ont leurs propres manières : le chat dort ou se lèche, puis file ; le chien renifle et suit ;
  les goélands et pigeons picorent en petits groupes.

**Camouflage**
- **Le chasseur ne voit pas les pseudos des chassés** (seulement après une capture). Les chassés, eux, voient
  les pseudos de tout le monde, et les PNJ n'en ont pas.
- **Dans un groupe** (un chassé à moins d'une case d'au moins deux PNJ), la détection **ne démarre que si
  le chasseur est dans son cercle de proximité** (1,5 case) : de loin, un chassé qui marche ou attend au
  milieu d'un groupe se confond avec la foule. S'il **court**, il sort du camouflage.
- Les PNJ n'arrêtent pas le cône : ce sont des personnes, pas des murs.

**Réactions à l'action en cours** (toutes visibles de tous)
- **Un chassé qui court tout près** d'un PNJ le fait sursauter (« ! » au-dessus de sa tête) et fait
  s'envoler les oiseaux voisins : **un indice pour le chasseur**. Les mouettes actuelles (§3.5) deviennent
  ces PNJ oiseaux.
- **Lumière coupée** (disjoncteur) : les PNJ du secteur ont peur un moment (« ! ») et courent vers une zone
  éclairée, puis reprennent leur vie quand la lumière revient.
- **Coup spécial** : les PNJ dans le rayon de l'effet sursautent, étonnés, et s'enfuient hors du rayon ;
  ils ne subissent jamais l'effet.
- **Round du boss** : les PNJ **évitent absolument le boss**, paniqués : ils courent dans la direction
  opposée dès qu'il approche, et la foule se vide autour de lui.

**Animations d'un PNJ** : profil, idle, fuite apeurée (course), marche, sursaut, à terre, se relever, plus 2 activités (§8.4).
Tant qu'elles n'existent pas, des placeholders de 32 px font l'affaire.

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
Les effets subis sont **les mêmes pour tous les persos**. Le code dessine les marques (étoiles,
résine, plumes…) ; **le perso joue en plus une animation d'effet** (*Julien, 23/10*), élément standard de
son character set (§8.1), la même pour tous.

| Effet | Marques par le code | Animation du perso (élément standard, clip) |
|---|---|---|
| Figé | contour bleu clair, petites étoiles | `etourdi` (Hit_Shoulder_L puis Hit_Shoulder_R : touché d'un côté puis de l'autre ; *Julien 23/10*) |
| Commandes inversées | plumes qui tournent au-dessus de la tête | `etourdi` |
| Renversé | étoiles | `renverse` (Hit_Knockback puis LayToIdle : il tombe et se relève) |
| Collé | flaque de résine sous les pieds | `colle` (Crouch_Fwd_Loop ; *Julien 23/10*) |
| Ralenti | traits bleus derrière | `ralenti` (Zombie_Walk_Fwd_Loop : marche lourde) |
| Aveuglé / masqué | écran noir ou bleu d'eau, silhouette du joueur seule | `aveugle` (Spell_Double_Shoot_Loop : yeux fermés, il tâtonne ; *Julien 23/10*) |
| Tracté | corde ou ligne tendue | `tracte` (Slide_Loop ; *Julien 23/10*) |
| Révélé | contour lumineux visible à travers les murs (pour le chasseur) | aucune |
| Insensible | halo doré | aucune |
| Invisible / enfoui | sprite à 30 % pour son joueur seulement, rien pour les autres | aucune |

### 4.6 Animation des coups (*recommandation retenue*)
- Chaque perso a **2 animations de lancement** (extras `cast_chasse`, `cast_chasseur`) : un clip
  Quaternius pour son coup de chassé, un pour son coup de chasseur, choisis par coup (liste des 26 à
  valider par Julien ; essai sur Txomin le 23/10). En attendant : placeholders (pose figée + flash).

**Clips de lancement** (*Julien, recette du 23/10 : selon la famille du coup — « lance » : OverhandThrow ; les autres : Spell_Simple_Enter + Spell_Simple_Exit* ; copie : `casts` dans `data/blackout/style_party_hard.json`)

| Perso | Coup de chassé : clip, action | Coup de chasseur : clip, action |
|---|---|---|
| louis | Spell_Simple_Enter+Spell_Simple_Exit, « raises one hand, then sweeps it forward as if passing through a wall » | Spell_Simple_Enter+Spell_Simple_Exit, « raises both hands to his mouth, then throws them open to call out » |
| txomin | OverhandThrow, « throws his red rescue buoy forward to a friend » | Spell_Simple_Enter+Spell_Simple_Exit, « raises his silver whistle to his lips, then lowers it after a sharp blow » |
| patxi | Spell_Simple_Enter+Spell_Simple_Exit, « lifts a small bucket up, then tips it forward to drop sardines on the ground » | OverhandThrow, « casts his fishing line far forward » |
| maia | Spell_Simple_Enter+Spell_Simple_Exit, « raises her arms, then sweeps them down as if diving under a wave » | Spell_Simple_Enter+Spell_Simple_Exit, « lifts her yellow surfboard up, then swings it forward » |
| xabi | Spell_Simple_Enter+Spell_Simple_Exit, « pulls his arms back, then pushes off forward in a quick dash » | OverhandThrow, « hurls a pelota ball with his chistera » |
| mattin | Spell_Simple_Enter+Spell_Simple_Exit, « raises both arms, then flexes them proudly » | OverhandThrow, « heaves a heavy round stone forward » |
| amaia | Spell_Simple_Enter+Spell_Simple_Exit, « lifts her hands high, then lands a quick light Basque dance step » | Spell_Simple_Enter+Spell_Simple_Exit, « raises her wooden makila stick, then brings it down on the ground » |
| kaio | Spell_Simple_Enter+Spell_Simple_Exit, « raises his wings, then flaps them down hard » | Spell_Simple_Enter+Spell_Simple_Exit, « raises his wings, then sweeps them forward with a loud call » |
| karramarro | Spell_Simple_Enter+Spell_Simple_Exit, « raises both claws, then digs them down into the sand » | Spell_Simple_Enter+Spell_Simple_Exit, « raises both claws, then sweeps them sideways » |
| ramuntxo | Spell_Simple_Enter+Spell_Simple_Exit, « lifts a round Basque cake up, then sets it forward on the ground » | OverhandThrow, « throws a small pot of red pepper » |
| itsaso | Spell_Simple_Enter+Spell_Simple_Exit, « raises her hand, then sweeps it forward » | Spell_Simple_Enter+Spell_Simple_Exit, « raises both hands, then pushes them down hard » |
| peio | Spell_Simple_Enter+Spell_Simple_Exit, « fakes a pass with both arms up, then pulls them back » | Spell_Simple_Enter+Spell_Simple_Exit, « raises his fists high, then shouts a war cry » |
| itsasargi | Spell_Simple_Enter+Spell_Simple_Exit, « raises his brass lantern high, then lowers it » | OverhandThrow, « swings his brass lantern overhead and forward » |

- Ce qui est lancé ou posé (pelote, bouée, pierre, gâteau, nuage, muret, geysers) : **formes simples
  en placeholder**, remplacées plus tard par de petits sprites pixelforge.
- Les effets subis : §4.5 (marques par le code, animation d'effet commune).

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
- Les boss sont **plus gros** (64 px, §8.1) et un peu plus rapides ; ils font fuir les PNJ (§3.8).
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
   au-dessus de la tête. Exception : **le chasseur ne voit pas les pseudos des chassés** (§3.8). Deux joueurs peuvent prendre le même perso.
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
| `portrait` | buste de **trois-quarts face**, 64×64 (HD 256), pour menus, versus, podium ; **obligatoire pour tout perso, PNJ et boss, en pixel (`px32/portrait_*`) et en HD (`hd/portrait_hd.png`, rapatrié avec la tâche A)** (*Julien, 23/10*) | — |
| `idle` | immobile | respiration faite par pixelforge (code) |
| `idle_long` | pose d'inactivité propre au perso (§8.2) | par perso |
| `run` | course | Sprint_Loop, 9 i/s (2,25 foulées/s, corrigé par pixelforge le 23/10) |
| `jump_hide` | saut vers la cachette (la sortie = à l'envers) | NinjaJump_Start + NinjaJump_Idle_Loop + NinjaJump_Land, 6 images ; la cloche du saut est dans la planche (pixelforge) (*Julien 23/10*) |
| `lift` | envol avant de devenir fantôme, couleurs normales ; le **code fait clignoter** le perso | LiftAir (version root motion demandée) : rendu sur place, la montée (0 à 30 % de la hauteur) est ajoutée dans la planche par pixelforge (*Julien 23/10*) |
| `ghost` | **fantôme générique, le même pour tous** (*Julien, 23/10*) : petit drap blanc aux grands yeux ronds et petit béret rouge, qui flotte et avance ; le pseudo au-dessus dit à qui il est | sprite commun (`assets/blackout/fantome/`) : style `pf_px__ghost` de pixelforge (drap dessiné une fois, mouvements par code : `float`, `advance`, `appear`) ; les sets des persos ne demandent pas `ghost` (liste `elements`, 23/10) |
| `cast_chasse`, `cast_chasseur` | lancement des coups spéciaux (§4.6), propres au perso | extras ; clip selon la famille du coup : OverhandThrow pour « lance », Spell_Simple_Enter + Spell_Simple_Exit pour les autres (*Julien 23/10*) |
| `interagir` | fouiller une cachette, actionner un disjoncteur (1 s) | élément standard, Interact |
| `victoire`, `defaite` | podium | éléments standard, Celebration et Crying (*Julien 23/10*) |
| `etourdi`, `renverse`, `colle`, `ralenti`, `aveugle`, `tracte` | effets subis (§4.5) | éléments standard, clips du §4.5 |

- Clips : **uniquement Quaternius**, nommés explicitement ; pixelforge a les bibliothèques UAL1 et
  **UAL2** depuis le 22/10 (182 clips, liste : `GET /v2/motions`).

### 8.2 Les 13 personnages
Les prompts sont volontairement **simples** : une description et une signature (ce qui doit se lire de
loin), sans négation. **Prompt envoyé** (*23/10, conseil de pixelforge*) : la description seule quand elle
porte déjà « clearly visible » sur son détail clé (règle 3 ci-dessous), sinon « <description>, with <signature>
clearly visible. » — le détail clé est une phrase de la description, sans en-tête ; l'ancienne formule
« Signature detail drawn large and bright » est abandonnée (« signature » fait écrire du texte, « large »
grossit les objets, « bright » sature). Mots à ne jamais écrire dans un prompt, sauf si c'est voulu :
signature, logo, text, writing, letters, label, emblem, badge. Pour un objet, préciser plutôt sa taille
relative et sa position (« about the size of his head, at hip height »).
**Règles de pixelforge** (*relecture du 23/10*) : (1) genre et âge toujours explicites (« a young woman »,
« an old man »), avec la coiffure ; (2) pronoms neutres dans ce qui est commun à tous les PNJ ; (3) le détail
clé une seule fois, « clearly visible » collé à lui, dans la description : le prompt envoyé est alors la
description seule ; (4) aucun effet dans un prompt (rayon, flash, flammes, fumée, lueur, « glowing ») : les
effets sont des VFX du jeu, les actions ne décrivent que le corps et l'objet tenu ; (5) l'action suit le clip
(Spell_Simple : lever le bras puis pousser, abaisser, balayer) ; (6) l'objet d'un extra est tenu en main,
jamais porté ni déjà sur le profil ; (7) silhouette à deux bras et deux jambes, sinon `pf_px__creature` ;
(8) aucun mot graphique ; (9) le perso regarde à droite, sa main droite est visible ; (10) matières en aplats
opaques (eau, vapeur). Les défauts de rendu (ombre, blanc entre les jambes, halos, flashs) sont à
corriger **chez pixelforge**, pas dans les prompts (Julien, 21/10).

**Bibliothèque de prompts v2 (22/10)** — copie machine : `data/blackout/style_party_hard.json`
(`persos`, `idle_long`) ; script de rejeu : `tools/blackout/party_hard_v2.py` (mêmes paramètres,
graine 7, chaîne moteur A → moteur B). Toute modification se fait ici d'abord, puis dans le JSON.

| Perso | Description (prompt) | Signature | idle_long : geste — clip |
|---|---|---|---|
| Louis — l'enfant du pays | a little Basque boy with short blond hair, a white short-sleeved shirt, a red belt and navy rolled-up trousers, a red Basque beret clearly visible on his blond hair | a red Basque beret on blond hair | folds his arms and taps his foot, looking around — Idle_FoldArms_Loop |
| Txomin — maître-nageur | a Basque lifeguard boy with dark brown skin and short black curly hair, black sunglasses, red swim shorts, barefoot, a red cap and a yellow tank top clearly visible | a red cap and a yellow tank top | talks into his walkie-talkie held at his mouth — Idle_TalkingPhone_Loop |
| Patxi — pêcheur | a bearded Basque fisherman man with a blue beanie, light blue trousers, a bright yellow raincoat and yellow rubber boots clearly visible | a bright yellow raincoat and yellow boots | casts a fishing rod and waits for a bite — Fish_Cast_Idle_Loop |
| Maïa — surfeuse | a young Basque surfer girl with a long brown ponytail, a turquoise wetsuit with a navy panel, barefoot, a small yellow surfboard strapped upright on her back, clearly visible | a small yellow surfboard upright on her back | chats with big hand gestures — Idle_Talking_Loop |
| Xabi — pelotari | a little Basque jai alai player with short dark brown hair, a white polo shirt, plain white trousers, a red sash, red espadrilles, a long curved wicker chistera on his right hand pointing forward, clearly visible | a long curved wicker chistera pointing forward | practises a chistera swing — Sword_Attack |
| Mattin — leveur de pierre | a short stocky Basque stone lifter man with a black beard, a red beret, a broad muscular chest in a red and white horizontally striped shirt clearly visible, navy trousers and brown shoes | red and white horizontal stripes on a broad chest | lifts a heavy round stone — PickUp_Table |
| Amaia — dantzari | a Basque folk dancer girl with long dark braided hair, a red headscarf, a green vest over a white blouse, a red skirt clearly visible, simple white shoes, a wooden makila stick on her back | a red headscarf and a red skirt | dances a few Basque folk steps — Dance_Loop |
| Kaio — goéland | an upright seagull with a white head and belly, light grey wings used as arms, a big yellow beak with a red dot and orange webbed feet clearly visible | a big yellow beak and orange webbed feet | stretches his neck up and calls out loud — Idle_Rail_Call |
| Karramarro — crabe | an orange cartoon crab standing upright on two short thin crab legs, two big raised pincers as arms, eyes on stalks and a yellow belly, the two big orange pincers clearly visible | two big raised orange pincers and eyes on stalks | scratches his head with a pincer — Zombie_Scratch |
| Ramuntxo — chef des Halles | a Basque chef man with a small brown mustache, a white chef jacket, a red neck scarf, plain red trousers and black shoes, a tall white chef hat clearly visible | a tall white chef hat | tastes a sauce from a wooden spoon — Consume |
| Itsaso — esprit de l'écume | a mythical girl spirit of the sea with opaque pale turquoise skin, long wavy aqua hair and a deep blue dress with a white foam-shaped hem, barefoot, the long aqua hair clearly visible | long flowing aqua hair and a white foam hem | holds her hands together in front of her, fingers moving gently — Spell_Simple_Shoot |
| Peio — rugbyman | a sturdy young Basque rugby player man with medium brown skin and short black hair, a red and white hooped jersey, black shorts, white socks, black boots, a brown oval rugby ball under his arm clearly visible | a brown oval rugby ball under his arm | spins his rugby ball in his hands — Interact |
| Itsasargi — gardien du phare | an old lighthouse keeper man with a white beard, a captain cap and a navy pea coat, holding a bright brass lantern by its handle in his right hand at hip height, the lantern about the size of his head and clearly visible | the bright brass lantern in his hand | raises his lantern and peers into the dark — Idle_Lantern_Loop |

Changements du 22/10 (retours de Julien sur le run du 21/10) : Txomin sans palmes, casquette rouge ;
Patxi sans canne (elle n'apparaît que dans son idle_long), pantalon bleu clair et bottes jaunes ; Xabi
pantalon blanc uni, chistera vers l'avant ; Mattin plus petit, torse musclé ; Amaia chaussures blanches
simples ; Kaio et Karramarro sans foulard, Karramarro sur pattes de crabe ; Ramuntxo pantalon rouge
uni et chaussures noires ; Itsaso écume blanche ; Itsasargi lanterne plus grosse, bien tenue. Louis,
Maïa et Peio inchangés.

- **Proportions fines** (*Julien, 23/10*, après un essai trapu) : ~5 têtes, 5 à 7 px de large à 32 px.
- **Character set complet** (*Julien, 23/10*) : éléments fixes + **9 éléments standard** communs à tous
  (`interagir`, `victoire`, `defaite` et les 6 animations d'effets), demandés à pixelforge le 23/10, + **3
  extras propres au perso** (`idle_long`, `cast_chasse`, `cast_chasseur`). Un perso déjà validé reçoit ce
  qui lui manque par le mode « extras seuls » (§14.1), sans toucher au reste.

### 8.4 Bibliothèque des PNJ (*v1, 23/10*)
Copie machine : `data/blackout/pnj.json` (fait foi ici d'abord, comme §8.2). Style identique aux persos :
pixel art Party Hard, 32 px, prompts simples (description + signature), clichés de soirée basque lisibles
de loin, aucune personnalisation, rien de violent.

**Character set d'un PNJ humain** (`pf_px__character_set`, case 64 en 32 px) : `profile`, `idle`, `portrait` (HD dans `hd/` et pixel dans `px32/`, *Julien, 23/10*), `run` (la
fuite apeurée : clip Sprint_Loop et action « runs away fast, arms up », passés dans
`clips`/`actions`), rien d'autre (liste `elements` : profile, idle, run, portrait ; pixelforge df70eab), et **6 extras**
(10 au plus chez pixelforge, commit 08ddeb3) : `marcher` (Walk_Loop), `sursaut` (Surprise, « jumps back, hands raised
in front of the chest »), `a_terre` (IdleToLay, « drops to the ground and lies flat » : renversé par un boss qui
fonce, gardé sur sa dernière image), `relever` (LayToIdle, « gets back up and dusts off their clothes ») et ses
**2 activités** prises dans le catalogue ci-dessous. Dans le jeu, la peur s'enchaîne : `sursaut` puis `run` (*Julien, 23/10*).

Chaque PNJ humain a un **prénom** pour qu'on puisse y faire référence (*Julien, 23/10*) ; l'id reste la clé
des fichiers.

**Catalogue d'activités** (extra : clip Quaternius, action, objet)
| Activité | Clip | Action | Objet |
|---|---|---|---|
| parler | Idle_Talking_Loop | chats with big hand gestures | — |
| telephone | Idle_TalkingPhone_Loop | talks on a smartphone | a smartphone |
| danser | Dance_Loop | dances happily | — |
| musique | Yes | nods to the music | — (casque déjà sur le profil) |
| journal | Idle_Torch_Loop | reads a newspaper held in front of him | a newspaper |
| boire | Consume | sips a drink | a glass of cider |
| assis | Sitting_Idle_Loop | sits and relaxes | — |
| attendre | Idle_FoldArms_Loop | waits with arms crossed | — |
| promener | Walk_Loop | walks holding a red leash out in front (le chien : sprite à part dans le jeu) | a red leash |
| jouer | Interact | plays a little tune | son instrument (`objet_jouer` : flûte, trompette, guitare) |

**Humains (42 : 22 spéciaux, 20 génériques)** — les *spéciaux* sont des personnages typés de la fête ; les
*génériques* sont des passants ordinaires, majoritaires dans la foule (environ 2 génériques pour 1 spécial
sur une carte).

| id | Prénom | Type | Description | Signature | Activités |
|---|---|---|---|---|---|
| festayre | Beñat | spécial | a young man festival-goer dressed all in white, a red sash and a red neckerchief clearly visible | a red neckerchief on an all-white outfit | danser, boire |
| txistulari | Joxe | spécial | a middle-aged man txistu flute player dressed in white, with a red beret and a long thin flute clearly visible | a long thin flute and a red beret | jouer, parler |
| amona | Maddalen | spécial | a little grandmother in a black dress with a red fan and a grey bun | a red fan | parler, assis |
| marin | Manex | spécial | an old man fisherman in a blue and white striped sailor shirt clearly visible and yellow boots | blue and white stripes | parler, boire |
| surfeuse | Nahia | spécial | a surfer girl with bleached hair in a black wetsuit carrying a longboard | a long white surfboard | telephone, parler |
| serveur | Jon | spécial | a young man waiter in a white shirt and black apron, carrying a round tray of cider glasses clearly visible | a round tray of glasses | parler, attendre |
| sardine | Xardin | spécial | a festival mascot person in a white outfit wearing a huge silver sardine head, clearly visible | a huge smiling fish head | danser, attendre |
| errege | Antton | spécial | a festival mascot person in a white outfit wearing a huge Basque king head with a golden crown, clearly visible | a huge crowned head | danser, attendre |
| ballon | Ane | spécial | a little kid in a yellow raincoat holding a red balloon | a red balloon on a string | attendre, danser |
| trompettiste | Iñaki | spécial | a bandas trumpet player in white and red | a shiny golden trumpet | jouer, boire |
| glacier | Gorka | spécial | a woman ice cream seller with a pink and white striped apron and cap clearly visible | a striped apron | parler, attendre |
| supporter | Battitte | spécial | a young man rugby fan with a painted face, a red and white scarf clearly visible | a red and white scarf | parler, boire |
| touriste | Gérard | spécial | a middle-aged man tourist in shorts, a flowery Hawaiian shirt and a camera clearly visible | a flowery shirt and a camera | telephone, attendre |
| jogger | Unai | spécial | a young woman jogger with a ponytail, a bright green tracksuit clearly visible, headphones on her ears | a bright green tracksuit | musique, attendre |
| ado | Eneko | spécial | a teenage boy in a purple hoodie, big headphones on his ears clearly visible | big headphones on a purple hoodie | musique, telephone |
| lecteur | Pantxoa | spécial | an old man in a beige coat and a black beret | a black beret and a newspaper | journal, assis |
| promeneuse | Kattalin | spécial | a woman in a long yellow coat walking her dog | a long yellow coat | promener, parler |
| cycliste | Ander | spécial | a man cyclist in a blue jersey standing beside a red bicycle, both hands on the handlebar, the red bicycle clearly visible | a red bicycle | attendre, boire |
| musicienne | Ainhoa | spécial | a young woman street guitarist with long dark hair, a denim jacket and a wooden guitar clearly visible | a wooden guitar | jouer, parler |
| amoureux | Mikel | spécial | a young man in a white shirt holding a single red rose | a red rose | parler, attendre |
| policier | Ellande | spécial | a man municipal police officer in a dark blue uniform, a dark blue cap clearly visible | a dark blue cap | parler, attendre |
| pecheuse | Maite | spécial | a fisherwoman in a yellow oilskin and green boots with a bucket | a yellow oilskin | parler, boire |
| passant_jean | Thomas | générique | a man in his thirties in a plain blue t-shirt and jeans | a plain blue t-shirt | telephone, attendre |
| passante_robe | Léa | générique | a young woman in a simple green summer dress | a green dress | parler, boire |
| papy_gilet | Fermin | générique | an old man in a brown cardigan and grey trousers | a brown cardigan | assis, journal |
| mamie_cabas | Mayi | générique | an old woman in a lilac coat carrying a shopping bag | a lilac coat | parler, attendre |
| femme_tailleur | Sophie | générique | a woman in a navy blazer and white trousers | a navy blazer | telephone, boire |
| homme_costume | Bernard | générique | a man in a grey suit and tie | a grey suit | telephone, attendre |
| etudiante | Leire | générique | a student girl with a backpack and a yellow sweater | a yellow sweater | musique, parler |
| etudiant | Hugo | générique | a student boy with a backpack and a red sweatshirt | a red sweatshirt | telephone, parler |
| maman | Garazi | générique | a mother in a white top and blue jeans | a white top | parler, attendre |
| papa | Didier | générique | a father in a checked flannel shirt and khaki trousers | a checked shirt | parler, boire |
| enfant_fille | Uxue | générique | a little girl in a pink t-shirt and shorts | a pink t-shirt | danser, attendre |
| enfant_garcon | Oihan | générique | a little boy in an orange t-shirt and blue shorts | an orange t-shirt | danser, attendre |
| femme_pull | Irati | générique | a woman in a teal knitted sweater and black trousers | a teal sweater | boire, parler |
| homme_polo | Stéphane | générique | a man in a white polo shirt and beige shorts | a white polo shirt | boire, parler |
| jeune_casquette | Bixente | générique | a young man in a black cap and grey hoodie | a black cap | musique, attendre |
| femme_imper | Isabelle | générique | a woman in a beige trench coat | a beige trench coat | telephone, journal |
| homme_doudoune | Iker | générique | a man in a dark green puffer jacket | a dark green jacket | attendre, telephone |
| femme_short | Chloé | générique | a woman in a striped t-shirt and denim shorts | a striped t-shirt | danser, boire |
| homme_chemise | Ximun | générique | a man in a light blue shirt with rolled sleeves | a light blue shirt | parler, boire |
| ado_skate | Lucas | générique | a teenage boy in a white t-shirt carrying a skateboard under his arm, clearly visible | a skateboard | musique, parler |

**Animaux (4, hors quota humain)** : pas de squelette humain ; méthode demandée à pixelforge (comme pour
les boss non humanoïdes). Chacun : idle, marcher, fuir, et une activité.
| id | Description | Activité |
|---|---|---|
| chat | a small dark grey cat with yellow eyes | dort roulé en boule, se lèche |
| chien | a happy brown and white beagle | renifle le sol, suit son maître en laisse |
| goeland | a big white and grey seagull with a yellow beak | picore, s'envole en criant |
| pigeon | a grey city pigeon with an iridescent green neck patch | picore, s'envole |

### 8.3 Boss
Même pipeline, `size: "boss"` (64 px dans une case de 128, §8.1). Éléments d'un boss (*23/10*) :
`profile`, `portrait` (versus), `idle`, `run` (sa démarche, clip propre au boss), `etourdi` (Zezengorri
contre un rocher) et 3 extras : `cri` (il repère un joueur), `pouvoir_1`, `pouvoir_2` (§5.2). Pas de saut
de cachette, d'envol ni de fantôme.

**Créatures non humaines** (*Julien, 23/10*) : Herensuge animé « en marionnette » par pixelforge (dessiné une
fois, parties découpées, mouvements calculés, comme le fantôme) ; pour les animaux PNJ, essai comparé sur le
chat entre la marionnette et des vidéos pilotes d'animaux 3D (Quaternius, CC0) avant de choisir.
Intxixuk : trois character sets (un par lutin, variantes), groupés par le jeu.

**Prompts des autres boss** (*relus par pixelforge le 23/10 ; rayon, pierres, flammes et fumée sont des VFX du jeu*) :
- Tartalo : « a big clumsy one-eyed ogre giant with a single large round eye in the middle of his forehead,
  tanned skin, a brown fur tunic and a big wooden club, the single eye and the wooden club clearly visible » ;
  `cri` « sniffs the air, then leans forward with his arms spread » (Idle_Rail_Call) ; `pouvoir_1` « stares hard, leaning forward »
  (Idle_Torch_Loop) ; `pouvoir_2` « slams his big wooden club onto the ground » (Sword_Attack).
- Intxixu 1 : « a small hunched cave goblin with grey stone-like skin, animal fur clothes, bright yellow eyes,
  a green moss tuft on his head and a pebble sling, the moss tuft clearly visible » ; Intxixu 2 et 3 : idem avec
  une touffe orange et un petit sac de cailloux, une touffe violette et un collier d'os ; `cri` « hunches and rubs his
  hands together » (Idle_Rail_Call) ; `pouvoir_1` « raises both hands from low to high » (Spell_Simple_Shoot) ;
  `pouvoir_2` « throws a handful of pointy pebbles » (OverhandThrow).
- Zezengorri (`pf_px__creature`, quadrupède) : « a massive bright scarlet red bull with yellow eyes and big
  curved horns ».
- Herensuge (marionnette, serpent à trois têtes) : « a long winged dragon-serpent with three reptile heads,
  scales the colour of antique bronze and sulphur yellow ».

**Essai du 23/10 : Basajaun.**
- Prompt (*relu par pixelforge le 23/10*) : « a giant forest lord covered in thick shaggy
  brown fur, big root-like hands, leaning on a carved tree trunk staff, a long green moss beard and the
  carved staff clearly visible ».
- `run` : Zombie_Walk_Fwd_Loop (démarche lourde) ; `cri` : Idle_Rail_Call, « raises his arms high » ; `pouvoir_1` Murmure des bois : Spell_Simple_Shoot, « raises one hand high, fingers spread »
  (feuilles en VFX) ; `pouvoir_2` Étreinte racinaire : Sword_Attack, « slams his carved trunk staff down
  onto the ground ».

### 8.5 Expressions faciales (*Julien, 23/10*)
Le visage d'une animation est **raccord avec l'action** : quelqu'un qui fuit ne sourit pas. **Une expression
ciblée par animation** ; les prompts et les actions ne décrivent jamais le visage ni l'émotion (sourire, bouche
ouverte, yeux écarquillés, « cheerful », « in panic »…) : c'est la variable `expression` qui le porte. Les expressions
vivent ici et dans les JSON (`style_party_hard.json` → `expressions`, `pnj.json` → `expression`), **jamais dans
les prompts**. Ce sont les clés de pixelforge (`GET /v2/expressions`). Profil et portrait sont faits en
« neutre » ; pour chaque expression utile, une variante (`expression` + `expression_of`), puis les éléments
de cette expression sont animés sur elle (`profile_of`). « base » = l'expression de base du perso.

**Persos joueurs, par élément** : `idle` base, `idle_long` base, `run` neutre, `jump_hide` inquiet, `lift` surpris, `interagir` determine, `victoire` rire, `defaite` pleure, `etourdi` etourdi, `renverse` choque, `colle` perplexe, `ralenti` fatigue, `aveugle` ebloui, `tracte` surpris, `cast_chasse` malicieux, `cast_chasseur` determine.
Portraits : menus base, versus_chasseur determine, versus_chasse inquiet, podium_gagnant rire, podium_perdant pleure (*Julien, 23/10 : seulement les expressions des animations, victoire et défaite comprises*).
**Pas d'expression pour les courses** (*Julien, 23/10*) : une seule course, neutre, pour les deux rôles et pour les PNJ.

| Perso | Base | Exceptions |
|---|---|---|
| louis | malicieux | idle_long ennui, cast_chasseur crie |
| txomin | fier | — |
| patxi | sourire | — |
| maia | sourire | — |
| xabi | determine | — |
| mattin | fier | — |
| amaia | sourire | — |
| kaio | malicieux | cast_chasseur crie |
| karramarro | rire | — |
| ramuntxo | sourire | — |
| itsaso | reveur | — |
| peio | determine | cast_chasseur crie |
| itsasargi | pensif | — |

**PNJ humains** : `idle` et `marcher` base, `run` (fuite apeurée) neutre, `sursaut` choqué, `a_terre` étourdi,
`relever` gêné ; activités : parler sourire, telephone base, danser rire, musique sourire, journal pensif, boire sourire, assis base, attendre ennui, promener sourire, jouer base ; portrait des menus : base.
Bases : Beñat (festayre) rire, Joxe (txistulari) sourire, Maddalen (amona) sourire, Manex (marin) pensif, Nahia (surfeuse) sourire, Jon (serveur) sourire, Xardin (sardine) rire, Antton (errege) fier, Ane (ballon) sourire, Iñaki (trompettiste) fier, Gorka (glacier) sourire, Battitte (supporter) rire, Gérard (touriste) surpris, Unai (jogger) determine, Eneko (ado) ennui, Pantxoa (lecteur) pensif, Kattalin (promeneuse) sourire, Ander (cycliste) sourire, Ainhoa (musicienne) reveur, Mikel (amoureux) reveur, Ellande (policier) fier, Maite (pecheuse) sourire, Thomas (passant_jean) sourire, Léa (passante_robe) rire, Fermin (papy_gilet) pensif, Mayi (mamie_cabas) sourire, Sophie (femme_tailleur) determine, Bernard (homme_costume) ennui, Leire (etudiante) rire, Hugo (etudiant) fatigue, Garazi (maman) sourire, Didier (papa) rire, Uxue (enfant_fille) rire, Oihan (enfant_garcon) malicieux, Irati (femme_pull) sourire, Stéphane (homme_polo) rire, Bixente (jeune_casquette) malicieux, Isabelle (femme_imper) mefiant, Iker (homme_doudoune) ennui, Chloé (femme_short) sourire, Ximun (homme_chemise) sourire, Lucas (ado_skate) malicieux.

**Boss** : Basajaun base méfiant (cri furieux, pouvoir_1 déterminé, pouvoir_2 colère) ; Tartalo base perplexe
(cri furieux, pouvoir_1 méfiant, pouvoir_2 colère) ; Intxixuk base malicieux (cri rire) ; `run` déterminé,
`etourdi` étourdi. Zezengorri (taureau) et Herensuge (marionnette) : sans objet.

**Ajoutées par pixelforge le 23/10 à notre demande** : `crie` (crier fort sans colère, pour « 1, 2, 3…
j'arrive ! », le cri de Kaio, le cri de guerre de Peio) et `ebloui` (yeux plissés par une lumière, pour
`aveugle`).
À noter : le prompt de Karramarro dit « a big happy open mouth », en conflit avec le profil neutre.

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
  vraie zone de jeu (§3.2). **Dans la lumière, persos, PNJ et boss ont des couleurs plus saturées**
  (*Julien, 23/10* : `rules.json` → `eclaire_saturation` 1,35, fondu `eclaire_saturation_s` 0,3 s).
- **Pays basque** : maisons labourdines blanchies à la chaux, colombages et volets rouges, toits de
  tuiles, crampottes, barques peintes, quais de pierre, lauburu et linge basque par touches, gâteaux
  basques, piments d'Espelette, chisteras.
- **Sols à motif** par zone, peu contrastés. **HUD minimal** en police pixel. **Textes nets** (*Julien, 23/10 : textes illisibles en 8 px*) : le jeu reste en
  640×360, mais le HUD, les pseudos et les bulles sont dessinés par-dessus en pleine résolution (1280×720),
  avec une police pixel plus grande, comme les menus.
- **Jamais inquiétant pour un enfant** : même les boss restent des créatures de conte.

## 10. Cartes

### 10.1 Jalon actuel : la carte « bac à sable »
*Décidé le 22/10 : on fait tourner le jeu et on affine personnages et gameplay avant le level design.*
- Cases de 32 px, **placeholders** (aplats et formes simples).
- Contenu : pièces et couloirs, **murets d'une case** (Louis, Kaio), **cloisons fines** (Louis),
  **grilles et fenêtres** (vue oui, passage non), **sol meuble** (Karramarro), **cachettes**, objets
  hauts et bas, **lampadaires** et zones d'ombre, **un disjoncteur** par secteur, gâteaux basques,
  PNJ oiseaux, 2 points de sortie, **points d'activité des PNJ** (bancs, bar, terrasse, piste de danse), 15 à 25 PNJ
  et quelques animaux.
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
  (PNJ qui sursautent, oiseaux qui s'envolent, toux, traces), lancer son coup au bon moment, réparer un disjoncteur.
- **Réaction du chasseur IA par paliers** (*Julien, 23/10*), comme un joueur : dès qu'un chassé entre
  dans sa vue (même jauge vide), il marque un temps d'arrêt et tourne la tête vers lui ; s'il reste
  visible, il marche vers l'endroit où il l'a vu (sans connaître sa position exacte dans l'ombre) ;
  au « ? », il fonce et peut lancer son coup. Temps de réaction selon la difficulté (Facile lent, Malin
  presque immédiat).
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
- Déploiement : `deploy.yml`, **à la racine** de https://miarritze.ijulien.com/ ; la racine ne garde que le
  jeu et `api/` (*Julien, 22/10* : le reste peut être effacé). Depuis le 24/10, la décision de Julien est
  l'acceptation d'une carte en QA sur le board local (§14.2) : le déploiement suit tout seul.

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
- éléments fixes : `profile` (pose debout tirée d'Idle_Loop), `portrait` (buste de trois-quarts face,
  fait depuis le profil seul), `idle` (respiration par code), `run` (4 poses à pas égal, Sprint_Loop ;
  `run_frames` 6 ou 8 possibles), `jump_hide` (NinjaJump_Start + NinjaJump_Idle_Loop + NinjaJump_Land, cloche dans la planche), `lift` (LiftAir, montée dans la planche), `ghost` (profil
  translucide par code). Le clip de `run`, `jump_hide` et `lift` se change avec `clips` ; `set.json`
  donne les clips utilisés ;
- **jusqu'à 4 extras** dans le même set (au-delà : refus au dépôt) : chacun `{name, motion, action,
  object, loop, fps, frames, anchor}`, même palette, même cadrage, même ligne de pieds. Aujourd'hui un
  seul (`idle_long`) ; demain aussi les lancements des coups spéciaux (§4.6) ;
- `set.json` : cadence, boucle, calage, ligne des pieds, palette, contrôles.

**Animation ajoutée à un perso déjà validé** (*question de Julien, 22/10, demandée à pixelforge*) :
mode « extras seuls » de `pf_px__character_set` (*en place le 22/10* : `base_task`, ou après la purge
`base_set` + `input_image` ; en B `base_task` de la réduction d'origine ou `base_set`). Référence = le perso validé : sa tâche si elle existe
encore, sinon son `profile_hd.png` et son `set.json`, que nous gardons dans `assets/blackout/persos/<id>/hd/`
(les tâches sont purgées après 48 h).
**Perso validé = conservé des deux côtés** (*Julien, 22/10*) : quand Julien valide un perso en QA, ses tâches
A et B sont marquées « à garder » chez pixelforge (jamais purgées ; `PATCH /v2/inferences/tasks/{id}` avec `{"keep": true}`, en place le 22/10 ; **toute la descendance est gardée aussi** : réduction B, animations ajoutées plus tard et leurs
enfants, qui héritent de la conservation) et sa référence est committée chez nous (`hd/profile_hd.png`, `hd/set.json` et le
dossier `px32/`). Tous les éléments fixes sont sautés, et la nouvelle animation garde
la même palette, le même cadrage, la même ligne des pieds et la même échelle. En B, la réduction reprend la
palette 32 px du set d'origine. Les éléments déjà validés ne sont jamais régénérés.

**Clip absent de sa banque** : uniquement des clips Quaternius nommés (21/10). Un clip inconnu est
**refusé au dépôt** (400, avant la file) avec les clips les plus proches (*en place le 22/10*) ; je soumets le remplaçant à
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

**Garanties de qualité** : écrites par pixelforge dans sa description (« traitements systématiques »),
chacune avec un contrôle chiffré dans `set.json` → `controls` ; les écarts sont dans `controls.warnings`.
Couleurs simplifiées dans le moteur A (aplats, aucune nuance jumelle, chaque zone verrouillée sur ses
couleurs du profil) ; B garde une palette resserrée et vive.
**Défauts de Louis v2** (22/10) : corrigés par pixelforge (commit dfc6dcc) ; Louis relancé seul pour
vérifier, avant les 12 autres.

**Recette d'un perso et retouches** (*Julien, 23/10*) : chaque perso, PNJ ou boss livré a sa carte chapeau
en QA sur /producer, qui montre toutes ses animations et leur description. Julien commente élément par
élément et **décide seul** quand un perso repart en file. Je ne renvoie alors **que ce qui doit changer** :
- si seuls des extras sont à refaire (idle_long, lancements, activités), j'utilise le mode « extras seuls » sur la tâche d'origine (`base_task`) ;
- run, jump_hide, lift, portrait, un standard ou un extra se refont seuls avec **`redo`** (*en ligne chez pixelforge le 23/10, commit f9b8803*). La requête reprend `base_task` (tâche A d'origine) et `redo: [éléments]`. Options : `clips`, `actions`, `run_frames`, `seed` (une autre graine pour une autre tentative). En B, `base_task` reprend la réduction d'origine. Seuls ces éléments sont livrés, avec la même palette, la même échelle et la même ligne des pieds. Outil : `tools/blackout/retouche.py`. Ses résultats sont intégrés par fusion dans le set (`retouche.py --integre`) ;
- **ajouter** une animation à un set livré, sans rien refaire : même `base_task` (ou `base_set` + son
  `profile_hd.png`, gardés dans `hd/`) avec les seuls nouveaux `extras` ou standards. Chaque tâche intégrée est
  marquée `keep` chez pixelforge par `integre_persos_v2.py`, pour ne pas être purgée (*23/10*) ;
- profile, idle et ghost ne se refont pas seuls : si le profil change, tout le set repart ;
Le reste du set est gardé tel quel.

- **Décor** : masques en suspens (§10.2).
- Méthode de travail : on intègre chaque rendu tel quel, **Julien tranche en QA** sur le board (§14.2).

### 14.2 Board de production local (*Julien, 24/10*)
Le /producer en ligne est supprimé (données migrées) et remplacé par un **service local** sur le Mac de
Julien, joignable de ses appareils par **Tailscale** seulement (pas de mot de passe ; jeton pour l'agent).
Fonctionnement détaillé, règles de passage et automatismes : **`docs/PRODUCER.md`**.
- Colonnes : **Backlog → Todo → Doing → QA → Validé → En prod**. Julien seul met en Todo (accord de mise en
  file) et accepte ou refuse en QA.
- **QA = le jeu lancé en local** : un build web commun, refait automatiquement après chaque intégration,
  servi sur Tailscale avec le board. Tout ce qui est en QA y est jouable.
- **✓ Accepter → Validé** ; le watcher committe et pousse les fichiers des cartes validées, puis déploie en
  prod 10 min après le dernier accept (un déploiement pour plusieurs cartes) ; les cartes passent alors
  **En prod**. ✗ Refuser renvoie en haut du Backlog, « à retraiter » ; ↻ Refuser et refaire (*24/10*) renvoie en
  haut du Todo : Claude (relève toutes les 30 min) applique le commentaire à la demande, puis l'élément seul est
  redemandé à pixelforge depuis le profil validé du perso. Commentaire obligatoire. Un profil de référence (base,
  expression) refusé emmène dans sa colonne ce qui en est fait (QA, Validé, En prod), refait ensuite depuis le
  nouveau profil (*Julien, 24/10*).
- Chaque animation, expression, portrait et base de perso, PNJ, boss ou asset a sa carte sous son chapeau, liée à
  ses tâches pixelforge ; chaque coup spécial a son chapeau sous son perso (lancement, objet, effet, icône) ;
  chaque asset de décor a sa carte sous sa carte de jeu (*Julien, 24/10*). Dans la fiche d'un perso, chaque
  élément se valide ou se refuse à part. Les tâches des cartes en Doing, QA, Validé et En prod sont marquées `keep`.
- Automatisé sans l'agent (aucun token) : synchronisation avec pixelforge, intégration locale, build QA,
  passage Doing → QA, chapeaux, commit, push et déploiement. L'agent n'intervient que pour un refus ou un
  travail de code.

## 15. Roadmap : jalons et travail à faire
**Cette liste est la roadmap.** Chaque jalon a un identifiant stable (`R1`…) ; le board en fait ses jalons
(titre « R3 · … », description renvoyant ici), dans cet ordre, par `tools/producer/reorganise_board.py`, qui
relit cette liste. Changer la roadmap = changer cette liste (datée au journal §16), puis relancer le script.
Chaque carte du board appartient à un jalon ; son chapeau y emmène sa famille.
1. **[R0] Studio local : board, QA et prod** : board local sur Tailscale, jeu de QA local, mise en prod
   groupée, watchers sans agent (§14.2).
2. **[R1] Jouable sur carte nue** : carte bac à sable, lumière et ombre, coups spéciaux en
   placeholders (13 × 2), effets communs, recharges, fantômes invisibles et délivrance, round du boss
   avec un boss placeholder, menu debug, pseudo seul, sans emotes. Échelle 640×360 et cases de 32 px.
3. **[R2] Persos : les 13 en itérations** : base neutre, expressions, puis chaque animation (§8.5) ; un perso
   après l'autre ; fantôme commun.
4. **[R3] PNJ et animaux** : la foule de la nuit (§3.8, §8.4), 42 humains et 4 animaux en itérations ; vie,
   groupes, camouflage.
5. **[R4] Boss** : 7 boss en 64 px (§8.3, Intxixuk en trio).
6. **[R5] Équilibrage** : rounds IA contre IA, puis tests avec Louis.
7. **[R6] Level design** : première vraie carte de Biarritz.
8. **[R7] En ligne** : salons branchés sur le jeu (signalisation `/room/signal`).
9. **[R8] Finitions** : son et musique, écran « tourne ton appareil », icônes et PWA, export Steam Deck.

### 15.1 Où on en est (soir du 23/10) et ce qui reste
**Fait et publié à la racine** (étapes 1 à 4 du jalon 1) : pixel art 640×360, cases de 32 px, carte bac à
sable, persos placeholders (Louis v5), nuit, lumière et ombre, disjoncteurs, menu debug, moteur des coups
spéciaux et **les 26 coups** (placeholders), 10 effets communs et garde-fous, pièges et emotes retirés.
71 tests ; IA contre IA : 70 % de trouvés, chasseur gagnant 90 % des rounds (trop fort, à équilibrer).

**Éléments livrés branchés dans le jeu** (*23/10, demande de Julien : « tous les éléments livrés dans le
jeu, même en QA »*) : effets subis joués par le perso (`etourdi` pour figé et commandes inversées,
`renverse`, `colle`, `ralenti`, `aveugle`, `tracte`, marques du code gardées, plus de sprite couché quand la
planche existe) ; `interagir` pendant une fouille et un disjoncteur (l'entrée en cachette garde `jump_hide`,
§8.1) ; `cast_chasse` / `cast_chasseur` selon le rôle au lancement de chaque coup, par-dessus la course
(et à la place du saut des coups de déplacement) ; `portrait` au versus, au HUD (rôle, scores du round) et
au podium (suivants) ; `victoire` / `defaite` en fin de round et au podium ; **fantôme commun** (#646 :
`appear` après l'envol, `float` à l'arrêt, `advance` en mouvement ; plus d'élément ghost cherché dans les
sets ; on le reconnaît à son pseudo seul, §8.1). Élément manquant : élément voisin, sinon silhouette de
repli (`BkPerso.VOISINS`). **PNJ, base de #647** (`src/blackout/bk_foule.gd`) : `pnj_nombre` humains (20,
réglable par carte), sets réels d'abord puis placeholders ; activités en boucle, marche entre des cases,
une part reste sur place ; sursaut puis fuite vers la lumière quand leur secteur est coupé, sursaut puis
fuite loin d'un coup spécial ; traversables, triés avec le décor, dans la nuit et la lumière, vus du
chasseur seulement dans son cône (silhouette dans l'ombre). **Reste sur #647** : camouflage dans un groupe
et détection (§3.8), sursaut au passage d'un chassé qui court, regroupements, points d'activité de la
carte, couple promeneur + chien, animaux, fuite devant le boss, synchronisation en ligne. Défaut de rendu
signalé : les planches de Kaio ont un fond clair sur une partie des images, et les portraits de Kaio et
Mattin des pixels parasites (à corriger chez pixelforge).

**Reste à faire, jalon 1** (cartes du kanban) :
- #644 vue du chasseur : cône et proximité fusionnés sans bordure, dégradé, halo pixellisé, vue à 4 cases
  dans le noir, silhouette progressive, plus de lumières et de disjoncteurs ;
- #645 textes du HUD, pseudos et bulles nets en 1280×720 ;
- #633 IA : réaction du chasseur par paliers (§11), coups, ombre, disjoncteurs, boss ;
- #631 fantômes visibles des seuls fantômes et délivrance par halo ;
- #632 round du boss final ; #636 versus, scores et podium aux règles Blackout ;
- chasseur sans pseudos des chassés (§3.8) ; équilibrage des coups.
**Écarts et points ouverts de l'étape 4** : Kaio n'a pas de cachettes en hauteur (la carte n'en a pas) ;
Débordement crabe dans la direction de marche ; appât de Patxi lu comme un rayon de 1,5 case ; l'IA lance
pot, faisceau et geysers vers un indice récent ; persos signalés par les rounds IA : Louis et Kaio trop
faibles en chassé, Itsasargi trop fort (flash ~7 fois par round), makila et piment peu efficaces,
projectiles qui touchent rarement une cible qui fuit.
**File pixelforge arrêtée** (nuit du 23/10, demande de Julien) : le batch (13 persos v3, fantôme commun,
42 PNJ, 5 boss) a été **annulé** par pixelforge à cause d'un bug de son côté (`skip: ["ghost"]` faisait
planter le contrôle final d'un set après tout le calcul). Correctif écrit, pas encore déployé. **Redéposé à la demande de
Julien** (23/10) : 13 persos et fantôme en priorité normale, 42 PNJ en priorité nuit, puis les 5 boss en priorité basse (low). Les requêtes sont prêtes à rejouer : `party_hard_v2.py`,
`pnj_jobs.py`, `taches_fantome.json` et `taches_boss_essai.json` (champ `requete`). Zezengorri n'a que les
animations de quadrupède : gratter le sol et souffle de soufre restent à demander.
**File vidée l'après-midi du 23/10** (Julien) : plus rien en file ; prochaine commande, sur son ordre,
un perso et un PNJ de test, puis le reste (§16). À intégrer tels quels (`tools/blackout/integre_persos_v2.py`) puis QA par Julien ; poser `keep` sur les
persos validés (§14.1). Animaux : chat et chien attendent le feu vert de Julien à pixelforge
(`pf_px__creature`) ; goéland et pigeon attendent un mode oiseau. Herensuge en marionnette, essai chat
a/b : en pause. PNJ (#647, reste après la base du 23/10) et masques du décor (§10.2) : après le jalon 1.
**Placeholders** (*Julien, 23/10*) : en attendant pixelforge, chaque PNJ, animal et boss sans rendu a un set temporaire au même format (silhouette aux couleurs de sa description, 2 à 4 images par élément, `set.json` → `"placeholder": true`), fait par `tools/blackout/placeholders_sets.py` dans `assets/blackout/pnj|animaux|boss/<id>/px32/` et chargé par le même chargeur que les persos (BkPerso) ; le vrai rendu le remplace à l'intégration (`integre_persos_v2.py`, `DEST=pnj|animaux|boss`). Liste des boss : `rules.json` → `boss`.

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
- **23/10** (recette des 13 persos v3) : nouveaux clips — jump_hide NinjaJump_Start + Idle + Land, lift LiftAir_RM,
  victoire Celebration, defaite Crying, etourdi Hit_Shoulder_L + R, colle Crouch_Fwd, aveugle Spell_Double_Shoot,
  tracte Slide ; lancements selon la famille du coup (OverhandThrow pour « lance », sinon Spell_Simple_Enter + Exit) ;
  portrait plus fiable et cadence de la course demandés à pixelforge ; retouches par `redo` en priorité normale
  déposées le 23/10 (13 jobs, `taches_retouches.json`) après les corrections de pixelforge (commits 24beeed, f471e43).
- **23/10 après-midi** (Julien : « annuler toute la queue, pas mal de retouches à faire ») : file pixelforge vidée
  (69 tâches : 8 retouches de persos, 52 PNJ, Itsasargi jamais parti). Retouches déjà livrées intégrées (Louis,
  Txomin, Patxi, Maïa). La suite repart **sur l'ordre de Julien**, avec **un perso et un PNJ de test** d'abord ;
  le reste plus tard. Côté jeu : quand la planche lift ou jump_hide monte d'elle-même, le jeu n'ajoute plus
  ni `lift_px` ni l'arc de sortie de cachette (`BkPerso._monte`).
- **23/10** (cycliste, Julien : option 2) : Wan anime le vélo de la référence avec lui ; le cycliste est décrit
  debout à côté de son vélo, et on accepte qu'il le pousse en se déplaçant. Ses visage, portrait et objets
  coupés sont corrigés chez pixelforge (12 h 30) : à refaire en set complet le moment venu.
- **23/10** (PNJ, Julien) : prénom pour chaque PNJ humain (§8.4) ; extras `a_terre` (IdleToLay) et `relever`
  (LayToIdle) ; portrait HD et pixel pour chaque PNJ (les 14 déjà livrés : à ajouter plus tard, par redo ["portrait"] si pixelforge l.accepte sur un set qui n.en a pas) ; la limite de pixelforge passant de 4 à 10 extras à la demande de Julien (Ainhoa, déposée avant,
  a « à terre » en `renverse`) ; `sursaut` passe à Surprise, suivi de la fuite apeurée (Sprint_Loop, bras en l'air),
  dont l'action n'était jusqu'ici pas envoyée à pixelforge (`pnj_jobs.py` la passe désormais).
- **23/10** (portraits, Julien) : chaque perso, PNJ et boss a un portrait pixel et un portrait HD. Pixelforge
  produit le HD dans la tâche A (`portrait_hd.png`), `integre_persos_v2.py` le rapatrie dans `hd/`. État :
  les 13 persos, Basajaun et Tartalo l'ont ; aucun des PNJ livrés (dont Ainhoa) ni Zezengorri, Herensuge et
  les Intxixuk : à ajouter au prochain envoi (élément `portrait`).
- **23/10** (chaîne HD → pixel de pixelforge, Julien) : les images `src64_<élément>.png` livrées avec un set
  sont gardées telles quelles dans `hd/` à l'intégration, pour d'éventuels menus ou usages en jeu.
- **23/10** (pixelforge, nouvelle API, demande de Julien) : le moteur A (`pf_px__character_set`) ne fait plus que
  le HD (profil, portrait, objets, animations Wan détourées) ; le moteur B (`pf_px__reduce`, chaîné ou sur un job A)
  le réduit d'un coup à la taille finale, en « pixel brut », et n'applique que les traitements demandés dans
  `steps` (`couleurs`, `zones`, `brightness`, `hysteresis`, `face`, `vote`). B se relance sur le même A autant
  qu'on veut. `party_hard_v2.py` et `pnj_jobs.py` envoient B sans réglage, ou ceux de `PF_STEPS`. Les sets
  d'avant (retouches par `base_task`) ne changent pas.
- **23/10** (pixelforge, Julien) : historique de pixelforge entièrement purgé, tâches `keep` comprises. Les
  sets livrés restent dans le jeu (`assets/blackout/`), mais plus aucun `base_task` / `px_task` d'avant n'est
  utilisable : retouche (`redo`) ou ajout d'extras d'un perso livré = nouveau set complet.
- **23/10** (style HD, Julien, après comparaison sur Mattin) : HD « cartoon » par défaut chez pixelforge
  (contour bleu nuit, une teinte d'ombre nette, visage dessiné ; `hd_style: "flat"` pour l'ancien) ; le pixel
  efface toujours les traits. Profil et portrait faits avec l'expression neutre ; variantes d'expression d'un
  perso par clé (`expression`, `expression_of`, liste `GET /v2/expressions`), animables via `profile_given`.
- **23/10** (itérations, Julien) : **plus de set complet**. Chaque animation = trois jobs gardés (keep) :
  (1) base neutre, profil et portrait (`preview`) ; (2) base avec l'expression de l'animation (`expression_of`
  la base neutre) ; (3) l'animation, dérivée de cette base (`profile_of`), puis réduite. Une expression ciblée
  par animation (§8.5), jamais dans le prompt. Outil : `tools/blackout/iteration.py` (persos et PNJ).
- **24/10** (board, Julien) : /producer en ligne supprimé après migration ; board local sur Tailscale ; QA = jeu
  local (build commun automatique) ; acceptation = commit, push et déploiement groupé en prod ; colonnes
  Validé et En prod ; toutes les animations en cartes sous leur chapeau, tâches pixelforge en `keep` (§14.2).
- **24/10** (refus, Julien) : deux boutons de refus, commentaire obligatoire : « Refuser » (Backlog) et « Refuser
  et refaire » (Todo) ; un sous-élément refait repart du profil validé (base ou expression socle), §14.2. Le
  commentaire est appliqué par Claude, réveillé toutes les 30 min, pas par un Claude lancé par le watcher.
- **24/10** (board, Julien) : une carte par portrait (perso, PNJ, boss) ; coups spéciaux détaillés par asset
  sous leur perso ; assets du décor sous leur carte de jeu ; ✓ / ✗ par élément dans la fiche d'un perso.
- **24/10** (versions, Julien) : tous les assets sont versionnés dans git : la HD en Git LFS, l'intégré non
  validé sur la branche `assets-integres` (mise à jour par le watcher) ; `main` et la prod ne reçoivent que le validé.
- **24/10** (chaîne HD → pixel, Julien) : tout rendu 32 px vient de la HD de sa carte, sur le même modèle de base ;
  le profil et le portrait 32 px d'un perso sont faits depuis sa base neutre (job portrait sur ce profil, puis
  pf_px__reduce ; iteration.job_base_px), déposés par le watcher après chaque base. Les anciens venaient de l'ancien modèle.
- **24/10** (autres assets, Julien, sur la réponse de pixelforge) : boss pilote **Basajaun** en itérations, après
  les 13 persos ; puis remise au contrat de `pf_px__creature` (HD cartoon, A/B, preview, expressions,
  portrait) pour Zezengorri, Herensuge et les animaux ; **essai animaux sans marionnette** (Wan) sur le chat,
  pour voir comment le modèle réagit (après les 13 persos, avant Basajaun ; chat de 16 px, « a small slender
  dark grey cat with bright yellow eyes, pointed ears and a long thin tail, the yellow eyes clearly visible » ;
  idle et walk sur vidéo pilote Quaternius, run, dormir et se lécher en image vers vidéo ; marionnette à côté) ; **portrait des boss en 128 px** au versus ; objets des coups
  (`pf_px__prop` proposé) après les 13 persos ; icônes des 26 coups dans un **cercle coloré par rôle** (bleu
  chassé, rouge chasseur) ; décor : lieu pilote **Port des Pêcheurs**, après le jalon 1. Effets des états :
  seuls étoile, plume, résine et traits en sprites, contours et halo restent dans le code.

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
Décidé le 23/10 : voir §3.8 (règles) et §8.4 (bibliothèque).
