# Miarritze Borroka — Design (résumé)

> Résumé de `SPEC-BORROKA.md`, qui reste la source de vérité.
> Jeu de combat 2D en pixel art, esprit Mortal Kombat mais **solaire, basque et pour enfants**. *Borroka* = « combat » en basque.

## Vision
Douze combattants fictifs de la côte basque s'affrontent sur les lieux de Biarritz. En solo, on grimpe la **pyramide du Phare** (9 étages) jusqu'au **Gardien du Phare** pour gagner la **txapela**. En multijoueur : versus local, ou en ligne contre un copain du **groupe** (code à 6 caractères, jamais d'inconnus).

**Piliers :** prise en main en 10 s (4 boutons + direction, aucune manip obligatoire) · chaque perso est une star (silhouette, 4 spéciaux, super, finish comique, fin illustrée) · Biarritz à chaque écran · le même jeu partout (clavier, manette, iPhone en paysage) · zéro donnée personnelle.

**Ton :** cartoon, slapstick. « PAF ! », « PLOUF ! » au K.O. Pas de sang, pas de lame, pas de mort.

## Modes
Titre → Profil (4 max, local d'abord) → Menu : **Pyramide** (Facile/Normal/Expert, continues illimités, score) · **Versus local** · **En ligne** (salon du groupe, défi, match rapide, choix de map, Elo K=32) · **Entraînement** (mannequin de sable Hondar, liste des coups) · **Profil** (carte de joueur : favori, costume, bannière, titre, emote prédéfinie) · **Réglages**.

## Combat
- Boutons **POING, PIED, SPÉCIAL, GARDE** + direction relative (avant = vers l'adversaire).
- Garde haute/basse ; chip 15 % sur spéciaux, jamais de K.O. par chip. Auto-combo POING×3. Uppercut « Txapel-cut » jouissif. Projection techable.
- 4 spéciaux par perso (SPÉCIAL + neutre/avant/bas/haut), manip classique optionnelle (+10 %).
- Jauge **Marée** 3 segments : spécial renforcé (1), **super** (3). « Retour de vague » une fois sous 25 % de vie.
- Finish **« BUKATU ! »** : Bas, Bas + SPÉCIAL, comique.
- 1000 PV (boss 1400), 60 s par round, meilleur des 3. Tick 60 Hz, hitstop 4/8/14/20, buffer 8 frames, scaling de combo, chute forcée à 6 coups.

## Roster
Louis (équilibré), Maïa (surfeuse rapide), Patxi (pêcheur lutteur), Xabi (pelotari zoneur), Mattin (leveur de pierre lourd), Amaia (dantzari technique), Txomin (maître-nageur contrôle), Kaio (goéland aérien), Karramarro (crabe défensif), Ramuntxo (chef des Halles pièges), Itsaso (esprit de l'écume, téléportation), Peio (rugbyman charges) + boss **Itsasargi**, le Gardien du Phare. 4 costumes (swap de palette).

## Stages
Grande Plage (+ soir), Côte des Basques (+ crépuscule), Port des Pêcheurs, Rocher de la Vierge, Port Vieux, Les Halles, Fronton, Stade, Aquarium, Sommet du Phare (nuit). Monde 576 px, parallaxe, sol 40 px, aucun danger en v1.

## Direction artistique
« Arcade de bord de mer » : décors i2i issus de photos réelles, palette chaude ~64 couleurs en rampes (`tools/palette.py`), contour brun-prune, sprites ~100 px de haut en cellules 128×128 indexées + shader de palette, UI « bois de bateau et laiton », lettrage basque, onomatopées pixel.

## Production des assets
RD (plafond 50 $) **seulement pour l'identité** : pose de base, idle, portrait, fins, décors. **Tout le mouvement par un rig cut-out procédural** (RotSprite, smear frames), le même moteur que les mannequins placeholders.

## Audio
Chiptune maison (`tools/gen_audio.py`), arrangements d'airs traditionnels basques du domaine public. Bus Music/SFX/Voice, ducking.
