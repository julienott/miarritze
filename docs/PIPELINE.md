# Pipeline de création : persos, mouvements, spéciaux, décors

But : tout décider **avant** de dépenser, générer par lots avec rejet
automatique, et ne demander à Julien que trois validations par perso.

## Combattant

| Étape | Outil | Coût | Validation Julien |
|---|---|---|---|
| 1. Fiche de conception | `tools/specs/fighters/<id>.yaml` (modèle : `kaio.yaml`) | 0 $ | lit la fiche |
| 2. Planche de poses clés | `.venv/bin/python tools/specs/keyposes.py <id>` | 0 $ | **① valide les intentions** |
| 3. Contrôle de la fiche | `.venv/bin/python tools/specs/spec.py check <id>` | 0 $ | — |
| 4. Explorations + pose de garde | `gen_fighter.py explore <id>` puis `neutral` / `prep_neutral` | ≈ 0,30 $ | **② choisit la proposition et la garde** |
| 5. Animations par lots | `gen_anims.py <id> --essais 2 --budget 12` | ≈ 7–8 $ | — |
| 6. Assemblage | `tools/sprites/build_rd_anims.py <id>` puis `build_fighter.py <id>` | 0 $ | — |
| 7. Recette | `tools/sprites/qa_fighter.py <id>` + captures en jeu | 0 $ | **③ valide en jeu (/producer)** |
| 8. Effets des spéciaux | `tools/rd/gen_vfx.py`, `tools/sprites/prep_vfx.py` | ≈ 1 $ | dans ③ |

### La fiche (tools/specs/fighters/<id>.yaml)

- `apparence` : la description envoyée à Retro Diffusion (anglais).
- `porte` : ce que le perso tient, et quand (sinon l'accessoire pollue tous les coups).
- `hauteur` : 112 px en garde (taille commune ; boss × 1,15 via `BOSS_SCALE`).
- `groupes_couleur` : zones recolorées par les costumes, par teinte /
  saturation / valeur ; `composante_min` réserve un groupe aux grandes zones
  d'un seul tenant (le béret, pas la bouche qui a les mêmes rouges).
- `mouvements` : pour chacun, `intention` (français, pour Julien), `mode`
  (attente, marche, attaque, saut, accroupi, action), `images`, `geste`
  (consigne anglaise), `depart` (`neutre` ou `<mouvement>:au_plus_bas|en_l_air`).
- `reprises` : animations du jeu prises dans un autre mouvement (tenue,
  à l'envers, chute puis sol, plage d'images). RD anime mal un perso en
  l'air : coups sautés et coup reçu en l'air viennent d'images au sol.
- `speciaux` : nom, intention, effet visuel, projectile, son.

### Rejet automatique pendant la génération

Chaque animation passe tout de suite trois contrôles (`gen_anims.raw_checks`) :
immobile (moins de 12 % de la silhouette change), halo ou effet parasite
(surface × 1,45), coup invisible (le membre dépasse de moins de 8 px). Ratée,
elle est relancée avec une autre graine, au plus `--essais` fois, sans dépasser
`--budget` pour le lancement. Journal : `tools/rd/out/<id>/gen_log.jsonl`.

### Variante gratuite : pixelforge (Wan 2.2 local)

`tools/pf/gen_anims_pf.py <id> [anim …] [--essais 4] [--refaire]` lit la même
fiche, part de `tools/rd/out/<id>/neutral_160.png` (perso tourné à droite) et
écrit au même endroit que `gen_anims.py` (`anims.json`, `gen_log.jsonl`) :
l'assemblage et la recette ne changent pas. Toujours l'action « custom »
(« attack » invente des armes, « walking » reste immobile). En plus des
contrôles RD, deux rejets propres à Wan : le perso change en cours d'animation
(couleur moyenne), une image saute (silhouette), et un objet inventé apparaît
(pixels gris, blancs ou bleus). La fin figée est coupée. Planche :
`tests/out/pf/<id>.png` ; les mouvements jamais réussis y sont « À REVOIR ».

### Méthode retenue : animation par morceaux + guidé (pixelforge)

Wan seul rate les non-humains ; la méthode validée le 2026-10-17 :

1. `tools/pf/choreo/<id>.py` découpe la garde en pièces (masques, pivots,
   ordre de dessin, bras qui relient une pince écartée) et décrit chaque
   mouvement en poses clés (rotation, décalage, échelle par pièce).
   `pieces.py <id> --controle` en tire la planche `tests/out/pf/<id>_pieces.png`.
2. `pieces.py <id> [anim …] [--graine D] [--refaire]` envoie les silhouettes à
   `pf_anim__guided`, qui redessine le perso en suivant exactement le geste.
   Rejets automatiques (relance avec une autre graine) : identité qui dérive,
   silhouette qui ne suit pas le contrôle, morceaux détachés, objet étranger,
   images manquantes (les mouvements de plus de 8 images partent par morceaux).
   Après les essais, ou pour les mouvements `mode="pieces"` (grosses
   rotations : le guidé perd le visage d'un perso retourné), on garde le
   rendu des pièces. Toujours relire la planche : un rendu « OK » peut garder
   un fantôme (voir `--graine`).
3. Assemblage et recette inchangés (`build_rd_anims.py`, `build_fighter.py`,
   `qa_fighter.py`). Les costumes viennent de la fiche quand ses groupes de
   couleur sont ceux de la palette.

Redessiner une feuille existante (`tools/pf/redraw.py`) n'améliore pas les
persos RD déjà propres (essai Louis : espadrilles devenues marron) : non retenu.

### Portrait, fin et effets (pixelforge)

`tools/pf/extras_pf.py portrait|fin|effets <id>` écrit des candidats et une
planche de choix `tests/out/pf/<id>_<commande>.png` ; puis
`extras_pf.py installer <id> fin=102 proj_x=101 sp_forward=trail:elem_a.101
sp_down=arc:elem_a.101+elem_b.102 super=ring:elem_a.101+elem_b.102`.
Le générateur réussit les petits objets isolés (32 px) mais rate traînées,
cercles et formats étroits : ces effets sont assemblés à partir de deux
éléments (traînée, arc au sol, couronne). Les projectiles de moins de 24 px
sont générés ×2 puis réduits. Le portrait passe par `make_rd_portraits.py`
(FACES : source, yeux et bouche du K.O., `diag` si le perso touche la
diagonale du fond, `fills` pour un trou de fond enfermé).

### Recette après assemblage

`qa_fighter.py` vérifie image par image : trous, morceaux détachés, bord de
case, sauts de taille, surface qui chute, taches crème sur la peau, coup
invisible à l'image d'impact, mouvement immobile, halo, hauteur commune ; et
produit les planches (fond de ciel clair) et le zoom des visages, à regarder.

## Décor

| Étape | Outil | Validation Julien |
|---|---|---|
| 1. Fiche | `tools/specs/stages/<id>.yaml` (modèle `_modele.yaml`) | lit la fiche |
| 2. Génération | `tools/stages/gen_new.py` / `build_stage.py` | choisit la proposition |
| 3. Recette des marges | `tools/stages/qa_stage.sh <id>` (5 formats, perso aux deux murs) | regarde les planches |
| 4. Musique | air traditionnel vérifié (`docs/MUSIC.md`), `tools/gen_audio.py` | écoute dans /producer |

## Suivi

Une carte /producer par étape de validation (`tools/producer/cli.py add-card`),
déplacée en « À vérifier » quand la planche est prête.
