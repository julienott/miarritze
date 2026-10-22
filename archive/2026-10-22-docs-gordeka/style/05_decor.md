# Décor et objets « façon Party Hard » (Gordeka)

> Proposition du 21/10/2026. Les blocs réutilisables sont dans
> `data/gordeka/style_party_hard.json` (`gabarits.prop`, `cachette`, `sol`, `mur`, `anime`,
> `decor_categories`). Les exemples sont repris et adaptés de `tools/gordeka/prompts_decor.json`.
> Échelle : **1 case = 32 px natifs = 1 perso adulte de haut**.

## 1. Catégories et échelle

| Catégorie | Emprise (cases) | Toile pixelforge (px) | `colors` | Style | Repère Party Hard |
|---|---|---|---|---|---|
| Sol | 1 × 1 | 32 × 32 | 8 | `pf_tile__texture` | carrelage sur grille de 8 px, lames de 5 px |
| Mur | 2 × 1 (module) | 64 × 64 | 12 | `pf__topdown_asset` | arête 5–6 px, face 16–27 px |
| Objet bas (bitte, banc, pot) | 1 × 1 | 32 × 32 | 12 | `pf__topdown_asset` | — |
| Mobilier (table, étal, comptoir) | 2 × 1 | 64 × 48 | 16 | `pf__topdown_asset` | canapé 42 × 27, baignoire 47 × 28 |
| **Cachette** | 1 × 1 (dépasse un peu) | 48 × 48 | 20 | `pf__topdown_asset` | WC de chantier 19 × 43, armoire 30 × 45 |
| Bâtiment (crampotte, base du phare) | 3 × 3 | 96 × 128 | 24 | `pf__topdown_asset` | — |
| Bateau | 3 × 2 | 96 × 64 | 16 | `pf__topdown_asset` | cheval 48 × 37 |
| Végétation (arbre, massif) | 2 × 2 | 64 × 80 | 12 | `pf__topdown_asset` | arbres en boule avec ombre en bas à gauche |
| Sortie | 2 × 2 | 64 × 64 | 16 | `pf__topdown_asset` | porte ≈ 1 perso |
| Objet animé | 1 × 1 | 32 × 32 × 4 images | 12 | `pf__topdown_asset`, puis `pf_anim__keyframes` | guirlandes, feu, néons, 4 images à 6 i/s |

Tous les prompts ci-dessous se terminent par le bloc **style commun** et le suffixe du type
(`01_style_commun.md`). On utilise `num_images` = 3 pour les objets et 2 pour les sols et les murs,
avec `seed` = 1.

## 2. Sols

```text
{sol}, dark evening tones. <style_commun.base> <par_type.sol>
```

Exemples pour `{sol}` :
- `warm sandstone quay slabs in staggered rows` (port) ;
- `grey-blue harbour cobblestones` (rues du port) ;
- `weathered teak planks five pixels wide` (pontons, terrasses) ;
- `red and white Basque checkered tiles of a cider house` (terrasse, cuisine) ;
- `pale gravel path` / `short dark green lawn` / `brown bark mulch of a playground` (parc) ;
- `golden sand with faint ripples` / `darker wet sand` / `rough ochre sandstone cave floor` (plage).

## 3. Murs

```text
{mur}, the top strip 6 pixels thick in near black #1b1e1f, the front face 24 pixels tall with {detail_facade}. <style_commun.base> <par_type.mur>
```

Exemples :
- `whitewashed Basque house wall` + `red half-timbering and a small window with red shutters` ;
- `harbour stone wall` + `big sandstone blocks and a mooring ring` ;
- `ochre sandstone cliff edge` + `layered rock strata and tufts of grass`.

## 4. Objets et mobilier

```text
{objet}, {taille_lisible}, seen from above at a three-quarter angle showing the top and the front face, aligned straight to the grid, muted evening colors with one warm light accent. <style_commun.base> <par_type.prop>
```

- `{taille_lisible}` donne la taille par rapport au perso, par exemple
  `about as tall as a child, two tiles wide` ou `knee high, one tile wide`.
- Exemples de `{objet}` :
  - `a mooring bollard with a coiled rope` ;
  - `a green seafront bench` ;
  - `a pot of blue hydrangeas` ;
  - `a café table with two red chairs under a striped parasol` ;
  - `a fish market stall with Bayonne hams and Espelette peppers` ;
  - `a bar counter with cider barrels` ;
  - `a tiny whitewashed fishermen's hut with red shutters and a red tile roof` ;
  - `a blue and white Basque rowboat on the quay` ;
  - `a round plane tree crown seen from above with a soft dark shadow toward the lower left`.

## 5. Cachettes

Dans Party Hard, les cachettes sont du mobilier qu'on reconnaît. On garde la convention de
`prompts_decor.json` : un **détail orange** (#ff8a1c) les signale, et elles sont **un peu plus
grosses** que les objets voisins.

```text
{objet}, a hiding spot big enough for a child to curl up inside, slightly bigger than the props around it, a bright orange #ff8a1c detail as its marker ({repere_orange}), seen from above at a three-quarter angle showing the top and the front face, aligned straight to the grid. <style_commun.base> <par_type.prop>
```

| Carte | `{objet}` | `{repere_orange}` |
|---|---|---|
| Port | a big round wooden and rope lobster pot lying on its side with a net flap as a door | orange floats tied to it |
| Port | a huge Basque cider barrel lying on a cradle with a round lid | an orange tap on the lid |
| Port | a tall soft heap of green and blue fishing nets with a child-sized hollow | orange floats |
| Plage | a small Biarritz beach cabin with blue and white vertical stripes and a triangular roof | a bright orange door |
| Plage | a chunky golden-grey rock with a dark round hollow at its front | an orange starfish stuck on it |
| Parc | a thick hollow tree trunk with a dark round hole at the bottom | an orange mushroom on the side |
| Parc | a short crawl tunnel, a fat plastic tube lying on the ground | the tube itself in orange |

Le jeu ajoute l'état « occupé » (l'objet tremble). Si une cachette doit montrer son état ouvert,
on fait une 2ᵉ image avec `the lid open` ou `the door open`.

## 6. Sorties

```text
{objet}, an exit marker glowing with a soft green lantern light, seen from above at a three-quarter angle showing the top and the front face. <style_commun.base> <par_type.prop>
```

Exemples :
- `a small rowboat waiting at the foot of a slipway` ;
- `a garden gate in a park fence` ;
- `the top landing of stone stairs` ;
- `a lifeguard dinghy at the end of a wooden pontoon`.

## 7. Objets animés (ornements)

D'abord l'image fixe (§4), puis 4 images en boucle à 6 i/s :

```text
{objet}, {mouvement}, 4 frame loop, gentle and readable. <style_commun.base> <par_type.anim>
```

| `{objet}` | `{mouvement}` |
|---|---|
| a string of colored festival lanterns | the bulbs twinkle in turn |
| Basque bunting in red, green and white | flapping in the breeze |
| a seagull standing on a bollard | turning its head and ruffling its wings |
| a neon sign of a cider bar | the letters flicker on and off |
| a chimney with a thin plume of smoke | the smoke curls upward |
| small waves breaking on the quay | white foam rolling in and out |

Dans le jeu, les **lumières** (halos des lampions, cônes de la scène) sont des `PointLight2D` ou
des sprites additifs, pas des pixels peints dans l'objet. Ainsi, le cône du chasseur et
l'assombrissement les gèrent correctement.
