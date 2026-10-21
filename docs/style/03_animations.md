# Animations « façon Party Hard » (Gordeka)

> Décision de Julien du 21/10/2026 : **on fait simple**. Chaque perso a 5 éléments, sans
> personnalisation. Les blocs réutilisables sont dans `data/gordeka/style_party_hard.json` →
> `animations`. Ils remplacent, pour ce style, la liste longue de `tools/gordeka/prompts_anims.json`
> (fouiller, détecter, piège, emotes…).

## 1. Ce que montrent les vidéos de Party Hard

Les mesures sont tirées de deux vidéos de la fiche Steam (détail dans `docs/STYLE_PARTY_HARD.md`
§10) :
- un let's play en 720p30, à ×2 exact du natif, caméra fixe ;
- la bande-annonce de lancement en 1080p60, zoomée.

| Mesure | Valeur |
|---|---|
| Cadence des poses | **10 i/s** : chaque pose est tenue environ 3 images à 30 i/s, 6 images à 60 i/s |
| Marche | **4 poses par cycle** (enjambée, pose de passage, autre enjambée, pose de passage), soit 0,4 s ; bras écartés de 1 px ; **rebond de 1 px** |
| Vitesse de marche | environ 27 px natifs par seconde (moins d'un perso par seconde) |
| Danse d'un PNJ | 5 poses en boucle à 10 i/s (coup de pied, accroupi, pas, debout) |
| DJ | 3 poses en boucle (≈ 0,3 s) |
| Directions | profil gauche-droite (miroir) et vue de face ; un PNJ qui descend en diagonale garde son sprite de face |
| Effets | la bulle « ! » apparaît en grossissant en 0,17 s ; pas de squash and stretch sur les corps |

**Ce qu'on en retient.** Peu d'images, une cadence franche et des poses très lisibles. Le mouvement
vient du **déplacement**, du **rebond de 1 px** et de la **pose** plutôt que du nombre d'images.

## 2. Les 5 éléments

Tous sont de profil, tournés vers la droite ; la gauche est le miroir. La toile fait 48 × 48 px,
`colors` = 12, et la référence est l'image retenue du profil.

| # | Élément | Images | Cadence | Boucle | Style pixelforge | Repli |
|---|---|---|---|---|---|---|
| 1 | **Profil** (sprite de référence) | 1 | — | — | `pf_pro__character` (`num_images` 3) | `pf__character` |
| 2 | **Idle** (statique animé) | 2 | 3 i/s | oui | `pf_anim__keyframes` | `pf_anim__guided` |
| 3 | **Course** | 4 | 12 i/s | oui | `pf_anim__walking` | `pf_anim__four_angle_walking` (on ne garde que le profil) |
| 4 | **Saut vers la cachette** ; la sortie = la même animation jouée à l'envers | 5 | 12 i/s | non | `pf_anim__keyframes` | `pf_anim__guided` |
| 5 | **Fantôme** | 4 | 6 i/s | oui | `pf_anim__keyframes` | `pf_anim__guided` |

**Assemblage** :
`{description}, {action}, {expression}.` + style commun + suffixe `anim`. La description vient de
`02_personnages.md`. Pour les styles de keyframes, on envoie aussi l'image de profil retenue.

### 2.1 Profil
`{action}` = `full body in a strict side view facing right, standing relaxed, arms along the body, feet flat on the ground line` ;
`{expression}` = `friendly small smile`.
C'est le prompt de `02_personnages.md` §3.

### 2.2 Idle (2 images, 3 i/s)
```text
{description}, standing still in side view facing right, gentle breathing: the body rises one pixel in the second frame, calm small smile.
```

### 2.3 Course (4 images, 12 i/s)
```text
{description}, bouncy cartoon run in side view facing right, four poses: long stride, passing pose with the body one pixel higher, long stride with the other leg, passing pose; arms swinging wide, excited determined grin.
```
Party Hard marche à 10 i/s ; 12 i/s donne une course. La vitesse de déplacement en jeu reste
réglée par `rules.json`. Les poses doivent suivre le pas : environ 0,4 s par cycle pour 1 case
parcourue par cycle.

### 2.4 Saut vers la cachette (5 images, 12 i/s ; sortie = à l'envers)
```text
{description}, jump into a hiding spot in side view facing right, five poses: crouch with a squash, spring up with a stretch, top of the jump tucked in a ball, dive forward and down, only the feet still visible at the bottom, excited grin with eyes shut while diving.
```
- La 5ᵉ image se termine dans l'objet. Le jeu fait trembler la cachette.
- Pour la sortie, on joue les images 5 → 1. Si le plongeon à l'envers se lit mal, on régénère une
  sortie dédiée avec le même prompt, en remplaçant `jump into` par `pop out of` et en inversant
  l'ordre des poses.

### 2.5 Fantôme (4 images, 6 i/s)
```text
{description}, floating in side view facing right as a pale translucent ghost of the same character, small white angel wings flapping, the body bobbing two pixels up and down, feet dangling above the ground, gentle smile.
```
Le jeu applique la transparence (environ 50 %) : le sprite reste opaque.

## 3. Cas particuliers

- **Kaio et Karramarro.**
  - Course : Kaio se dandine, ailes en arrière ; Karramarro court de côté, toutes les pattes en
    vague, sur 4 poses quand même. On ajoute l'allure de `prompts_anims.json` (`allure`) après
    `{action}`.
- **Accessoires.** Ils restent fixés et gardent leur forme : planche de Maïa, canne de Patxi,
  chistera de Xabi, ballon de Peio, lanterne d'Itsasargi. Dans `{action}`, on ajoute
  `the {objet} stays attached in the same place in every frame`.
- **Après génération.**
  1. Réduire à 48 px et quantifier à 12 couleurs.
  2. Caler les pieds sur la même ligne.
  3. Faire une planche contact ×4 et la regarder (CLAUDE.md, règle 6).
