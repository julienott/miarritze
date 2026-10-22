# Un modèle sur GPU pour les masques du décor : recherche

> **Document d'analyse, sans décision.** Les décisions qui en sortiront vont dans `GDD-BLACKOUT.md`
> (§10.2 règles du décor, §14 pipeline pixelforge). Recherche du 22/10/2026 : dépôt, archive du décor
> flat cartoon (69 images, 34 masques), API `GET /v2/styles` de pixelforge (lecture seule, 70 styles) et
> sources web 2020–2026 citées en fin de document. Suite de `docs/RECHERCHE_MASQUES_DECOR.md` (« la
> première recherche ») : ce qui y est dit reste valable sauf mention contraire, et n'est pas répété.

La question de Julien : « J'ai des doutes sur votre spec avec pixelforge, je verrais bien un modèle
destiné à correctement faire les masques de collision des objets 2D pour que ce soit fait sans
consommation de tokens et avec un GPU. »

Reformulée : à partir de **l'image seule** d'un objet de décor (HD 128 px par case, ou pixel art
32 px), un **réseau qui tourne sur le GPU de pixelforge** produit collision, vue, tri et ombre, sans
LLM et sans proxy écrit à la main pour chaque objet.

---

## 0. Réponse courte

1. **Aucun modèle prêt à l'emploi** ne fait ça pour des sprites de jeu. Les outils Godot et Unity
   tracent l'alpha. Les générateurs de normal maps lisent la luminosité. Le seul modèle de recherche
   qui prédit l'empreinte cachée d'un objet isolé est **ORG** (*Floating No More*, CVPR 2025). Son code
   n'est pas publié, et son prédécesseur (PixHt-Lab) est réservé à un usage non commercial.
2. **En revanche, la bonne représentation existe et a fait ses preuves.** ORG prédit pour chaque pixel
   sa **« hauteur de pixel » avant et arrière** : la distance à l'écran entre le point de l'objet et
   son pied au sol, pour la surface vue (avant) et pour la surface de sortie cachée (arrière). Dans
   notre projection (`écran_y = y − h`), ces deux cartes donnent **directement** `sol_y`, l'empreinte
   complète (bord arrière caché compris) et la hauteur de chaque pixel. Tout le reste (collision,
   vue, couches, ombre) s'en déduit par un calcul déterministe (§6).
3. **Recommandation : C, hybride, centrée sur un modèle dédié (B).** On affine **Depth Anything V2
   Small** (Apache-2.0, 25 M de paramètres) pour prédire ces cartes, sur **des images synthétiques
   rendues dans notre projection** (formes procédurales et modèles 3D CC0). La vérité y est exacte et
   gratuite. Les objets générés depuis un proxy (spec déjà décidée) **deviennent aussi des données
   d'entraînement**. Image → 3D (TRELLIS, TripoSG) sert de **référence de comparaison** au premier
   essai, pas de chaîne de production.
4. **Coût estimé** : 4 à 6 jours de travail côté pixelforge (fabrique de données, entraînement, post-
   traitement partagé avec `pf_geo__proxy`) et **3 ou 4 nuits de GPU** sur la RTX 5080 (16 Go) de
   pixelforge : le modèle tient en 8–12 Go, un entraînement dure 4 à 10 h, avec un point de reprise
   toutes les 30 min. Ensuite **< 1 s par objet**, zéro token. Ce sont des estimations par analogie
   (§5.4), non mesurées.
5. **Incertitude principale** : la profondeur cachée est apprise, donc *plausible*, pas garantie.
   Elle sera juste pour les familles d'objets vues à l'entraînement (caisses, bancs, tables, pots,
   bassins), moins pour l'inédit. Il faut donc une **confiance mesurée** et un repli (proxy déclaré).

---

## 1. Ce que la question change par rapport à la première recherche

La première recherche a conclu « la géométrie se déclare, l'image s'y conforme » (proxy 3D écrit en
données, image générée dessus, masques calculés depuis le proxy). Le doute de Julien porte sur un
point réel : **quelqu'un doit écrire chaque proxy**. Dans la spec, c'est Claude (donc des tokens et
une relecture), et le repli `pf_geo__fit` pour les images existantes exige aussi un proxy approché.

Ce qui reste valable et qu'on réutilise tel quel :
- la **projection** : `écran_x = x`, `écran_y = y·k_sol − h·k_haut`, `k_sol = k_haut = 1` (§2.3 et
  §6.7 de la première recherche) ;
- le **format de livraison** : `prop.json`, `geo.png` (R = `sol_y`, G = `h`, B = partie, A = alpha),
  couches de tri par tranches de 16 px, `ombre.png`, `hd/` à ×4 et les règles de réduction (§4.2–4.3) ;
- les **critères** A4 à A9 (recomposition, réduction exacte, polygones valides, déterminisme) ;
- les **trois exemples** (pot, fontaine, banc) comme cas de test ;
- le **diagnostic** : l'image ne contient pas le bord arrière ; toute méthode doit soit le connaître,
  soit l'*apprendre*. La première recherche a choisi « le connaître ». Ce document évalue « l'apprendre ».

Remarque sur le corpus archivé : sur les 34 masques, **4 objets sont en vue de coin** (`caisses_poisson`,
`chalutier_quai`, `fronton`, `table_terrasse`) et les 30 autres en « front34 », mais avec une face du
dessus souvent à peine visible (`k_sol` réel nettement < 1). Ces images ne sont **pas** dans la
projection Party Hard visée. Elles servent de test de robustesse, pas de référence de qualité (§8).

---

## 2. Existe-t-il déjà un modèle ou un outil ?

| Travail | Ce qu'il fait | Proche de nous ? | Utilisable ? |
|---|---|---|---|
| **ORG**, *Floating No More* (Man et al., CVPR 2025) | Depuis une image : **hauteur de pixel avant et arrière** + champ de perspective → objet posé sur son sol, ombres, contact | **Très** : c'est exactement `sol_y` et le bord arrière caché | Code non publié (« will release ») ; **la recette est décrite** : 3,36 M rendus Objaverse, PVTv2-b3 + décodeur SegFormer, 5 canaux en régression L2, 60 k pas, 4 A100 |
| PixHt-Lab / *Controllable Shadow Generation Using Pixel Height Maps* (Sheng et al., ECCV 2022, CVPR 2023) | Hauteur de pixel d'un objet détouré (réseau HENet) → ombres et reflets | Oui (objet isolé) | Dépôt `ShengCN/PixHtLab-Src` **non commercial** ; ne garder que l'idée |
| *Footprints and Free Space from a Single Color Image* (Watson et al., CVPR 2020) | Sol praticable caché derrière les objets d'une **scène** | Partiel (scène photo, pas objet isolé) | Recherche ; idée de « empreinte » apprise |
| *Amodal Ground Truth and Completion in the Wild* (CVPR 2024), pix2gestalt (CVPR 2024) | Complètent le **masque 2D** caché d'un objet | Non : complètent l'image, pas le sol | — |
| **SpriteToMesh** (2026) | Segmente le premier plan de sprites (U-Net, 100 000 paires de 172 jeux, IoU 0,87) puis maille | Montre que **les réseaux denses apprennent bien sur des sprites** | Masque seulement, pas de géométrie |
| Plugins Godot (Sudden Sprite2D, Sprite StaticBody Builder, AutoColliders…) et Unity (`PolygonCollider2D.CreateFromSprite`) | Contour de l'alpha, simplification Douglas–Peucker | Non : c'est notre ancien calcul local | — |
| Générateurs de normal maps (SpriteIlluminator, Laigter, Sprite-AI…) | Normales depuis la luminosité (ou, chez Sprite-AI, un modèle entraîné sur des rendus 3D, non vérifié) | Non pour l'empreinte ; éventuellement pour l'éclairage | — |
| `pf_2d__footprint` (pixelforge, actuel) | Heuristiques sur l'alpha (trapèze, losange, « sur pieds ») | C'est ce qu'on veut remplacer | Avertissements = aveux d'heuristique (première recherche §1.2) |

Recherches sans résultat pertinent : « sprite collision mask generation », « footprint estimation
game sprite », « isometric sprite depth », « 2.5D sprite height map AI », plugins d'éditeurs avec IA.
**Personne ne publie de modèle qui sort l'empreinte au sol d'un sprite de jeu.**

**Conclusion** : il n'y a rien à télécharger qui réponde à la question. Mais ORG montre que **prédire
l'empreinte cachée d'un objet isolé, à partir d'une seule image, avec un réseau dense entraîné sur des
rendus synthétiques**, fonctionne. Notre cas est **plus simple** que le sien : caméra connue et fixe
(pas de champ de perspective à estimer), objets isolés sur fond transparent, une seule famille de
styles.

---

## 3. La représentation : deux hauteurs par pixel

### 3.1 Dans notre projection
Un pixel d'écran `(u, v)` voit tous les points `(x = u, y = v + h, h)` avec `h ≥ 0` : une droite qui
monte vers le spectateur. Le long de cette droite, le premier point touché est celui de plus grand `h`
(surface **avant**, celle qu'on voit). Le dernier point de matière est celui de plus petit `h` (surface
**arrière**, cachée). On prédit pour chaque pixel opaque :

| Canal | Sens | Unité |
|---|---|---|
| `hf` | hauteur du point vu (avant) | px d'écran HD |
| `hb` | hauteur du dernier point de matière sur la même ligne de vue (arrière caché) | px d'écran HD |
| `classe` | nature de la matière vue (§3.3) | 4 à 6 classes |

On en tire, **sans rien deviner de plus** :
- `sol_y` (canal R de `geo.png`) = `v + hf` : le pied au sol du point vu, donc le tri du pixel ;
- `h` (canal G) = `hf` : jusqu'où un perso est masqué (pieds, buste, tête) ;
- l'**empreinte complète** : chaque pixel « couvre » au sol le segment vertical `x = u`,
  `y ∈ [v + hb, v + hf]`. L'union de ces segments est la projection verticale de l'objet, **bord
  arrière caché compris**. Une ligne de vue qui traverse deux morceaux (pied avant puis pied arrière
  d'un banc) donne un segment plein, exactement ce que fait la « fermeture » voulue en jeu ;
- les **tranches de hauteur** : la partie du segment où la matière est sous une hauteur `H` est
  `y ∈ [v + hb, v + min(hf, H)]` si `hb < H`. C'est ce qui sépare « bloque le passage » (matière près
  du sol) de « passe au-dessus » (assise, feuillage, dossier).

Pourquoi en **pixels d'écran** et pas en unités du monde (argument d'ORG) : la hauteur de pixel ne
dépend pas de la caméra. Si une image générée montre un peu moins le dessus (`k_sol` réel 0,7 au lieu
de 1), l'empreinte prédite reste celle **que le joueur voit à l'écran**, donc juste en jeu, puisque la
carte est dessinée dans le même repère d'écran. Les seuils de hauteur (§6) gardent `k_haut = 1`.

### 3.2 Ce que les deux cartes ne disent pas
Une forme ne dit pas l'**intention** : une grille et un muret ont la même géométrie ; un buisson bloque
le passage (GDD §10.2), un feuillage d'arbre non. D'où un troisième canal.

### 3.3 Classes de matière (proposées)
| Classe | Exemples | Passage | Vue |
|---|---|---|---|
| `plein` | caisse, pierre, bois, métal | selon hauteur | selon hauteur |
| `ajoure` | grille, rambarde, filet tendu, barreaux | oui (au sol) | **non** (la vue passe) |
| `souple` | fleurs, feuillage, linge, buisson | selon hauteur | oui si assez haut |
| `plat` | tapis, filet au sol, plaque, flaque | non | non |
| `eau` | eau d'un bassin (pour l'animation, §4.5 première recherche) | — | — |

La table « classe → règles » est une **donnée** (`rules.json` ou `prop.json`), pas un réglage du
modèle (règle d'or n° 8). En cas de doute sur un objet, un **drapeau par objet** d'un mot (`ajoure`,
`traversable`) écrase la prédiction : c'est une donnée, pas un proxy.

---

## 4. Briques sur étagère (inférence GPU, sans tokens)

Critères : ce que la brique apporte à `hf` / `hb` / `classe`, qualité attendue sur notre style
(aplats, contour, pixel art), licence en France, coût.

### 4.1 Tableau
| Brique | Licence (à revérifier au fichier) | Apporte | Qualité attendue sur nos objets | Rôle |
|---|---|---|---|---|
| Depth Anything V2 **Small** | Apache-2.0 (Base/Large/Giant : CC-BY-NC) | profondeur relative de la face vue | plausible mais lissée ; aucune étude ne la teste sur du pixel art (une étude Eurographics 2025 sur la peinture : « aucun modèle directement utilisable », DA2 parmi les meilleurs) | **colonne vertébrale à affiner** (§5) |
| Depth Anything 3 Small / Base | Apache-2.0 (Large, Giant : CC-BY-NC) | idem, plus récent | idem | alternative à DA2-S |
| MoGe-2 (Microsoft, 2025) | code MIT, poids annoncés MIT ; sous-module DINOv2 à part | carte de points + normales | pensé pour des photos de scène | complément normales |
| Marigold (+ affinage « E2E » en une étape, WACV 2025) | Apache-2.0 (v1-0) | profondeur, normales, très fines | lent (diffusion), même limite | non retenu |
| Depth Pro (Apple) | `apple-ascl` | profondeur métrique | photos | non retenu |
| SAM 2.1 | Apache-2.0 | parties (pieds, pot, fleurs) | bon sur aplats | **contour net** des classes en post-traitement, optionnel |
| SAM 3 / 3.1 | « SAM License » (commerce permis avec restrictions, à lire) | parties par concept texte | bon | **SAM 3.1 déjà installé chez pixelforge** (`pf_2d__tenue`) ; optionnel |
| TRELLIS (v1) | MIT | maillage complet, **face cachée estimée** | forme générale correcte ; style cartoon hors données | **référence de comparaison** |
| TRELLIS.2 | MIT, mais nvdiffrast / nvdiffrec sous licence NVIDIA non commerciale dans la chaîne d'origine (le portage ComfyUI natif dit s'en passer) | idem, meilleur | idem | à éviter tant que la licence n'est pas claire |
| TripoSR | MIT, ~6 Go | maillage grossier, < 1 s | grossier | référence rapide |
| TripoSG (VAST) | MIT annoncé, > 8 Go | maillage net | à mesurer | **référence de comparaison** |
| Step1X-3D | Apache-2.0 | maillage + texture | à mesurer | alternative |
| Stable Fast 3D | Stability Community (gratuit < 1 M$ CA) | maillage < 1 s | grossier | possible |
| SAM 3D Objects | licence SAM | objet partiellement caché | à mesurer | non prioritaire |
| Hunyuan3D 2.x | **exclut l'UE** | — | — | **éliminé** |

### 4.2 Voie A : sur étagère seule
Deux montages possibles, aucun sans réserve :

**A1. Profondeur monoculaire seule.** Notre image n'a pas de sol, donc pas de plan auquel caler la
profondeur, et la surface arrière n'existe pas dans la sortie. La profondeur donne au mieux un ordre
relatif *dans* la face vue. **Ne répond pas à la question** (déjà vu en §3.1 de la première recherche).

**A2. Image → 3D → rendu dans notre projection.** On redresse l'image (étirement vertical de 1/√2 :
notre projection = caméra orthographique inclinée à 45°, sol et hauteur réduits du même cos 45°), on
génère un maillage (TRELLIS ou TripoSG), on le **recale** (lacet par pas de 90° puis fin, échelle,
position) en maximisant l'IoU entre sa silhouette rendue et l'alpha, puis on rend `hf`, `hb` et
l'empreinte exactement. C'est la seule brique qui sort une face cachée.
- Pour : aucun entraînement ; générique.
- Contre : 10 s à 1 min par objet ; sur les 16 Go de pixelforge, TRELLIS v1 et TripoSG passent
  (juste pour TRELLIS), TRELLIS.2 (~24 Go) non ; poids de plusieurs Go (accord de Julien au-delà de
  5 Go) ; la profondeur est **inventée sans connaître nos
  conventions** (un banc de pique-nique ou de chapelle, une fontaine à bassin bas…) ; style cartoon et
  pixel art loin des données ; recalage fragile sur les vues « front34 » où le dessus est caché ;
  pas de classes de matière ; licences à surveiller dans les dépendances.
- Verdict : **utile comme étalon** au premier essai (§8) et comme repli exceptionnel. Pas comme
  chaîne de production de dizaines d'objets par carte.

---

## 5. Voie B : un modèle dédié, entraîné sur données synthétiques

### 5.1 Principe
Un **prédicteur dense** : image RGBA de l'objet (HD, 518 px de côté au plus, fond transparent) →
cartes `hf`, `hb`, `classe` (+ une carte d'incertitude). C'est le montage d'ORG, simplifié (caméra
connue), et c'est la façon dont Depth Anything V2 a lui-même été construit : un enseignant entraîné
**uniquement sur des images synthétiques**, dont la vérité est exacte.

### 5.2 La fabrique de données (`pf_geo__dataset`)
**Sources de formes, sans problème de licence :**
| Source | Licence | Volume | Rôle |
|---|---|---|---|
| **Gabarits procéduraux** (code) : boîtes, cylindres, ellipsoïdes, pieds, plateaux, dossiers, bassins, pots, grilles, blobs de feuillage, assemblés aléatoirement | — (notre code) | illimité | cœur du jeu de données : vérité exacte, **parties et classes connues par construction** ; ce sont les gabarits de la première recherche (§3.5), tirés au hasard au lieu d'être écrits |
| Kenney (Furniture Kit, City Kit, Pirate Kit…), Quaternius, Poly Haven | CC0 | ~1 000 à 3 000 modèles | objets réalistes de nos familles |
| Objaverse / Objaverse++ (sous-ensemble filtré par qualité) | par objet : ~721 k CC-BY, ~3,5 k CC0, le reste NC (à exclure) | plusieurs milliers après tri | diversité ; garder CC0 et CC-BY, journaliser les attributions |
| **Sorties de `pf_px__prop`** (objets générés depuis un proxy) | les nôtres | quelques dizaines puis centaines | **les vraies images de notre style, avec vérité exacte** (le proxy) : la meilleure donnée possible, gratuite |

**Rendu** (Blender en ligne de commande ou rastériseur maison ; pas nvdiffrast) :
1. Pose au sol, lacet aléatoire (pas de 90° majoritaires, comme nos meubles alignés sur la grille,
   plus quelques angles libres), échelle tirée pour 1 à 4 cases.
2. Caméra orthographique à 45°, puis étirement vertical de √2 : exactement `écran_y = y − h`. Variante
   d'augmentation : `k_sol` tiré dans [0,6 ; 1] (images générées qui montrent moins le dessus).
3. **Vérité** par lancer de rayons (trimesh + Embree, multi-impacts) : pour chaque pixel, premier et
   dernier impact → `hf`, `hb` ; identifiant et classe de la partie touchée ; maillages non étanches
   réparés ou voxelisés (nombre d'enroulement).
4. **Habillage** pour approcher notre style, du moins cher au plus cher :
   - *toon* : ombrage en 2–3 aplats, contour épais (Freestyle ou contour de silhouette et d'arêtes),
     palette aléatoire vive, bruit de texture léger ;
   - *pixel art* : réduction ×4 par `pf_px__reduce` ou par simple quantification + plus proche voisin,
     puis ré-agrandissement ×4 (le modèle voit les mêmes blocs qu'en production) ;
   - *Qwen Image Edit 2511* sur le rendu argile (méthode des persos) pour une partie du lot, en gardant
     seulement les images dont la silhouette reste à IoU ≥ 0,9 du rendu, labels recalés sur l'alpha
     généré (pixels nouveaux rattachés au plus proche voisin). C'est le plus réaliste et le plus cher
     (~20–40 s par image) : 2 000 à 5 000 images, pas plus.
5. Augmentations à l'entraînement : couleur, teinte, contour plus ou moins épais, flou de bord, retrait
   ou ajout de quelques pixels d'alpha, symétrie horizontale (`hf`, `hb` inchangés).

**Taille visée** : 30 000 à 60 000 images, issues de ~3 000 à 5 000 formes (×10 variantes de pose,
d'échelle et d'habillage). ORG a utilisé 3,36 M d'images, mais pour toutes les caméras et tous les
objets du monde ; notre domaine est beaucoup plus étroit. À ajuster sur la courbe d'apprentissage du
premier essai (§8 : on commence à 10 000).

**Coût du rendu** : de l'ordre de 0,5 à 1,5 s par image sur un poste (rendu toon + rayons),
parallélisable sur les cœurs CPU : ~10–20 h pour 50 000 images, sans GPU dédié. Plus la part Qwen :
~1 à 2 jours de GPU pour 3 000 images. Le GPU étant partagé avec la file, ce serait 2 ou 3 nuits ; à
décider après le premier essai.

### 5.3 Le modèle
- **Colonne vertébrale** : encodeur DINOv2 ViT-S/14 de **Depth Anything V2 Small** (Apache-2.0,
  24,8 M de paramètres), déjà robuste aux styles grâce à ses 62 M d'images réelles pseudo-annotées.
  Alternative : DA3-Small (Apache-2.0). DINOv3 : licence propre, à lire avant usage.
- **Tête** : DPT (celle de DA2) avec 2 canaux de régression (`hf`, `hb`, normalisés par la hauteur
  de l'image comme ORG), 1 canal d'incertitude (perte de Laplace : le modèle dit où il doute), et une
  tête de classes (4–6 classes, entropie croisée).
- **Pertes** : L1 sur `hf` et `hb` dans l'alpha ; **perte d'empreinte** : IoU douce entre l'empreinte
  reconstruite (§3.1, différentiable par rastérisation de segments) et l'empreinte vraie ;
  contrainte `0 ≤ hb ≤ hf` ; pénalité sur `hf` au bas de chaque colonne (contact au sol ≈ 0).
- **Référence plus simple** à entraîner en parallèle au premier essai : un U-Net (encodeur
  EfficientNet ou ResNet-34) comme SpriteToMesh. Si l'U-Net fait aussi bien, on le garde (plus petit,
  plus rapide).
- **Entrée** : image HD (128 px par case) mise à 518 px en gardant les proportions, ou par tuiles pour
  les grands objets (maison, chalutier) avec raccord. Un sprite 32 px est d'abord agrandi ×4 au plus
  proche voisin.

### 5.4 Entraînement (estimations)
| Poste | Estimation | Base |
|---|---|---|
| Mémoire | 8–12 Go (lot de 8–16 à 518 px, bf16) | ViT-S + DPT : modèle de 25 M de paramètres |
| Débit | ~40 à 120 images/s sur la **RTX 5080 (16 Go)** de pixelforge | ~55 GFLOP par image à 518 px en avant, ×3 pour l'apprentissage ; rendement réel prudent |
| Durée d'un entraînement | 40 000 images × 25 époques ≈ 1 M d'échantillons → **3 à 8 h** | une nuit, file vide |
| Contraintes de la machine | GPU partagé avec la file ; 2 écrans bleus déjà | entraînement de nuit ou file vide ; **point de reprise toutes les 30 min** (poids, optimiseur, état du hasard, rang de l'échantillon) et reprise automatique ; la file reprend la main si un job arrive (pause propre) |
| Téléchargements | DA2-S ≈ 100 Mo, packs CC0 < 1 Go, Blender < 1 Go | sous le seuil ; Objaverse, TRELLIS ou TripoSG au-delà de 5 Go : **accord de Julien** |
| Nombre d'entraînements | 3 ou 4 (v0 sur 10 000 images, v1 complet, v2 avec la part Qwen et les sorties de proxy) | — |
| Inférence | **20–60 ms** par objet sur GPU (+ ~100 ms de post-traitement CPU) ; ~1 s sur CPU | ViT-S |

Repères publiés : DA2 a affiné ses enseignants sur 595 000 images synthétiques (lot 64, 160 000 pas) ;
un affinage de DA2 sur Hypersim : 80 000 pas ; ORG : lot 8, 60 000 pas, 4 A100. Nos chiffres sont
**plus petits d'un ordre de grandeur**, car le domaine est étroit et la caméra fixe ; ils sont à
valider par la courbe d'apprentissage de l'essai v0.

### 5.5 Risques, honnêtement
| Risque | Gravité | Parade |
|---|---|---|
| **Écart synthétique → réel** : le modèle lit bien les rendus toon et mal les vraies images générées | haute | DA2-S part d'un encodeur vu sur des photos et du dessin ; habillage pixel art et Qwen ; **sorties de proxy injectées dans l'entraînement** ; mesure sur un jeu de test réel (§5.6) avant toute production |
| **Profondeur cachée inventée** pour un objet inédit (barque retournée, tas de filets) | moyenne | la perte d'incertitude + l'écart entre l'image et son miroir donnent une confiance ; sous le seuil : repli proxy déclaré ou carte en Backlog |
| **Pixel art 32 px** : trop peu d'information | moyenne | on prédit **toujours sur la HD** (128 px par case) avant réduction ; un 32 px seul est agrandi ×4 et traité comme tel, avec une tolérance plus large |
| **Objets organiques** (fleurs, linge, filets) | moyenne | classe `souple` ; ils bloquent rarement le passage ; seuils de hauteur |
| **Caméra des images générées** qui dérive (vue de coin) | moyenne | hauteurs en pixels d'écran (§3.1) ; une petite tête qui estime `k_sol` sert de **refus** (vue de coin = image refusée, pas masque deviné) |
| **Grands objets** (maison, chalutier, phare : jusqu'à 640 px) | basse | tuiles avec recouvrement, ou réduction de l'entrée ; un bâtiment a de toute façon une emprise simple |
| **Intention de design** (grille vs muret) | basse | classes + drapeau d'un mot par objet |
| **Licences** des données | basse | gabarits maison + CC0 d'abord ; Objaverse filtré, attribution journalisée ; aucun poids non commercial |
| **Coût de développement** sous-estimé | moyenne | le post-traitement (§6) est **le même code** que celui de `pf_geo__proxy` : un proxy se rend en `hf` / `hb` / `classe` exacts, puis suit le même chemin ; on ne développe qu'une fois |

### 5.6 Mesurer la qualité
Trois jeux de test, du plus exact au plus réaliste :
1. **Synthétique tenu à part** : 300 formes jamais vues (un pack CC0 entier mis de côté). Vérité exacte.
2. **Objets nés d'un proxy** : le lot d'essai de la première recherche (pot, fontaine, banc, cabine)
   et la suite. Images réelles de notre style, vérité exacte.
3. **Objets réels annotés à la main** : 20 à 30 images (archive flat cartoon choisies en « front34 »,
   plus les premiers objets pixel art du bac à sable). Annotation une fois pour toutes : polygone de
   collision, ligne de bord arrière, ligne de contact, « bloque la vue » oui/non. C'est le seul endroit
   où l'on écrit de la géométrie à la main, et c'est pour mesurer, pas pour produire.

Mesures (en px de jeu, case = 32) :
| Mesure | Définition |
|---|---|
| IoU de collision | polygone prédit vs vérité, au sol |
| Erreur du bord arrière | par colonne, écart du y le plus haut de l'empreinte ; médiane et max |
| Erreur de contact | par colonne, écart entre le bas dessiné et le bas de l'empreinte (≈ `ecart_base_*` de `mesure_decor.gd`) |
| Erreur de tri | part des pixels opaques rangés dans la mauvaise tranche de 16 px |
| Vue | objet « bloque / ne bloque pas » juste ; IoU du polygone de vue |
| Sondes | `tests/decor/mesure_decor.gd` : le cercle d'un perso s'arrête au contact, des 4 côtés |
| Calibration | parmi les objets au-dessus du seuil de confiance, part qui passe les seuils |

---

## 6. Post-traitement géométrique déterministe (`geo → prop.json`)

**Entrées** (HD, 128 px par case) : alpha, `hf`, `hb`, `classe`, `incertitude`. Mêmes entrées que le
rendu analytique d'un proxy : **un seul code pour les deux voies**. Bibliothèques : numpy, OpenCV,
shapely. Aucun hasard, aucune décision floue.

Paramètres (données, en px de jeu, `rules.json` ou `prop.json`) : `h_passage` (hauteur sous laquelle la
matière bloque, proposée 8 px = un quart de perso), `h_vue` (au-dessus de laquelle elle coupe le cône,
liée à `vue_oeil`), `fermeture_px` (12, diamètre de collision d'un perso), `bande_tri_px` (16),
`h_ombre_lumiere` (hauteur minimale pour un occulteur).

1. **Nettoyage** : `hf ← max(hf, 0)`, `hb ← clamp(hb, 0, hf)` ; médiane 3×3 dans l'alpha ; classes par
   vote 3×3 ; option : contours des classes recalés sur les masques SAM 2.1.
2. **Empreinte par tranches de hauteur** : pour chaque pixel opaque `(u, v)` de classe concernée, on
   remplit au sol, colonne `x = u`, l'intervalle `[v + hb, v + min(hf, H)]` si `hb < H` (vectorisé
   par colonne). Avec `H = h_passage` → **masque de passage** ; avec la partie au-dessus de `h_vue` →
   **masque de vue**. Table des classes (§3.3) : `ajoure` compte pour le passage et pas pour la vue ;
   `plat` ne compte pour rien ; `souple` compte selon la hauteur.
3. **Fermeture morphologique** du masque de passage par un disque de `fermeture_px` (les pieds d'un
   banc deviennent une bande), ouverture des miettes (< 2 px de jeu), comblement des trous, composantes
   trop petites retirées.
4. **Polygones** : contours (OpenCV), simplification Douglas–Peucker à 0,5 px de jeu, ≤ 24 sommets,
   sens antihoraire, coordonnées **en px de jeu** dans le repère du sol de l'objet (§4.3 de la première
   recherche) : la HD n'est jamais « réduite », on divise par 4.
5. **Vue**, **occulteur de lumière** (masque des pixels de hauteur ≥ `h_ombre_lumiere`, projeté),
   **`hauteur_max`** (= max `hf`, en px de jeu).
6. **`geo.png`** : R = `sol_y = v + hf` (moins `canevas.origine.y`), G = `hf`, B = identifiant de partie
   (composantes connexes par classe et par saut de `sol_y`), A = alpha.
7. **Couches de tri** : chaque pixel va dans la tranche de son `sol_y` (`bande_tri_px`) ; objet peu
   profond (≤ 1 case) et sans débord : une seule couche, triée au milieu de la collision ; `tri` = milieu
   de la tranche. Recomposition contrôlée au pixel près.
8. **Ombre de contact** : masque des pixels de hauteur ≤ `h_passage`, projeté, adouci, en `ombre.png`.
9. **Réduction ×4** : l'image entière est réduite une fois (`pf_px__reduce`, palette verrouillée) ;
   `geo` par bloc 4×4 (`sol_y` et `h` par médiane, partie et classe par vote) ; couches découpées dans
   l'image réduite avec la carte réduite (règles §4.2 de la première recherche) ; polygones inchangés
   (déjà en px de jeu).
10. **Confiance** (écrite dans `controle`) : moyenne de l'incertitude dans l'empreinte ; IoU entre
    l'empreinte de l'image et celle de son miroir (remis à l'endroit) ; contact : `hf` du pixel le plus
    bas de chaque colonne ≈ 0 ; rapport profondeur/largeur dans la plage vue à l'entraînement ;
    `k_sol` estimé dans la tolérance.

---

## 7. Comparatif et recommandation

| Critère | A : sur étagère (image → 3D) | B : modèle dédié | C : hybride (B + proxy + A en étalon) |
|---|---|---|---|
| Tokens | 0 | 0 | 0 en production ; proxy écrit seulement en repli |
| Bord arrière caché | inventé sans nos conventions | **appris sur nos conventions** | appris, et exact pour les objets nés d'un proxy |
| Classes (grille, feuillage) | non | **oui** | oui |
| Notre projection | par redressement + recalage | **native** | native |
| Pixel art | hors données | **par habillage** | idem + données réelles |
| Vitesse par objet | 10 s – 1 min, 12–16 Go (TRELLIS.2 exclu à 16 Go) | **< 1 s**, 2–4 Go | < 1 s |
| Déterminisme | médiocre (générateur) | **bon** (inférence fixe, arrondi au px) | bon |
| Mise en place | 1 jour | 4–6 jours + 1–2 jours de GPU | idem B |
| Confiance mesurable | IoU du recalage | incertitude + miroir + contact | les deux |
| Licences | pièges (nvdiffrast, Hunyuan) | Apache-2.0 + CC0 | idem B |

**Classement** :
1. **C, hybride, centrée sur B (recommandée).**
   - **En production** : toute image d'objet (générée librement, générée depuis un proxy, ou existante)
     passe par `pf_geo__predict`. Zéro token.
   - **Les objets générés depuis un proxy** gardent leurs masques exacts du proxy, et la prédiction sert
     de **contrôle croisé** gratuit (IoU proxy vs prédiction). Chaque paire alimente l'entraînement
     suivant : le modèle s'améliore sur notre vrai style à chaque lot.
   - **Repli** sous le seuil de confiance : proxy déclaré (la voie de la première recherche), ou carte en
     Backlog avec la raison. Jamais de masque deviné en silence.
   - **A** (TRELLIS / TripoSG) seulement comme étalon du premier essai : si B ne bat pas A, on le saura.
2. **B seul** : même chose sans les proxys. Perd la vérité exacte des objets générés et le contrôle
   croisé. Acceptable si Julien veut abandonner les proxys entièrement.
3. **A seul** : rapide à essayer, mais lent, non natif, sans classes, à la licence fragile.
   Déconseillé en production.

Ce que ça change à la spec décidée : **rien n'est jeté**. `pf_geo__proxy` devient (1) un générateur
de vérité exacte pour l'entraînement et (2) le repli. Son code de masques (§6) est partagé. La
génération guidée par proxy reste possible, mais n'est plus **obligatoire** pour avoir des masques.

**Ce que pixelforge doit installer ou écrire** (RTX 5080 16 Go, Windows + ComfyUI ; SAM 3.1, Qwen Image
Edit 2511 et FLUX déjà là ; tout téléchargement > 5 Go soumis à l'accord de Julien) :
- Python : PyTorch (déjà là), poids **Depth-Anything-V2-Small** (Apache-2.0), `trimesh` + `embree`
  (pyembree ou embreex) pour les rayons, Blender 4.x en ligne de commande (rendu toon), OpenCV,
  shapely, scikit-image ;
- packs CC0 (Kenney, Quaternius, Poly Haven) ; en option, Objaverse filtré (CC0 et CC-BY) ;
- pour l'étalon A : TripoSG (MIT annoncé) ou TRELLIS v1 (MIT), sans nvdiffrast si possible ; poids > 5 Go : accord de Julien ;
- entraînement **reprenable** (points de reprise, reprise après écran bleu), lancé file vide ;
- trois styles : `pf_geo__dataset`, `pf_geo__train`, `pf_geo__predict` (§9).

---

## 8. Plan d'essai court (savoir vite si ça marche)

**Jour 0 — jeu de test et étalon (sans entraînement, ~1 jour)**
- Choisir **12 objets archivés** (`archive/2026-10-21-flat-cartoon/assets/decor/objets/`) couvrant les
  cas : `banc_chapelle`, `banc_vert`, `fontaine_place`, `pot_hortensias`, `barriques_cidre`,
  `lavoir_bassin`, `etal_criee`, `etabli_atelier`, `cachette_poubelle_ruelle`, `cachette_coffre_quai`,
  `lampadaire_port`, `platane_place`. Plus 2 vues de coin (`table_terrasse`, `caisses_poisson`) comme
  test de **refus**.
- Les annoter à la main (collision, bord arrière, contact, vue) : ~15 min par objet.
- Mesurer sur ce jeu : le masque `pf_2d__footprint` archivé (`masks.json`, la base à battre) et l'étalon
  **A2** (TripoSG ou TRELLIS + recalage + rendu).

**Jours 1–2 — fabrique v0**
- 300 gabarits procéduraux (bancs, tables, caisses, pots, bassins, grilles, arbres) + 200 modèles CC0 ;
  10 000 images toon + version pixel art ; vérité `hf`, `hb`, `classe`.
- Planche de contrôle : 50 images, vérité en surimpression (on vérifie la fabrique avant d'entraîner).

**Nuit 2 — entraînement v0**
- DA2-S + tête DPT 3 canaux + classes, et l'U-Net de référence, ~4–6 h chacun.

**Jour 3 — verdict**
- Mesures sur les trois jeux de test (§5.6). **Feu vert** si, sur le jeu réel annoté :
  - IoU de collision médiane **≥ 0,80**, et aucun objet sous 0,5 sans confiance basse ;
  - bord arrière : médiane **≤ 2 px de jeu** ;
  - contact : médiane **≤ 1 px de jeu** ;
  - vue juste sur **≥ 90 %** des objets ;
  - **meilleur que** `pf_2d__footprint` et que l'étalon A sur la moyenne des IoU ;
  - les 2 vues de coin sont **refusées**.
- Sinon : on lit les échecs. Si le défaut vient du style (bon en synthétique, mauvais en réel), on passe
  à l'habillage Qwen et aux sorties de proxy. Si le défaut vient de la forme (mauvais partout), on
  revient au proxy déclaré : la voie B ne vaut pas son coût.

**Ensuite** : les 4 objets du lot proxy (pot, fontaine, banc, cabine) sont prédits et comparés à leur
vérité exacte ; intégration telle quelle dans `bk_decor.gd` (même `prop.json`), mesure avec
`mesure_decor.gd`, Julien tranche en QA.

---

## 9. Proposition de spec pour pixelforge

> Brouillon de **demande de capacité** (GDD §14 : les jobs passent par la file, les messages servent aux
> demandes de capacité). Noms de styles proposés. Format de sortie = celui de la première recherche
> (§4.2, §4.3, §6.3), pour que `bk_decor.gd` lise la même chose quelle que soit la voie.

### 9.1 `pf_geo__predict` (inférence, GPU, zéro token)
**Entrées**
| Champ | Type | Sens |
|---|---|---|
| `input_image` ou `prop_task` (+ `variant`) | image / tâche | objet détouré, HD (128 px par case) de préférence ; un 32 px est agrandi ×4 |
| `id` | texte | identifiant de l'objet |
| `cases` | [l, p] | emprise sur la grille, si connue (sert au cadrage et au contrôle) ; sinon déduite |
| `px_par_case` | entier | 32 (px de jeu) ; HD = ×4 |
| `drapeaux` | liste | facultatif, un mot chacun : `ajoure`, `traversable`, `plat`, `cachette` ; écrasent les classes |
| `cachette` | objet | facultatif, comme `prop.json` (entrée, sortie, porte) |
| `params` | objet | `h_passage` (8), `h_vue` (d'après `vue_oeil`), `fermeture_px` (12), `bande_tri_px` (16), `h_ombre_lumiere` |
| `seuils` | objet | voir §9.3 (défauts fournis) |
| `modele` | texte | version des poids (défaut : la dernière validée) |
| `reduce` | booléen | enchaîner `pf_px__reduce` étendu (défaut vrai) |

**Sorties** (arborescence §4.2 de la première recherche)
- `prop.json` complet : `canevas`, `collision`, `vue`, `occulteur_lumiere`, `hauteur_max`, `couches`,
  `ombre`, `controle` ; `primitives` absent (ou proxy d'origine si `prop_task`).
- `geo.png` (R = `sol_y`, G = `h`, B = partie, A = alpha), `couches/*.png`, `ombre.png`, `hd/`.
- **Nouveau** : `hd/pred.npz` (cartes brutes `hf`, `hb`, `classe`, `incertitude`, en float16) pour
  l'analyse ; `classes.png` (couleur par classe).
- `apercu.png` : la planche §6.5 de la première recherche (image, collision verte, vue bleue, lignes de
  tri rouges, mannequin 32 px à 8 positions, version 32 px), **plus** une rangée « cartes » (`hf`, `hb`
  et classes en fausses couleurs).
- `controle` : `confiance` (0–1), `incertitude_moy`, `iou_miroir`, `contact_px`, `k_sol_estime`,
  `profondeur_sur_largeur`, `raisons` (liste) ; si `prop_task` : `iou_proxy_prediction`.
- **Refus** : si `confiance < seuil` ou `k_sol_estime` hors tolérance, pas de `prop.json` mais un
  `refus.json` avec les raisons chiffrées (comme les extras ignorés de `pf_px__character_set`).

### 9.2 `pf_geo__dataset` et `pf_geo__train` (hors ligne, sur demande)
- `pf_geo__dataset` : `gabarits` (nombre), `packs` (liste de sources CC0 / CC-BY), `variantes` par
  forme, `habillage` (`toon`, `pixel`, `qwen` avec proportion), `k_sol` (plage), `taille` (518),
  `graine`. Sorties : images RGBA, `hf` / `hb` / `classe` en float16, `meta.jsonl` (source, licence,
  attribution, pose, échelle), planche de contrôle de 50 images.
- Les tâches `pf_px__prop` (objets nés d'un proxy) sont **versées automatiquement** au jeu de données
  (vérité = rendu du proxy recalé).
- `pf_geo__train` : `dataset` (liste de tâches), `base` (`da2-small` | `unet`), `epoques`, `lot`,
  `graine`. Lancé seulement file vide (ou de nuit), **reprenable** : point de reprise toutes les
  30 min, reprise automatique après redémarrage, cède le GPU à un job de la file. Sorties : poids versionnés, courbes, **mesures sur les trois jeux de test** (§5.6) dans
  `eval.json`. Un poids n'est promu « défaut » de `pf_geo__predict` que s'il passe §9.3 et bat le
  précédent.

### 9.3 Critères d'acceptation mesurables
| Code | Critère | Seuil proposé |
|---|---|---|
| P1 | IoU de collision, jeu réel annoté | médiane ≥ 0,80 ; aucun objet accepté sous 0,5 |
| P2 | IoU de collision, synthétique tenu à part et objets nés d'un proxy | médiane ≥ 0,90 |
| P3 | Bord arrière (par colonne) | médiane ≤ 2 px de jeu, max ≤ 6 |
| P4 | Contact au sol (par colonne) | médiane ≤ 1 px de jeu, max ≤ 3 |
| P5 | Tri : pixels dans la mauvaise tranche | ≤ 5 % |
| P6 | Vue : objet « bloque / ne bloque pas » juste | ≥ 90 % des objets |
| P7 | Calibration : objets acceptés (confiance ≥ seuil) qui passent P1 | ≥ 95 % ; part refusée ≤ 20 % |
| P8 | Vues de coin et images hors projection | refusées à 100 % sur le jeu de test |
| P9 | Déterminisme : même entrée, mêmes poids → mêmes fichiers | identique au bit près (inférence fp32 ou noyaux déterministes, cartes arrondies au px avant post-traitement) |
| P10 | Temps | ≤ 1 s par objet (prédiction + post-traitement), hors réduction |
| P11 | Format | A4 à A7 de la première recherche (recomposition, réduction exacte, polygones valides, chaque pixel opaque a `sol_y`, `h`, couche) |

### 9.4 Plan d'entraînement
| Étape | Données | Modèle | Coût | Sortie attendue |
|---|---|---|---|---|
| v0 | 10 000 images (300 gabarits + 200 CC0), toon + pixel | DA2-S + DPT ; U-Net en parallèle | ~2 jours de dev, une nuit de GPU | verdict §8 |
| v1 | 40 000–60 000 images, tous les packs CC0, Objaverse filtré | le meilleur de v0 | une nuit à une journée | P1–P8 |
| v2 | + 2 000–5 000 images habillées par Qwen + toutes les sorties de proxy | affinage de v1 | 2–3 nuits de GPU partagé (Qwen surtout) | gain sur le jeu réel |
| ensuite | + chaque lot de décor accepté en QA | affinage court | quelques heures | amélioration continue |

---

## Sources

**Modèle le plus proche et idée de la hauteur de pixel**
- ORG, *Floating No More: Object-Ground Reconstruction from a Single Image* (CVPR 2025) : https://arxiv.org/html/2407.18914v1 ; CVPR : https://openaccess.thecvf.com/content/CVPR2025/html/Man_Floating_No_More_Object-Ground_Reconstruction_from_a_Single_Image_CVPR_2025_paper.html ; supplément (hauteurs avant / arrière normalisées) : https://openaccess.thecvf.com/content/CVPR2025/supplemental/Man_Floating_No_More_CVPR_2025_supplemental.pdf
- Sheng et al., *Controllable Shadow Generation Using Pixel Height Maps* (ECCV 2022) : https://arxiv.org/abs/2207.05385 ; *PixHt-Lab* (CVPR 2023) : https://arxiv.org/pdf/2303.00137.pdf ; code (non commercial) : https://github.com/ShengCN/PixHtLab-Src
- Watson et al., *Footprints and Free Space from a Single Color Image* (CVPR 2020) : https://arxiv.org/pdf/2004.06376
- *Amodal Ground Truth and Completion in the Wild* (CVPR 2024) : https://arxiv.org/abs/2312.17247
- SpriteToMesh (segmentation de sprites, 2026) : https://arxiv.org/html/2602.21153v1

**Outils d'éditeurs (alpha seulement)**
- Unity, `PolygonCollider2D.CreateFromSprite` : https://docs.unity.cn/6000.3/Documentation/ScriptReference/PolygonCollider2D.CreateFromSprite.html
- Godot, Sprite StaticBody Builder : https://store.godotengine.org/asset/rohan-choudhary/sprite-staticbody-builder/ ; Sprite Collision Generator : https://store.godotengine.org/asset/zwickarr/godot-sprite-collision-generator/ ; AutoColliders : https://github.com/graycastle/godot-AutoColliders/blob/main/README.md
- Normal maps de sprites : https://www.codeandweb.com/spriteilluminator/knowledgebase/emboss-tool ; comparatif (blog d'éditeur) : https://www.sprite-ai.art/blog/normal-map-generators-compared

**Profondeur et géométrie monoculaires**
- Depth Anything V2 (recette synthétique → réel, licences par taille) : https://arxiv.org/pdf/2406.09414 ; Small : https://huggingface.co/depth-anything/Depth-Anything-V2-Small-hf
- Depth Anything 3 (licences par taille) : https://huggingface.co/depth-anything/DA3-BASE/blob/main/README.md ; https://huggingface.co/SpatialHub/depth-anything-3-onnx
- MoGe / MoGe-2 : https://github.com/microsoft/moge ; https://arxiv.org/abs/2507.02546v1
- Affinage E2E de Marigold : https://arxiv.org/html/2409.11355v2
- Profondeur sur peintures (Eurographics 2025) : https://diglib.eg.org/handle/10.2312/dh20253048 ; sur bande dessinée (WACV 2022) : https://arxiv.org/abs/2110.03575v2
- Évaluer la profondeur monoculaire : https://arxiv.org/html/2510.19814v1
- DINOv3 (licence propre) : https://huggingface.co/facebook/dinov3-vits16-pretrain-lvd1689m

**Image → 3D**
- TRELLIS.2 et la réserve nvdiffrast : https://cgworld.jp/flashnews/01-202601-TRELLIS2.html ; https://github.com/microsoft/TRELLIS/issues/298 ; portage ComfyUI sans dépendance non commerciale : https://blog.comfy.org/p/trellis2-and-pixal3d-are-now-native
- TripoSR (MIT, ~6 Go) : https://www.cgchannel.com/?p=155878 ; TripoSG : https://gittrend.io/repo/VAST-AI-Research/TripoSG ; Step1X-3D (Apache-2.0) : https://comfyui-wiki.com/en/news/2025-05-13-step1x-3d-news
- Licence SAM (SAM 3, SAM 3D) : https://huggingface.co/facebook/sam3/blob/main/LICENSE ; https://scancode-licensedb.aboutcode.org/sam-2025-11-19.html

**Données 3D**
- Objaverse (licences par objet) : https://arxiv.org/pdf/2212.08051 ; Objaverse++ : https://arxiv.org/pdf/2504.07334
- Kenney (CC0) : https://kenney.nl/assets ; Quaternius (CC0) : https://quaternius.com ; Poly Haven (CC0) : https://polyhaven.com/models

**Dépôt**
- `docs/RECHERCHE_MASQUES_DECOR.md` (première recherche, format `prop.json`, critères A1–A10, §6.7) ;
  `GDD-BLACKOUT.md` §3, §9, §10.2, §14 ; `data/blackout/rules.json` (`vue_oeil`, `decor_*`) ;
  `archive/2026-10-21-flat-cartoon/assets/decor/objets/` (69 images) et `…/masques/*/masks.json`
  (34 masques : 4 vues de coin, confiances 0,65 à 1,0) ; `tests/decor/mesure_decor.gd` ;
  `GET https://stellar.tailbeda4d.ts.net/v2/styles` (lu le 22/10/2026 : 70 styles, aucun `pf_geo__*`
  encore, `pf_2d__footprint` heuristique, SAM déjà utilisé par `pf_2d__tenue` et `pf_2d__flap`).
