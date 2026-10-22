# Personnages « façon Party Hard » (Gordeka)

> Proposition du 21/10/2026. Les blocs réutilisables sont dans
> `data/gordeka/style_party_hard.json` (`gabarits.perso`, `gabarits_corps`, `persos`, `pnj_fete`).
> Décision de Julien : **aucune personnalisation** (ni masque de tenue, ni couleur de joueur). Les
> persos sont **de profil, tournés vers la droite** ; la gauche est le miroir.

## 1. Gabarit

| Point | Règle | Mesure Party Hard |
|---|---|---|
| Toile | 48 × 48 px, pieds sur la ligne du tiers bas | — |
| Hauteur | adulte 32 px, costaud 33 px, enfant 28 px, créature 28 px (en largeur jusqu'à 30 px) | 30–32 px |
| Proportions | adulte environ 5 têtes ; enfant environ 4 têtes, tête un peu plus grosse | environ 5 têtes, tête de ~6 px |
| Largeur | torse 6–7 px, 8–9 px avec les bras | idem |
| Membres | bras et jambes de 1 px (2 px pour les costauds), jambes séparées de 1 px | idem |
| Tête | bloc de cheveux simple, visage en quelques pixels de peau, un point sombre pour l'œil | visage de 2–3 px, souvent sans yeux |
| Couleurs | 12 au plus, dont 2–3 grandes masses franches + chaussures vives | 6–10 teintes propres |
| Contour | ton sombre de chaque couleur, pas de trait noir | idem |
| Lisibilité | on reconnaît le perso à sa **silhouette** et à **un détail-signature agrandi** (béret, planche, chistera, pinces) | clichés de PNJ |

## 2. Anatomie de la silhouette à 32 px

En partant du haut :

- **Coiffe ou cheveux** : 4–6 px. Le détail-signature (béret, toque, bonnet) peut dépasser de
  2–3 px.
- **Visage** : 3–4 px, peau, un pixel d'œil.
- **Torse** : 9–10 px. C'est la plus grande masse de couleur ; une bande ou un motif (rayures,
  ceinture rouge) se lit à partir de 2 px.
- **Jambes** : 11–12 px, de la couleur du pantalon ou de la peau.
- **Pieds** : 2 px, de couleur vive (espadrilles rouges, bottes noires, palmes orange).
- **Accessoire porté** (planche, canne à pêche, makila) : il dépasse de la silhouette d'au moins
  4 px, sinon il disparaît.

## 3. Prompt modèle

- **Style** : `pf_pro__character`, ou `pf__character` en repli. Toile 48 × 48 px, `colors` = 12,
  `num_images` = 3, `seed` = 1.
- **Prompt** (style commun ajouté ensuite, voir `01_style_commun.md`) :

```text
Tiny party game character, {gabarit_corps}, strict side view facing right, standing relaxed, {description}. Signature detail drawn large and bright: {signature}. Hair as a simple block, face as a few skin pixels with one dark eye dot, bright shoes. <style_commun.base> <par_type.perso>
```

Valeurs de `{gabarit_corps}` :

| Corps | Texte |
|---|---|
| enfant | `child proportions about four heads tall, 28 pixels tall, one-pixel arms and legs, slightly bigger head` |
| adulte | `slim proportions about five heads tall, 32 pixels tall, one-pixel arms and legs` |
| costaud | `broad sturdy proportions about five heads tall, 33 pixels tall, thick arms two pixels wide` |
| créature | `chunky round mascot proportions, 28 pixels tall, big head and big expressive eyes` |

## 4. Fiches de nos persos

Les descriptions viennent de `tools/gordeka/prompts_anims.json` et, pour Itsasargi, de
`tools/rd/prompts/fighters.yaml`. Elles sont raccourcies pour se lire à 32 px.

| Perso | Corps | `{description}` | `{signature}` |
|---|---|---|---|
| Louis | enfant | a little Basque boy with blond hair, a red beret, a white short-sleeved shirt, a red belt and navy rolled-up trousers | a red Basque beret on blond hair |
| Txomin | enfant | a Basque lifeguard boy with dark brown skin and short black curly hair, black sunglasses, a yellow tank top, red swim shorts, blue swim fins hanging from his belt, barefoot | black sunglasses and blue swim fins hanging at the hip |
| Patxi | adulte | a bearded Basque fisherman with a blue beanie, a yellow raincoat, navy trousers, black boots and a fishing rod strapped diagonally on his back | a fishing rod sticking up diagonally from his back |
| Maïa | enfant | a young Basque surfer girl with a brown ponytail, a turquoise wetsuit with a navy panel, a small yellow surfboard strapped upright on her back, barefoot | a small yellow surfboard upright on her back |
| Xabi | enfant | a little Basque jai alai player with short dark brown hair, a white polo shirt, white trousers, a red sash, red espadrilles and a long curved wicker chistera on his right hand | a long curved wicker chistera on his right hand |
| Mattin | costaud | a strong Basque stone lifter with a black beard, a red beret, a red and white horizontally striped shirt, navy trousers, brown shoes and big muscular arms | red and white horizontal stripes and big arms |
| Amaia | enfant | a Basque folk dancer girl with a red headscarf, a green vest over a white blouse, a red skirt, white espadrilles and a wooden makila stick on her back | a red headscarf and a red skirt |
| Kaio (la mouette) | créature | a cheeky upright seagull with a white head and belly, light grey wings used as arms, a big yellow beak with a red dot, orange webbed feet and a small neckerchief | a big yellow beak and orange webbed feet |
| Karramarro (le crabe) | créature | a cheerful orange cartoon crab with thin legs, two big raised pincers, eyes on stalks, a yellow belly, a big happy open mouth and a small neckerchief | two big raised orange pincers and eyes on stalks |
| Ramuntxo | costaud | a jolly Basque chef with a small brown mustache, a tall white chef hat, a white chef jacket, a red neck scarf, red and white checkered trousers and a black frying pan at his belt | a tall white chef hat |
| Itsaso | enfant | a mythical girl made of sea water with pale cyan skin, long wavy aqua hair and a dress of deep blue waves edged with white foam, barefoot | long flowing aqua hair and a foamy wave hem |
| Peio | costaud | a sturdy young Basque rugby player with medium brown skin and short black hair, a red and white hooped jersey, black shorts, white socks, black boots and an oval rugby ball under his arm | a brown oval rugby ball under his arm |
| Itsasargi (gardien du phare) | adulte | an old lighthouse keeper with a white beard, a captain cap, a navy pea coat and a glowing brass lantern held forward | a glowing yellow lantern held forward |

**Exemple assemblé (Louis)**, prêt à copier. Style `pf_pro__character`, 48 × 48, `colors` 12,
`num_images` 3 :

```text
Tiny party game character, child proportions about four heads tall, 28 pixels tall, one-pixel arms and legs, slightly bigger head, strict side view facing right, standing relaxed, a little Basque boy with blond hair, a red beret, a white short-sleeved shirt, a red belt and navy rolled-up trousers. Signature detail drawn large and bright: a red Basque beret on blond hair. Hair as a simple block, face as a few skin pixels with one dark eye dot, bright shoes. Pixel art game asset with crisp hard square pixels and a small limited palette. Top-down three-quarter cutaway view like a dollhouse with the roof lifted off: the ground seen from above, walls and objects showing their top and their front face, orthographic straight grid, every object square to the viewer. Setting: a summer evening festival in Biarritz in the French Basque Country at dusk, dark muted blue-violet base colors with saturated accents of Basque red, green and white, warm glowing lanterns and string lights. Each shape is edged with a darker shade of its own color, flat shading with one shadow tone and one highlight tone, light from above, cheerful and friendly mood for children. Single full-body character centered on a plain solid white background, feet on the bottom third line, readable silhouette at tiny size.
```

## 5. Lisibilité dans le jeu

- **Deux persos jouables côte à côte ne partagent pas la même masse principale.** Les blancs
  (Louis, Xabi, Ramuntxo) se distinguent par le rouge du béret, de la chistera ou de la toque. On
  vérifie sur une planche des 13 persos à 100 % sur un sol sombre.
- **Le joueur local se repère par le jeu, pas par le sprite** : ellipse pointillée blanche au sol,
  comme dans Party Hard. Le chasseur garde son cône de lampe.
- **Taille dans le décor** : un perso fait 1 case de haut (32 px natifs). Une porte fait 24–32 px,
  une cachette 1 case et un peu plus (voir `05_decor.md`).

## 6. PNJ de fête (foule de décor, sans effet de jeu)

Dans Party Hard, c'est la foule qui fait la « fête ». Chez nous, ce sont des ornements animés
(idle et danse) posés près des scènes, des bars et de la place. Mêmes gabarit et prompt modèle,
`{signature}` = l'élément en gras de la liste :

- a festival-goer dressed all in white with **a red sash and a red neckerchief** ;
- a txistu flute player in white with **a red beret** ;
- a grandmother in a black dress **waving a red fan** ;
- a fisherman in **a striped blue and white sailor shirt** and yellow boots ;
- a surfer with bleached hair **carrying a longboard** ;
- a waiter in a white shirt **with a tray of cider glasses** ;
- a giant-head festival mascot of **a smiling sardine** ;
- a giant-head festival mascot of **a Basque king with a crown** ;
- a kid with **a red balloon** ;
- a bandas trumpet player **in white and red** ;
- an ice cream seller with **a striped apron** ;
- a pelota fan in **a green polo shirt**.

Pour les PNJ, une vue de face à la Party Hard (`seen from the front at a slight high angle` au
lieu de `strict side view facing right`) donne plus de variété à la foule. C'est une option.
