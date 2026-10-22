# Gordeka — style 2D façon Among Us, animations et pipeline pixelforge

> **Décidé le 2026-10-19 (Julien)** : le rendu 3D est abandonné (« pas content du tout du résultat »).
> Repli sur le style visuel d'Among Us : **2D flat cartoon, légèrement en perspective**.
> Ce document remplace les parties 3D de `SPEC-GORDEKA.md` §9 et §16.

## 1. Ce qu'on observe dans Among Us

Sources : 10 captures officielles de la page Steam, bandes-annonces *Release*, *Hide n Seek* et
*The Fungle* (décomposées image par image), wiki Among Us (pages Crewmate, Ghost, Hide n Seek).

### Caméra et décor
- **Sol vu de dessus**, murs et objets **légèrement de face** (on voit la face avant des murs, des
  caisses, des tables) : c'est le « léger 3/4 ». Pas de vraie perspective : pas de point de fuite,
  tout est à la même échelle partout sur la carte.
- Décor en **aplats** : une couleur de base, une ombre plus sombre, quelques détails au trait. Contour
  sombre épais autour des objets, plus fin pour les détails intérieurs.
- Vision : tout est **assombri hors de la zone visible**. Les murs coupent la lumière. En
  Hide n Seek, le chercheur a une **lampe torche en cône** (notre cône).
- Les objets du décor sont des images séparées, triées par hauteur (le perso passe derrière une
  caisse quand il est plus haut qu'elle à l'écran).

### Personnages
- **Toujours de profil** (vue de côté, tournés vers la droite ou la gauche). Quand on monte ou
  descend, le perso garde son dernier côté. La gauche est le **miroir** de la droite.
- Silhouette **trapue et ronde**, gros contour sombre régulier, **deux tons** par couleur (aplat et
  ombre franche, sans dégradé), un petit reflet blanc sur la visière.
- **Ombre au sol** : une ellipse sombre et douce sous les pieds, qui ne bouge pas avec le saut du
  corps.
- **Couleur du joueur** = toute la combinaison, avec une teinte d'ombre propre à chaque couleur.
- Les chapeaux, animaux et tenues sont des **calques** posés sur le corps et suivent son balancement.

### Animations (relevées image par image)
| Animation | Ce qu'on voit | Rythme |
|---|---|---|
| Immobile | une seule image fixe, aucun mouvement | — |
| Marche | ~12 images par cycle, jambes qui s'étirent beaucoup (étirement et écrasement), corps qui monte et descend, petite inclinaison vers l'avant ; accessoires décalés d'une image | 24 i/s, cycle ≈ 0,5 s |
| Bouche d'aération | saut avec écrasement, le perso plonge et disparaît ; le couvercle s'anime | ~8 images |
| Mort | animation plein écran (fond rouge à éclairs) ; le corps reste au sol | — |
| Fantôme | même perso, **une queue à la place des jambes**, **translucide** (~50 %), flotte doucement, traverse les murs, voit tout | boucle lente |
| Chercheur (Hide n Seek) | même gabarit mais transformé (bouche dentée) ; transformation au début du round (tremblement, cri) ; court plus vite | — |
| Victoire / défaite | grandes illustrations de groupe | — |

Interface Hide n Seek utile pour nous : barre de temps en haut, rangée de petites silhouettes
barrées pour les joueurs éliminés, bandeau « X a été tué » avec la plaque du joueur, **jauge de
danger** (de bleu à rouge, qui tremble au maximum), phase finale où tout passe au rouge.

## 2. Ce qu'on adapte pour Gordeka

- **Persos** : les 12 de Borroka redessinés en **flat cartoon façon Among Us** (contour épais #1d2230,
  deux tons, sans texture), proportions trapues (≈ 2,5 têtes), **de profil tourné à droite**,
  gauche en miroir. Ils gardent leur identité (Louis : cheveux blonds, béret rouge, chemise blanche,
  ceinture rouge, pantalon marine, espadrilles).
- **Couleur du joueur** sur la « tenue » (Louis : la chemise), en deux tons calculés comme dans Among
  Us (aplat + ombre). Le reste garde ses couleurs.
- **Taille à l'écran** : ~90 px de haut en 1280×720. On dessine les cases en **256 px** (×2,5 pour
  l'iPhone et les grands écrans).
- **Décor** : retour à la vue 2D de dessus avec murs et objets en léger 3/4 (`pf_hd__prop`, déjà prêt
  et dans ce style). La vue 3D (`gk_view3d.gd`) est mise de côté ; les règles n'ont jamais quitté la 2D.
- **Pas de violence** : quand on est trouvé, pas de mort ni de cadavre. Un bandeau rigolo
  « Trouvé ! », puis le fantôme apparaît sur place.

## 3. Animations dont on a besoin

Toutes de profil vers la droite (gauche = miroir), cases de 256 px, pieds sur la même ligne de sol,
24 images par seconde. **Lot 1** : nécessaire pour jouer ; **lot 2** : à faire ensuite.

| # | Animation | Qui | Images | Boucle | Description |
|---|---|---|---|---|---|
| 1 | `idle` | tous | 6 | oui | quasi fixe comme Among Us, mais une respiration douce et un clignement (enfants : plus vivant) |
| 2 | `walk` | chassés, chasseur | 12 | oui | marche façon Among Us : jambes étirées, corps qui rebondit, penché en avant |
| 3 | `run_scared` | chassés | 10 | oui | quand le chasseur est tout près : fuite affolée, bras en l'air, plus penché (même vitesse, juste l'allure) |
| 4 | `hide_in` | chassés | 8 | non | entrer dans une cachette : petit saut, écrasement, plonge et disparaît (comme la bouche d'aération) |
| 5 | `hide_out` | chassés | 8 | non | ressortir : jaillit, s'étire, retombe |
| 6 | `found` | chassés | 12 | non | **être surpris** : sursaut, yeux ronds, « ! », les pieds décollent, puis s'écroule en riant |
| 7 | `ghost` | trouvés | 8 | oui | fantôme : queue à la place des jambes, flotte de haut en bas, translucide (transparence faite par le jeu) |
| 8 | `ghost_move` | trouvés | 8 | oui | fantôme qui se déplace : penché, la queue ondule derrière |
| 9 | `trap` | chassés | 10 | non | poser un piège : s'accroupit, pose l'objet au sol, se relève content |
| 10 | `trapped` | chasseur | 8 | oui | pris dans un piège : englué, tire sur ses pieds (3 s de ralenti) |
| 11 | `search` | chasseur | 12 | oui | fouiller une cachette (1 s) : penché en avant, bras qui farfouillent |
| 12 | `detect` | chasseur | 12 | non | détection : main à l'oreille ou nez qui renifle, regard à gauche puis à droite |
| 13 | `extract` | chassés | 10 | non | atteindre une sortie : saut de joie et sortie de l'écran (dans la barque, en haut de l'escalier…) |
| 14 | `victory` | gagnants | 12 | oui | saut, bras en l'air, en boucle sur le podium |
| 15 | `sad` | perdants | 6 | oui | épaules basses, petit soupir (podium) |
| 16 | `hunter_reveal` | chasseur | 16 | non | lot 2 : au tirage, il chausse sa lampe torche, la secoue, elle s'allume |
| 17 | `emote_1…6` | tous | 8-12 | non | lot 2 : salut, rire, danse, pouce levé, « chut », tirer la langue |

En plus, par perso : un **portrait** (menus, HUD, podium), une **tête « surprise »** et une **tête
« contente »** (calques de tête échangés pendant les animations), une **icône de piège** et une
**icône de détection**. La lampe torche du chasseur est un **calque d'objet** tenu en main, commun à tous.

### Expressions (Julien, 2026-10-19)
La tête change selon ce que fait le perso, avec le même cadrage et le même pivot de cou pour toutes :
- neutral : immobile ; blink : clignement ;
- **malicious**, sourire malicieux « je vais me cacher » : marche, fantôme qui bouge, pose d'un piège ;
- scared : fuite affolée, pris au piège ;
- **surprised** : imposée par le jeu dès que le chasseur le voit (la jauge monte), et pour « trouvé » ;
- happy : victoire, sortie, sortie de cachette ; sad : déçu ;
- focused : chasseur qui fouille ou lance sa détection.

## 4. Pipeline avec pixelforge

> **Révisé le 2026-10-19 (Julien : « ça me va »)** : après trois allers-retours sur Louis (pieds,
> bras, hanches), on abandonne la découpe d'un dessin libre par perso au profit d'un **gabarit de
> corps commun**, comme Among Us.
> - Un corps « humain » (et un « crabe » pour Karramarro) est dessiné pour l'animation : articulations
>   en disques, pivots et proportions fixes. Les 15 chorégraphies y sont validées une fois.
> - Chaque perso est un **habillage** du gabarit : tête et expressions, cheveux, chapeau en calque, couleurs
>   et motifs par zone, chaussures. Les membres gardent la forme du gabarit.
> - Compromis assumé : même silhouette pour tous ; on reconnaît les persos à leur tête, leur chapeau,
>   leur tenue et leur couleur.
>
> Les étapes 2 et 3 ci-dessous décrivent l'approche d'avant (découpe par perso).


Règle de base : l'outillage est **chez pixelforge** (styles de son API, testés dans sa CI) ;
le jeu ne fait que demander, relire et intégrer.

1. **Modèle du perso** — `pf_hd__edit` (existe déjà). Entrée : le perso Borroka validé
   (`tools/rd/out/<id>/neutral_160.png`). Sortie : 4 candidats flat cartoon, de profil vers la
   droite, debout, bras le long du corps. **Julien choisit.**
2. **Découpe en calques** — nouveau style `pf_2d__cutout`. Entrée : le modèle validé. Sortie, sur un
   même canevas aligné :
   - calques : jambe arrière, jambe avant, corps, bras ou main arrière, bras ou main avant, tête,
     accessoires (béret…) ; parties cachées complétées (inpainting) ;
   - variantes de tête (normale, surprise, contente) et corps de fantôme (queue à la place des jambes) ;
   - **masque de tenue** par calque, en niveaux de gris (l'ombrage reste, la couleur vient du jeu) ;
   - pivots (hanches, épaules, cou) en JSON.
3. **Animation** — nouveau style `pf_2d__anim`. Entrée : les calques + une **chorégraphie** (images
   clés par calque : position, rotation, écrasement, changement de tête), en JSON. Les chorégraphies
   sont **communes aux 12 persos** (une variante pour les persos non humains, comme Karramarro).
   Sortie : une planche par animation (cases de 256 px, pieds alignés), la planche de masque de
   tenue, un GIF d'aperçu et un JSON (images par seconde, boucle, ancrage des pieds). Le découpage
   garantit un perso **identique d'une image à l'autre**. Pour une pose impossible en calques, une
   passe de redessin guidé (Kontext) peut retoucher une image clé.
4. **Contrôle** chez pixelforge : planche contact et GIF, contour régulier, pas de déformation ni
   d'objet inventé, pieds sur la ligne de sol ; tests dans la CI.
5. **Intégration** dans le jeu : `SpriteFrames` par perso, shader de recoloration par le masque
   (12 couleurs, deux tons), ombre au sol en ellipse dessinée par le jeu, miroir à gauche,
   transparence du fantôme ; je relis tout en jeu (captures) avant de montrer à Julien.

Ordre : Louis d'abord, de bout en bout, montré à Julien ; puis les 11 autres en file, sans
intervention.
