# Musique : sources et droits

Toute la bande-son est **synthétisée** par `tools/gen_audio.py` (chiptune maison : carré, triangle, bruit LFSR 15 bits, steel pan additif), exportée en OGG Vorbis (≈ 80–90 kbps mono, 32 kHz, crête −3 dBFS vérifiée après décodage).

**Principe de droits.** Aucune mélodie n'est reprise d'une œuvre à auteur identifié, ni d'une partition ou d'un MIDI tiers. Plutôt que de transcrire de mémoire des airs traditionnels précis (risque d'approximation, voire de confusion avec un arrangement protégé), **chaque morceau est une composition originale écrite dans une FORME traditionnelle basque**. Ces formes (fandango, arin-arin, zortziko, aurresku, kalejira, ezpata-dantza, berceuse « lo-lo ») sont des genres de danse et de chant populaires anonymes, sans auteur : elles appartiennent au domaine public. Les compositions elles-mêmes sont originales (créées pour le jeu).

*Hegoak* (Txoria txori, musique de Mikel Laboa) : œuvre protégée, retirée en Phase 0 puis **rétablie le 2026-10-13 à la demande de Julien** sur l'accueil (titre, profils, menu, réglages) : `assets/audio/music/hegoak.mp3`, l'arrangement de l'ancien jeu. `title.ogg` reste dans le dépôt, prêt à servir si on le retire de nouveau.

| Fichier | Rôle | Forme traditionnelle (domaine public) | Mélodie | Notes d'arrangement |
|---|---|---|---|---|
| `music/title.ogg` | Écran titre | Marche d'honneur (ezpata-dantza / aurresku) | Originale, sol majeur, 4/4 | Lead carré 50 %, doublure steel pan à l'octave, basse fondamentale/quinte, arpèges 12,5 %, caisse claire de défilé. A B A, 55 s. |
| `music/select.ogg` | Sélection, menus | Fandango (3/4 vif) | Originale, ré majeur | Lead carré 25 %, basse valse, shaker au contretemps. A B A B A, 43 s. |
| `music/tower.ogg` | Pyramide du Phare | Aurresku (danse d'honneur, marche) | Originale, la mineur → do majeur | Tambour régulier qui « monte ». 50 s. |
| `music/grande_plage.ogg` | Stage Grande Plage | Arin-arin (danse vive 2/4) | Originale, do majeur | Tempo 152, arpèges en croches, batterie entraînante. A B A B, 50 s. |
| `music/cote_basques.ogg` | Stage Côte des Basques | Fandango balancé (6/8) | Originale, la mixolydien | Lead 12,5 % « surf », basse en noires pointées, souffle de vagues (bruit grave) toutes les 2 mesures. 44 s. |
| `music/port_pecheurs.ogg` | Stage Port des Pêcheurs | Chant de rameurs (arraun-kanta), valse | Originale, mi mineur | Calme : triangle au premier plan, carré discret, cloche du port (steel pan). 63 s. |
| `music/rocher_vierge.ogg` | Stage Rocher de la Vierge | Zortziko (5/8, 2+3) | Originale, ré mineur | Mesure boiteuse caractéristique, basse en 2+3, tension « embruns ». 48 s. |
| `music/port_vieux.ogg` | Stage Port Vieux | Kalejira (défilé festif de rue) | Originale, fa majeur | Swing léger, cuivre de carré 50 %. 53 s. |
| `music/halles.ogg` | Stage Les Halles | Arin-arin de marché | Originale, sol majeur | « Accordéon » : deux carrés à la tierce diatonique, toc de bois. 48 s. |
| `music/fronton.ogg` | Stage Fronton | Fandango à palmas | Originale, mi mineur | Palmas (bruit en rafales) sur les temps 2–3, claquements de pelote (toc de bois) au contretemps. 48 s. |
| `music/stade.ogg` | Stage Stade | Marche festive (fanfare de tribune) | Originale, si bémol majeur | La plus énergique : grosse caisse + caisse claire, toms. 49 s. |
| `music/aquarium.ogg` | Stage Aquarium | Berceuse marine (6/8) | Originale, ré majeur | Steel pan + triangle, arpèges « bulles », shaker doux. 53 s. |
| `music/phare_sommet.ogg` | Boss, Sommet du Phare | Aurresku nocturne | Originale, ré mineur harmonique | Plus sombre et martial : basse en octaves, doublure en dent de scie, arpèges descendants (le faisceau). 46 s. |
| `music/victory.ogg` | Jingle de victoire | — | Originale | 3,4 s, non bouclé. |
| `music/txapeldun.ogg` | Fanfare « TXAPELDUN ! » | Fanfare de remise de prix | Originale, sol majeur (motif du titre) | Roulements de caisse claire, harmonie à la tierce. 8,5 s, non bouclé. |
| `music/ending.ogg` | Fins illustrées | Berceuse « lo-lo » (bercement 6/8) | Originale, fa majeur | Txistu simulé : triangle + vibrato lent, arpèges de steel pan, très doux. 51 s. |

Les musiques bouclées sont coupées exactement à la mesure, et la queue des dernières notes est repliée au début de la boucle (pas de trou ni de clic).

## Bruitages et jingles

- `sfx/` (31 fichiers, ≈ 0,3 Mo) : coups léger/lourd/uppercut/super, garde (« toc » de bois), coup dans le vide, saut, réception, projection, esquive, PLOUF, vague, super, spécial, projectile, K.O., parfait, round, tic du chrono, interface (ok/déplacement/refus), sifflet (Txomin), pelote (Xabi), goéland (Kaio), pince (Karramarro), feu (Ramuntxo), foule, éclaboussure, seau, BORROKA. Tous synthétisés, fondus d'entrée/sortie (aucun clic), crête ≤ −3 dBFS après décodage.
- `voice/` : **pas de voix enregistrée** (décision : annonces textuelles à l'écran + jingles chiptune courts `borroka`, `bukatu`, `txapeldun`, `plouf`). La piste « voix enregistrées par les enfants » (SPEC §12) reste possible plus tard : déposer des fichiers du même nom dans `assets/audio/voice/` suffit.

## Régénérer

```bash
.venv/bin/pip install soundfile numpy        # libsndfile embarque Vorbis ; ffmpeg n'est pas requis
.venv/bin/python tools/gen_audio.py all       # ou : music | sfx | voice [noms…]
```
