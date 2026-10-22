# Style commun « façon Party Hard » (Gordeka)

> Proposition du 21/10/2026, à valider par Julien. L'analyse et les mesures sont dans
> `docs/STYLE_PARTY_HARD.md`. Les blocs de prompts que les scripts assemblent sont dans
> `data/gordeka/style_party_hard.json`.
> Règles d'écriture des prompts :
> - en anglais, sans négation (les modèles ajoutent ce qu'on nomme) ;
> - sans nom de jeu existant ;
> - assemblés ainsi : gabarit rempli + `style_commun.base` + `style_commun.par_type[type]`.

## 1. Les règles du style

| Point | Règle | Pourquoi (mesuré sur Party Hard) |
|---|---|---|
| Résolution | Monde dessiné en **640×360** natif, affiché ×2 dans le projet 1280×720, filtre nearest | PH1 est en 640×360, ×3 en 1080p |
| Échelle | **1 case = 32 px natifs** (= `tile_px` 64 en jeu) = 1 perso adulte de haut | perso PH1 de 30–32 px ; porte ≈ 1 perso |
| Perspective | Vue de dessus oblique « maison de poupée » : sol vu d'en haut, murs du fond et objets montrent dessus + face, grille orthogonale, sans point de fuite ni isométrie | PH1 |
| Toits | Retirés en permanence ; les façades sud se dessinent sous le sol | PH1 (maison, dortoir, station) |
| Murs | Arête quasi noire de **6 px** (#1b1e1f) ; face du mur du fond de **20–26 px** | 5–6 px et 16–27 px |
| Contour | Pas de trait noir autour des persos et des objets ; chaque forme est bordée d'un **ton plus sombre de sa propre couleur** | persos et objets de PH1 |
| Ombrage | Aplat + 1 ton d'ombre + 1 ton de lumière, lumière du haut | PH1 |
| Palette | Grandes surfaces sombres et peu contrastées ; couleurs franches réservées aux persos, aux lumières et aux cachettes | luminance médiane 40–50 sur 255 |
| Ambiance | **Soir de fête à Biarritz** (heure bleue, crépuscule) : lampions, guirlandes, néons de bar, fenêtres chaudes | toujours la nuit dans PH1 |
| Lumière | Halos additifs ronds et doux (jaunes autour des lampes, colorés autour des enseignes), cônes de projecteur sur la scène ; vignette sombre aux bords | PH1 |
| Ombres | Ombre portée sombre et diffuse seulement sous les gros volumes (arbres, maisons, bateaux), vers le bas à gauche ; les persos n'en ont pas, le jeu ajoute leur marqueur | comm_60 |
| Couleurs par asset | perso 12, objet 16–24, tuile 8, mur 12, maquette de zone 40 | perso PH1 : 6–10 teintes propres |
| Marqueurs | Joueur local : **ellipse pointillée blanche** au sol (dessinée par le jeu) ; cachette : **détail orange #ff8a1c** | PH1 ; convention de `prompts_decor.json` |

## 2. Bloc « style commun » à coller

À coller après chaque prompt de pixelforge (styles `pf_pro__character`, `pf__character`,
`pf__topdown_asset`, `pf_tile__texture`, `pf__topdown_map`, `pf_anim__*`) :

```text
Pixel art game asset with crisp hard square pixels and a small limited palette. Top-down three-quarter cutaway view like a dollhouse with the roof lifted off: the ground seen from above, walls and objects showing their top and their front face, orthographic straight grid, every object square to the viewer. Setting: a summer evening festival in Biarritz in the French Basque Country at dusk, dark muted blue-violet base colors with saturated accents of Basque red, green and white, warm glowing lanterns and string lights. Each shape is edged with a darker shade of its own color, flat shading with one shadow tone and one highlight tone, light from above, cheerful and friendly mood for children.
```

Suffixe selon le type d'asset (à ajouter après le bloc) :

| Type | Suffixe |
|---|---|
| perso | `Single full-body character centered on a plain solid white background, feet on the bottom third line, readable silhouette at tiny size.` |
| anim | `Same character, same colors and same proportions in every frame, feet on the same ground line, evenly spaced frames on a plain solid white background.` |
| prop | `Single isolated object centered on a plain solid white background, the whole object inside the frame.` |
| sol | `Seamless tileable floor texture seen straight from above, filling the whole square edge to edge, low contrast, subtle pattern on an 8 pixel grid.` |
| mur | `Modular wall piece on a plain solid white background: a dark wall top strip seen from above and the wall front face below it.` |
| carte | `Whole area visible at once, seen from above with the roof lifted off, rooms outlined by thick dark wall tops, each room with its own floor pattern, dense furniture along the walls, open walkways two tiles wide.` |

## 3. Palette de référence

| Rôle | Teintes |
|---|---|
| Fond de nuit, arêtes de murs | #141718 #1b1e1f #252831 #2c3245 #2b2541 |
| Sols chauds (pierre, bois) | #2a2d29 #4c322a #5f4840 #a09a86 |
| Mer au crépuscule | #082235 #113145 #375e6d #83a1a8 |
| Végétation du soir | #181c12 #223217 #2b3e1e #385146 |
| Lumières | #ffd25a (lampion) #ff9a3c (fenêtre) #ff4fa3 #3fe0ff #a020f0 (néons, bulles) |
| Basque | #c8102e (rouge) #00843d (vert) #f4efe6 (blanc chaulé) #1d2230 (marine) |
| Cachette | #ff8a1c |

## 4. Après génération

Contrôle systématique (CLAUDE.md, règle 6) : planche contact ×4 en nearest.

1. Réduire au gabarit si pixelforge rend plus grand.
2. Quantifier à `colors` sans tramage.
3. Vérifier la silhouette à 100 % sur fond sombre.
4. Vérifier qu'aucune forme ne garde de trait noir.
