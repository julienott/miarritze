# Persos 2D animés par IA : bonnes pratiques (recherche du 2026-10-19)

Synthèse d'une recherche web faite pour pixelforge après les premiers retours sur Louis 2D
(pieds superposés, genoux cassés, restes du béret). Voir `docs/GORDEKA_STYLE_2D.md`.

## Découpe en calques
- **Compléter chaque pièce au-delà de sa partie visible** (inpainting « amodal ») : crâne complet sous le
  chapeau, haut de cuisse et épaule sous le corps, contour d'origine effacé sous les recouvrements. C'est
  la cause des trous au pivot et des restes de contour.
- Outils à évaluer, tous deux sous Apache 2.0 : **See-through** (SIGGRAPH 2026, illustration vers PSD d'au
  plus 23 calques, parties cachées complétées, ordre déduit ; licence des poids à vérifier) et
  **Qwen-Image-Layered** (image vers N calques RGBA).
- Règles de découpe (Spine, Toon Boom, Tahoma2D) :
  - pièces dessinées droites, au repos ;
  - **bout de membre en disque centré sur le pivot**, qui passe sous la pièce voisine ;
  - contour au-dessus *et* au-dessous du recouvrement ;
  - pièce « rustine » pour un genou ou un coude qui plie fort.
- Façon Among Us : **une pièce par jambe, de la hanche au pied, pantalon compris**.

## Rigging automatique
- Meta **Animated Drawings** (MIT, archivé en 2025) : utile comme modèle (déformation ARAP, rejeu de
  mouvements BVH), mais il ne gère que les persos de face.

## Identité stable et profil
- **Approche hybride** : les calques donnent la pose ; un redessin léger image par image, guidé par silhouette
  ou contour, répare les joints ; on verrouille ensuite les couleurs sur la palette du perso.
- **ToonCrafter** (Apache 2.0) intercale entre deux poses clés. **Wan 2.2 Animate/VACE** anime d'après un
  squelette ; il faut toujours recaler sur la ligne de sol.
- **Profil strict** : un mannequin Blender en profil sert de ControlNet, ou **Qwen-Image-Edit-2511 + LoRA
  « Multiple Angles »** à 90° (Apache 2.0, licence de la LoRA à vérifier).
- **Licence** : FLUX.1 Kontext [dev] permet un usage commercial des images produites, mais **faire tourner
  le modèle en production commerciale demande une licence BFL**. Vérifier SAM 3 aussi (licence Meta
  maison).

## Principes d'animation
- **Marche en 8 images** : contact, descente, passage, montée, ×2. Les bras vont à l'opposé des jambes, et la
  dernière image ne répète pas la première.
- **Au repos, pieds décalés** : jambe arrière décalée de 15 à 25 % de la largeur du pied, assombrie de
  15 à 25 %, légèrement plus petite, déphasée d'une demi-période dans la marche.
- **Écrasement et étirement à volume constant** (sx = 1/sy), sur le corps seulement.
- **Durées par image en données** : tenir les poses clés plutôt qu'ajouter des images.

## Contrôles automatiques
- **Trous au pivot** : rotation de chaque pièce sur toute sa plage, puis recherche de pixels transparents
  près du joint.
- **Restes de contour** : chapeau ôté, la tête ne doit contenir aucun pixel de contour hors de sa zone.
- **Pied d'appui** : même hauteur (±1 px) sur les images de contact, sans glisser.
- **Stabilité** : hauteur de la boîte englobante stable (±3 %), palette et identité proches de la référence.
- **Boucle** : la dernière image s'enchaîne sur la première sans saut.

## Sources principales
[Qwen-Image-Layered](https://github.com/QwenLM/Qwen-Image-Layered) ·
[See-through](https://github.com/shitagaki-lab/see-through) ·
[Spine : découper ses assets](https://en.esotericsoftware.com/blog/How-to-cut-your-assets-for-animation) ·
[Animated Drawings](https://github.com/facebookresearch/AnimatedDrawings) ·
[ToonCrafter](https://github.com/Doubiiu/ToonCrafter) ·
[LoRA Multiple Angles](https://huggingface.co/fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA) ·
[Licence FLUX.1 Kontext dev](https://huggingface.co/black-forest-labs/FLUX.1-Kontext-dev/blob/main/LICENSE.md)
