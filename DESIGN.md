# Miarritze — Design Document

> L'aventure d'un jeune Basque, Louis, à travers Biarritz.
> Jeu web arcade, tactile-first, pensé pour les enfants (~9 ans) et le défi entre copains.

---

## 1. Vision

**Pitch.** Louis parcourt une Biarritz en pixel art ensoleillé et s'affronte sur des épreuves inspirées de la vie locale — course sur le sable, surf, pêche au port, lancer d'espadrille. Chaque épreuve donne un score ; on cumule, on grimpe au Phare, et on se compare à ses copains via un classement en ligne.

**Intention.** Trois motivations, dans cet ordre :
1. **Un jeu pour Louis (bientôt 9 ans) et ses copains**, partageable en un lien sur tablette et téléphone.
2. **Un hommage à Biarritz et à la culture basque**, reconnaissable au premier coup d'œil.
3. **Un projet publiable** (hébergement propre, potentiellement itch.io) avec une petite ambition d'audience.

**Pilier non négociable.** *Accessibilité et enchantement.* Un enfant prend le téléphone et joue en une seconde, sans tutoriel, sans échec punitif. Le plaisir vient de la variété et du « je veux battre mon score / mon copain ».

**Références (le goût de Louis).** Mario, Zelda, Lego Batman, Fez, Astro Bot. Le fil rouge : explorer, s'émerveiller, collectionner, dans une difficulté douce. Aucune référence punitive → **le jeu n'est jamais frustrant**.

---

## 2. Genre et boucle de jeu

**Genre.** Collection de mini-épreuves arcade reliées par un hub, avec score cumulé et leaderboard privé. Format « pick-up-and-play », idéal en récré.

**Boucle principale.**
```
Hub (carte de Biarritz) → choisir un lieu → jouer l'épreuve → score
   → high score mémorisé → cumul mis à jour → leaderboard mis à jour
   → retour au hub → (le cumul débloque le Phare)
```

**Modèle de carte : hub-sélection.** La carte de Biarritz est une belle antichambre, pas un niveau de plateforme. On la parcourt légèrement, on tape un lieu pour lancer son épreuve. Tout le skill et le score vivent **dans** les épreuves.

---

## 3. Les lieux

Six lieux emblématiques de Biarritz. Les Halles servent de camp de base ; cinq lieux sont des épreuves « cœur » ; le Phare est l'épreuve-climax débloquée par le score.

| Lieu | Rôle | Mécanique | Contrôle | Score |
|---|---|---|---|---|
| **Les Halles** | Camp de base | Hub / point de départ, ravitaillement, cœur social | — | — |
| **Grande Plage** | Épreuve | Runner latéral, course auto, saut par-dessus obstacles (châteaux de sable, parasols, crabes) | Tap = saut | Distance + pièces |
| **Côte des Basques** | Épreuve | Surf sur la face de la vague ; position verticale automatique, décollage/figure au sommet | Tap = décollage/figure | Figures + style + durée sans chute |
| **Port des Pêcheurs** | Épreuve | Ferrage puis gestion de la tension de ligne en rythme | Tap = remonter / relâcher quand la ligne se tend | Taille + rareté + nombre (temps limité) |
| **Rocher de la Vierge** | Épreuve | Traversée-timing façon Frogger ; vagues rythmées, avancer dans la bonne fenêtre | Tap = avancer | Temps + traversée sans être balayé |
| **Port Vieux** | Épreuve | Lancer d'espadrille façon Angry Birds ; viser des cibles (boîtes, bouées, mouettes chapardeuses) | Glisser = viser/doser, relâcher = lancer | Précision + cibles + combos |
| **Phare** | Épreuve-climax | Ascension-plateforme verticale **débloquée par le score cumulé** ; sommet = salle des trophées / leaderboard | Tap = saut | High score d'ascension |

**Principe de design.** Chaque épreuve teste une compétence **différente** : réflexe (course), timing de saut (surf), rythme sous tension (pêche), lecture de motif (Rocher), visée (espadrille), agilité verticale (Phare). Variété généreuse, esprit Astro Bot.

**Principe de contrôle.** *Tap unique* pour tout ce qui est mouvement/timing (course, surf, pêche, Rocher, Phare). *Glisser* pour l'unique épreuve de visée (espadrille). Un seul geste par épreuve, zéro apprentissage.

---

## 4. Détail des épreuves

### 4.1 Grande Plage — course sur le sable
Louis court automatiquement de gauche à droite. Un tap = saut. Obstacles thématiques (châteaux de sable, parasols, crabes) et pièces à ramasser. C'est l'épreuve d'ouverture idéale : la plus simple à comprendre.
*Évolution possible (post-test) : double-tap = double saut.*
**Feedback clé :** vitesse lisible, atterrissage clair.

### 4.2 Côte des Basques — surf
L'épreuve « sensation » et signature du jeu. Louis suit la vague ; on tape au bon moment pour décoller au sommet et enchaîner une figure aérienne, puis retomber proprement. Tout le skill est dans le **timing** du tap et l'enchaînement.
**Feedback clé :** traînée/écume pour la vitesse, **fenêtre de réception indulgente** (un enfant ne doit pas rater sans comprendre pourquoi).

### 4.3 Port des Pêcheurs — pêche
L'épreuve « calme », contraste après la vitesse. On ferre, puis on gère la **tension de la ligne** en tapant en rythme pour remonter le poisson sans casser. Un gros poisson résiste plus longtemps → montée de tension, « je l'ai eu ! » satisfaisant.
**Feedback clé :** jauge de tension très lisible **vert / orange / rouge**, comprise sans texte.

### 4.4 Rocher de la Vierge — traversée
L'épreuve de **lecture du rythme**. Embruns et vagues déferlent par cycles ; Louis progresse de plateforme en plateforme en tapant pile quand le passage est dégagé. Thématiquement parfait : franchir le passage battu par l'océan entre deux vagues.
**Feedback clé :** la vague est **télégraphiée** (on la voit venir et se retirer) → on anticipe au lieu de subir.

### 4.5 Port Vieux — lancer d'espadrille
L'épreuve « folklore » et fun-décalée. On tire l'espadrille en arrière (glisser), une trajectoire s'affiche, on relâche pour lancer vers des cibles (boîtes de conserve, bouées, mouettes chapardeuses).
**Feedback clé :** trajectoire prévisualisée, impact satisfaisant, combos valorisés.

### 4.6 Phare — ascension & salle des trophées
Débloqué quand le score **cumulé** franchit un seuil. Ascension-plateforme verticale (sauter de palier en palier) jusqu'au sommet, où se trouve la salle des trophées : rang du joueur, scores des copains, vue sur toute la Biarritz parcourue. Récompense symbolique et moteur de rejouabilité (« encore une fois pour monter au classement »).

---

## 5. Score, progression et leaderboard

### 5.1 Score
- **High score par épreuve** : chaque épreuve est une borne d'arcade avec son propre meilleur score mémorisé.
- **Score cumulé** = somme des meilleurs scores des **5 épreuves cœur**. C'est lui qui débloque le Phare (seuil à régler au playtest).
- **Pas de médailles, pas de monnaie, pas de cosmétiques en v1.** Message limpide : « améliore chaque épreuve pour monter au sommet et grimper au classement ».

### 5.2 Leaderboard (moteur social)
- **Double classement** : par épreuve **et** au cumul. Chacun peut être « le roi du surf » sans être premier au général.
- **Identité = pseudo seul.** Pas de compte, pas d'email, pas de nom réel → zéro friction, quasi-anonyme.
- **Portée = groupe privé** rejoint via un **code partageable**. Les copains entre eux, pas un mur d'inconnus.
- **Sécurité / hygiène** (voir CLAUDE.md pour l'implémentation) : validation de plausibilité des scores côté serveur, jeton par joueur, **filtre anti-gros-mots** sur les pseudos.

### 5.3 Conformité (données enfants)
Le pseudo-seul + code de groupe est aussi le choix le plus propre côté RGPD : aucune donnée personnelle sensible (pas de nom, email, ni compte). À maintenir comme principe : **rien de nominatif ne doit être collecté**.

---

## 6. Univers et direction artistique

**Cadre.** Biarritz réelle, stylisée : le sable, les vagues, les toits rouges et blancs, le Rocher de la Vierge, le Phare. Reconnaissable immédiatement par un local — c'est le cœur émotionnel du jeu.

**Style visuel.** **Pixel art coloré, ensoleillé, lisible**, dans l'esprit de Fez. Meilleur rapport charme / faisabilité / performance web, et pile dans le goût de Louis. Palette limitée (le pixel art est plus cohérent contraint), rendu **pixel-perfect** scalé proprement sur tablette et téléphone.

**UI/HUD.** Minimal et arcade, lisible pour un enfant : score bien visible, jauges claires (tension de pêche, trajectoire d'espadrille), boutons tactiles généreux.

---

## 7. Audio

**Musique.** **Chiptune à couleur basque.** Base : mélodies **traditionnelles** basques (domaine public — ex. airs de fête, fandango, *Agur Jaunak*) **arrangées en propre** en chiptune. Une ambiance musicale distincte par épreuve (surf énergique, pêche calme, course rythmée).

> ⚠️ **Vigilance droits.** Partir de la mélodie traditionnelle et faire **son propre arrangement MIDI/chiptune** — ne pas reprendre un fichier MIDI trouvé en ligne (arrangeur inconnu). Éviter les œuvres à auteur identifié : *Hegoak (Txoria Txori)* est de Mikel Laboa → **pas domaine public**, à écarter pour un jeu publié.

**SFX.** Banque de bruitages punchy, essentiels au game feel : saut, pièce, espadrille en vol, poisson qui mord, vague qui déferle, jingle de victoire au sommet du Phare.

---

## 8. Cible technique et livrable

- **Plateforme** : jeu **web HTML5**, tactile-first, responsive **tablette + téléphone**. Desktop/clavier en bonus quasi gratuit.
- **Orientation** : **paysage** (avec écran « tourne ton appareil » si tenu en portrait).
- **Distribution** : accessible par une **URL** (hébergement propre), sans installation.
- **Moteur** : Godot 4.7, GDScript, export web.
- **Backend** : PHP + SQLite (petite API leaderboard).

Détails d'architecture, contraintes web et conventions → **CLAUDE.md**.

---

## 9. Périmètre

**v1 = le jeu complet** : 5 épreuves cœur + hub des Halles + Phare + leaderboard.
**Stratégie de construction** : *squelette d'abord* (hub, score, backend, pipeline export web/tactile, un template d'épreuve générique construit **une seule fois**), puis déclinaison des 5 épreuves, puis **polissage itératif de chaque morceau après les tests de Louis**. C'est ce qui rend le périmètre complet tenable en solo.

**Reporté en v2 (pistes) :** médailles bronze/argent/or, monnaie et cosmétiques (tenues de Louis, couleurs d'espadrille), décor 2.5D via Gaussian splatting (desktop, hors contrainte WASM), plus de lieux (ex. secrets tapotables sur la carte).

---

## 10. Hypothèses à confirmer au playtest

Ces points sont volontairement laissés ouverts et se règlent en jouant :
- **Seuil de déblocage du Phare** (valeur du cumul).
- **Le Phare compte-t-il dans le leaderboard** comme une 6ᵉ épreuve à part entière, ou reste-t-il une récompense hors classement ? *(Hypothèse retenue par défaut : oui, son ascension a son propre high score et sa propre colonne de classement.)*
- **Durées / temps limites** de chaque épreuve.
- **Nombre de types d'obstacles / cibles / poissons** par épreuve.
- **Barème de points** précis (poids des figures, des combos, des pièces).
