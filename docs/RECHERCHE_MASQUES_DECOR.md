# Masques du décor : recherche et proposition de livraison

> **Document d'analyse, sans décision.** Les décisions qui en sortiront vont dans `GDD-BLACKOUT.md`
> (§10.2 règles du décor, §14 pipeline pixelforge). Recherche du 22/10/2026 : lecture du dépôt, de
> l'API `GET /v2/styles` de pixelforge (lecture seule) et de sources web 2024–2026, citées en fin de
> document.

Le problème, dans les mots de Julien : un pot de fleurs sur lequel on ne marche pas, mais derrière
lequel on passe (derrière le pot et derrière les fleurs) ; une fontaine dont on fait le tour ; un banc
derrière lequel on passe tant qu'on est derrière ses pieds. Il faut que chaque objet de décor arrive
dans Godot avec des masques propres, si possible livrés par pixelforge.

---

## 1. Ce qu'on a déjà essayé, et pourquoi c'était fragile

### 1.1 Les deux sources actuelles
1. **Calcul local sur l'alpha** (`src/blackout/bk_decor.gd`, `_shape`) : silhouette, ouverture
   morphologique (mâts et pieds fins disparaissent), « enveloppe basse » (point opaque le plus bas de
   chaque colonne = contact avec le sol), puis le bord arrière de l'empreinte **déduit par symétrie
   centrale**, avec une profondeur minimale (`decor_profondeur_min`).
2. **`pf_2d__footprint` de pixelforge** (`tools/blackout/masques_pf.py`) : `footprint.png`,
   `occluder.png`, `ground_contact.png`, `ground_y.png` et `masks.json` (`polygons`, `front_y`,
   `back_y`, `baseline_y`, `blocks_view`, `confidence`, `warnings`). Le jeu le préfère au calcul local,
   sauf si `confidence < decor_masques_pf_confiance_min` ou si l'emprise couvre plus de
   `decor_masques_pf_part_max` de la silhouette (repli).

### 1.2 Ce que montrent les 34 masques archivés
(`archive/2026-10-21-flat-cartoon/assets/decor/masques/*/masks.json`, aperçus dans
`tools/blackout/masques/`)

- Les avertissements de pixelforge sont **des aveux d'heuristique** : « profondeur estimée … faute de
  face du dessus lisible » (8 objets), « rapport largeur/profondeur hors de [1,5 ; 6] » (9),
  « caméra en coin : emprise approchée (losange sur le bord bas) », « losange plafonné en profondeur »,
  « emprise imposée (footprint_override) » (2 objets corrigés à la main).
- Seuls 7 objets sur 34 ont une confiance de 1,0 ; 5 sont à 0,65.
- **Fontaine** (`fontaine_place`, confiance 0,8) : 7 morceaux fusionnés « dans la face avant d'une base
  ronde ». Sur l'aperçu, l'emprise verte rate tout le côté gauche du bassin et ne remonte pas jusqu'au
  bord arrière.
- **Banc** (`banc_chapelle`, 0,8) : l'emprise couvre presque toute la hauteur du dossier et de
  l'assise (« profondeur estimée 86 px »), alors qu'on attend la bande entre pieds avant et pieds
  arrière.

### 1.3 La cause de fond
**L'image d'un objet vu de 3/4 face ne contient pas l'information qu'on lui demande.** Le bord arrière
de l'empreinte est caché derrière l'objet. La profondeur d'un banc ou d'un bassin n'est lisible que si
la face du dessus est visible et reconnue. Toute méthode qui part du seul alpha doit donc *deviner* :
symétrie, rapport largeur/profondeur plausible, losange de la vue en coin. Ces suppositions sont
justes pour une caisse et fausses pour un banc, une fontaine ou un pot qui déborde.

S'y ajoutent trois causes secondaires :
- la **caméra n'est pas fixée** à la génération : FLUX dessine « un peu de dessus », parfois en coin,
  parfois avec une perspective. L'outil doit alors détecter la caméra (« vue en coin détectée »)
  avant de deviner l'empreinte ;
- la **nature des parties** (pieds, socle, dossier, feuillage) n'est pas connue, alors que c'est elle
  qui décide « bloque le passage », « bloque la vue » ou « passe devant » ;
- **un seul tri par objet** (`back_y`) : un grand objet dont on fait le tour (fontaine, bassin) ne
  peut pas être juste devant et derrière à la fois.

Conclusion : améliorer l'heuristique ne suffira pas. Il faut que **la géométrie soit connue, pas
devinée** : soit déclarée avant la génération, soit reconstruite en 3D et vérifiée contre l'image.

---

## 2. Comment font les jeux 2D vus de dessus en 3/4

### 2.1 Les principes communs
- **Origine au point de contact avec le sol.** Le guide de style de *Threadbare* (jeu Godot de la
  fondation Endless Access) l'énonce : persos et accessoires ont leur origine « at their contact point
  with the ground », la collision du perso est une capsule sur son ombre, et l'illusion de profondeur
  vient entièrement du tri en Y.
- **Empreinte de collision séparée du dessin** : petite, au sol (pieds, socle, tronc). Le haut du
  sprite (feuillage, toit, dossier) ne collisionne pas. On le retrouve dans les tutos Godot, Unity
  (« pivot at the feet ») et les jeux RPG 16 bits.
- **Tri en Y sur un point unique par sprite.** Pour un objet fixe, la règle souvent citée est de
  placer le point de tri **au fond de la collision** : comme on ne peut pas y entrer, tout perso plus
  bas est devant. C'est le choix actuel de `bk_decor.gd` (`back_y`).
- **Découper ce qui ne se trie pas avec un seul point.** *Stardew Valley* range ses cartes en couches
  `Back`, `Buildings`, `Paths`, `Front`, `AlwaysFront` : un arbre de `Front` est dessiné par-dessus le
  joueur s'il est au nord et dessous s'il est au sud ; `AlwaysFront` passe toujours devant (feuillage).
  Les moteurs isométriques découpent les grands objets en tranches qui se trient chacune. Le
  principe : **un objet = plusieurs morceaux, chacun avec son point de tri**.
- **La 3D comme outil de production d'une 2D propre.** *Dead Cells* rend ses persos depuis des modèles
  3D (3ds Max) avec un outil maison, et sauve la **carte de normales** à côté de chaque image pour
  l'éclairage. Les décors sont peints à la main puis « redessinés en normal maps » pour que les
  torches éclairent du bon côté. Plusieurs outils Blender font la même chose (caméra orthographique,
  échelle fixe px/unité, PNG transparent) : `blender-sprite-render`, Blender Pixel Kit, True Pixel Art
  Generator.

### 2.2 Ce que Godot 4.7 offre
| Besoin | Outil Godot | Remarque |
|---|---|---|
| Tri en profondeur | `CanvasItem.y_sort_enabled` sur le parent commun | « this and child CanvasItem nodes with a higher Y position are rendered in front » ; tri seulement entre nœuds de même `z_index`. Un nœud y-trié imbriqué fait trier ses enfants avec ceux du parent : un objet peut donc porter plusieurs `Sprite2D`, chacun à sa position de tri. |
| Point de tri | position du nœud (pas l'`offset` du sprite) | on place le `Sprite2D` à `y = sort_y` et on remonte l'image avec `offset`. |
| Collision | `StaticBody2D` + `CollisionPolygon2D` | polygone au sol, en px de la carte. |
| Ombres des lumières 2D | `LightOccluder2D` + `OccluderPolygon2D` | « For shadows to appear in the scene, LightOccluder2D nodes must be added » ; filtre `None` conseillé pour le pixel art ; `occluder_light_mask` choisit les lumières. Les occulteurs alimentent aussi un champ de distance signée (SDF) lisible par shader. |
| Relief sous la lumière | `CanvasTexture` (diffuse + normal map + specular) | effet seulement sous des `Light2D` ; normales attendues en X+, Y+, Z+ ; la lumière paraît plus faible, il faut monter `height` et `energy`. |
| Tuiles | `TileData.y_sort_origin`, couches physique et occlusion du `TileSet` | pratique pour des objets d'une case ; un objet de plusieurs cases avec des parties devant et derrière reste mieux en scène ou en nœuds. |
| Polygone depuis une image | `BitMap.create_from_image_alpha` + `opaque_to_polygons` | c'est la brique du calcul local actuel : utile pour un masque, pas pour deviner une empreinte cachée. |

**Vue du chasseur** (GDD §3.1) : elle est calculée par notre code (rayons sur le plan du sol), pas par
Godot. Il lui faut un **polygone « bloque la vue » au sol**, distinct de la collision (une grille
bloque le passage et pas la vue ; un feuillage bloque la vue et pas le passage).

### 2.3 Notre projection
`docs/STYLE_PARTY_HARD.md` : vue de dessus oblique façon RPG 16 bits, sans point de fuite. Le sol est
vu d'en haut et tout ce qui est vertical est dessiné de face. Un point à la position `(x, y)` au sol
et à la hauteur `h` s'affiche donc à :

```
écran_x = x
écran_y = y · k_sol − h · k_haut        (px de jeu, 32 par case ; k_sol = k_haut = 1 à vérifier
                                         sur les mesures de Party Hard, ex. bibliothèque 30×45)
```

C'est une projection **exacte et simple**. Une caméra orthographique inclinée à 45° la reproduit à
un facteur près (sol et hauteur réduits du même cos 45°). Tout ce qu'on veut savoir d'un objet s'en
déduit sans ambiguïté **dès qu'on connaît sa géométrie**.

---

## 3. Les approches par IA pour produire les masques

Critères : qualité pour *notre* besoin (empreinte cachée, nature des parties, tri), vitesse sur un GPU
grand public, licence (on est en France : les licences qui excluent l'UE sont éliminatoires),
adéquation au pixel art. Note : on travaille toujours sur l'**image HD** (128 px par case) avant
réduction. Aucun de ces modèles n'est fiable sur un sprite de 32 px.

### 3.1 Profondeur monoculaire
| Modèle | Licence | Vitesse | Remarque |
|---|---|---|---|
| Depth Anything V2 | Small : Apache-2.0 ; Base/Large/Giant : **CC-BY-NC-4.0** | < 1 s | relatif ; Small seul utilisable sans réserve |
| Depth Anything 3 (nov. 2025) | Mono-Large, Metric-Large, Base, Small annoncés Apache-2.0 ; Giant et « nested » CC-BY-NC | < 1 s | sources contradictoires sur Base : vérifier le fichier de licence |
| Marigold (ETH, diffusion) | Apache-2.0 (code et poids v1-0 ; v1-1 à vérifier) | quelques s | très fin, plus lent |
| Depth Pro (Apple) | licence Apple (`apple-ascl`), à lire | < 1 s | métrique, pensé pour les photos |

**Pour nous** : la profondeur classe bien les pixels *à l'intérieur* de l'objet (le rebord avant du
bassin est plus près que la colonne). C'est utile pour découper en couches et pour les normales.
Mais **elle ne donne pas l'empreinte** : notre image n'a pas de sol (fond transparent), donc pas de
plan de référence à ajuster, et la face arrière reste invisible. Sur des aplats cartoon à contour
épais, la profondeur relative est plausible mais lissée. **Rôle possible : complément, pas
source.**

### 3.2 Segmentation
| Modèle | Licence | Remarque |
|---|---|---|
| SAM 2 / 2.1 (Meta, sept. 2024) | Apache-2.0 (code et poids) | invite par points ou boîtes ; rapide |
| SAM 3 (Meta, nov. 2025) | « SAM License » maison | invite **par concept** (« legs », « flowers ») : toutes les instances d'un coup |
| Grounded-SAM / Grounded-SAM-2 | Grounding DINO 1.0 : Apache-2.0 (1.5 / 1.6 : API payante) | texte → boîtes → masques |

**Pour nous** : la segmentation répond à « quelle partie est-ce ? » : pieds, socle, pot, feuillage,
dossier. C'est exactement ce qui manquait aux heuristiques, et pixelforge l'utilise déjà
(`pf_2d__tenue`, `pf_2d__flap` font du SAM image par image). **Elle ne dit pas où est le bord
arrière caché** : un masque « pieds » donne les pieds avant visibles, pas la ligne des pieds arrière
quand ils sont masqués. **Rôle possible : étiqueter les parties ; utile seul pour les objets « posés
sur des pieds » si on suppose la profondeur.**

### 3.3 Génération ou décomposition en calques
| Modèle | Licence | Remarque |
|---|---|---|
| LayerDiffuse (Zhang & Agrawala, 2024) | dépôt d'origine à vérifier ; port FLUX communautaire (RedAIGC) | avant-plan transparent + arrière-plan, pas de découpe sémantique |
| **Qwen-Image-Layered** (Alibaba, déc. 2025) | **Apache-2.0** | une image → N calques RGBA (3, 4, 8…), parties cachées complétées, décomposition récursive ; 640 px conseillé ; ~45 Go en pointe à 1024 px (FP8 : 16–24 Go ; GGUF Q4 ~13 Go) |
| pix2gestalt (CVPR 2024) | recherche | complétion « amodale » de l'objet caché ; entraîné sur photos |

**Pour nous** : Qwen-Image-Layered est l'outil le plus proche de l'idée de Julien (« générer des
layers de sprites »). Il séparerait « fleurs » et « pot », « dossier » et « assise », et compléterait
ce qui est caché. Limites : les calques sont **sémantiques, pas rangés en profondeur** ; un benchmark
de 2026 (UniWorld-Design) lui donne un IoU d'alpha de 0,55 sur des visuels graphiques ; Scenario
signale des bords à nettoyer. Et **il ne donne toujours pas l'empreinte**. **Rôle possible : couches
d'un objet déjà généré, en complément d'une géométrie connue.**

### 3.4 Image → 3D, puis rendu
| Modèle | Licence | GPU | Remarque |
|---|---|---|---|
| TRELLIS (Microsoft, 2024) | MIT | 16 Go conseillés (8 Go min., source tierce) | maillage + texture, bonne forme générale |
| TRELLIS.2 (déc. 2025, 4 Md) | MIT, **mais** dépendances nvdiffrast/nvdiffrec sous licence NVIDIA (recherche/évaluation) | ~24 Go | meilleur, licence à éclaircir |
| Hunyuan3D 2.0 / 2.1 | licence Tencent **qui exclut l'UE, le Royaume-Uni et la Corée du Sud** | 6–10 Go pour la forme | **éliminé** (on est en France) |
| Stable Fast 3D | Stability Community (gratuit sous 1 M$ de CA) | < 1 s | dérivé de TripoSR |
| TripoSR | MIT (non revérifié ici) | < 1 s | forme grossière |
| SAM 3D Objects (Meta, nov. 2025) | licence SAM 3, à lire | — | reconstruit un objet *partiellement caché* à partir d'un masque |
| PartCrafter / OmniPart (2025) | recherche | — | 3D **découpée en parties** (pieds, assise, dossier) |

**Pour nous** : c'est la seule famille qui *estime la face cachée*. Une fois le maillage obtenu, tout
devient exact : rendu de dessus → empreinte ; rendu dans notre projection → profondeur et hauteur de
chaque pixel → tri, couches, normales. Mais :
- la face arrière et la profondeur sont **hallucinées** (plausibles, pas garanties) ;
- il faut **recaler** le maillage sur l'image (caméra, échelle). Le recalage se mesure (IoU entre la
  silhouette rendue et l'alpha), et c'est un vrai indice de confiance, contrairement aux
  avertissements actuels ;
- les objets plats cartoon à contour épais sont loin des données d'entraînement (photos, rendus 3D
  réalistes).

**Rôle possible : repli pour les images qui existent déjà (photos de Julien, décors déjà générés).**

### 3.5 L'inverse : partir d'un volume simple (« proxy ») et générer l'image dessus
On décrit l'objet par **quelques primitives** (boîtes, cylindres, ellipsoïdes) posées sur ses cases.
On rend ce proxy dans notre projection (profondeur, normales, silhouette, identifiant de primitive par
pixel). On génère l'image **guidée par ces rendus** (ControlNet de profondeur, ou édition d'un rendu
gris). Les masques viennent **du proxy**, donc exacts par construction. On vérifie seulement que
l'image respecte le proxy.

- Pixelforge sait déjà guider une génération par des images de contrôle : `pf__pose` (« silhouette ou
  rendu de mannequin »), `pf_anim__guided` (« silhouettes, profondeur »), `pf_2d__mannequin`.
  Côté modèles : ControlNet Union pour Qwen-Image (InstantX : canny, soft edge, **depth**, pose),
  patchs DiffSynth, Qwen-Image 2.1 Fun ControlNet Union (sept. 2026, à vérifier).
- Les meubles de Party Hard sont **des boîtes alignées sur la grille** (GDD §9 : « meubles dessus +
  face alignés sur la grille »). Une douzaine de gabarits paramétrés (caisse, table, banc, armoire,
  cabine, pot, fontaine, lampadaire, arbre, muret, poubelle, barque) couvrent presque tout.
- C'est le procédé de *Dead Cells* (la 3D sert à produire la 2D et ses normales), appliqué au décor,
  avec la diffusion à la place du rendu final.
- La caméra est **imposée** à la génération : fini « vue en coin détectée ».

**Limite** : les parties organiques (feuillage, fleurs, linge) débordent du proxy. On les déclare
« libres » : elles ne bloquent rien, et leurs pixels hors proxy sont rattachés à la primitive la plus
proche pour le tri.

### 3.6 Comparatif
| Approche | Empreinte cachée | Nature des parties | Tri / couches | Vitesse | Licence | Pixel art 32 px | Verdict |
|---|---|---|---|---|---|---|---|
| Heuristique sur l'alpha (actuel) | devinée | non | 1 ligne | instantané | — | via HD | fragile (§1) |
| Profondeur monoculaire | non | non | oui (relatif) | < 1 s | DA2-S, DA3, Marigold OK | via HD | complément |
| Segmentation (SAM 2.1/3) | non | **oui** | non | < 1 s | SAM 2.1 OK, SAM 3 à lire | via HD | complément |
| Calques (Qwen-Image-Layered) | non | oui (sémantique) | partiel | ~1–2 min, 16–24 Go | Apache-2.0 | via HD, bords à nettoyer | complément, à tester |
| Image → 3D (TRELLIS, SAM 3D) | **estimée** | avec PartCrafter | **oui** | 10 s–1 min, 16–24 Go | TRELLIS MIT ; Hunyuan éliminé | via HD | **repli** pour l'existant |
| **Proxy → image guidée** | **exacte** | **exacte** (déclarée) | **exact** | génération + rendu instantané | modèles déjà chez pixelforge | réduction cohérente | **voie principale** |

---

## 4. Recommandation

### 4.1 La géométrie se déclare, l'image s'y conforme
**Voie principale : chaque objet de décor naît d'un proxy 3D déclaré en données** (cases, primitives,
hauteurs, rôle de chaque primitive). Pixelforge rend le proxy dans notre projection, génère l'image
HD guidée par ce rendu, la contrôle, puis calcule tous les masques **depuis le proxy**, recalés sur
les pixels réels. La réduction ×4 traite l'image et les masques ensemble.

Pourquoi :
1. **Exact par construction.** L'empreinte, la profondeur de chaque pixel, la ligne de tri et le rôle
   des parties sont connus avant la génération. Plus de « profondeur estimée », plus de « losange
   plafonné ».
2. **Mesurable.** Le contrôle « l'image respecte-t-elle le proxy ? » est un IoU et une distance en
   pixels : on refuse une image, on ne bricole pas un masque.
3. **Fidèle au GDD.** Les règles (§10.2 : bas / haut / traversable, objet haut qui masque à moitié)
   deviennent des drapeaux par primitive, donc des **données** (règle d'or n° 8).
4. **Bonus gratuit** : normales, hauteur, ombre au sol et occulteur de lumière exacts (GDD §3.2).
5. **Proche de ce que pixelforge sait faire** : rendus de contrôle et génération guidée existent pour
   les persos.

**Repli pour les images existantes ou non guidées** : image → 3D (TRELLIS, MIT) ou, plus simplement,
proxy écrit à la main et **recalé** sur l'image (échelle et position ajustées pour maximiser l'IoU),
puis mêmes sorties. Si le recalage reste sous le seuil, la carte de l'objet repart en Backlog avec la
raison, sans masque deviné.

**Compléments à évaluer** (ni l'un ni l'autre n'est requis) : SAM 2.1 pour rattacher les pixels qui
débordent du proxy (fleurs) ; Qwen-Image-Layered pour compléter la partie cachée d'une couche « arrière »
si on veut l'animer séparément.

### 4.2 Ce que contient un objet livré
Un dossier par objet, par exemple `assets/blackout/decor/<id>/`.

| Fichier | Contenu | Unités |
|---|---|---|
| `prop.json` | description complète (schéma §4.3) | px de jeu (32 par case) |
| `sprite.png` | image entière, 32 px par case, PNG indexé, palette du décor | px de jeu |
| `couches/<nom>.png` | une image par couche de tri, **même canevas** que `sprite.png` ; leur superposition = `sprite.png` au pixel près | px de jeu |
| `ombre.png` | ombre au sol, calculée depuis le proxy (couche « sol ») | px de jeu |
| `geo.png` | RGBA 8 bits : R = `sol_y` (y au sol sous le pixel, depuis le haut du canevas), G = hauteur `h`, B = identifiant de primitive, A = alpha | px de jeu |
| `normales.png` | facultatif ; normales X+ Y+ Z+ (convention de `CanvasTexture`) | — |
| `hd/` | les mêmes images à ×4 (128 px par case) : source de la réduction et de la recette | px HD = 4 × px de jeu |
| `apercu.png` | planche de recette (§5.4) | — |

Règles qui font **survivre le tout à la réduction ×4** :
- **Toutes les données vectorielles sont en px de jeu**, dans le repère du sol de l'objet (§4.3). La
  HD n'est qu'un ×4 : aucun polygone n'est jamais « réduit ».
- **Canevas HD = 4 × canevas de jeu, ancré au même coin**, et l'origine des cases tombe sur une
  frontière de bloc 4×4. Ainsi un bloc HD = un pixel de jeu, sans demi-pixel.
- **On réduit l'image entière une seule fois** (`pf_px__reduce`, palette verrouillée), puis on la
  **découpe en couches avec la carte d'identifiants réduite** (vote majoritaire par bloc 4×4). Réduire
  chaque couche séparément ferait des contours doublés et des trous aux joints.
- `geo.png` se réduit par bloc : `sol_y` et `h` par médiane, identifiant par vote majoritaire. Normales
  : moyenne renormalisée, puis éventuellement quantifiée en quelques directions (look pixel art).
- Les parties plus fines qu'un pixel de jeu (pied de 3 px HD) disparaissent à l'image. Elles restent
  pourtant dans la collision, puisque celle-ci vient du proxy et non des pixels.

### 4.3 Schéma `prop.json` (commenté)

```jsonc
{
  "version": 1,
  "id": "banc_promenade",
  "type": "bas",                      // résumé pour le jeu : sol | bas | haut | traversable | cachette | ornement
  "cases": [2, 1],                    // emprise sur la grille [largeur, profondeur]
  "px_par_case": 32,                  // px de jeu ; la HD est à ×4
  "projection": { "k_sol": 1.0, "k_haut": 1.0 },   // écran_y = y·k_sol − h·k_haut

  // Repère du sol de l'objet : origine = coin arrière gauche de ses cases, x à droite, y vers le
  // spectateur (bas de l'écran), en px de jeu. Une fois l'objet posé, ces coordonnées s'ajoutent
  // telles quelles à celles de la carte.
  "canevas": {
    "taille": [64, 52],               // taille de sprite.png
    "origine": [0, -20]               // position du coin haut gauche du canevas dans le repère du sol
  },

  // Proxy : source de toutes les formes. Hauteurs en px de jeu (un perso = 32).
  "primitives": [
    { "nom": "pieds_avant",  "forme": "boite", "x": 3,  "y": 24, "l": 58, "p": 3,  "h0": 0,  "h1": 10,
      "passage": true,  "vue": false, "libre": false },
    { "nom": "pieds_arriere","forme": "boite", "x": 3,  "y": 12, "l": 58, "p": 3,  "h0": 0,  "h1": 10,
      "passage": true,  "vue": false },
    { "nom": "assise",       "forme": "boite", "x": 1,  "y": 12, "l": 62, "p": 15, "h0": 10, "h1": 13,
      "passage": false, "vue": false },          // en hauteur : son ombre au sol ne bloque rien d'elle-même
    { "nom": "dossier",      "forme": "boite", "x": 1,  "y": 11, "l": 62, "p": 3,  "h0": 13, "h1": 26,
      "passage": false, "vue": false }
  ],

  // Formes dérivées du proxy (livrées pour que le jeu n'ait rien à recalculer).
  "fermeture_px": 12,                                 // vides plus étroits qu'un perso comblés (entre les pieds)
  "collision": [ [[3,12],[61,12],[61,27],[3,27]] ],  // union des primitives "passage" projetées au sol, fermée
  "vue": [],                                          // union des primitives "vue" : bloque le cône du chasseur
  "occulteur_lumiere": [],                            // LightOccluder2D : primitives assez hautes pour porter une ombre
  "hauteur_max": 26,                                  // px ; comparée à l'œil du chasseur et à la taille d'un perso

  // Couches de tri : chaque couche est un Sprite2D placé à y = tri (repère du sol), dans le
  // calque y-trié des persos.
  "couches": [
    { "nom": "tout", "fichier": "couches/tout.png", "tri": 19.5 }
  ],
  "ombre": { "fichier": "ombre.png" },

  // Cachettes uniquement.
  "cachette": null,                   // { "entree": [x, y], "sortie": [x, y], "couche_ouverte": "porte_ouverte" }

  // Recette (rempli par pixelforge).
  "controle": {
    "iou_proxy": 0.93,                // silhouette du proxy rendu vs alpha de l'image HD
    "contact_sol_px": 0.8,            // écart moyen entre le bas dessiné et le bas du proxy, px de jeu
    "pixels_libres": 0.04,            // part des pixels hors proxy (rattachés à la primitive la plus proche)
    "recomposition_ok": true,         // somme des couches == sprite.png au pixel près (jeu et HD)
    "graine": 7, "modele": "…", "date": "…"
  }
}
```

Règles de calcul livrées avec le format :
- **Collision** = union des primitives `passage: true`, prise **au sol** (le rectangle `x, y, l, p`,
  quelle que soit la hauteur `h0` : on bute sur le pied, l'assise posée sur des pieds n'ajoute rien).
  Pour une primitive sans contact au sol (`h0 > 0`) et `passage: true`, on compte son ombre au sol
  (une table basse sans pieds visibles). Les vides plus étroits que `fermeture_px` (diamètre de
  collision d'un perso) sont ensuite comblés : les deux rangées de pieds du banc forment une seule
  bande, comme on l'attend en jeu.
- **Vue** = union des primitives `vue: true`, projetées au sol (GDD §3.1, §10.2 : un feuillage bloque
  la vue sans bloquer le passage ; une grille l'inverse).
- **Tri** : une couche par **tranche de profondeur** de l'empreinte. Son `tri` est le milieu de sa
  tranche. Un objet peu profond (≤ 1 case) et sans débord a une seule couche, triée au milieu de son
  empreinte. Un objet dont on fait le tour (fontaine, bassin) a des tranches de 16 px. Chaque pixel
  de l'image va dans la tranche de son `sol_y`. Comme la collision empêche d'entrer dans l'empreinte,
  l'erreur de tri reste sous une demi-tranche, cachée par le rayon du perso.
- **Masquage à moitié** (GDD §10.2) : le jeu sait quelles couches sont devant un perso (`tri >
  pieds`) et quels pixels le recouvrent ; `h` dans `geo.png` dit jusqu'où (pieds, buste, tête). La
  transparence pour les coéquipiers s'applique aux seules couches devant.

### 4.4 Montage dans Godot (pour mémoire, sans décision)
```
Objet (Node2D, y_sort_enabled = true, position = coin arrière gauche des cases)
├─ Ombre (Sprite2D, dans le calque « sol » sous les persos)
├─ Couche « tout » (Sprite2D, position = (0, tri), offset = canevas.origine − (0, tri), centered = false)
├─ StaticBody2D → CollisionPolygon2D × N (collision)
├─ LightOccluder2D (occulteur_lumiere, filtre None)
└─ (polygones « vue » remis au code du cône, pas à Godot)
```
Le format reste du JSON lu au chargement par `bk_decor.gd`, comme `masks.json` aujourd'hui. Générer des
`.tscn` hors ligne est possible, mais ajoute une étape sans gain évident.

### 4.5 Trois exemples traités (px de jeu, case = 32)

**Pot de fleurs** — 1×1 case, type `haut`. « On ne passe pas sur le pot, on passe derrière le pot et
derrière les fleurs. »
| Primitive | Forme | Position / taille | h0–h1 | passage | vue |
|---|---|---|---|---|---|
| pot | cylindre | centre (16, 16), r 9 | 0–14 | oui | non |
| fleurs | ellipsoïde, `libre` | centre (16, 15), rx 14, ry 11 | 12–40 | non | oui |

- Collision : octogone r 9 autour de (16, 16). Le feuillage plus large ne bloque pas : on longe le
  pot et on frôle les fleurs.
- Vue : ellipse 14 × 11 au sol (un enfant de 32 px derrière est caché par 40 px de fleurs).
- Tri : une couche à `tri = 16` (milieu). Un perso derrière (pieds < 7, bloqué par la collision) est
  sous le pot et les fleurs ; devant (pieds > 25), il passe dessus. Sur le côté, il est devant ou
  derrière selon qu'il est au sud ou au nord du centre.
- Masquage : derrière, `h` des fleurs (40) dépasse la tête : perso masqué ; coéquipiers voient les
  fleurs en transparence.

**Fontaine** — 3×3 cases (96 × 96), type `bas`. « On en fait le tour. »
| Primitive | Forme | Position / taille | h0–h1 | passage | vue |
|---|---|---|---|---|---|
| bassin | cylindre | centre (48, 48), r 44 | 0–12 | oui | non |
| eau | disque | centre (48, 48), r 38 | 9 | non | non |
| colonne | cylindre | centre (48, 48), r 6 | 0–48 | oui | non |
| vasque | cylindre | centre (48, 48), r 14 | 38–44 | non | non |

- Collision : disque r 44 (polygone de 16 côtés). On en fait le tour sur tous les côtés, y compris
  à gauche et derrière, ce qui manquait à `fontaine_place`.
- Vue : aucune. Le bassin (12 px) est sous l'œil du chasseur, la colonne est fine ; si on voulait
  qu'elle coupe la vue, ce serait un drapeau sur `colonne`, pas une heuristique.
- Tri : 6 couches de 16 px de profondeur (`tri` = 12, 28, 44, 60, 76, 92). Un perso qui longe le flanc
  gauche à mi-profondeur passe devant le rebord arrière et derrière le rebord avant. La colonne et la
  vasque tombent dans la tranche centrale.
- Animation de l'eau : couche `eau` séparée, possible (`pf_2d__loop`), sans toucher aux masques.

**Banc** — 2×1 cases (64 × 32), type `bas`. « On passe derrière tant qu'on est derrière ses pieds. »
(primitives du schéma §4.3)
- Collision : bande des pieds, de y = 12 (pieds arrière) à y = 27 (pieds avant), sur 58 px. On ne
  bute ni sur le dossier (en hauteur, il est au-dessus de la ligne des pieds arrière) ni sur l'air.
- Vue : aucune (26 px < un perso debout). Le banc ne cache pas un perso : il le masque à moitié
  (jambes et bas du corps, d'après `h`).
- Tri : une couche, `tri = 19,5` (milieu de la bande). Derrière les pieds arrière, le perso est sous
  le dossier ; devant les pieds avant, il est dessus.

---

## 5. Risques et ce qu'il faut tester

### 5.1 Risques
| Risque | Effet | Parade |
|---|---|---|
| La génération guidée s'écarte du proxy (formes molles, perspective qui revient) | IoU bas, image refusée | ControlNet profondeur + rendu gris en `input_image` ; seuil d'IoU ; jusqu'à N candidats |
| Parties organiques (fleurs, arbres, linge) | pixels hors proxy | primitives `libre` ; rattachement à la plus proche ; elles ne bloquent rien |
| Écrire les proxys coûte du temps | blocage de la production | gabarits paramétrés ; proxy écrit par nous (Claude) depuis la description de l'objet, revu sur l'aperçu |
| Projection de Party Hard mal mesurée (`k_sol`, `k_haut`) | objets trop plats ou trop hauts | mesurer sur `docs/STYLE_PARTY_HARD.md` (bibliothèque 30×45) avant le premier lot |
| Pieds de 1 px à 32 px | disparaissent à l'image | normal : la collision vient du proxy, pas des pixels |
| Couches multiples | coûts de dessin, coutures | recomposition contrôlée au pixel près ; quelques sprites par objet restent négligeables |
| Tri imbriqué Godot | couche qui ne se trie pas avec les persos | test dédié dans `bk_tests.gd` (nœud y-trié imbriqué, même `z_index`) |
| Licences | outil inutilisable plus tard | Hunyuan3D éliminé (UE exclue) ; DA2 Base/Large non commerciaux ; TRELLIS.2 (nvdiffrast) et SAM 3 / SAM 3D à lire ; FLUX.1 [dev] utilisé par pixelforge : vérifier aussi ses conditions sur les images produites |
| Normal maps sur du pixel art à aplats | lumière moins vive (doc Godot), look « plastique » | essai A/B sur 3 objets, normales quantifiées |

### 5.2 Essais proposés
1. **Projection** : mesurer `k_sol` / `k_haut` sur les captures de Party Hard ; rendre un proxy de
   bibliothèque et superposer.
2. **Fidélité de la génération guidée** : 4 objets du lot d'essai (§6.6), 4 candidats chacun ;
   mesurer l'IoU proxy / alpha et le contact au sol. Cible : ≥ 3 candidats sur 4 au-dessus du seuil.
3. **Repli image → 3D** : TRELLIS sur `fontaine_place.png` et `banc_chapelle.png` (archive) ; comparer
   l'empreinte au masque `pf_2d__footprint` actuel avec `tests/decor/mesure_decor.gd` (sondes,
   `ecart_base_*`).
4. **Calques** : Qwen-Image-Layered sur le pot de fleurs généré ; les calques correspondent-ils aux
   primitives (IoU par primitive) ? Gain réel par rapport au découpage par `sol_y` ?
5. **Tri en tranches dans Godot** : fontaine en 6 couches, perso piloté en cercle autour ; captures
   tous les 15° (`visite_decor.gd`).
6. **Normales** : fontaine et banc avec et sans `normales.png` sous un lampadaire.

---

## 6. Proposition de spec pour pixelforge

> Brouillon à envoyer à pixelforge comme **demande de capacité** (GDD §14 : les jobs passent par la
> file ; les messages servent aux demandes de capacité). Les noms de styles sont des propositions.

### 6.1 Vue d'ensemble
Trois étapes chaînées (`then`), sur le modèle de `pf_px__character_set` → `pf_px__reduce` :

1. **`pf_geo__proxy`** (code, sans GPU) : proxy JSON → rendus de contrôle dans notre projection.
2. **`pf_px__prop`** (moteur A, décor) : prompt + rendus de contrôle → objet pixel art HD (128 px par
   case), guidé par la profondeur, fond transparent, sans ombre ni sol, puis contrôle de fidélité et
   calcul des masques depuis le proxy.
3. **`pf_px__reduce`** étendu (moteur B) : `prop_task` → même kit réduit ×4, couches et `geo`
   comprises.

Variante de repli : **`pf_geo__fit`** : `input_image` (objet déjà dessiné) + proxy approché → proxy
recalé (échelle, position, hauteurs) par maximisation de l'IoU, puis mêmes sorties que l'étape 2 sans
génération. Option `estimate: "trellis"` pour proposer un proxy depuis un maillage TRELLIS quand on
n'en a pas.

### 6.2 Entrées
| Champ | Type | Sens |
|---|---|---|
| `prop` | objet | `prop.json` partiel : `id`, `type`, `cases`, `px_par_case` (32), `projection`, `primitives` (formes : `boite`, `cylindre`, `ellipsoide`, `disque` ; champs `x, y, l, p` ou centre + rayons, `h0, h1`, `passage`, `vue`, `libre`), `cachette` |
| `prompt` | texte | description simple, sans négation |
| `colors` | entier | palette (comme les persos) |
| `num_images` | entier | candidats (défaut 4) |
| `seed` | entier | graine |
| `bande_tri_px` | entier | épaisseur des tranches de tri en px de jeu (défaut 16 ; 0 = une seule couche) |
| `fermeture_px` | entier | vides de collision comblés sous cette largeur, px de jeu (défaut 12) |
| `seuils` | objet | voir §6.4 (défauts fournis) |
| `normales` | booléen | produire `normales.png` (défaut vrai) |

### 6.3 Sorties (par candidat retenu)
Arborescence identique à §4.2. Toutes les tailles de jeu sont des multiples exacts : `hd/*` = 4 ×.
- `prop.json` complet : `canevas`, `collision`, `vue`, `occulteur_lumiere`, `hauteur_max`, `couches`
  (nom, fichier, `tri`), `ombre`, `controle`. Polygones fermés, simples, sens antihoraire, sommets en
  px de jeu entiers ou demi-entiers, ≤ 24 sommets chacun.
- `sprite.png`, `couches/*.png`, `ombre.png` : PNG indexés, palette commune, même canevas.
- `geo.png` : R = `sol_y` − `canevas.origine.y` (0–255), G = `h` (0–255), B = identifiant de primitive
  (0 = libre), A = alpha.
- `normales.png` (si demandé).
- `controles/` : `profondeur.png`, `silhouette.png`, `ids.png` du proxy (pour la recette).
- `apercu.png` : planche de recette (§6.5).
- Rejets : pour chaque candidat écarté, la raison chiffrée dans `set.json` (comme les extras ignorés
  de `pf_px__character_set`).

### 6.4 Critères d'acceptation (mesurés par pixelforge, écrits dans `controle`)
| Code | Critère | Seuil proposé |
|---|---|---|
| A1 | IoU entre la silhouette du proxy rendu (hors primitives `libre`) et l'alpha de l'image HD | ≥ 0,85 |
| A2 | Contact au sol : pour chaque colonne du proxy touchant le sol, écart entre le bas dessiné et le bas du proxy | médiane ≤ 1 px de jeu, max ≤ 3 |
| A3 | Pixels de l'image hors proxy (dilaté de 2 px de jeu) qui ne sont pas rattachés à une primitive `libre` | ≤ 3 % |
| A4 | Recomposition : superposition des couches == `sprite.png` | 0 pixel différent (jeu et HD) |
| A5 | Réduction : `hd/sprite.png` réduit == `sprite.png` livré ; frontières de couches sur la grille 4×4 | exact |
| A6 | Collision dans les cases de l'objet (sauf débord déclaré) ; polygones valides | exact |
| A7 | Chaque pixel opaque a un `sol_y`, un `h` et une couche | 100 % |
| A8 | Pas de sol, pas d'ombre peinte dans `sprite.png` (l'ombre est dans `ombre.png`) | pixels sombres sous le contact ≤ 1 % |
| A9 | Reproductibilité : même entrée + même graine → mêmes fichiers | identique |
| A10 | Temps : étapes 1 + 3 | < 10 s ; étape 2 ≤ 2 min pour 4 candidats |

### 6.5 Planche de recette (`apercu.png`)
Une rangée par vue, ×4 au plus proche voisin :
1. image seule ; 2. collision en vert, vue en bleu, lignes de tri en rouge, tranches colorées ;
3. silhouette du proxy en surimpression (contour) avec l'IoU écrit ;
4. un **mannequin de 32 px** composité selon les règles de tri à 8 positions : devant, derrière,
   gauche, droite, et les 4 coins, au contact de la collision ; 5. version 32 px finale.
C'est la même lecture que `docs/TEST_DECOR.md` §2, mais faite à la livraison.

### 6.6 Lot d'essai
Les quatre proxys sont donnés en px de jeu (case = 32). Ils sont repris de §4.5.

1. **Pot de fleurs** (`pot_fleurs`, 1×1, `haut`) : « a round terracotta flower pot overflowing with red
   and yellow geraniums ». Primitives : `pot` cylindre centre (16,16) r 9 h 0–14 passage ; `fleurs`
   ellipsoïde centre (16,15) rx 14 ry 11 h 12–40 vue, libre.
2. **Fontaine** (`fontaine_place`, 3×3, `bas`) : « a round stone fountain with a low basin of water and
   a slender central column with a small bowl ». Primitives : `bassin` r 44 h 0–12 passage ; `eau`
   disque r 38 h 9 ; `colonne` r 6 h 0–48 passage ; `vasque` r 14 h 38–44. `bande_tri_px` 16.
3. **Banc** (`banc_promenade`, 2×1, `bas`) : « a wooden park bench with green slats and black iron
   legs ». Primitives du schéma §4.3.
4. **Cabine de plage** (`cabine_plage`, 1×1, `cachette`) : « a small striped blue and white wooden
   beach hut with a door on the front ». Primitives : `cabine` boîte x 2 y 4 l 28 p 26 h 0–60 passage,
   vue ; `toit` boîte x 0 y 2 l 32 p 30 h 60–68 vue. Cachette : `entree` (16, 36), `sortie` (16, 38),
   couche supplémentaire `porte_ouverte` (même canevas). Attendu : un perso derrière est entièrement
   masqué ; devant, jamais recouvert.

Pour chaque objet : 4 candidats, graine 7, planche de recette. Intégration telle quelle dans le jeu
(`bk_decor.gd` lit `prop.json`), mesure avec `tests/decor/mesure_decor.gd`, Julien tranche en QA.

---

## Sources

**Pratiques des jeux et de Godot**
- Threadbare, *Perspective* (origine au sol, tri en Y) : https://threadbare-docs.readthedocs.io/en/latest/visual_style/perspective/
- Godot, `CanvasItem.y_sort_enabled` : https://docs.godotengine.org/en/stable/classes/class_canvasitem.html
- Godot, *2D lights and shadows* (LightOccluder2D, filtres, SDF, normal maps) : https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html
- Godot, `LightOccluder2D` : https://docs.godotengine.org/en/4.2/classes/class_lightoccluder2d.html
- Godot, `CanvasTexture` : https://docs.godotengine.org/en/4.2/classes/class_canvastexture.html
- Godot, `TileData.y_sort_origin`, collision et occulteur par tuile : https://godot.readthedocs.io/en/4.2/classes/class_tiledata.html
- Godot, `TileMapLayer` : https://docs.godotengine.org/fr/4.x/classes/class_tilemaplayer.html
- Forum Godot, polygone de collision depuis une image (`opaque_to_polygons`) : https://forum.godotengine.org/t/how-can-i-automatically-create-a-collisionpolygon2d-from-an-image-using-gdnative-or-gdscript/22437
- Forum Godot, disparition du nœud YSort dans Godot 4 : https://forum.godotengine.org/t/what-happened-to-ysort-node-in-godot4/4095
- Stardew Valley, couches de carte (Back, Buildings, Front, AlwaysFront) : https://stardewvalleywiki.com/Modding:Maps
- Dead Cells, entretien (décors peints puis normal maps) : https://80.lv/articles/interview-with-the-developers-of-dead-cells
- Dead Cells, pipeline 3D → 2D des persos : https://80.lv/articles/case-study-dead-cells-character-art-pipeline/
- Rendu de sprites depuis Blender : https://github.com/coreway-labs/blender-sprite-render
- Laigter (normal maps 2D, GPL-3.0, mode ligne de commande) : https://laigter.readthedocs.io/en/latest/Introduction/intro.html

**Profondeur**
- Depth Anything V2 (licences par taille) : https://cdn.jsdelivr.net/gh/depthanything/depth-anything-v2@main/README.md
- Depth Anything 3 : https://huggingface.co/depth-anything/DA3-BASE/blob/main/README.md
- Marigold : https://github.com/prs-eth/marigold
- Depth Pro (Apple) : https://venturebeat.com/ai/apple-releases-depth-pro-an-ai-model-that-rewrites-the-rules-of-3d-vision/ ; licence `apple-ascl` : https://huggingface.co/mickeyvanolst/depthpro-coreml

**Segmentation**
- SAM 2 / 2.1 : https://github.com/facebookresearch/sam2
- SAM 3 : https://roboflow.com/blog/what-is-sam3 ; licence : https://huggingface.co/cubert-gmbh/sam3
- Grounded SAM : https://playground.roboflow.com/models/idea-research/grounded-sam

**Calques**
- LayerDiffuse : https://physics.paperswithcode.com/paper/transparent-image-layer-diffusion-using ; port FLUX : https://www.runcomfy.com/comfyui-nodes/ComfyUI_FluxLayerDiffuse
- Qwen-Image-Layered : https://huggingface.co/Qwen/Qwen-Image-Layered ; article : https://arxiv.org/html/2512.15603v1
- Qwen-Image-Layered, mémoire et temps : https://comfyui-wiki.com/en/tutorial/advanced/image/qwen/qwen-image-layered
- Qwen-Image-Layered, limites constatées : https://help.scenario.com/en/articles/qwen-image-layered-multi-layer-assets
- UniWorld-Design (comparatif d'IoU d'alpha) : https://arxiv.org/pdf/2608.03971
- pix2gestalt (complétion amodale) : https://gestalt.cs.columbia.edu/

**Image → 3D et génération guidée**
- TRELLIS.2 : https://huggingface.co/microsoft/TRELLIS.2-4B/blob/main/README.md ; réserve nvdiffrast : https://cgworld.jp/flashnews/01-202601-TRELLIS2.html
- TRELLIS (licence MIT) : https://docs.api.nvidia.com/nim/reference/microsoft-trellis
- Hunyuan3D, licence (territoire hors UE) : https://huggingface.co/tencent/Hunyuan3D-2/blob/main/LICENSE ; 2.1 : https://arxiv.org/html/2506.15442v1 ; mémoire : https://comfy.icu/node/Hy3D21MeshGenerator
- Stable Fast 3D : https://huggingface.co/stabilityai/stable-fast-3d
- SAM 3D Objects : https://ai.meta.com/sam3d/ ; article : https://arxiv.org/pdf/2511.16624
- PartCrafter (3D en parties) : https://arxiv.org/html/2506.05573v1
- ControlNet Union pour Qwen-Image (dont profondeur) : https://huggingface.co/InstantX/Qwen-Image-ControlNet-Union

**Dépôt**
- `src/blackout/bk_decor.gd` (`_shape`, `_pf_shape`), `tools/blackout/masques_pf.py`, `docs/TEST_DECOR.md`,
  `docs/STYLE_PARTY_HARD.md`, `archive/2026-10-22-docs-gordeka/SPEC-GORDEKA.md` (§ règles du décor),
  `archive/2026-10-21-flat-cartoon/assets/decor/masques/`, `tools/blackout/masques/*.png`,
  `GET https://stellar.tailbeda4d.ts.net/v2/styles` (lu le 22/10/2026).

### 6.7 Amendements après l'avis de pixelforge (22/10)
Avis de pixelforge : faisable ; toute la géométrie se calcule sans GPU ; seul risque, la fidélité de la
génération (A1). Retenu d'un commun accord :
- **Guidage** : rendu « argile » gris du proxy en image 1 de Qwen Image Edit 2511 (méthode des persos) ;
  ControlNet Union (profondeur) seulement si A1 échoue. Qwen est sous Apache-2.0.
- **Conformité** : recalage translation/échelle ±5 % au meilleur IoU, puis coupe hors proxy dilaté de
  2 px (hors primitives `libre`) ; A3 tenu par construction.
- **Drapeau `rendu`** par primitive (vrai par défaut) : une primitive `rendu: false` compte pour la
  collision mais pas pour la silhouette. Banc : 4 pieds réels (`rendu`, `passage`) + 2 bandes
  `rendu: false`, `passage` ; idem grilles et barrières.
- **Cartes d'ids et `geo`** calculées analytiquement au pixel de jeu, ×4 en HD ; pixels libres rattachés
  en HD puis vote 4×4.
- **Porte de cachette** : `porte: {face, x0, x1, h0, h1}` ; couche `porte_ouverte` par retouche Qwen,
  refusée si l'IoU hors porte < 0,97 ; repli : intérieur sombre peint par le code. Cabine du lot : face
  avant, x 10–22, h 0–40.
- **Ombre v1** : ombre de contact (empreinte adoucie). Les ombres des lumières sont calculées en jeu
  (`occulteur_lumiere`, GDD §3.2).
- **Projection** : `k_sol = 1`, `k_haut = 1` (sol à grille carrée et perso de 32 px = une case, §2 de
  STYLE_PARTY_HARD), gardés en paramètres.
- **Palette** : une par objet pour l'essai.
- **A9** : géométrie identique au bit près ; images identiques à graine égale sur la même machine et les
  mêmes versions. **A10** : ≤ 5 min pour 4 candidats (lot d'essai), 2 candidats par défaut ensuite.
- **`pf_geo__fit`** sans TRELLIS en v1 (supprimé le 19/10) : proxys écrits par Claude.
- **Découpage** : 1) `pf_geo__proxy` + masques + aperçu, avec livraison des proxys rendus des 4 objets
  avant toute génération ; 2) `pf_px__prop` ; 3) `pf_px__reduce` étendu et lot d'essai
  (`miarritze/decor_proxy_essai`) ; 4) `pf_geo__fit`.
