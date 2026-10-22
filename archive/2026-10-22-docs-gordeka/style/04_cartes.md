# Cartes « façon Party Hard » (Gordeka)

> Proposition du 21/10/2026. Les blocs réutilisables sont dans
> `data/gordeka/style_party_hard.json` (`echelle`, `gabarits.carte_zone`, `cartes`). Les plans
> viennent de `assets/maps/<id>/zones.json` et de SPEC-GORDEKA §8.

## 1. Structure et lecture d'un niveau (Party Hard)

- **Un aimant central** (piste, scène, piscine) concentre la foule. Autour, 6 à 12 pièces ou îlots
  meublés. Une rue ou de l'eau borde un côté, avec 2–3 sorties en bord de carte.
- **On lit le plan en une seconde** :
  - arêtes de murs noires et épaisses ;
  - un motif de sol par pièce ;
  - mobilier reconnaissable ;
  - aucune mini-carte.
- **Les cachettes sont du mobilier** (armoire, WC, cabine, coffre), pas des icônes.
- **Caméra fixe** dans PH1 : le niveau tient en un écran (640×360). Les bandes-annonces zooment
  (×4,7 à ×5), ce qui montre que le moteur sait cadrer plus serré.

## 2. Transposition à Gordeka

| Point | Party Hard | Gordeka |
|---|---|---|
| Taille | 1 écran (20 × 11 cases de 32 px) | **96 × 40–42 cases** = 3072 × 1280 px natifs ≈ 4,8 × 3,6 écrans |
| Caméra | fixe | **suit le joueur**, 20 × 11 cases visibles (640×360 natif ×2) ; zoom arrière possible en fin de round |
| Zones | 6–12 pièces | 14–16 zones reliées par des couloirs en baïonnette (§8.1 à §8.3) |
| Toits | retirés | retirés pour les intérieurs (criée, chapelle, cuisines) ; les petites maisons gardent un toit qui masque (règle des masques) |
| Lumière | nuit et néons | soir de fête : lampions, guirlandes, fenêtres ; le cône du chasseur assombrit le reste |

**Échelle** :
- 1 case = 32 px natifs = 64 px en jeu = 1 perso adulte de haut ;
- une zone typique fait 12 × 7 cases, soit **384 × 216 px natifs**, exactement la taille maximale
  de `pf__topdown_map` : une zone = une maquette.

## 3. Prompt modèle d'une zone (maquette d'ambiance)

- **Style** : `pf__topdown_map`, 384 × 216, `colors` = 40, `num_images` = 3, `seed` = 1.
- **Usage** : la maquette sert de référence de couleurs, de densité et de lumière. La carte
  jouable reste assemblée par le code (`map.txt`) à partir des sols, murs et objets de
  `05_decor.md`.

```text
Top-down cutaway map of {zone} in {carte} at a summer evening festival, {contenu}, {lumieres}, a few small festival-goers for scale. <style_commun.base> <par_type.carte>
```

## 4. Nos trois cartes

### 4.1 Port des Pêcheurs (`port_pecheurs`, 96 × 40, 14 zones)

- `{carte}` = `the old fishermen's port of Biarritz`.
- `{lumieres}` = `lantern strings across the streets, warm windows, a lighthouse beam, reflections on the dark harbour water`.
- **Sols** :
  - dalles de grès (quais) ;
  - pavés bleu-gris (rues) ;
  - planches de teck (pontons) ;
  - damier rouge et blanc (cidrerie, terrasse).
- **Aimant** : la place du fronton (bandas, fanions).
- **Sorties** : bout de la jetée, barque au pied de la cale, escalier de la ville, phare.

| Zone | `{contenu}` |
|---|---|
| Jetée | a stone jetty with bollards, coiled ropes and an exit at the far end |
| Bassin | the harbour basin with moored blue and red Basque boats |
| Criée | the fish market hall with stalls, ice boxes and cider barrels |
| Phare | the foot of a small white and red lighthouse with rope chests |
| Crampottes | a row of tiny whitewashed fishermen's huts with red and green shutters |
| Quai des chalutiers | a quay with a big trawler, fish crates and nets |
| Place du fronton | a festival square with a pelota wall, plane trees, a bandstand and Basque bunting |
| Hangar à filets | a net shed with heaps of green nets and orange floats |
| Chapelle des marins | a small sailors' chapel with pews, candles and a model boat |
| Cale sèche | a slipway with boats on blocks, a wood pile and a rowboat at the bottom |
| Terrasse | a café terrace with red chairs, small tables and string lights |
| Lavoir | a stone washhouse with a basin and Basque linen drying on lines |
| Atelier | a boat workshop with sails, tools and paint pots |
| Escalier de la ville | stone steps climbing to the town with hydrangea pots |

**Exemple assemblé** (place du fronton), prêt à copier. Style `pf__topdown_map`, 384 × 216,
`colors` 40, `num_images` 3 :

```text
Top-down cutaway map of a festival square with a pelota wall, plane trees, a bandstand and Basque bunting in the old fishermen's port of Biarritz at a summer evening festival, lantern strings across the streets, warm windows, a lighthouse beam, reflections on the dark harbour water, a few small festival-goers for scale. Pixel art game asset with crisp hard square pixels and a small limited palette. Top-down three-quarter cutaway view like a dollhouse with the roof lifted off: the ground seen from above, walls and objects showing their top and their front face, orthographic straight grid, every object square to the viewer. Setting: a summer evening festival in Biarritz in the French Basque Country at dusk, dark muted blue-violet base colors with saturated accents of Basque red, green and white, warm glowing lanterns and string lights. Each shape is edged with a darker shade of its own color, flat shading with one shadow tone and one highlight tone, light from above, cheerful and friendly mood for children. Whole area visible at once, seen from above with the roof lifted off, rooms outlined by thick dark wall tops, each room with its own floor pattern, dense furniture along the walls, open walkways two tiles wide.
```

### 4.2 Parc Mazon (`parc_mazon`, 96 × 42, 15 zones)

- `{carte}` = `Mazon park, a leafy children's park in Biarritz`.
- `{lumieres}` = `paper lanterns in the trees, a lit bandstand, glowing park lamps`.
- **Sols** : gravier clair (allées), pelouse sombre, copeaux d'aire de jeux, terre rouge du
  fronton.
- **Ici, les massifs d'arbres jouent le rôle des murs** : la couronne se voit d'en haut, avec une
  ombre douce vers le bas à gauche.
- **Aimant** : le terrain du fronton.

| Zone | `{contenu}` |
|---|---|
| Entrée du gardien | the keeper's cottage at the park gate |
| Labyrinthe de haies | a maze of trimmed hedges |
| Aire des grands | a playground with a play castle and a big slide |
| Mare aux canards | a duck pond with reeds and a little wooden bridge |
| Potager du jardinier | a vegetable garden with a glass greenhouse and a compost bin |
| Allée du fronton | a narrow walkway behind the pelota wall |
| Bosquet | a grove of thick trees and hollow bushes |
| Kiosque à musique | a round green bandstand with a lattice base |
| Terrain du fronton | a wide open pelota court in front of a tall pelota wall with a Basque flag |
| Grande pelouse | a big lawn with picnic blankets |
| Aire des petits | a toddler playground with a sandbox, a merry-go-round and a playhouse |
| Fontaine | a stone fountain with benches |
| Buvette | a snack kiosk with a giant ice cream cone sign |
| Jardin des cabanes | children's huts made of branches |
| Allée des platanes | an alley of tall plane trees |

### 4.3 Plage de la Côte des Basques (`plage`, 96 × 40, 16 zones)

- `{carte}` = `the Côte des Basques beach in Biarritz under an ochre sandstone cliff`.
- `{lumieres}` = `a pink and orange sunset over the ocean, lantern strings on the restaurant terraces, glowing cave lamps`.
- **Sols** : sable doré, sable mouillé plus sombre, planches de terrasse, grès ocre des grottes.
- **Ici, la falaise joue le rôle des murs** : son arête est vue d'en haut, sa face ocre en dessous.
- **La mer occupe le bord bas**, comme la mer sur la plage de Miami (en haut chez eux).
- **Aimant** : la grande plage.

| Zone | `{contenu}` |
|---|---|
| Escalier de la falaise | zigzag stairs carved in the cliff between grassy rocky banks |
| Grotte des contrebandiers | a smugglers' cave with old chests and a lamp |
| Grotte aux sirènes | a cave with tide pools and shells |
| Grotte de la marée | a damp cave with dripping water and seaweed |
| Rampe du Port-Vieux | a sloping stone ramp up to the old port |
| Cuisine de l'Itsasoa | a red restaurant kitchen dug into the rock with a stove and a big fridge |
| Cuisine du Txiringito | a green beach bar kitchen dug into the rock |
| Cabines rayées | staggered rows of blue and white striped beach cabins |
| Restaurant Itsasoa | a red restaurant terrace with tables and parasols |
| Poste de secours | a lifeguard tower on stilts with flags |
| Restaurant Txiringito | a green beach bar terrace with planters |
| Port-Vieux | a small cove with white cabins, rocks, a bench and a shower |
| Rochers du Basta | a jumble of rocks with tide pools |
| Grande plage | an open beach with an ice cream kiosk, a sandcastle, windbreaks, surfboard racks, parasols and deckchairs |
| Bateaux au sec | small boats pulled up on the sand |
| Digue | a stone breakwater reaching into the waves |

## 5. Règles de mise en page reprises de Party Hard

- **Un motif de sol par zone**, à faible contraste (±15 de luminance).
- **Les arêtes de murs** (6 px quasi noirs) cernent chaque pièce fermée. En extérieur, ce sont
  les massifs, les haies, la falaise ou les quais qui tiennent ce rôle.
- **Mobilier le long des murs, centre dégagé**, et toujours au moins 2 cases de passage.
- **Sources de lumière comme repères** : chaque zone a au moins une lumière chaude (lampion,
  fenêtre, enseigne) qui l'identifie de loin.
- **Les sorties se repèrent par une lumière verte** (lanterne au bout de la jetée, au portillon) ;
  les cachettes, par un détail orange.
