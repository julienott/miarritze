# Demande à pixelforge : refaire un perso entièrement côté serveur

Décision de Julien (2026-10-18) : **l'outillage de génération est côté pixelforge**.
Miarritze ne garde que ce qui est propre au jeu : le mannequin articulé et la bibliothèque
de poses (`tools/mannequin`, `tools/rig/poses`), qui fabriquent les **contrôles**.
Tout le reste (ci-dessous) est aujourd'hui codé chez nous en prototype dans
[`tools/pf/from_mannequin.py`](../tools/pf/from_mannequin.py) : à reprendre côté serveur,
puis nous supprimons notre version.

## Ce que le jeu envoie

Un appel par animation (`pf_anim__guided`, idéalement en `/v2` + polling) :

| champ | contenu |
|---|---|
| `input_image` | modèle propre **sans accessoire**, en garde, case 160, pieds en (80, 152) |
| `control_frames[]` | rendus du mannequin (couleur, fond transparent), déjà à la taille du modèle |
| `frame_angles[]` | **nouveau** : inclinaison du buste par image (degrés ; 0 = debout) |
| `target_frames[]` | **nouveau** : silhouette tournée réelle (pour recaler après rotation) |
| `tuck_image` | **nouveau** : pose groupée (boule) du perso, pour les saltos |
| `tuck_frames[]` | **nouveau** : indices des images de salto (en l'air et tournées) |
| `overlays[]` | **nouveau** : accessoires à coller par image, voir plus bas |
| `ignore_masks` | **nouveau** : vrai = la QA ignore les pixels des `overlays` |

## Ce que le serveur fait

1. **Redressement** (`frame_angles`) : si |angle| > 40°, le contrôle envoyé est déjà rendu
   corps droit ; le serveur redessine droit, puis **tourne** le résultat de l'angle avec une
   rotation pixel art propre (RotSprite : ×8 par scale2x, rotation, vote 8→1 ; pas de plus
   proche voisin) autour du centroïde, sens choisi par recouvrement avec `target_frames[i]`,
   puis recale le centroïde sur la cible. Sans ça : tête en bas = visage perdu, couché = tête en boule floue.
2. **Saltos** (`tuck_frames`) : au lieu du redessin (jambes repliées en « lambeaux »),
   `tuck_image` mise à la hauteur du contrôle, centrée, puis tournée comme en 1.
3. **Accessoires** (`overlays`) : liste par image de
   `{image (RGBA), pivot [x,y], position [x,y], angle, devant: bool}` ; le serveur tourne
   l'image (RotSprite) autour du pivot, la pose à la position, devant ou derrière le perso.
   Exemples : chistera de Xabi sur la main, palmes de Txomin accrochées au bassin.
   Jamais redessinés (Julien : « chistera fidèle »).
4. **QA** : `identity_drift`, `extra_area_vs_control` et `detached_px` calculés **hors**
   overlays (sinon dérive 0,3–0,98 et 5 relances inutiles à chaque animation).
5. Renvoie la planche finale + par image : angle appliqué, essai retenu, QA.

## Aussi, `pf__edit` (Kontext)

- **Détourage** : retirer seulement le fond **relié au bord** (remplissage), jamais le blanc
  enclos dans le perso (pantalon blanc de Xabi devenu trous), + option ombre portée retirée.
  Renvoyer aussi l'image brute.
- **Pose par silhouette** (souhait) : « même perso dans cette pose » à partir d'une image de
  contrôle ; aujourd'hui garde et boule s'obtiennent au prompt, 3 à 6 essais chacun.

## Références

- prototype : `tools/pf/from_mannequin.py` (`place`, `rotsprite`, `turn`, `tuck_sprite`,
  `Accessory.layer`, `hip_layer`, `compose`)
- détourage depuis le bord : `tools/pf/model_sans_acc.py` (`clean`)
- résultats du pilote Xabi : `tests/out/pf/xabi.png` (local)
