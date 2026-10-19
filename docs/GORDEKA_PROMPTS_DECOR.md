# Gordeka — prompts de génération du décor (Port des Pêcheurs v2)

> Préparé le 2026-10-19. **Rien n'a été envoyé** à pixelforge ni à Retro Diffusion. Même contenu en JSON : `tools/gordeka/prompts_decor.json`. Sources : `tools/gordeka/make_port_v2.py`, `assets/maps/port_pecheurs/map.txt` et `zones.json`, `src/gordeka/gk_map.gd`, `docs/GORDEKA_STYLE_2D.md`, `SPEC-GORDEKA.md` §8, §9, §16.

## 1. Préambule de style commun

**Avec pixelforge**, le préambule est déjà intégré aux styles `pf_hd__prop` (objets, vue 3/4, fond transparent, 512 px par défaut, jusqu'à 1024), `pf_hd__ground` (sols sans couture vus de dessus, 1024 px, jamais de `theme`) et `pf_hd__texture` (même chose vue de face : façades). Les payloads du JSON (`payloads`) n'envoient donc que le prompt court et concret, couleurs nommées en hexa, avec `theme: "basque"` quand il y a boiseries, volets ou tuiles, `shadow` (`layer` pour les objets, `none` pour ce qui est à plat au sol), `num_images` (2 à 4), `width`/`height` et `seed`. Les variantes d'état (ouvert, allumé, image suivante de l'eau) passent par `pf_hd__edit` sur l'image validée (`edits`). Le préambule complet ci-dessous sert pour tout autre outil (champ `prompt`).

Chaque prompt = **préambule** + **suffixe du type** + **description propre à l'élément**. Le préambule décrit notre propre style (contour bleu marine épais et régulier, aplats et une ombre franche, « no pixel art ») sans citer de jeu existant (Julien, 2026-10-20).

```text
Clean flat 2D vector cartoon game asset in the art style of our game Miarritze Gordeka: thick uniform dark navy outline, flat colors with one darker hard cel-shadow tone, tiny white highlights, no gradient, no texture, no noise, smooth clean cartoon, no pixel art. Camera: top-down view with a slight 3/4 tilt: we see the top of things from above and a small strip of their front face, orthographic, no vanishing point, not isometric. Setting: the old fishermen's port of Biarritz in the French Basque Country: whitewashed walls, Basque red and dark green paint, red clay roof tiles, warm golden sandstone, navy and turquoise sea. Cute, friendly and readable from far away for 9 year old children, nothing scary, no weapons, no people, no text, no letters, no logo.
```

Suffixes par type :

- **objet** : Single isolated object, centered and fully inside the frame, on a transparent background (or a plain white background to be removed), no cast shadow on the ground (the game draws it), soft light from above.
- **tuile_sol** : Seamless tileable floor texture seen straight from above, filling the whole square edge to edge and repeating without visible seams, flat colors with thin slightly darker joint lines instead of thick outlines, low contrast so that characters stand out, no objects, no shadows, no border.
- **tuile_bord** : Modular edge tile set on a transparent background, seen from above with the slight 3/4 tilt, each piece seamless along its length so that pieces connect end to end, thick dark navy outline only on the outer silhouette.
- **bande_facade** : Horizontally seamless strip (left and right edges match), front face of a wall seen with the slight 3/4 tilt, flat colors, thick dark navy outline on the top and bottom edges only, transparent background.
- **decal** : Flat decal painted on the ground, seen straight from above, transparent background, slightly faded so it reads as paint on the floor, thin outline.

Prompt négatif commun (si l'outil l'accepte) :

```text
pixel art, gradient, photorealistic, 3d render, isometric, strong perspective, texture, noise, grain, blur, text, letters, watermark, logo, people, characters, animals, weapons, blood, dark horror mood
```

Repères de couleur (à donner en mots au générateur, en hexa pour la retouche) : contour `#1d2230`, rouge basque `#9e1b1b`, vert basque `#1f6b3a`, blanc chaux `#f4f1ea`, grès `#d9c39a`, tuile `#c4562f`, mer `#2f7fb8`, accent des cachettes `#e08a2e`.

Tailles : une case fait **64 px en jeu** (`rules.json` → `tile_px`) ; sortie conseillée **128 px par case** (×2). Générer plus grand (côté long ≈ 1024 px) puis réduire. Le débord vers le haut (`debord_haut_cases`) est compté dans la taille.

### Caméra commune (ajoutée le 2026-10-20, demande de Julien)

Pour un angle pseudo 3D identique sur tout le décor, chaque payload se termine par la
même consigne de caméra selon son style (`camera_commune` dans `tools/gordeka/prompts_decor.json`) :

- objets (`pf_hd__prop`) : vue de 3/4 du dessus, de face, environ 40° au-dessus ; on voit le dessus et
  la face avant, face avant parallèle à l'écran, pas de face latérale, orthographique, pas isométrique ;
- sols (`pf_hd__ground`) : vus de la même caméra, à plat, donc droit du dessus, sans perspective ;
- façades (`pf_hd__texture`) : face avant seule, parallèle à l'écran.

Lumière commune : en haut à gauche. Priorité de file : `low` (décor = 2).

Les payloads ne citent aucun jeu existant : chacun se termine par la caméra et la description de notre style (`camera_commune`).

## 2. Liste des éléments

57 éléments. « Vue » = bloque la vue du chasseur ; « Passage » = bloque le passage.

| id | car. | catégorie | cases | sortie (px) | type | vue | passage | cachette | variantes |
|---|---|---|---|---|---|---|---|---|---|
| `sol_dalles_quai` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 3 |
| `sol_carrelage_criee` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 2 |
| `sol_beton_atelier` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 3 |
| `sol_paves_ruelle` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 3 |
| `sol_paves_place` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 2 |
| `sol_planches_terrasse` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 2 |
| `sol_tomettes_chapelle` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 2 |
| `sol_rocher_phare` | `.` | sol | 2×2 | 256×256 | tuile_sol | non | non | non | 2 |
| `eau_mer` | `~` | eau | 2×2 | 256×256 | tuile_sol | non | oui | non | 4 |
| `bord_quai_eau` | `~ / .` | eau | 1×1 | 128×128 | tuile_bord | non | oui | non | 12 |
| `mur_pierre` | `#` | mur | 1×1 | 128×128 | tuile_bord | oui | oui | non | 16 |
| `toit_tuiles` | `#` | mur | 2×2 | 256×256 | tuile_sol | oui | oui | non | 2 |
| `facade_labourdine` | `#` | mur | 4×1 | 512×128 | bande_facade | oui | oui | non | 4 |
| `maison_crampotte` | `#` | batiment | 4×3 (+1 haut) | 512×512 | objet | oui | oui | non | 6 |
| `chambre_froide` | `#` | batiment | 4×4 (+1 haut) | 512×640 | objet | oui | oui | non | 2 |
| `tour_phare` | `#` | repere | 5×5 (+3 haut) | 640×1024 | objet | oui | oui | non | 2 |
| `fronton` | `#` | repere | 10×1 (+2 haut) | 1280×384 | objet | oui | oui | non | 2 |
| `rayonnage_filets` | `#` | batiment | 2×4 (+1 haut) | 256×640 | objet | oui | oui | non | 3 |
| `autel_chapelle` | `#` | repere | 2×2 (+1 haut) | 256×384 | objet | oui | oui | non | 2 |
| `comptoir_bar` | `#` | batiment | 3×2 | 384×256 | objet | oui | oui | non | 2 |
| `mur_soutenement` | `#` | batiment | 2×8 | 256×1024 | objet | oui | oui | non | 1 |
| `caisses_poisson` | `c` | objet | 2×2 (+1 haut) | 256×384 | objet | oui | oui | non | 4 |
| `barque_mouillage` | `B` | bateau | 6×2 | 768×256 | objet | oui | non | non | 6 |
| `chalutier_quai` | `B` | bateau | 7×4 (+1 haut) | 896×640 | objet | oui | oui | non | 2 |
| `coque_sur_ber` | `B` | bateau | 6×3 (+1 haut) | 768×512 | objet | oui | oui | non | 2 |
| `coque_chantier` | `B` | bateau | 5×4 (+1 haut) | 640×640 | objet | oui | oui | non | 1 |
| `etal_criee` | `t` | objet_bas | 5×1 | 640×128 | objet | non | oui | non | 2 |
| `bitte_amarrage` | `t` | objet_bas | 1×1 | 128×128 | objet | non | oui | non | 2 |
| `tas_filets` | `t` | objet_bas | 3×1 | 384×128 | objet | non | oui | non | 2 |
| `fontaine_place` | `t` | repere | 4×4 | 512×512 | objet | non | oui | non | 2 |
| `banc_vert` | `t` | objet_bas | 3×1 | 384×128 | objet | non | oui | non | 1 |
| `banc_chapelle` | `t` | objet_bas | 4×1 | 512×128 | objet | non | oui | non | 1 |
| `etabli_atelier` | `t` | objet_bas | 5×1 | 640×128 | objet | non | oui | non | 2 |
| `marches_escalier` | `t` | objet_bas | 6×1 | 768×128 | objet | non | oui | non | 2 |
| `table_terrasse` | `t` | objet_bas | 2×1 | 256×128 | objet | non | oui | non | 2 |
| `treteaux_cale` | `t` | objet_bas | 3×1 | 384×128 | objet | non | oui | non | 1 |
| `lavoir_bassin` | `~` | repere | 6×3 | 768×384 | objet | non | oui | non | 2 |
| `cachette_casier_homards` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_coffre_quai` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_caisse_glace` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_coffre_cordages` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_poubelle_ruelle` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_bac_poissons` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_malle_pelotes` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_tas_filets_cachette` | `H` | cachette | 1×1 (+1 haut) | 128×256 | objet | oui | oui | oui | 2 |
| `cachette_confessionnal` | `H` | cachette | 1×1 (+1 haut) | 128×256 | objet | oui | oui | oui | 2 |
| `cachette_barque_retournee` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_tonneau_cidre` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_panier_linge` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_caisse_voiles` | `H` | cachette | 1×1 | 128×128 | objet | oui | oui | oui | 2 |
| `cachette_cabine_plage` | `H` | cachette | 1×1 (+1 haut) | 128×256 | objet | oui | oui | oui | 2 |
| `sortie_barque_jetee` | `E` | sortie | 2×3 | 256×384 | objet | non | non | non | 2 |
| `sortie_echelle_phare` | `E` | sortie | 2×3 | 256×384 | objet | non | non | non | 2 |
| `sortie_barque_cale` | `E` | sortie | 2×2 | 256×256 | objet | non | non | non | 2 |
| `sortie_porte_ville` | `E` | sortie | 2×2 (+1 haut) | 256×384 | objet | non | non | non | 2 |
| `depart_lauburu` | `S` | sol | 2×1 | 256×128 | decal | non | non | non | 1 |
| `piege_generique` | `—` | piege | 1×1 | 128×128 | decal | non | non | non | 2 |

Total des images demandées (variantes et états compris) : **150**.

## 3. Questions ouvertes

1. Vue exacte : la face avant des objets fait-elle 0,42 case comme dans le prototype (DEPTH), et les objets hauts (phare, fronton, crampottes, cabine, chalutier) débordent-ils vers le haut de leur emprise comme dans Among Us (ce qui change le tri d'affichage et la forme d'occlusion) ? J'ai proposé un débord par élément (debord_haut_cases).
2. Taille des cases en jeu : rules.json dit tile_px = 64 et les persos font ~90 px de haut (≈ 1,4 case). Je conseille une sortie à 128 px par case (×2 pour iPhone et grands écrans), générée plus grand puis réduite. Faut-il plutôt viser 256 px par case comme les planches de persos ?
3. Grandes masses « # » entre les zones : toits de tuiles rouges vus d'en haut avec une façade au sud (proposé), ou murs sombres façon salles fermées d'Among Us ?
4. Sols : tuiles qui se répètent (proposé, avec 2 ou 3 variantes chacune) ou une grande image peinte par zone (SPEC §16) ? Et faut-il des transitions entre sols de zones voisines ?
5. Bords d'eau et murs en jeux de raccords (autotile) : combien de pièces accepte-t-on (12 pour le quai, 16 pour les murs) ? Un générateur d'images tient mal les raccords exacts : retouche à prévoir.
6. Cachettes et sorties : deux états dessinés (fermé, ouvert) suffisent-ils ? L'accent orange commun aux cachettes est-il souhaité ?
7. Chalutier : sur la carte il est posé sur le quai (cases de sol autour), donc sur un ber ; ou faut-il creuser une darse d'eau autour ?
8. Escalier de la ville : les 3 rangées de marches bloquent le passage (« t ») ; est-ce voulu ou faut-il en faire un sol franchissable avec des jardinières seulement aux extrémités ?
9. Chapelle des marins : autel et confessionnal conviennent-ils, ou préfère-t-on un lieu non religieux (abri du canot de sauvetage) ?
10. Couleurs des bateaux et des portes : variantes d'images (proposé) ou un masque recoloré par le jeu comme la tenue des persos ?
11. Outil : styles pixelforge pf_hd__prop (objets) et pf_hd__texture (sols) à confirmer pour ce rendu flat ; le fond transparent est-il natif ou faut-il détourer un fond blanc ?
12. Ambiance non bloquante (mouettes, linge basque qui sèche, ikurriña, hortensias, flaques) : à ajouter maintenant ou après le premier lot ?

## 4. Fiches par élément

Pour chaque fiche : la description propre à l'élément, puis le ou les payloads pixelforge prêts à déposer (un par taille quand l'élément existe en plusieurs tailles), puis la variante d'état éventuelle. Le prompt complet pour un autre outil (préambule + suffixe + description) est dans le JSON (`prompt`).

### Sols

#### `sol_dalles_quai` — Dalles de quai

- Caractère : `.` · zones : Jetée, Bassin (quai nord), Quai des chalutiers, Lavoir
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 3
- Remarques : Sol le plus étendu : très calme pour que les persos ressortent. 3 variantes de la même tuile pour casser la répétition (le jeu les mélange).

```text
Large rectangular warm sandstone paving slabs of an old harbour quay, staggered rows, beige and light golden tones, a few slabs slightly lighter or darker, rounded corners, tiny pebbles in some joints.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Large rectangular warm sandstone paving slabs of an old harbour quay, staggered rows, beige and light golden tones, a few slabs slightly lighter or darker, rounded corners, tiny pebbles in some joints.", "num_images": 3, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_carrelage_criee` — Carrelage de la criée

- Caractère : `.` · zones : Criée
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Couleur froide pour distinguer la criée d'un coup d'œil. Pas d'écailles ni de sang de poisson.

```text
Clean white and very light blue-grey square ceramic tiles of a fish market hall, checkerboard pattern, a couple of small wet shiny spots.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Clean white and very light blue-grey square ceramic tiles of a fish market hall, checkerboard pattern, a couple of small wet shiny spots.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_beton_atelier` — Béton du hangar, de l'atelier et de la cale

- Caractère : `.` · zones : Hangar à filets, Atelier, Cale sèche
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 3
- Remarques : Une variante plus chaude (cale sèche, au soleil) et une plus froide (hangar, à l'intérieur).

```text
Smooth light grey concrete floor of a boat workshop, large square slabs with straight expansion joints, a few flat pale paint splashes in Basque red and green.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Smooth light grey concrete floor of a boat workshop, large square slabs with straight expansion joints, a few flat pale paint splashes in Basque red #9e1b1b and green.", "num_images": 3, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_paves_ruelle` — Pavés des ruelles

- Caractère : `.` · zones : Crampottes, couloirs (rue des pêcheurs, passages entre zones), Escalier de la ville
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 3
- Remarques : Sert aussi pour tous les couloirs (aujourd'hui sans sol dessiné, zone -1).

```text
Rounded cobblestones of a narrow Basque fishermen's lane, warm grey and beige stones of slightly different sizes in offset rows, soft rounded shapes.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Rounded cobblestones of a narrow Basque fishermen's lane, warm grey and beige stones of slightly different sizes in offset rows, soft rounded shapes.", "num_images": 3, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_paves_place` — Pavage de la place du fronton

- Caractère : `.` · zones : Place du fronton
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Plus clair que les ruelles : la place est le cœur de la carte (départ).

```text
Light golden sandstone pavement of a Basque village square arranged in a fan pattern (calade), pale cream and ochre stones.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Light golden sandstone #d9c39a pavement of a Basque village square arranged in a fan pattern (calade), pale cream and ochre stones.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_planches_terrasse` — Planches de la terrasse

- Caractère : `.` · zones : Terrasse
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Planches horizontales (le dessin du prototype les met à l'horizontale).

```text
Wooden deck boards of a seaside bar terrace, warm honey brown planks running horizontally, staggered board ends, a few darker knots drawn as simple ovals.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Wooden deck boards of a seaside bar terrace, warm honey brown planks running horizontally, staggered board ends, a few darker knots drawn as simple ovals.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_tomettes_chapelle` — Tomettes de la chapelle

- Caractère : `.` · zones : Chapelle des marins
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Aujourd'hui « dalles » par défaut dans gk_map.gd : proposition pour donner un repère de couleur.

```text
Hexagonal terracotta floor tiles (tomettes) of a small Basque sailors' chapel, warm red-orange tones, thin cream joints.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Hexagonal terracotta floor tiles (tomettes) of a small Basque sailors' chapel, warm red-orange tones, thin cream joints.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `sol_rocher_phare` — Plateforme rocheuse du phare

- Caractère : `.` · zones : Phare
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Les flaques restent petites et plates : ce n'est pas de l'eau bloquante.

```text
Flat platform of smoothed golden sandstone rock at the foot of a harbour lighthouse, large irregular rounded plates, a few tiny tide pools drawn as small turquoise ovals.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Flat platform of smoothed golden sandstone #d9c39a rock at the foot of a harbour lighthouse, large irregular rounded plates, a few tiny tide pools drawn as small turquoise #2fa7b8 ovals.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `depart_lauburu` — Marque de départ

- Caractère : `S` · zones : Place du fronton · positions (x,y) : (44,16) 2×1
- Gameplay : vue libre, passage libre, franchissable
- Taille : 2×1 cases → 128×64 px en jeu, sortie 256×128 px
- Type : decal · style suggéré : `pf_hd__prop` · variantes : 1
- Remarques : Optionnel : le départ n'est pas montré aujourd'hui. Le lauburu reste petit et décoratif.

```text
A lauburu (Basque cross with four comma shaped arms) painted in Basque red inside a white circle, flat on the paving.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "A lauburu (Basque cross with four comma shaped arms) painted in Basque red #9e1b1b inside a white circle, flat on the paving.", "theme": "basque", "shadow": "none", "num_images": 2, "width": 1024, "height": 512, "seed": 1}
```

### Eau

#### `eau_mer` — Eau du port et de la mer

- Caractère : `~` · zones : Jetée, Bassin, Cale sèche
- Gameplay : vue libre, passage bloqué (bloque le passage, pas la vue)
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 4
- Remarques : 4 images qui se suivent pour une animation lente des vagues (boucle). Mer bien lisible comme « on ne passe pas », mais pas inquiétante.

```text
Calm harbour sea water, deep turquoise and navy blue, simple flat cartoon wave crests drawn as small white curved lines, a few lighter ripple shapes.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Calm harbour sea water, deep turquoise #2fa7b8 and navy blue, simple flat cartoon wave crests drawn as small white curved lines, a few lighter ripple shapes.", "num_images": 4, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (3×) : « same object, same style, but the wave crests shifted a little to the right (next animation frame) »

#### `bord_quai_eau` — Bord de quai sur l'eau

- Caractère : `~ / .` · zones : Jetée, Bassin, Cale sèche
- Gameplay : vue libre, passage bloqué (purement visuel : la limite reste celle des cases)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : tuile_bord · style suggéré : `pf_hd__prop` · variantes : 12
- Remarques : Jeu de bords (4 droits, 4 coins extérieurs, 4 coins intérieurs) ; seule la face sud montre sa face avant de pierre (3/4). À valider avec la question sur les transitions.

```text
Edge of a sandstone harbour quay meeting the water: a rounded stone coping on the quay side, a short visible front face of stacked golden stone blocks dropping into turquoise water, a thin line of white foam where it touches the water. Provide straight pieces for the north, south, east and west sides plus outer and inner corners.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Edge of a sandstone harbour quay meeting the water: a rounded stone coping on the quay side, a short visible front face of stacked golden stone blocks dropping into turquoise #2fa7b8 water, a thin line of white foam where it touches the water. Provide straight pieces for the north, south, east and west sides plus outer and inner corners.", "shadow": "layer", "num_images": 4, "width": 1024, "height": 1024, "seed": 1}
```

### Murs et toits

#### `mur_pierre` — Mur de pierre (bord de carte, murs entre zones)

- Caractère : `#` · zones : toute la carte
- Gameplay : vue bloquée, passage bloqué
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : tuile_bord · style suggéré : `pf_hd__prop` · variantes : 16
- Remarques : Jeu de murs à raccords (autotile) pour les contours ; la face avant ne se voit que côté sud.

```text
Thick old harbour wall: flat top of dark grey-blue capstones seen from above, and a front face of large golden sandstone blocks with rounded corners. Provide pieces for straight runs, ends, corners and T junctions.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Thick old harbour wall: flat top of dark grey-blue capstones seen from above, and a front face of large golden sandstone #d9c39a blocks with rounded corners. Provide pieces for straight runs, ends, corners and T junctions.", "theme": "basque", "shadow": "layer", "num_images": 4, "width": 1024, "height": 1024, "seed": 1}
```

#### `toit_tuiles` — Toits de tuiles rouges (grandes masses bâties)

- Caractère : `#` · zones : masses entre zones (crampottes, criée, hangar, chapelle…)
- Gameplay : vue bloquée, passage bloqué
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : tuile_sol · style suggéré : `pf_hd__ground` · variantes : 2
- Remarques : Pour remplir les grands blocs « # » entre les zones : on voit des toits au lieu d'un gris. Plus un faîtage (ligne de crête) à prévoir si les toits sont à deux pentes.

```text
Red clay Basque roof tiles (canal tiles) seen from above, rows of rounded orange-red tiles, a few slightly darker or lighter tiles, simple flat shapes.
```

```json
{"prompt_style": "pf_hd__ground", "prompt": "Red clay Basque roof tiles (canal tiles) seen from above, rows of rounded orange-red tiles, a few slightly darker or lighter tiles, simple flat shapes.", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `facade_labourdine` — Façade blanche à colombages

- Caractère : `#` · zones : face sud des masses bâties
- Gameplay : vue bloquée, passage bloqué
- Taille : 4×1 cases → 256×64 px en jeu, sortie 512×128 px
- Type : bande_facade · style suggéré : `pf_hd__texture` · variantes : 4
- Remarques : Bande de 4 cases raccordable à gauche et à droite ; 2 variantes rouges, 1 verte, 1 bleue (pêcheurs). Posée sous le bord sud des toits.

```text
Front face of a Labourd Basque house: whitewashed wall with red half-timbering beams, small windows with Basque red shutters (some dark green), a red wooden door, a flower box with pink hydrangeas.
```

```json
{"prompt_style": "pf_hd__texture", "prompt": "Front face of a Labourd Basque house: whitewashed #f4f1ea wall with red half-timbering beams, small windows with Basque red #9e1b1b shutters (some dark green #1f6b3a), a red wooden door, a flower box with pink hydrangeas.", "num_images": 4, "width": 1024, "height": 256, "seed": 1}
```

### Bâtiments et grands meubles

#### `maison_crampotte` — Crampotte (cabane de pêcheur)

- Caractère : `#` · zones : Crampottes · positions (x,y) : 7 blocs : 4×3 (2,15), 4×3 (8,14), 3×3 (13,16), 3×4 (2,20), 4×3 (7,19), 4×3 (12,21), 4×2 (6,24)
- Gameplay : vue bloquée, passage bloqué
- Taille : 4×3 cases + 1 vers le haut → 256×256 px en jeu, sortie 512×512 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 6
- Remarques : Tailles présentes : 4×3 (×4), 3×3, 3×4, 4×2. Une variante par taille, portes de couleurs différentes : ce sont les repères des ruelles.

```text
Tiny Basque fishermen's hut (crampotte) of the Biarritz port seen from above with the slight 3/4 tilt: red clay tile roof, whitewashed front wall with a brightly painted wooden door (red, green or blue) and one small shuttered window, a coiled rope and an oar leaning against the wall.
```

```json
{"taille_cases": [4, 3], "prompt_style": "pf_hd__prop", "prompt": "Tiny Basque fishermen's hut (crampotte) of the Biarritz port: red clay tile roof, whitewashed #f4f1ea front wall with a brightly painted wooden door (red, green or blue) and one small shuttered window, a coiled rope and an oar leaning against the wall. Footprint 4 by 3 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [3, 3], "prompt_style": "pf_hd__prop", "prompt": "Tiny Basque fishermen's hut (crampotte) of the Biarritz port: red clay tile roof, whitewashed #f4f1ea front wall with a brightly painted wooden door (red, green or blue) and one small shuttered window, a coiled rope and an oar leaning against the wall. Footprint 3 by 3 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 768, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [3, 4], "prompt_style": "pf_hd__prop", "prompt": "Tiny Basque fishermen's hut (crampotte) of the Biarritz port: red clay tile roof, whitewashed #f4f1ea front wall with a brightly painted wooden door (red, green or blue) and one small shuttered window, a coiled rope and an oar leaning against the wall. Footprint 3 by 4 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 640, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [4, 2], "prompt_style": "pf_hd__prop", "prompt": "Tiny Basque fishermen's hut (crampotte) of the Biarritz port: red clay tile roof, whitewashed #f4f1ea front wall with a brightly painted wooden door (red, green or blue) and one small shuttered window, a coiled rope and an oar leaning against the wall. Footprint 4 by 2 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 768, "seed": 1}
```

#### `chambre_froide` — Chambre froide de la criée

- Caractère : `#` · zones : Criée · positions (x,y) : (76,1)
- Gameplay : vue bloquée, passage bloqué
- Taille : 4×4 cases + 1 vers le haut → 256×320 px en jeu, sortie 512×640 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Repère de la criée. Pas de texte (pas de « FRIGO »).

```text
Cold storage room of a fish market: white boxy building with rounded corners, a big light blue insulated door with a silver handle, a painted blue fish shape on the wall, a few frost marks drawn as white snowflake shapes.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Cold storage room of a fish market: white boxy building with rounded corners, a big light blue insulated door with a silver handle, a painted blue fish shape on the wall, a few frost marks drawn as white snowflake shapes.", "shadow": "layer", "num_images": 2, "width": 832, "height": 1024, "seed": 1}
```

#### `rayonnage_filets` — Rayonnage du hangar à filets

- Caractère : `#` · zones : Hangar à filets · positions (x,y) : (60,15) 2×4, (64,17) 2×5, (68,14) 2×4, (68,20) 2×3, (72,16) 2×5
- Gameplay : vue bloquée, passage bloqué
- Taille : 2×4 cases + 1 vers le haut → 128×320 px en jeu, sortie 256×640 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 3
- Remarques : Tailles présentes : 2×4 (×2), 2×5 (×2), 2×3. Une variante par hauteur. Bloque la vue : c'est un dédale.

```text
Tall wooden shelving unit in a net shed seen from above with the slight 3/4 tilt: shelves loaded with rolled green and blue fishing nets, round orange and yellow floats, coiled ropes and small wooden crates.
```

```json
{"taille_cases": [2, 3], "prompt_style": "pf_hd__prop", "prompt": "Tall wooden shelving unit in a net shed: shelves loaded with rolled green and blue fishing nets, round orange and yellow floats, coiled ropes and small wooden crates. Footprint 2 by 3 tiles.", "shadow": "layer", "num_images": 2, "width": 512, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [2, 4], "prompt_style": "pf_hd__prop", "prompt": "Tall wooden shelving unit in a net shed: shelves loaded with rolled green and blue fishing nets, round orange and yellow floats, coiled ropes and small wooden crates. Footprint 2 by 4 tiles.", "shadow": "layer", "num_images": 2, "width": 384, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [2, 5], "prompt_style": "pf_hd__prop", "prompt": "Tall wooden shelving unit in a net shed: shelves loaded with rolled green and blue fishing nets, round orange and yellow floats, coiled ropes and small wooden crates. Footprint 2 by 5 tiles.", "shadow": "layer", "num_images": 2, "width": 320, "height": 1024, "seed": 1}
```

#### `comptoir_bar` — Comptoir de la terrasse

- Caractère : `#` · zones : Terrasse · positions (x,y) : (36,34)
- Gameplay : vue bloquée, passage bloqué
- Taille : 3×2 cases → 192×128 px en jeu, sortie 384×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Boissons sans alcool à l'image (cidre en tonneau seulement comme décor traditionnel).

```text
Wooden bar counter of a seaside Basque terrace, front panel painted Basque red, a top covered with a striped Basque linen cloth, two small cider barrels and a glass jar of lemonade on it.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Wooden bar counter of a seaside Basque terrace, front panel painted Basque red #9e1b1b, a top covered with a striped Basque linen cloth, two small cider barrels and a glass jar of lemonade on it.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 704, "seed": 1}
```

#### `mur_soutenement` — Mur de soutènement de l'escalier

- Caractère : `#` · zones : Escalier de la ville · positions (x,y) : (89,27)
- Gameplay : vue bloquée, passage bloqué
- Taille : 2×8 cases → 128×512 px en jeu, sortie 256×1024 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 1
- Remarques : Vertical (2 de large, 8 de haut).

```text
Long narrow retaining wall of golden sandstone blocks seen from above with the slight 3/4 tilt, a flat stone top with a row of pink and blue hydrangeas and a dark green iron railing.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Long narrow retaining wall of golden sandstone #d9c39a blocks, a flat stone top with a row of pink and blue hydrangeas and a dark green #1f6b3a iron railing.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 256, "height": 1024, "seed": 1}
```

### Repères de zone

#### `tour_phare` — Tour du phare (feu du port)

- Caractère : `#` · zones : Phare · positions (x,y) : (86,3)
- Gameplay : vue bloquée, passage bloqué (on en fait le tour)
- Taille : 5×5 cases + 3 vers le haut → 320×512 px en jeu, sortie 640×1024 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Plus grand repère de la carte : il dépasse vers le haut (environ 3 cases). Une variante feu allumé (phase finale), une éteinte.

```text
Small round harbour lighthouse seen from above with the slight 3/4 tilt: white stone tower with a wide red band at the top, a glass lantern room with a yellow light, a little green door at its base, round stone base. The top of the tower rises above its footprint.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small round harbour lighthouse: white stone tower with a wide red band at the top, a glass lantern room with a yellow light, a little green door at its base, round stone base. The tower is tall.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 640, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the lantern light switched off »

#### `fronton` — Fronton de pelote basque

- Caractère : `#` · zones : Place du fronton · positions (x,y) : (36,14)
- Gameplay : vue bloquée, passage bloqué
- Taille : 10×1 cases + 2 vers le haut → 640×192 px en jeu, sortie 1280×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Long mur au nord de la place ; la face visible est celle qui regarde la place (sud). Dépasse vers le haut (2 cases). Pas de texte « PLAZA ».

```text
Basque pelota wall (fronton) seen from above with the slight 3/4 tilt: tall wall of warm pink sandstone with the typical curved rounded top, a painted horizontal red line near the bottom, a few small green plants at its foot.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Basque pelota wall (fronton): tall wall of warm pink sandstone with the typical curved rounded top, a painted horizontal red line near the bottom, a few small green plants at its foot.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

#### `autel_chapelle` — Autel de la chapelle des marins

- Caractère : `#` · zones : Chapelle des marins · positions (x,y) : (87,20)
- Gameplay : vue bloquée, passage bloqué
- Taille : 2×2 cases + 1 vers le haut → 128×192 px en jeu, sortie 256×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Repère calme et neutre ; le bateau-maquette est le signe distinctif.

```text
Small wooden altar of a Basque sailors' chapel, white cloth with a red and green Basque linen stripe, a little wooden model sailing boat (ex-voto) on top, two short candles, a vase of blue hydrangeas.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small wooden altar of a Basque sailors' chapel, white cloth with a red and green Basque linen stripe, a little wooden model sailing boat (ex-voto) on top, two short candles, a vase of blue hydrangeas.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 704, "height": 1024, "seed": 1}
```

#### `fontaine_place` — Fontaine de la place

- Caractère : `t` · zones : Place du fronton · positions (x,y) : (43,18)
- Gameplay : vue libre, passage bloqué (basse : on voit par-dessus, on en fait le tour)
- Taille : 4×4 cases → 256×256 px en jeu, sortie 512×512 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Repère central, juste à côté du départ. 2 images pour l'eau qui bouge.

```text
Round low stone fountain of a Basque village square seen from above with the slight 3/4 tilt: golden sandstone basin with turquoise water, a small central column with a lauburu (Basque cross) carved on it and a thin water spout.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Round low stone fountain of a Basque village square: golden sandstone #d9c39a basin with turquoise #2fa7b8 water, a small central column with a lauburu (Basque cross) carved on it and a thin water spout.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the water ripples and spout slightly changed (next animation frame) »

#### `lavoir_bassin` — Bassin du lavoir

- Caractère : `~` · zones : Lavoir · positions (x,y) : (45,35)
- Gameplay : vue libre, passage bloqué (eau basse : on voit par-dessus, on en fait le tour)
- Taille : 6×3 cases → 384×192 px en jeu, sortie 768×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Sur la carte c'est de l'eau « ~ » ; dessiné comme un seul objet bas. Pas de toit (sinon il cacherait la vue). 2 images pour l'eau.

```text
Old Basque public washing basin (lavoir) seen from above with the slight 3/4 tilt: rectangular sandstone basin with sloped stone washing edges, clear turquoise water, a wooden washing board and a few floating soap bubbles.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Old Basque public washing basin (lavoir): rectangular sandstone basin with sloped stone washing edges, clear turquoise #2fa7b8 water, a wooden washing board and a few floating soap bubbles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 512, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the water ripples slightly changed (next animation frame) »

### Caisses

#### `caisses_poisson` — Pile de caisses de poisson

- Caractère : `c` · zones : Jetée, Criée, Phare, Quai des chalutiers, Place du fronton, Atelier, Escalier de la ville · positions (x,y) : 2×2 : (5,8), (52,21), (73,36) ; 2×1 : (63,10), (83,8), (20,23), (83,37) ; 1×2 : (30,15)
- Gameplay : vue bloquée, passage bloqué
- Taille : 2×2 cases + 1 vers le haut → 128×192 px en jeu, sortie 256×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 4
- Remarques : Tailles présentes : 2×2, 2×1, 1×2. Une variante par taille + une deuxième 2×2. Les cachent, mais ce ne sont pas des cachettes : bien les distinguer visuellement des « H ».

```text
Stack of wooden fish crates and light blue plastic crates of a fishing port, two levels high, one crate on top slightly askew, a coiled rope beside them.
```

```json
{"taille_cases": [2, 2], "prompt_style": "pf_hd__prop", "prompt": "Stack of wooden fish crates and light blue plastic crates of a fishing port, two levels high, one crate on top slightly askew, a coiled rope beside them. Footprint 2 by 2 tiles.", "shadow": "layer", "num_images": 2, "width": 704, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [2, 1], "prompt_style": "pf_hd__prop", "prompt": "Stack of wooden fish crates and light blue plastic crates of a fishing port, two levels high, one crate on top slightly askew, a coiled rope beside them. Footprint 2 by 1 tiles.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

```json
{"taille_cases": [1, 2], "prompt_style": "pf_hd__prop", "prompt": "Stack of wooden fish crates and light blue plastic crates of a fishing port, two levels high, one crate on top slightly askew, a coiled rope beside them. Footprint 1 by 2 tiles.", "shadow": "layer", "num_images": 2, "width": 320, "height": 1024, "seed": 1}
```

### Bateaux

#### `barque_mouillage` — Barque basque au mouillage

- Caractère : `B` · zones : Bassin · positions (x,y) : (31,2) 6×2, (42,4) 7×2, (51,2) 4×2
- Gameplay : vue bloquée, passage libre (dans l'eau : cache la vue, l'eau empêche déjà d'y aller)
- Taille : 6×2 cases → 384×128 px en jeu, sortie 768×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 6
- Remarques : Tailles présentes : 6×2, 7×2, 4×2. 2 couleurs par taille. Couleurs vives des barques du port des Pêcheurs.

```text
Small traditional Basque wooden fishing boat seen from above with the slight 3/4 tilt, floating on its own, horizontal (bow to the right), brightly painted hull (white with a red, green or blue stripe), warm wooden inside with a bench, two oars and a small coiled net, no water around it.
```

```json
{"taille_cases": [6, 2], "prompt_style": "pf_hd__prop", "prompt": "Small traditional Basque wooden fishing boat, floating on its own, horizontal (bow to the right), brightly painted hull (white with a red, green or blue stripe), warm wooden inside with a bench, two oars and a small coiled net, no water around it. Footprint 6 by 2 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

```json
{"taille_cases": [7, 2], "prompt_style": "pf_hd__prop", "prompt": "Small traditional Basque wooden fishing boat, floating on its own, horizontal (bow to the right), brightly painted hull (white with a red, green or blue stripe), warm wooden inside with a bench, two oars and a small coiled net, no water around it. Footprint 7 by 2 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

```json
{"taille_cases": [4, 2], "prompt_style": "pf_hd__prop", "prompt": "Small traditional Basque wooden fishing boat, floating on its own, horizontal (bow to the right), brightly painted hull (white with a red, green or blue stripe), warm wooden inside with a bench, two oars and a small coiled net, no water around it. Footprint 4 by 2 tiles.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 512, "seed": 1}
```

#### `chalutier_quai` — Chalutier à quai

- Caractère : `B` · zones : Quai des chalutiers · positions (x,y) : (22,17)
- Gameplay : vue bloquée, passage bloqué (on en fait le tour)
- Taille : 7×4 cases + 1 vers le haut → 448×320 px en jeu, sortie 896×640 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Repère de la zone. Sur la carte il est posé sur le quai (pas dans l'eau) : voir questions ouvertes.

```text
Chunky friendly cartoon fishing trawler seen from above with the slight 3/4 tilt, horizontal (bow to the right), red and white hull, a small white wheelhouse with round windows, a short mast with a green flag, piles of nets and orange floats on the deck, sitting on wooden blocks.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Chunky friendly cartoon fishing trawler, horizontal (bow to the right), red and white hull, a small white wheelhouse with round windows, a short mast with a green flag, piles of nets and orange floats on the deck, sitting on wooden blocks.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 704, "seed": 1}
```

#### `coque_sur_ber` — Coque sur ber (cale sèche)

- Caractère : `B` · zones : Cale sèche · positions (x,y) : (3,30), (11,33)
- Gameplay : vue bloquée, passage bloqué
- Taille : 6×3 cases + 1 vers le haut → 384×256 px en jeu, sortie 768×512 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Deux coques, couleurs différentes.

```text
Wooden fishing boat hull out of the water resting on a wooden cradle, seen from above with the slight 3/4 tilt, horizontal, half repainted (one half fresh Basque green, the other faded), a small ladder leaning on the side, paint pots on the ground next to it.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Wooden fishing boat hull out of the water resting on a wooden cradle, horizontal, half repainted (one half fresh Basque green #1f6b3a, the other faded), a small ladder leaning on the side, paint pots on the ground next to it.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 704, "seed": 1}
```

#### `coque_chantier` — Coque en chantier (atelier)

- Caractère : `B` · zones : Atelier · positions (x,y) : (68,30)
- Gameplay : vue bloquée, passage bloqué (on en fait le tour)
- Taille : 5×4 cases + 1 vers le haut → 320×320 px en jeu, sortie 640×640 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 1
- Remarques : Doit rester « plein » (il cache la vue) : coque bordée, pas un squelette de membrures.

```text
Wooden boat being built in a workshop, seen from above with the slight 3/4 tilt: a nearly finished planked hull in natural honey wood with a few planks still missing at the bow, wood clamps, a stack of planks beside it.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Wooden boat being built in a workshop: a nearly finished planked hull in natural honey wood with a few planks still missing at the bow, wood clamps, a stack of planks beside it.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

### Objets bas

#### `etal_criee` — Étal de la criée

- Caractère : `t` · zones : Criée · positions (x,y) : (64,3), (71,3), (64,7), (71,7)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 5×1 cases → 320×64 px en jeu, sortie 640×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 4 étals (deux rangées dont on fait le tour). Poissons mignons, rien de découpé.

```text
Long low fish market stall table seen from above with the slight 3/4 tilt: steel table covered with crushed ice, rows of smiling cartoon fish, a few crabs and shrimps, lemons, a string of red Espelette peppers hanging at one end.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Long low fish market stall table: steel table covered with crushed ice, rows of smiling cartoon fish, a few crabs and shrimps, lemons, a string of red Espelette peppers hanging at one end.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 256, "seed": 1}
```

#### `bitte_amarrage` — Bitte d'amarrage

- Caractère : `t` · zones : Jetée, Bassin (quai nord) · positions (x,y) : (20,7), (38,10), (50,10)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Une variante avec corde, une sans.

```text
Short round cast iron mooring bollard painted dark green with a thick beige rope looped around it.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Short round cast iron mooring bollard painted dark green #1f6b3a with a thick beige rope looped around it.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

#### `tas_filets` — Filets et casiers posés au sol

- Caractère : `t` · zones : Jetée, Hangar à filets · positions (x,y) : (13,9) 3×1, (61,21) 2×1
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 3×1 cases → 192×64 px en jeu, sortie 384×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Tailles présentes : 3×1 (jetée) et 2×1 (filets étendus du hangar).

```text
Low pile of fishing nets spread on the ground with round orange floats and two small lobster pots of wood and rope.
```

```json
{"taille_cases": [3, 1], "prompt_style": "pf_hd__prop", "prompt": "Low pile of fishing nets spread on the ground with round orange floats and two small lobster pots of wood and rope. Footprint 3 by 1 tiles.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

```json
{"taille_cases": [2, 1], "prompt_style": "pf_hd__prop", "prompt": "Low pile of fishing nets spread on the ground with round orange floats and two small lobster pots of wood and rope. Footprint 2 by 1 tiles.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 512, "seed": 1}
```

#### `banc_vert` — Banc vert du front de mer

- Caractère : `t` · zones : Place du fronton · positions (x,y) : (50,16), (37,22)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 3×1 cases → 192×64 px en jeu, sortie 384×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 1
- Remarques : Mobilier vert foncé typique de Biarritz.

```text
Classic dark green wooden and cast iron seaside bench of Biarritz seen from above with the slight 3/4 tilt, horizontal.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Classic dark green #1f6b3a wooden and cast iron seaside bench of Biarritz, horizontal.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

#### `banc_chapelle` — Banc de la chapelle

- Caractère : `t` · zones : Chapelle des marins · positions (x,y) : (83,14), (89,14), (83,16), (89,16), (83,18), (89,18)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 4×1 cases → 256×64 px en jeu, sortie 512×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 1
- Remarques : 6 bancs (3 rangées × 2).

```text
Simple dark wooden chapel bench (pew) seen from above with the slight 3/4 tilt, horizontal, a small red cushion at one end.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Simple dark wooden chapel bench (pew), horizontal, a small red cushion at one end.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 256, "seed": 1}
```

#### `etabli_atelier` — Établi de l'atelier

- Caractère : `t` · zones : Atelier · positions (x,y) : (61,29), (61,33)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 5×1 cases → 320×64 px en jeu, sortie 640×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Outils ronds et inoffensifs (pas de scie ni de lame visible).

```text
Long wooden carpenter's workbench seen from above with the slight 3/4 tilt: a wooden plane, wood shavings curls, a mallet, a coil of rope and small pots of red and green paint.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Long wooden carpenter's workbench: a wooden plane, wood shavings curls, a mallet, a coil of rope and small pots of red and green paint.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 256, "seed": 1}
```

#### `marches_escalier` — Marches de l'escalier de la ville

- Caractère : `t` · zones : Escalier de la ville · positions (x,y) : (81,28), (81,31), (81,34)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 6×1 cases → 384×64 px en jeu, sortie 768×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 3 rangées ; on passe entre elles, pas dessus (bloque le passage). Voir questions ouvertes.

```text
Low block of three wide golden sandstone steps seen from above with the slight 3/4 tilt, horizontal, a terracotta pot of pink hydrangeas at each end.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Low block of three wide golden sandstone #d9c39a steps, horizontal, a terracotta pot of pink hydrangeas at each end.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 256, "seed": 1}
```

#### `table_terrasse` — Table de terrasse

- Caractère : `t` · zones : Terrasse · positions (x,y) : (24,36), (28,36), (32,36)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 2×1 cases → 128×64 px en jeu, sortie 256×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Chaises rouges et nappe en linge basque.

```text
Small round bistro table with a red and white striped Basque linen tablecloth, a slice of gâteau basque on a plate, and two red wooden chairs on each side, seen from above with the slight 3/4 tilt.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small round bistro table with a red and white striped Basque linen tablecloth, a slice of gâteau basque on a plate, and two red wooden chairs on each side.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 512, "seed": 1}
```

#### `treteaux_cale` — Tréteaux et planches de la cale

- Caractère : `t` · zones : Cale sèche · positions (x,y) : (14,29)
- Gameplay : vue libre, passage bloqué (on voit par-dessus, on n'y passe pas)
- Taille : 3×1 cases → 192×64 px en jeu, sortie 384×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 1

```text
Two wooden trestles holding a few long planks and a pair of oars, seen from above with the slight 3/4 tilt, horizontal.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Two wooden trestles holding a few long planks and a pair of oars, horizontal.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 320, "seed": 1}
```

### Cachettes (une par zone)

#### `cachette_casier_homards` — Casier à homards géant

- Caractère : `H` · zones : Jetée · positions (x,y) : (9,10)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Big round wooden and rope lobster pot lying on its side, large enough for a child to curl up inside, a net flap as a door, a couple of orange floats tied to it. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Big round wooden and rope lobster pot lying on its side, large enough for a child to curl up inside, a net flap as a door, a couple of orange floats tied to it. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_coffre_quai` — Coffre de quai

- Caractère : `H` · zones : Bassin · positions (x,y) : (44,9)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Big wooden harbour storage chest painted Basque green with iron bands and a rounded lid, coiled rope on top. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Big wooden harbour storage chest painted Basque green #1f6b3a with iron bands and a rounded lid, coiled rope on top. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_caisse_glace` — Caisse à glace

- Caractère : `H` · zones : Criée · positions (x,y) : (75,2)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Large white insulated ice box of a fish market with a light blue lid and big handles, a few ice cubes around the lid. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Large white insulated ice box of a fish market with a light blue lid and big handles, a few ice cubes around the lid. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_coffre_cordages` — Coffre à cordages du phare

- Caractère : `H` · zones : Phare · positions (x,y) : (92,8)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Sturdy red wooden chest for ropes and lanterns at the foot of a lighthouse, rounded lid, a brass lantern and a coiled rope on top. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Sturdy red wooden chest for ropes and lanterns at the foot of a lighthouse, rounded lid, a brass lantern and a coiled rope on top. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_poubelle_ruelle` — Grande poubelle de ruelle

- Caractère : `H` · zones : Crampottes · positions (x,y) : (11,18)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Big friendly dark green wheeled street bin with a rounded lid, clean, with a seagull feather stuck on the lid. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Big friendly dark green #1f6b3a wheeled street bin with a rounded lid, clean, with a seagull feather stuck on the lid. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_bac_poissons` — Grand bac à poissons

- Caractère : `H` · zones : Quai des chalutiers · positions (x,y) : (19,21)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Large blue plastic fish tub with a lid, the kind used on fishing quays, rounded corners, a small white fish drawn on its side. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Large blue plastic fish tub with a lid, the kind used on fishing quays, rounded corners, a small white fish drawn on its side. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_malle_pelotes` — Malle à pelotes

- Caractère : `H` · zones : Place du fronton · positions (x,y) : (35,24)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Big wicker trunk with a leather strap, lid ajar showing white pelota balls and a curved wicker chistera basket. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Big wicker trunk with a leather strap, lid ajar showing white pelota balls and a curved wicker chistera basket. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_tas_filets_cachette` — Montagne de filets

- Caractère : `H` · zones : Hangar à filets · positions (x,y) : (74,22)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases + 1 vers le haut → 64×128 px en jeu, sortie 128×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent. Dépasse vers le haut (1 case).

```text
Tall soft heap of green and blue fishing nets with orange floats, a child-sized hollow hidden inside. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Tall soft heap of green and blue fishing nets with orange floats, a child-sized hollow hidden inside. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 512, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_confessionnal` — Confessionnal en bois

- Caractère : `H` · zones : Chapelle des marins · positions (x,y) : (93,13)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases + 1 vers le haut → 64×128 px en jeu, sortie 128×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent. Dépasse vers le haut (1 case).

```text
Small wooden booth of an old chapel with a red velvet curtain as a door and a little carved boat on top. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small wooden booth of an old chapel with a red velvet curtain as a door and a little carved boat on top. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 512, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_barque_retournee` — Barque retournée

- Caractère : `H` · zones : Cale sèche · positions (x,y) : (18,37)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Small wooden rowboat turned upside down on two blocks, painted blue with a white stripe, a gap under it to slide inside. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small wooden rowboat turned upside down on two blocks, painted blue with a white stripe, a gap under it to slide inside. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_tonneau_cidre` — Tonneau de cidre géant

- Caractère : `H` · zones : Terrasse · positions (x,y) : (23,38)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Huge wooden Basque cider barrel lying on a cradle with a round lid on its front end, red metal hoops. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Huge wooden Basque cider barrel lying on a cradle with a round lid on its front end, red metal hoops. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_panier_linge` — Grand panier à linge

- Caractère : `H` · zones : Lavoir · positions (x,y) : (54,37)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Big round wicker laundry basket overflowing with red, green and white striped Basque linen. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Big round wicker laundry basket overflowing with red, green and white striped Basque linen. Clearly a hiding spot, with a warm orange #e08a2e accent.", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_caisse_voiles` — Caisse à voiles de l'atelier

- Caractère : `H` · zones : Atelier · positions (x,y) : (60,37)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent.

```text
Large wooden sail chest with rope handles, a folded white sail sticking out from under the lid. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Large wooden sail chest with rope handles, a folded white sail sticking out from under the lid. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

#### `cachette_cabine_plage` — Cabine de plage rayée

- Caractère : `H` · zones : Escalier de la ville · positions (x,y) : (93,26)
- Gameplay : vue bloquée, passage bloqué, cachette (1 joueur, 20 s max ; Entrer/Sortir ; le chasseur fouille 1 s)
- Taille : 1×1 cases + 1 vers le haut → 64×128 px en jeu, sortie 128×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermé et entrouvert (pour l'entrée et la sortie ; le tremblement est fait par le jeu). Les cachettes partagent un accent orange (couleur du prototype #e08a2e) pour que les enfants les repèrent. Dépasse vers le haut (1 case).

```text
Small wooden beach changing cabin of Biarritz with blue and white vertical stripes, a little door and a triangular roof. Make it clearly a hiding spot: slightly bigger than the props around it, a warm orange accent.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Small wooden beach changing cabin of Biarritz with blue and white vertical stripes, a little door and a triangular roof. Clearly a hiding spot, with a warm orange #e08a2e accent.", "theme": "basque", "shadow": "layer", "num_images": 2, "width": 512, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but its lid or door slightly open, a dark gap inside »

### Sorties possibles

#### `sortie_barque_jetee` — Sortie : barque au bout de la jetée

- Caractère : `E` · zones : Jetée · positions (x,y) : (1,2) 2×3
- Gameplay : vue libre, passage libre, franchissable, sortie (2 sorties tirées au sort par round, ouvertes à 90 s ; 4 s sur la case pour sortir)
- Taille : 2×3 cases → 128×192 px en jeu, sortie 256×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : fermée (lanterne éteinte, corde nouée) et ouverte (lanterne allumée, petit fanion vert). Le perso marche dessus : le dessin reste au niveau du sol.

```text
End of a stone jetty with a small iron ladder going down to a little red and white Basque rowboat waiting alongside, a lantern on a post, vertical layout.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "End of a stone jetty with a small iron ladder going down to a little red and white Basque rowboat waiting alongside, a lantern on a post, vertical layout.", "theme": "basque", "shadow": "none", "num_images": 2, "width": 704, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the lantern lit and a small green pennant flying »

#### `sortie_echelle_phare` — Sortie : échelle derrière le phare

- Caractère : `E` · zones : Phare · positions (x,y) : (93,1) 2×3
- Gameplay : vue libre, passage libre, franchissable, sortie (2 sorties tirées au sort par round, ouvertes à 90 s ; 4 s sur la case pour sortir)
- Taille : 2×3 cases → 128×192 px en jeu, sortie 256×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : portillon fermé / ouvert.

```text
Iron ladder going down the rocks behind a lighthouse, with a small green garden gate at the top, vertical layout, sea foam at the bottom edge.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Iron ladder going down the rocks behind a lighthouse, with a small green garden gate at the top, vertical layout, sea foam at the bottom edge.", "theme": "basque", "shadow": "none", "num_images": 2, "width": 704, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the gate wide open »

#### `sortie_barque_cale` — Sortie : barque de la cale

- Caractère : `E` · zones : Cale sèche · positions (x,y) : (1,37) 2×2
- Gameplay : vue libre, passage libre, franchissable, sortie (2 sorties tirées au sort par round, ouvertes à 90 s ; 4 s sur la case pour sortir)
- Taille : 2×2 cases → 128×128 px en jeu, sortie 256×256 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : barque attachée / barque prête (fanion vert).

```text
Concrete boat ramp sloping into the water with a small blue rowboat ready to leave, oars inside.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Concrete boat ramp sloping into the water with a small blue rowboat ready to leave, oars inside.", "theme": "basque", "shadow": "none", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but a small green pennant flying on the boat, rope untied »

#### `sortie_porte_ville` — Sortie : porte de la ville

- Caractère : `E` · zones : Escalier de la ville · positions (x,y) : (92,36) 2×2
- Gameplay : vue libre, passage libre, franchissable, sortie (2 sorties tirées au sort par round, ouvertes à 90 s ; 4 s sur la case pour sortir)
- Taille : 2×2 cases + 1 vers le haut → 128×192 px en jeu, sortie 256×384 px
- Type : objet · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : 2 états : porte fermée / grande ouverte avec de la lumière. Dépasse vers le haut (1 case).

```text
Top of a stone stairway leading up to the town through a small sandstone arch with a Basque red wooden door.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "Top of a stone stairway leading up to the town through a small sandstone arch with a Basque red #9e1b1b wooden door.", "theme": "basque", "shadow": "none", "num_images": 2, "width": 704, "height": 1024, "seed": 1}
```

Variante par `pf_hd__edit` (1×) : « same object, same style, but the door wide open with warm light inside »

### Piège

#### `piege_generique` — Piège générique (flaque collante)

- Caractère : `—` · zones : posé par les chassés, n'importe où
- Gameplay : vue libre, passage libre, franchissable (ralentit le chasseur 3 s ; visible des chassés, du chasseur seulement à moins de 2 cases)
- Taille : 1×1 cases → 64×64 px en jeu, sortie 128×128 px
- Type : decal · style suggéré : `pf_hd__prop` · variantes : 2
- Remarques : Pas sur map.txt (posé en jeu) ; aujourd'hui un cercle jaune de 18 px. Les 12 pièges par perso (§4.2) viendront plus tard. Rigolo, pas dégoûtant.

```text
A funny sticky puddle of golden honey-like goo with a few bubbles and two cartoon sparkles, round and flat on the ground.
```

```json
{"prompt_style": "pf_hd__prop", "prompt": "A funny sticky puddle of golden honey-like goo with a few bubbles and two cartoon sparkles, round and flat on the ground.", "shadow": "none", "num_images": 2, "width": 1024, "height": 1024, "seed": 1}
```
