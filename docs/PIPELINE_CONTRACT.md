# Contrat pipeline sprites ↔ jeu

Ce document fige le format des fichiers produits par `tools/` et lus par le jeu.

## 1. Indices de palette (32 entrées, communs à tout le roster)

| Index | Rôle | Rampe |
|---|---|---|
| 0 | transparent | — |
| 1 | `outline` (58,38,52) | — |
| 2 | blanc des yeux / reflets | — |
| 3–6 | `skin` | clair → ombre (4) |
| 7–9 | `hair` | 3 |
| 10–13 | `outfit_a` (vêtement principal) | 4 |
| 14–17 | `outfit_b` (vêtement secondaire) | 4 |
| 18–21 | `hat` (couvre-chef / accessoire principal) | 4 |
| 22–25 | `acc_b` (accessoire 2 : planche, chistera, pierre…) | 4 |
| 26–28 | `acc_c` (chaussures, ceinture…) | 3 |
| 29–31 | `extra` | 3 |

`palette_roles` dans `data.json` reprend ce tableau. Les costumes 2–4 ne modifient **jamais** `skin` ni `outline`.

## 2. Fichiers par combattant : `assets/fighters/<id>/`

- `sheet.png` : PNG **niveaux de gris 8 bits** (mode `L`), la valeur du pixel = index de palette (0 = transparent). Cellules **128×128** rangées à la suite dans une grille de `cols` colonnes (16 → 2048 px de large ; hauteur ≤ 4096 pour WebGL2). La frame `i` d'une animation est la cellule `first + i` (ligne `k // cols`, colonne `k % cols`). Pied du personnage au point **(64, 120)** de la cellule, regard vers la **droite**. (Boss : cellules 160×160, pied en (80, 152).)
- `palettes.png` : RGBA **32×4**, une rangée par costume, une colonne par index.
- `anims.json` (produit par le pipeline) :
```json
{
  "cell": 128, "cols": 16, "foot": [64, 120],
  "anims": {
    "idle": {"row": 1, "first": 8, "frames": 8, "fps": 10, "loop": true},
    "punch_1": {"row": 9, "frames": 4, "fps": 20, "loop": false, "hit_frame": 2}
  },
  "boxes": {
    "hurt": {"idle": [[[-14,-96,28,24],[-16,-72,32,38],[-14,-34,28,34]], ...par frame]},
    "hit":  {"punch_1": [18, -66, 22, 12]}
  }
}
```
  Boîtes en px, `[x, y, w, h]`, relatives au pied, x vers l'avant (droite), y vers le haut négatif. `hurt` : 3 boîtes (tête, torse, jambes) par frame. `hit` : une boîte pour la frame `hit_frame` de chaque animation d'attaque.
- `data.json` : fiche de jeu complète (SPEC §8.5), produite par `tools/sprites/build_fighter.py` en fusionnant `tools/fighters/<id>.json` (moveset écrit à la main) et `anims.json`.

## 3. Liste des animations (ordre dans la feuille)

`intro, idle, walk, run, crouch, crouch_idle, jump_up, jump_fwd, fall, block, crouch_block, punch_1, punch_2, punch_3, kick, kick_high, crouch_punch, sweep, uppercut, jump_punch, jump_kick, throw, thrown, hit_high, hit_low, hit_air, knockdown, getup, dizzy, ko, win, sp_neutral, sp_forward, sp_down, sp_up, super, finisher`

Animations d'attaque (avec `hit_frame`) : `punch_1/2/3, kick, kick_high, crouch_punch, sweep, uppercut, jump_punch, jump_kick, throw, sp_*`, `super`.
Animations « en l'air » (pas de recalage au sol) : `jump_up, jump_fwd, fall, jump_punch, jump_kick, hit_air, thrown`.
