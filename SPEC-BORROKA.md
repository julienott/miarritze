# SPEC — Miarritze Borroka

> Refonte de *Miarritze* en **jeu de combat 2D en pixel art**, dans l'esprit de Mortal Kombat, mais solaire, basque et adapté aux enfants.
> Spec d'exécution destinée à **Claude Code**. À lire en entier avant la première ligne de code.
> Date : 12/10/2026. Langue du code et des commentaires : français (comme l'existant).

*Borroka* signifie « combat » en basque. Le nom évite toute confusion avec la marque Mortal Kombat : on ne réutilise ni le « K », ni les logos, ni les noms ou les sons de MK. Seul l'esprit est repris : roster, coups spéciaux, pyramide, palettes alternatives et finish.

---

## 0. Mode d'emploi pour Claude Code

1. **Lis cette spec en entier**, puis `CLAUDE.md` et `DESIGN.md` actuels, qui décrivent l'ancien jeu. En **Phase 0**, tu remplaces `DESIGN.md` et `CLAUDE.md` par des versions dérivées de cette spec. Cette spec reste la source de vérité ; les deux fichiers en sont des résumés opérationnels.
2. **Travaille phase par phase** (§15). Chaque phase a un **critère de sortie vérifiable**. Ne commence pas la suivante tant que le critère n'est pas atteint. Fais un commit atomique par étape.
3. **Retro Diffusion : budget TOTAL plafonné à 50 $ (tout le projet, essais compris).** C'est une contrainte dure. Le client RD tient un registre des dépenses et **refuse** toute requête qui ferait dépasser le plafond (§11.2). Avant chaque lot, fais un dry run avec `check_cost: true`, affiche le coût du lot et le cumul, et **demande confirmation** si un lot dépasse 5 $. Mets les résultats en cache : on ne régénère jamais une image déjà validée. La stratégie d'assets (§11) est conçue pour tenir dans environ 21 $, avec près de 29 $ de marge.
4. **Vérifie visuellement tout asset produit.** Monte une planche contact agrandie en ×4 (nearest), puis ouvre-la pour la regarder. Un asset jamais regardé n'est pas livré.
5. **La simulation de combat doit être déterministe** (§8.2). C'est une règle d'architecture non négociable : le jeu en ligne en dépend.
6. Quand la spec laisse un choix ouvert (marqué **[À trancher]**), choisis l'option la plus simple qui respecte les piliers, note-la dans `docs/DECISIONS.md` et continue.
7. La clé Retro Diffusion vit dans `.rd_api_key` à la racine (gitignorée, préfixe `rdpk-`). Si elle est absente ou invalide, continue avec les mannequins et le procédural, et consigne le problème dans `docs/STATUS.md`.
8. **Mode autonome (choix de Julien, prioritaire sur tout point d'arrêt ou toute demande de confirmation de cette spec).** Claude Code enchaîne les phases 0 à 8 **sans attendre de validation humaine** :
   - Les « points d'arrêt » et « validations par Julien » (Phase 3, lots > 5 $) deviennent des **revues autonomes**. Un sous-agent qui n'a pas produit le travail examine les planches contact et les GIF avec les critères de la spec, et rend un verdict accepté ou à refaire (2 itérations maximum). Le verdict est consigné dans `docs/REVIEWS.md`.
   - Les décisions **[À trancher]** se prennent seules (option la plus simple qui respecte les piliers) et se consignent dans `docs/DECISIONS.md`.
   - Les tests sur vrai iPhone sont remplacés par Playwright **WebKit** avec émulation tactile iPhone (viewport paysage 844×390, multitouch). La checklist manuelle reste dans `docs/TEST_IPHONE.md` pour plus tard.
   - **Ce qui reste bloquant** :
     - le plafond RD de 50 $ : le client refuse, et on termine avec les mannequins et le procédural ;
     - aucun déploiement en production et aucun `git push` sur `main`, tout reste sur la branche `borroka` ;
     - aucune suppression hors du dépôt.
   - Si une phase échoue à son critère de sortie après 3 tentatives, consigner le blocage dans `docs/STATUS.md`, livrer la meilleure version possible et **passer à la suite** plutôt que de s'arrêter.
   - `docs/STATUS.md` est tenu à jour à chaque fin de phase : phase atteinte, ce qui marche, captures, dépense RD, blocages.

---

## 1. Vision

**Pitch.** Douze combattants de la côte basque s'affrontent sur les lieux emblématiques de Biarritz. En solo, on grimpe la **pyramide du Phare**, étage par étage, jusqu'au Gardien du Phare, pour décrocher la **txapela** : le béret du champion, *txapeldun* en basque, la vraie récompense des compétitions basques. En multijoueur, on défie un copain de son groupe en ligne, ou à deux sur le même clavier.

**Joueurs cibles.** Louis (9 ans) et ses copains d'abord, puis tout public. Le jeu reste « MK pour enfants » : lisible, généreux, jamais punitif, et sans aucune violence graphique.

**Piliers (non négociables)**
1. **Prise en main en 10 secondes.** Les boutons Poing, Pied, Spécial et Garde, combinés à une direction, suffisent à tout faire. Aucune manipulation en quart de cercle n'est obligatoire.
2. **Chaque personnage est une star.** Une silhouette reconnaissable, quatre spéciaux, un super, un finish comique et une fin illustrée.
3. **Biarritz à chaque écran.** On reconnaît les décors réels, la culture basque (pelote, force basque, danse, makila, txapela, lauburu, ikurriña) et la mer.
4. **Le même jeu partout.** Ordinateur au clavier ou à la manette, iPhone avec une manette virtuelle ou des gestes. Le jeu se joue toujours en paysage, dans le navigateur.
5. **Zéro donnée personnelle.** Le joueur n'a qu'un pseudo et un code de groupe. Il n'y a ni chat ni texte libre entre joueurs.

**Ton.** Cartoon, slapstick, soleil. Les coups font « PAF ! », les K.O. font « PLOUF ! ». Il n'y a pas de sang, pas d'armes tranchantes et pas de mort : un combattant K.O. voit des étoiles, finit trempé ou couvert de plumes.

---

## 2. Inventaire de l'existant : garder ou jeter

L'existant contient un vrai savoir-faire : web, iOS, pipeline d'images, audio et backend. **On garde le savoir-faire, on jette le gameplay.**

### 2.1 À garder (en l'adaptant)

| Élément | Fichier(s) | Pourquoi / adaptation |
|---|---|---|
| Stack Godot 4.7 + GDScript typé + renderer Compatibility + export Web | `project.godot`, `export_presets.cfg` | Inchangé. Le C# reste interdit. |
| `.htaccess` COOP/COEP, MIME wasm, Cache-Control no-cache, rewrite `/api` | `web/.htaccess` | Inchangé. |
| CI de déploiement (Godot headless → rsync, backend vers `api/`) | `.github/workflows/deploy.yml` | Inchangé, plus un job de tests headless (§14). |
| Iris de transition pixelisé, file d'attente des navigations | `src/autoload/scene_router.gd` | On garde le mécanisme et on remplace la table des scènes. |
| Overlay « Tourne ton appareil » + pause | `src/autoload/orientation_overlay.gd` | Inchangé. |
| Déblocage audio web au premier geste | `src/autoload/audio_manager.gd` | On garde le mécanisme et on ajoute les bus Music/SFX/Voice et le ducking (§12). |
| QaCapture (capture headless) | `src/autoload/qa_capture.gd` | On l'étend avec `--autofight`, `--scene=` et `--frames=` (§14). |
| **Correctif iOS : l'index du toucher est arbitraire** | `src/shared/input/touch_input.gd` | La leçon est capitale : on ne suppose **jamais** qu'un index de toucher vaut 0. Le nouveau pad virtuel suit N touchers par index (§7.3). |
| Clavier virtuel web pour le pseudo | `export_presets.cfg` (`experimental_virtual_keyboard`) | Inchangé. |
| PixelBg (cover, calé en bas, frames d'eau animées) | `src/shared/components/pixel_bg.gd` | Réutilisé pour les écrans de menu. Les stages utilisent un composant parallaxe dédié (§10.6). |
| Fx (rafales de gros pixels) | `src/shared/components/fx.gd` | Base du système d'étincelles d'impact. |
| Palette limitée chaude | `tools/palette.py` | Étendue (§10.2). Elle reste **l'unique source** des couleurs. |
| Pipeline **img2img photos réelles → pixel art** | `tools/rd_i2i.py`, `tools/rd_post.py` | C'est le cœur de la DA des décors. On le migre vers l'API v2 et on l'étend aux stages larges (§11.4). |
| Synthé chiptune maison (carré, triangle, bruit LFSR, steel pan) | `tools/gen_audio.py` | On garde le moteur et on écrit de nouveaux morceaux (§12). |
| Backend PHP + SQLite : groupes, joueurs, secret, `Profanity`, `Validation`, rate limit, CORS strict | `backend/` | On garde le socle et on ajoute profils, présence, matchs et signalisation (§9). |
| Police Press Start 2P (OFL) | `assets/fonts/` | On la garde pour les petits textes. |

### 2.2 À jeter

- `src/challenges/**`, `src/hub/**`, `src/shared/config/challenges.gd`, `balance.gd` (remplacés), `louis_sprite.gd`, `pixel_gauge.gd`, et `src/shared/fsm/**` (la sim n'utilise pas de FSM à nœuds, cf. §8).
- Les sprites `play_*`, `louis*.png`, les props des épreuves (crabe, château de sable, poissons, etc.) et `tools/gen_props.py` / `gen_bg.py` / `gen_louis.py`.
  → Garder `gen_louis.py` seulement comme **référence de méthode** (grilles ASCII) dans `tools/legacy/`. Il sert pour les icônes UI.
- Les **décors i2i existants** (`bg_*`) sont conservés **temporairement** comme fonds de menus et comme *input* pour les nouveaux stages. Ils seront ensuite remplacés par les versions larges (§11.4).
- Les **musiques** actuelles. ⚠️ `menu.mp3` contient *Hegoak* (Mikel Laboa), qui **n'est pas** dans le domaine public (cf. DESIGN.md §7 d'origine). **Retirer *Hegoak* du jeu**, il ne doit apparaître dans aucun build publié.
- Backend : la table `scores` et les routes par épreuve sont remplacées. Écris une migration propre, sans compatibilité ascendante : le jeu n'a jamais eu de public.

---

## 3. Modes de jeu et boucle

```
Titre ─► Profil (créer / choisir) ─► Menu principal
           ├─ PYRAMIDE (solo)  : choisir combattant ─► tour du Phare ─► combats ─► fin illustrée
           ├─ VERSUS LOCAL     : J1 vs J2 sur le même appareil (clavier×2 ou clavier+manette)
           ├─ EN LIGNE         : salon du groupe ─► défier un copain / match rapide ─► choix map ─► combat
           ├─ ENTRAÎNEMENT     : mannequin (Itsaso de sable), liste des coups, affichage des entrées
           ├─ PROFIL           : personnalisation, costumes, titres, stats, txapelas
           └─ RÉGLAGES         : contrôles (manette virtuelle / gestes), sons, difficulté
```

### 3.1 Profil et personnalisation (« créer son profil »)
- **Identité** : pseudo seul, de 2 à 15 caractères, filtré par `Profanity`. On rejoint ou on crée un **groupe** avec un code de 6 caractères, comme avant. Les profils sont **locaux d'abord** (`user://profiles.json`) et synchronisés au serveur s'il y a un groupe. **Jusqu'à 4 profils** sur un appareil (frères, sœurs, copains).
- **Carte de joueur**, la vraie personnalisation, visible au salon et à l'écran de versus :
  - **Combattant favori** + **costume** : chaque combattant a 4 palettes, la 1 par défaut et les 2 à 4 à débloquer (§5.4).
  - **Bannière** : choix parmi 8 motifs basques pixelisés (lauburu, makhila croisés, vagues, ikurriña stylisée, rayures linge basque…).
  - **Titre** débloqué, par exemple « Roi de la Côte des Basques », « Txapeldun », « Invaincu du fronton ».
  - **Emote d'avant-combat** : 4 phrases prédéfinies seulement (« Agur ! », « Prêt·e ? », « Bravo ! », « Encore ! »). **Jamais de texte libre.**
- **Stats** : combats, victoires, pyramides terminées par combattant, txapelas gagnées (une par combattant et par difficulté), meilleur score de pyramide et rang de groupe.

### 3.2 Pyramide du Phare (solo, façon tour MK)
- Le joueur choisit son combattant et une difficulté : **Facile** (par défaut), **Normal** ou **Expert**.
- La tour est dessinée comme le **phare de Biarritz en coupe**, chaque étage portant le portrait de l'adversaire. Il y a **9 étages** :
  1–5. Cinq adversaires aléatoires, à difficulté IA croissante, sans doublon et différents du joueur.
  6. **Combat en double** : deux adversaires à la suite sur une seule barre de vie pour le joueur, l'équivalent de « l'endurance » de MK.
  7. **Le Reflet** : combat miroir contre son propre personnage, en costume alternatif.
  8. Un adversaire « rival » prédéfini pour chaque personnage (§5.1, colonne « Rival »).
  9. **Le Gardien du Phare** (boss, §5.3), sur le stage Sommet du Phare, la nuit.
- **Continues illimités.** Une défaite renvoie au même étage. Le score est réduit de 20 %, sans aucun autre malus.
- Le **score de pyramide** se calcule par combat : victoire, bonus de vie restante, bonus de temps, *Perfect* (×2) et finish réussi. Le total est envoyé au classement du groupe si c'est le meilleur.
- **Fin** : la cinématique « TXAPELDUN ! » montre la remise de la txapela. Vient ensuite la **fin illustrée du personnage** : une image RD en 3 cadrages, avec 3 courts textes (§5.1, §11.5). On débloque un costume, plus le Gardien jouable après une première victoire, dans n'importe quelle difficulté.

### 3.3 Versus local
- J1 et J2 sur le même appareil : clavier gauche/droite, clavier plus manette, ou deux manettes. Les deux choisissent leur combattant et leur costume. Si les costumes sont identiques, J2 passe automatiquement à la palette suivante.
- Choix de la map, avec une option « Aléatoire ». Le match se joue au meilleur des 3 rounds, configurable à 1, 3 ou 5.
- Sur iPhone, le versus local n'est pas proposé, faute de place pour deux manettes virtuelles. **[À trancher en playtest]** : un mode « iPad à deux », avec une manette par côté.

### 3.4 En ligne (« matchmaking sur le serveur »)
- Le joueur ne voit **que** les membres de son groupe : son cercle de copains, via le code de groupe. **Il n'y a pas de matchmaking public avec des inconnus** (enfants, cf. pilier 5).
- **Salon** : liste des membres du groupe en ligne (présence, §9.3) avec leur carte de joueur. Actions possibles :
  - **Défier** un copain : il reçoit une invitation, avec 20 secondes pour accepter.
  - **Match rapide** : appariement automatique avec n'importe quel membre du groupe en attente.
  - **Code de salle** : salle privée à 4 lettres, pour un ami qui n'est pas dans le groupe. **[À trancher]** si utile en v1.
- **Choix de la map** : chacun propose une map. Si les choix sont identiques, c'est celle-là ; sinon, une roulette visuelle tire entre les deux. Chacun choisit librement son combattant et son costume, avec un compte à rebours de 30 s. À la fin du chrono, le favori du profil est sélectionné.
- Le match se joue au meilleur des 3 rounds. À la fin : « Revanche ? » (les deux doivent accepter) ou retour au salon.
- **Classement de groupe** : un score Elo simplifié (K=32, départ 1000), plus les victoires et défaites. Le résultat n'est enregistré que si **les deux clients rapportent le même vainqueur**, avec le même checksum final (§9.5).

### 3.5 Entraînement
- Un mannequin, « Hondar », bonhomme de sable inerte (palette sable de la Grande Plage), qui peut aussi bloquer, sauter ou répéter un coup.
- Affichage de la **liste des coups**, de l'historique des entrées et des dégâts du combo. C'est l'écran clé pour que Louis apprenne les spéciaux.

---

## 4. Système de combat

Le principe : **profondeur MK, simplicité Smash.** Tout se joue avec 4 boutons et une direction.

### 4.1 Entrées abstraites
La sim ne connaît qu'un **masque de bits par frame et par joueur**, `InputFrame` (§8.3) :

| Bit | Nom | Clavier J1 (défaut) | Clavier J2 (défaut) | Manette | Tactile |
|---|---|---|---|---|---|
| 0–3 | Haut / Bas / Gauche / Droite | W S A D | ↑ ↓ ← → | stick G / croix | joystick virtuel |
| 4 | **POING** | J | Num1 (ou `,`) | X / □ | bouton rouge |
| 5 | **PIED** | K | Num2 (ou `.`) | A / ✕ | bouton vert |
| 6 | **SPÉCIAL** | L | Num3 (ou `/`) | B / ○ | bouton or |
| 7 | **GARDE** | Espace / I | Num0 (ou `Shift droit`) | R1 / RB | bouton bleu |

En solo, J1 accepte **aussi** les flèches et les touches J/K/L/Espace, pour qu'il n'y ait jamais de confusion. Les touches sont reconfigurables dans les Réglages (persistées dans `user://`).

Les directions sont **relatives** à l'orientation du combattant : « avant » = vers l'adversaire. La sim convertit gauche/droite en avant/arrière.

### 4.2 Mouvements de base (communs à tous)
- **Marcher** avant/arrière. **S'accroupir** (Bas). **Sauter** : neutre, avant ou arrière (Haut, avec une diagonale possible).
- **Courir** : double appui sur Avant. Utile mais pas obligatoire.
- **Garder** (GARDE maintenu) : il n'y a qu'une garde haute et une garde basse (accroupi + GARDE). Un coup « bas » (balayette) doit être gardé accroupi, un coup « aérien » debout ; tout le reste se garde dans les deux positions. Sur garde, les **spéciaux infligent 15 % des dégâts** (chip) et les coups normaux 0. **Pas de K.O. par chip** : on garde toujours au moins 1 PV.
- **Se relever** après une chute : relevé automatique, avec une invincibilité courte (20 frames). Une option « relevé rapide » en appuyant sur GARDE à la réception.

### 4.3 Coups normaux (communs, animation propre à chaque personnage)
| Entrée | Coup | Propriété |
|---|---|---|
| POING | Direct | Rapide. **Auto-combo** : POING, POING, POING enchaîne 3 coups (le 3ᵉ repousse). |
| PIED | Coup de pied | Plus lent, plus de portée. |
| Avant + PIED | Pied haut | Grande portée. |
| Bas + POING | Petit coup accroupi | Le plus rapide du jeu. |
| **Bas + PIED** | **Balayette** | Coup **bas**, fait chuter. |
| **Arrière + POING accroupi** ou **Bas puis Haut + POING** | **Uppercut** (« Txapel-cut ») | Le coup signature MK : envoie en l'air, gros dégâts, gros hitstop. Il doit être *jouissif*. |
| Saut + POING / PIED | Coup sauté | Coup « aérien » (se garde debout). |
| Avant + POING au contact | **Projection** | Inesquivable par la garde. On la « tech » avec POING dans les 10 frames : les deux combattants sont alors repoussés. |

### 4.4 Spéciaux et super
- **SPÉCIAL + direction** donne 4 spéciaux par personnage : **Neutre**, **Avant**, **Bas** et **Haut**. Haut est en général un anti-aérien ou un déplacement.
- **Entrées « à l'ancienne »**, bonus clavier et manette pour les experts : chaque spécial a **aussi** une manipulation MK (ex. `Arrière, Avant + POING`). Elle donne **+10 % de dégâts**. C'est une récompense pour les experts, jamais une obligation.
- **Jauge « Marée »** (3 segments) : elle se remplit en donnant et en recevant des coups.
  - **1 segment** : *Spécial renforcé* (SPÉCIAL + GARDE + direction), avec plus de dégâts et de propriétés.
  - **3 segments** : **Super « Coup du Txapeldun »** (SPÉCIAL + GARDE sans direction, ou deux doigts sur le pad). L'écran s'assombrit, une vague passe en fond, un insert portrait de 0,5 s est suivi d'une séquence de 2 à 4 coups. Dégâts : 30 % de la vie max.
- **Retour de vague** (anti-frustration, comparable au X-Ray/Fatal Blow) : une fois par match, sous 25 % de vie, la jauge se remplit instantanément. Le jeu affiche « LA MARÉE MONTE ! ».

### 4.5 Fin de match : le finish « BUKATU ! » (*bukatu* = finir, en basque)
- Après le dernier round, l'adversaire titube 4 secondes et « BUKATU ! » s'affiche. L'entrée commune est **Bas, Bas + SPÉCIAL**, à moins de 2 corps de distance. Il n'y a pas de manipulation propre à chaque personnage, pour que les enfants y arrivent.
- Le **finish est toujours comique et non violent**, propre à chaque personnage (§5.1). Il dure 3 à 5 s et se termine par « PLOUF ! », « FIESTA ! » ou « ZORIONAK ! » (félicitations).
- Un finish réussi rapporte un bonus de score et une stat. En ligne, il est désactivable par l'un ou l'autre joueur via le réglage « Combats express ».

### 4.6 Règles d'un match
- **Vie** : 1000 PV (le boss en a 1400). **Timer** : 60 secondes réelles par round, ce qui est plus lisible pour un enfant qu'un décompte de 99.
- Le match se joue au meilleur des 3 rounds. En cas d'égalité au chrono, c'est le pourcentage de vie restante qui départage ; en cas d'égalité parfaite, les deux marquent.
- Sur le HUD, les **rounds gagnés** sont des **petites txapelas** rouges.
- **Arène** : murs invisibles aux bords du stage. La caméra contraint les deux combattants dans la vue (distance max = largeur vue − 2×24 px).

### 4.7 Ressenti (game feel), tous paramètres en données
| Paramètre | Valeur de départ | Note |
|---|---|---|
| Tick de simulation | **60 Hz fixe** | Indépendant du framerate d'affichage. |
| Hitstop coup léger / lourd / uppercut / super | 4 / 8 / 14 / 20 frames | Les deux combattants se figent. |
| Screen shake | 0 / 2 / 4 / 6 px | Décroissance sur 10 frames, pixel-snappé. |
| Recul sur coup / sur garde | 6 / 10 px | Au coin, c'est l'attaquant qui recule. |
| Buffer d'entrée | **8 frames** | Généreux, pour enfants. Un spécial entré pendant la récupération sort dès que possible. |
| Fenêtre d'auto-combo | 14 frames | |
| Dégâts en combo (scaling) | 100 %, 90 %, 80 %… min 40 % | Empêche les combos infinis. |
| Combo max | Après 6 coups, l'adversaire tombe automatiquement. | Anti-frustration. |
| Facile : aide | L'IA bloque moins, et le joueur a un *auto-guard* sur 30 % des coups s'il ne touche à rien. | Seulement en Facile solo. |

### 4.8 Données de coups (frame data)
Chaque coup est décrit dans le JSON du combattant (§8.5) : `startup`, `active`, `recovery`, `damage`, `hitstun`, `blockstun`, `pushback`, `hit_level` (`mid`|`low`|`air`|`throw`|`unblockable`), `knockdown`, `launch` (vecteur), `cancel_into` (liste), `meter_gain`, `hitstop`, `sfx`, `vfx`, ainsi que des **hitboxes par frame active** (rects relatifs au pied du personnage, en px). Les **hurtboxes** sont générées automatiquement (§11.6) et surchargeables.

---

## 5. Le roster

Les 12 personnages et le boss sont tous **fictifs** (aucune personne réelle). Seul **Louis** reprend le héros du jeu original. Les noms sont basques ou locaux.

### 5.1 Fiches

Légende des spéciaux : **N**eutre, **A**vant, **B**as, **H**aut (avec SPÉCIAL). Entre crochets, la manipulation classique.

| # | Combattant | Archétype | Look (silhouette d'abord) | Spéciaux | Super « Txapeldun » | Finish « Bukatu » | Stage maison | Rival |
|---|---|---|---|---|---|---|---|---|
| 1 | **Louis** — l'enfant du pays | Équilibré (le « Ryu ») | Blond, **béret rouge**, chemise blanche, ceinture rouge, espadrilles | N : **Espadrille boomerang** (projectile qui revient) [↓↘→+P] · A : **Charge du béret** (coup d'épaule glissé) · B : **Balayette d'écume** (glissade basse) · H : **Saut du Phare** (uppercut montant, invulnérable au départ) | Enchaînement espadrilles + béret lancé qui tourne autour de l'adversaire | Lui enfonce son béret jusqu'aux épaules ; l'adversaire tourne en rond, perdu, avant de tomber dans un seau d'eau | Grande Plage | Maïa |
| 2 | **Maïa** — surfeuse de la Côte des Basques | Rapide, rushdown | Combinaison turquoise, cheveux mouillés, **planche dans le dos** | N : **Coup de planche** (balayage large) · A : **Glisse** (traverse l'écran sur une langue d'eau, touche 2×) · B : **Rouleau** (vague basse qui avance au sol) · H : **Aerial** (saut avec rotation de planche) | Surfe une énorme vague qui roule sur l'adversaire | Une vague emporte l'adversaire au large, il revient en bouée canard | Côte des Basques | Louis |
| 3 | **Patxi** — pêcheur du Port | Lutteur, contrôle | Ciré jaune, bonnet bleu, barbe, **canne à pêche** | N : **Lancer de sardines** (3 petits projectiles en éventail) · A : **« Viens par ici ! »** (ligne + hameçon qui ramène l'adversaire, l'hommage MK) · B : **Filet** (immobilise 40 frames) · H : **Rame tournoyante** (anti-aérien) | Pêche l'adversaire, le fait tourner au-dessus de sa tête et le relâche | Le met dans un énorme filet, une mouette se pose sur sa tête | Port des Pêcheurs | Kaio |
| 4 | **Xabi** — pelotari | Zoneur, projectiles | Tenue blanche, **chistera** (gant d'osier) au bras droit, ceinture rouge | N : **Pelote** (projectile très rapide) · A : **Pelote rasante** (projectile bas) · B : **Rebond de fronton** (la pelote rebondit sur un mur imaginaire et revient de derrière) · H : **Pelote en cloche** (arc, anti-saut) | Une rafale de 6 pelotes, la dernière géante | Une pelote géante lui tombe dessus façon cloche, « CHAPEAU ! » | Le Fronton | Peio |
| 5 | **Mattin** — leveur de pierre (*harri-jasotzaile*) | Lourd, lent, gros dégâts | Énorme, maillot rayé rouge et blanc, **pierre de granit** | N : **Lancer de pierre** (projectile lourd et lent) · A : **Bélier** (charge, super-armure 1 coup) · B : **Séisme** (frappe le sol, onde basse, à sauter) · H : **Soulevé** (projection anti-aérienne) | Soulève l'adversaire comme une pierre, 3 tours d'épaule et le pose | Le pose sur un socle de pierre ; l'adversaire devient une statue « exposée » au musée | Les Halles | Karramarro |
| 6 | **Amaia** — dantzari (danseuse basque) | Technique, coups de pied | Jupe rouge, gilet vert, rubans, **makila** (bâton basque) | N : **Moulinet de makila** (zone devant elle) · A : **Entrechat** (saut avant + coup de pied, passe les projectiles bas) · B : **Fandango** (pirouette basse, 3 coups) · H : **Saut du *zortziko*** (coup de pied en ciseaux montant) | Danse en cercle, l'adversaire est pris dans le rythme et prend 8 coups | Force l'adversaire à danser le fandango, il s'effondre essoufflé | Rocher de la Vierge (passerelle) | Itsaso |
| 7 | **Txomin** — maître-nageur sauveteur | Contrôle, étourdissement | Short rouge, débardeur jaune, lunettes de soleil, **sifflet**, **palmes à la ceinture** | N : **Coup de sifflet** (onde sonore, étourdit 30 frames, courte portée) · A : **Lancer de palmes** (lance une palme qui tournoie) · B : **Pavillon rouge** (pose un drapeau : zone « baignade interdite », l'adversaire y est ralenti) · H : **Plongeon** (saut et retombée en piqué) | Plongeon depuis une chaise de surveillance géante | Réanime l'adversaire au bouche-à-bouche… avec un poisson. L'adversaire s'enfuit en hurlant | Grande Plage (variante soir) | Maïa |
| 8 | **Kaio** — le goéland voleur | Aérien, harcèlement | **Goéland** anthropomorphe, gros bec jaune, sac de chips volé | N : **Fiente !** (projectile en cloche, comique) · A : **Piqué** (dash aérien diagonal) · B : **Vol à l'étalage** (vole 10 % de jauge Marée) · H : **Envol** (vol stationnaire 1 s, triple saut) | Nuée de goélands qui picorent | Vole les chaussures (puis le pantalon : on voit un caleçon à cœurs) de l'adversaire | Port Vieux | Patxi |
| 9 | **Karramarro** — le crabe des rochers | Défensif, armure | **Crabe géant** debout, carapace orange, pinces énormes | N : **Bulles** (projectile lent qui flotte) · A : **Pas de côté** (déplacement latéral éclair, passe à travers) · B : **Carapace** (contre : si frappé, riposte en pince) · H : **Pince-ciel** (anti-aérien) | Pince l'adversaire et le fait sauter comme une crêpe | Pince le nez de l'adversaire et ne le lâche pas | Rocher de la Vierge | Mattin |
| 10 | **Ramuntxo** — le chef des Halles | Polyvalent, pièges | Toque, tablier blanc, foulard rouge, **louche** | N : **Piment d'Espelette** (souffle de feu court, « CA PIQUE ! ») · A : **Jambon de Bayonne** (gourdin, grosse portée) · B : **Gâteau basque** (pose un gâteau : qui marche dessus glisse) · H : **Poêle à l'envers** (anti-aérien, ricoche sur les projectiles) | Prépare une piperade géante à la poêle et sert l'adversaire dedans | Lui verse une marmite de chocolat chaud de Bayonne sur la tête | Les Halles | Kaio |
| 11 | **Itsaso** — l'esprit de l'écume | Mystique, téléportation | Jeune femme faite d'écume et d'eau turquoise, cheveux en vague, pieds nus sur une flaque | N : **Perle** (projectile qui ralentit) · A : **Ressac** (téléportation derrière l'adversaire) · B : **Marée basse** (piège au sol, aspire les pieds) · H : **Geyser** (colonne d'eau, anti-aérien) | Marée qui monte : l'écran se remplit d'eau, l'adversaire flotte et prend des coups | Transforme l'adversaire en château de sable, une vague l'efface | Côte des Basques (crépuscule) | Amaia |
| 12 | **Peio** — rugbyman du « BO » de Biarritz (fictif, couleurs rouge et blanc, sans logo) | Puissant, charges | Maillot rouge et blanc, short noir, **ballon ovale**, oreilles en chou-fleur | N : **Drop** (ballon en cloche, anti-saut) · A : **Plaquage** (charge, projection en course) · B : **Raffut** (poussée qui renverse les projectiles) · H : **Touche** (attrape aérien, comme une chandelle) | Mêlée : 7 coéquipiers fantômes poussent l'adversaire | Transforme l'adversaire en poteau de rugby ; Peio passe une transformation entre ses bras | Stade (Aguilera, version générique) | Xabi |

**Fins illustrées** : une image RD en 3 cadrages (§11.5) et 3 phrases chacune, ton conte d'été. Exemple pour Louis : (1) « Louis rapporte la txapela à la Grande Plage. » (2) « Toute la plage scande son nom. » (3) « Mais au loin, un goéland lorgne déjà le béret… »

### 5.2 Rééquilibrage
- Les archétypes sont différents, mais les **vitesses de marche et les PV restent proches** : ±10 % maximum, et ±20 % pour Mattin et Kaio. On équilibre avec un *tier list* calculé par simulation IA contre IA (§14.4) : aucun personnage ne doit gagner moins de 40 % ni plus de 60 % de ses matchs contre l'ensemble.

### 5.3 Boss : le Gardien du Phare (*Itsasargi*)
- Un vieux gardien de 1,3 fois la taille d'un combattant, en caban marin, avec une **lanterne** et une longue-vue. Il a 1400 PV et ne subit pas de recul sur les coups légers.
- Spéciaux : **Faisceau** (rayon de lumière horizontal, à sauter ou à garder), **Brume** (devient intangible 1 s), **Corne de brume** (onde qui repousse), **Rotation de la lentille** (faisceau qui balaie de haut en bas).
- Stage : sommet du Phare, la nuit, avec le faisceau qui tourne en fond.
- Il devient jouable une fois battu. Son finish : il éclaire l'adversaire, qui se transforme en papillon de nuit attiré par la lumière.

### 5.4 Costumes (palettes alternatives, façon MK)
- 4 palettes par personnage. La **palette 1** est le défaut. La 2 se débloque après **5 victoires** avec ce personnage, la 3 en terminant la **pyramide** avec lui, la 4 en terminant la **pyramide en Expert**.
- C'est un pur **swap de palette par shader** (§10.4), sans aucun sprite en plus. Exemples : Louis en béret vert (ikurriña), Maïa en combinaison corail, Patxi en ciré rouge, Peio en maillot de l'équipe adverse bleue.

### 5.5 Mannequin d'entraînement « Hondar »
C'est un bonhomme de sable : on réutilise les animations d'un personnage de base, avec une palette sable. Il n'a pas de spéciaux.

---

## 6. Les stages (maps)

Les **10 stages** sont tous reconnaissables par un Biarrot. Chacun a un fond large qui défile en parallaxe, un sol jouable et 1 ou 2 éléments animés d'ambiance. **Aucun danger de stage en v1.**

| ID | Stage | Source (photo i2i) | Ambiance animée | Variante |
|---|---|---|---|---|
| `grande_plage` | Grande Plage, devant le Casino art déco | `grande plage 1.webp` (existant) | vagues qui s'étalent, parasols, goélands | `grande_plage_soir` (coucher de soleil, Txomin) |
| `cote_basques` | Côte des Basques, Villa Belza sur la falaise | `cote des basques.jpg.webp` | surfeurs au loin, vagues | `cote_basques_crepuscule` (Itsaso) |
| `port_pecheurs` | Port des Pêcheurs | `port des pêcheurs.jpg` | bateaux qui tanguent, mouettes | — |
| `rocher_vierge` | Passerelle Eiffel du Rocher de la Vierge | `cote des basques.jpg.webp` (crop rocher) | embruns qui jaillissent derrière la rambarde | — |
| `port_vieux` | Crique du Port Vieux | `port vieux 2.jpg` | baigneurs stylisés au loin (silhouettes), eau turquoise | — |
| `halles` | Les Halles de Biarritz (intérieur, étals) | **photo à fournir par Julien** (sinon txt2img) | foule d'étals, jambons suspendus qui se balancent | — |
| `fronton` | Fronton de pelote basque, mur rose, public sur gradins | photo à fournir (sinon txt2img) | public qui applaudit (3 frames) | — |
| `stade` | Stade de rugby rouge et blanc (générique, sans logo) | txt2img | tribunes, drapeaux | — |
| `aquarium` | Aquarium du Musée de la Mer (grand bassin bleu) | photo à fournir (sinon txt2img) | poissons, phoques qui passent | — |
| `phare_sommet` | Sommet du Phare de Biarritz, la nuit | `bg_lighthouse_intro` (existant) + txt2img | **faisceau tournant**, étoiles, ville éclairée | boss uniquement + débloqué ensuite |

**Sélection** : vignettes animées et nom du lieu en lettrage basque (§10.3). Une option « Aléatoire » représentée par un lauburu qui tourne.

**Musique** : un thème par stage (§12).

---

## 7. Contrôles (ordinateur et iPhone)

### 7.1 Architecture d'entrée
```
Sources (KeyboardSource, GamepadSource, VirtualPadSource, GestureSource, AiSource, NetRemoteSource)
   └─► InputHub (autoload) : assigne une source à chaque slot de joueur, échantillonne
        UNE FOIS par tick de sim ─► InputFrame (int 8 bits) ─► FightSim
```
- **Aucun code de jeu ne lit les `InputEvent` bruts**, sauf les sources. C'est la même règle que l'ancien `touch_input.gd`.
- Les menus utilisent les actions Godot standard (`ui_*`), **plus** le tactile direct (gros boutons). La navigation au clavier ou à la manette doit marcher dans tous les menus.

### 7.2 Clavier et manette
- Mappings du §4.1. Les manettes passent par l'API Gamepad (Godot `Input.get_joy_*`, supporté en web). Il faut un premier appui pour « réveiller » la manette sous Chrome ; afficher « Appuie sur un bouton de la manette ».
- Écran **Réglages > Contrôles** : réassignation touche par touche, plus « Réinitialiser ».

### 7.3 iPhone : manette virtuelle (mode par défaut)
- **Joystick flottant** dans la moitié gauche de l'écran. Il apparaît là où le pouce se pose : rayon 56 px logiques × échelle, zone morte de 25 %, et 8 directions numériques avec une **hystérésis angulaire de 10°** pour éviter le tremblement entre deux directions.
- **4 boutons en losange** dans la moitié droite : POING (rouge), PIED (vert), SPÉCIAL (or, le plus gros), GARDE (bleu). Diamètre ≥ **64 pt physiques** (cibles généreuses, pouces d'enfant). Ils sont translucides et affichent une icône (poing, espadrille, lauburu, bouclier). Ils s'éclairent au toucher.
- **Glisser d'un bouton à l'autre** sans lever le doigt est autorisé (roll), par exemple de POING vers SPÉCIAL.
- **Multitouch** : chaque toucher est suivi par son `index`, qui est **arbitraire sur iOS**. Une table `index → contrôle` est attribuée au `pressed` et libérée au `released`. Il faut tester avec des index aléatoires (QaCapture, §14).
- **Raccourci super** : un bouton « MARÉE » s'affiche au-dessus du losange quand la jauge est pleine. Un appui déclenche le super.
- **Zones sûres** : tout le HUD et les contrôles respectent `DisplayServer.get_display_safe_area()` (encoche et barre d'accueil de l'iPhone). Rien d'essentiel dans les 44 pt du bord.
- **Retour haptique** : `Input.vibrate_handheld(20)` sur un coup porté, si le navigateur le supporte (pas sur iOS Safari : on ignore silencieusement).
- **Option** : taille des boutons (S/M/L) et opacité, persistées.

### 7.4 iPhone : mode « Gestes » (alternative, Réglages)
| Zone | Geste | Action |
|---|---|---|
| Moitié gauche | Maintenir et glisser | Déplacement (stick relatif) |
| Moitié gauche | Swipe haut / bas | Saut / accroupi |
| Moitié droite | Tap | POING (taps rapides = auto-combo) |
| Moitié droite | Swipe vers l'adversaire | PIED (pied haut) |
| Moitié droite | Swipe haut / bas / arrière | SPÉCIAL Haut / Bas / Neutre |
| Moitié droite | Double tap | SPÉCIAL Avant |
| Moitié droite | Appui long (> 180 ms) | GARDE (tant que maintenu) |
| N'importe où | Tap à deux doigts | Super (jauge pleine) |

Seuil de swipe : 28 px logiques en moins de 220 ms. Les gestes produisent le **même `InputFrame`**, et la sim ne fait aucune différence.

### 7.5 Tutoriel intégré
Au premier lancement, après la création du profil : un **combat d'apprentissage** contre Hondar, en 6 étapes guidées (bouger, frapper, garder, uppercut, spécial, super). Chaque étape attend que le geste soit réussi. Il est passable et rejouable depuis Entraînement.

---

## 8. Architecture technique

### 8.1 Arborescence cible
```
miarritze/
├── SPEC-BORROKA.md                 # ce fichier
├── DESIGN.md, CLAUDE.md            # régénérés en Phase 0 depuis la spec
├── docs/DECISIONS.md               # journal des choix [À trancher]
├── project.godot, export_presets.cfg
├── assets/
│   ├── fighters/<id>/              # sheet.png (indexée), palettes.png, portrait*.png, ending_*.png, data.json
│   ├── stages/<id>/                # far.png, mid.png (opt.), floor.png, anim_*.png, stage.json
│   ├── vfx/                        # impacts, projectiles, poussières, écume
│   ├── ui/                         # cadres, boutons, icônes, logo, bannières, police
│   ├── fonts/
│   └── audio/{music,sfx,voice}/
├── src/
│   ├── autoload/
│   │   ├── profiles.gd             # (remplace GameState) profils locaux + sync
│   │   ├── api.gd                  # (remplace LeaderboardClient) client HTTP de l'API
│   │   ├── input_hub.gd            # sources ↔ slots joueurs
│   │   ├── audio_manager.gd        # gardé + bus
│   │   ├── scene_router.gd         # gardé
│   │   ├── orientation_overlay.gd  # gardé
│   │   └── qa_capture.gd           # gardé + étendu
│   ├── fight/
│   │   ├── sim/                    # 100 % déterministe, aucun Node, aucun float
│   │   │   ├── fight_sim.gd        # état du match + step(inputs)
│   │   │   ├── fighter_state.gd
│   │   │   ├── projectile_state.gd
│   │   │   ├── move_runner.gd      # exécute la frame data
│   │   │   ├── collision.gd        # AABB hit/hurt/push
│   │   │   ├── input_buffer.gd     # buffer 8 frames, détection des manips
│   │   │   ├── fx_events.gd        # événements émis pour la vue (son, vfx, shake)
│   │   │   └── xrng.gd             # xorshift32 maison
│   │   ├── data/fighter_db.gd      # charge assets/fighters/*/data.json → structures typées
│   │   ├── view/                   # lit l'état de la sim, ne le modifie jamais
│   │   │   ├── fight_scene.tscn/.gd
│   │   │   ├── fighter_view.gd     # sprite indexé + shader palette
│   │   │   ├── stage_view.gd       # parallaxe + anims
│   │   │   ├── fight_camera.gd
│   │   │   ├── hud.gd              # vie, jauge, timer, rounds (txapelas), noms
│   │   │   ├── announcer.gd        # « BORROKA ! », « PLOUF ! », « BUKATU ! »
│   │   │   └── vfx_pool.gd
│   │   ├── ai/ai_brain.gd          # produit des InputFrame
│   │   └── modes/                  # orchestration : tower_mode.gd, versus_mode.gd, online_mode.gd, training_mode.gd
│   ├── input/                      # sources (§7)
│   ├── net/
│   │   ├── signaling.gd            # dialogue PHP (polling)
│   │   ├── p2p_link.gd             # WebRTCPeerConnection + data channels
│   │   └── rollback_session.gd     # rollback + délai, checksums
│   └── ui/
│       ├── boot/ title/ profile_select/ profile_edit/ main_menu/
│       ├── fighter_select/ stage_select/ tower/ versus_splash/
│       ├── lobby/ results/ ending/ training_menu/ settings/ move_list/
│       └── widgets/                # bouton pixel, carte de joueur, cadre basque…
├── backend/                        # §9
└── tools/                          # §11, §12
    ├── palette.py                  # étendue
    ├── rd/                         # client v2 + scripts de génération
    ├── sprites/                    # post-traitement, hitbox, indexation, planches
    ├── mannequin/                  # sprites placeholder procéduraux
    ├── gen_audio.py
    └── legacy/
```

### 8.2 Déterminisme (règles)
La sim tourne identiquement sur deux navigateurs différents. Cela permet le rollback en ligne, les replays et l'équilibrage IA contre IA.
- **Aucun `float`** dans `src/fight/sim/` : positions et vitesses en **entiers « sous-pixels »** (1 px = 256 unités). Un test lint (§14) échoue si `float`, `randf`, `randi`, `Time.`, `OS.` ou `Engine.` apparaissent dans `sim/`.
- **RNG** : `XRng` (xorshift32), graine fixée au début du match et partagée en ligne.
- **Aucun nœud ni signal** dans la sim : de simples classes `RefCounted`. La sim **émet des événements** (`fx_events`) dans un tableau que la vue consomme après chaque tick **confirmé**. En rollback, la vue rejoue sans dupliquer les sons (§8.6).
- **Ordre d'itération fixe** : J1 puis J2, projectiles par ID croissant.
- **`save_state() -> PackedByteArray`** et **`load_state(bytes)`** : sérialisation compacte de tout l'état. Taille cible < 1 Ko.
- **`checksum() -> int`** : hash FNV-1a de l'état sérialisé.

### 8.3 InputFrame
`int` sur 8 bits : `UP=1, DOWN=2, LEFT=4, RIGHT=8, PUNCH=16, KICK=32, SPECIAL=64, GUARD=128`. La sim garde l'historique dans `InputBuffer` pour détecter les appuis (front montant), les doubles tapes et les manipulations à l'ancienne (fenêtre de 20 frames).

### 8.4 Boucle d'affichage
- `fight_scene.gd::_physics_process` avec `Engine.physics_ticks_per_second = 60`. On fait au plus 1 tick de sim par physics frame en local, un rattrapage en ligne (§8.6), puis la vue interpole **sans** float côté sim (la vue a le droit aux floats).
- **Résolution logique 384×216**, `stretch_mode = viewport`, `aspect = expand`. Le paramètre `scale_mode` (`integer` ou `fractional`) est **[À trancher]** après test sur iPhone : on prend `integer` si les bandes sont acceptables, sinon `fractional` avec filtre nearest. Avec `aspect = expand`, la largeur logique peut monter à environ 468 sur un iPhone en 19,5:9. Stages et caméra doivent le supporter (§10.6).

### 8.5 Format de données d'un combattant (`assets/fighters/<id>/data.json`)
```json
{
  "id": "louis",
  "name": "Louis",
  "title": "L'enfant du pays",
  "archetype": "equilibre",
  "health": 1000,
  "walk_fwd": 640, "walk_back": 512, "run": 1100,
  "jump_v": -2300, "gravity": 120, "jump_h": 700,
  "push_w": 22, "push_h": 70,
  "palettes": "palettes.png",
  "palette_roles": {"outfit_a": [5,6,7], "outfit_b": [8,9], "hat": [10,11,12], "skin": [1,2,3]},
  "anims": {
    "idle":   {"row": 0, "frames": 8, "fps": 10, "loop": true},
    "punch":  {"row": 6, "frames": 6, "fps": 20, "loop": false}
  },
  "moves": {
    "punch_1": {
      "anim": "punch", "input": "P", "startup": 4, "active": 2, "recovery": 8,
      "damage": 40, "hitstun": 14, "blockstun": 10, "pushback": 6, "hit_level": "mid",
      "hitstop": 4, "meter_gain": 4, "cancel_into": ["punch_2", "specials"],
      "hitboxes": {"4": [[18, -62, 22, 12]], "5": [[18, -62, 22, 12]]},
      "sfx": "hit_light", "vfx": "spark_s"
    },
    "sp_neutral": {
      "anim": "sp_neutral", "input": "S", "classic": "D,DF,F+P",
      "spawn": {"frame": 9, "projectile": "espadrille", "offset": [24, -58]}
    }
  },
  "projectiles": {
    "espadrille": {"anim": "proj_espadrille", "speed": 1400, "returns": true, "damage": 70, "hitbox": [-8,-6,16,12], "life": 90}
  },
  "hurtbox_overrides": {},
  "ai": {"aggression": 0.5, "zoning": 0.4, "anti_air": 0.6, "favorite_moves": ["sp_neutral", "uppercut"]},
  "ladder_rival": "maia",
  "home_stage": "grande_plage",
  "ending": ["ending_0.png", "ending_1.png", "ending_2.png"],
  "ending_text": ["…", "…", "…"]
}
```
Les coordonnées sont en px, relatives au **pied du personnage** (x vers l'avant, y vers le haut négatif). Les vitesses sont en sous-pixels par frame. Un validateur JSON (`tools/sprites/validate_fighter.py`) tourne en CI.

### 8.6 Netcode : rollback et délai
- **Délai d'entrée** : 2 frames par défaut, ajusté automatiquement entre 1 et 4 selon le RTT mesuré (`délai = clamp(ceil(RTT/2 / 16.7ms), 1, 4)`).
- **Rollback** : jusqu'à **8 frames** de prédiction. On prédit l'entrée distante = dernière entrée connue. À la réception d'une entrée réelle différente, on fait `load_state(frame)` puis on resimule jusqu'au présent. Au-delà de 8 frames d'avance, **on gèle la sim locale** (stall) et on affiche une icône « vague » de connexion.
- **Paquet d'entrée** (data channel non fiable, non ordonné) : `[u8 type=1][u32 frame][u8 n][n × u8 inputs][u32 ack_frame]`. Chaque paquet transporte les **8 dernières entrées locales** (redondance contre les pertes), envoyé chaque tick.
- **Checksums** : toutes les 60 frames confirmées, on échange `[type=2][frame][u32 checksum]`. En cas de désaccord, on enregistre un log de désynchro (états + entrées) téléchargeable en debug, et le match se termine en « match nul technique », sans Elo.
- **Vue et sons en rollback** : les événements `fx_events` portent la frame d'origine. La vue ne joue un son ou un vfx **qu'une fois** par (frame, type, acteur) ; une resimulation qui supprime un coup peut couper les vfx encore actifs.
- **Pause** : impossible en ligne. Un onglet en arrière-plan (`NOTIFICATION_APPLICATION_FOCUS_OUT`, `visibilitychange`) déclenche un **forfait après 10 s**, avec un compte à rebours visible des deux côtés.
- **Implémentation progressive** (§15) : faire d'abord fonctionner le **délai seul** (lockstep, rollback désactivé), puis activer le rollback. Le design de la sim (save/load) est là dès la Phase 2.

---

## 9. Réseau : WebRTC P2P + PHP

### 9.1 Principe
Le serveur LAMP ne fait **pas** de temps réel : il gère la présence, les invitations, les matchs et **la signalisation WebRTC par polling HTTP**. Le combat lui-même passe en **pair-à-pair** (data channels WebRTC, supportés nativement par l'export web de Godot via `WebRTCPeerConnection`).

### 9.2 Connexion P2P (côté Godot)
```gdscript
var pc := WebRTCPeerConnection.new()
pc.initialize({"iceServers": ice_servers})            # reçus de GET /api/net/config
var ch_input := pc.create_data_channel("input", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
var ch_ctrl  := pc.create_data_channel("ctrl",  {"negotiated": true, "id": 2})   # fiable, ordonné
pc.session_description_created.connect(func(t, sdp): pc.set_local_description(t, sdp); signaling.send({"kind": t, "sdp": sdp}))
pc.ice_candidate_created.connect(func(m, i, n): _pending_ice.append([m, i, n]))  # envoyés par lots toutes les 300 ms
# appeler pc.poll() à chaque frame ; l'hôte (player_id le plus petit) crée l'offre
```
- **ICE** : `GET /api/net/config` renvoie `{"ice_servers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]}`, avec des serveurs **TURN** optionnels ajoutables côté `config.php` sans recompiler le jeu. C'est **[À trancher]** plus tard, si des échecs NAT apparaissent : un coturn sur un petit VPS.
- **Délai de connexion** : 15 s maximum. En cas d'échec, afficher : « Impossible de relier vos deux appareils. Essayez sur le même Wi-Fi, ou réessayez. » La cause est loguée côté serveur (`/api/net/report`).
- Les data channels négociés (`negotiated: true`) évitent un aller-retour de signalisation. Vérifier en Phase 6 qu'ils fonctionnent dans Safari iOS ; sinon, revenir au mode non négocié.

### 9.3 Schéma SQLite (remplace `scores`)
```sql
-- groups, players : inchangés (players.secret = jeton d'auth)

CREATE TABLE profiles (                    -- carte de joueur publique dans le groupe
  player_id   INTEGER PRIMARY KEY REFERENCES players(id),
  fighter     TEXT NOT NULL DEFAULT 'louis',
  costume     INTEGER NOT NULL DEFAULT 0,
  banner      INTEGER NOT NULL DEFAULT 0,
  title       TEXT NOT NULL DEFAULT '',
  emote       INTEGER NOT NULL DEFAULT 0,
  stats_json  TEXT NOT NULL DEFAULT '{}',  -- victoires, txapelas… (validé côté serveur, taille max 4 Ko)
  rating      INTEGER NOT NULL DEFAULT 1000,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE presence (
  player_id   INTEGER PRIMARY KEY REFERENCES players(id),
  status      TEXT NOT NULL,               -- 'lobby' | 'queue' | 'busy'
  last_seen   INTEGER NOT NULL             -- heartbeat ; en ligne si < 15 s
);

CREATE TABLE matches (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL,
  p1          INTEGER NOT NULL, p2 INTEGER NOT NULL,     -- p1 = hôte (crée l'offre)
  state       TEXT NOT NULL,               -- invited|accepted|signaling|playing|finished|cancelled|expired
  stage_p1    TEXT, stage_p2 TEXT, stage TEXT,
  seed        INTEGER NOT NULL,
  winner_p1   INTEGER, winner_p2 INTEGER,  -- rapport de chaque client
  checksum_p1 INTEGER, checksum_p2 INTEGER,
  created_at  INTEGER NOT NULL, updated_at INTEGER NOT NULL
);

CREATE TABLE signals (                     -- boîte aux lettres de signalisation
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  match_id    INTEGER NOT NULL REFERENCES matches(id),
  to_player   INTEGER NOT NULL,
  payload     TEXT NOT NULL,               -- JSON {kind:'offer'|'answer'|'ice', ...}, max 16 Ko
  created_at  INTEGER NOT NULL
);
CREATE INDEX idx_signals_to ON signals(to_player, id);

CREATE TABLE tower_scores (
  player_id   INTEGER NOT NULL REFERENCES players(id),
  fighter     TEXT NOT NULL,
  difficulty  TEXT NOT NULL,
  best_score  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (player_id, fighter, difficulty)
);
```
Purge : signaux de plus de 10 min, matchs non finis de plus de 1 h (au fil de l'eau, 1 requête sur 50).

### 9.4 Routes (toutes authentifiées par `player_id` + `secret`, sauf mention)
| Méthode | Route | Rôle |
|---|---|---|
| POST | `/api/group`, `/api/group/join` | Inchangés |
| GET/POST | `/api/profile` | Lire/écrire la carte de joueur (validation : fighter ∈ roster, costume débloqué de façon *plausible*) |
| POST | `/api/presence` | Heartbeat toutes les 5 s au salon `{status}` → renvoie la liste des membres en ligne + **invitations entrantes** + match en cours (une seule requête pour tout, économie) |
| POST | `/api/match/invite` | `{to}` → crée un match `invited` (expire en 20 s) |
| POST | `/api/match/queue` | Match rapide : apparie avec un autre membre en `queue`, sinon passe en `queue` |
| POST | `/api/match/respond` | `{match_id, accept}` |
| POST | `/api/match/stage` | `{match_id, stage}` → dès que les 2 ont choisi : tirage côté serveur, `seed` |
| POST | `/api/signal` | `{match_id, payload}` → dépose pour l'autre joueur |
| GET | `/api/signal?match_id=&after=` | Récupère les messages (poll 250 ms pendant la signalisation seulement) |
| POST | `/api/match/report` | `{match_id, winner, checksum, rounds}` → si les 2 rapports concordent : Elo + stats |
| GET | `/api/net/config` | Serveurs ICE (sans auth) |
| POST | `/api/net/report` | Télémétrie d'échec de connexion (anonyme : type d'échec, navigateur) |
| POST | `/api/tower/score` | Score de pyramide (plafond de plausibilité dans `Validation.php`) |
| GET | `/api/leaderboard?code=&type=rating\|tower` | Classements du groupe |

Rate limits : présence 20/min, signal 240/min, autres 30/min, par joueur et par IP (mécanisme existant).

### 9.5 Intégrité (anti-triche légère, cohérente avec un jeu d'enfants)
- L'Elo n'est mis à jour que si `winner_p1 == winner_p2` et `checksum_p1 == checksum_p2` (checksum de l'état final).
- Un rapport manquant après 2 min laisse le match sans effet. Pas de punition.
- Pas de chat, pas de texte libre : les emotes sont des index 0 à 3.

---

## 10. Direction artistique

### 10.1 Intention
**« Arcade de bord de mer. »** L'énergie d'une borne d'arcade des années 90 rencontre la lumière de Biarritz en été. On garde ce qui marche dans l'existant : décors **issus de vraies photos** (i2i), palette chaude, contours brun-prune (jamais noirs purs), écume blanc cassé, rouge et vert basques. Ce qu'on ajoute :
- des **sprites grands et expressifs** : environ 100 px de haut sur 216, soit près de la moitié de l'écran comme dans MK ;
- un **cadre d'interface « bois de bateau et laiton »** : planches peintes, rivets, cordages, typographie en lettrage basque ;
- des **impacts lisibles** : étincelles en étoile, onomatopées pixelisées (« PAF ! », « TXAK ! », « PLOUF ! ») et éclaboussures selon le stage (sable, eau, farine aux Halles).

### 10.2 Palette
- On étend `tools/palette.py` à environ **64 couleurs**, groupées en **rampes** de 3 à 5 tons : peau (4 tons, plusieurs carnations), tissus (rouge basque, vert basque, bleu marine, turquoise, jaune ciré, blanc linge), métal et laiton, bois, écume et mer, nuit (Phare), UI.
- **Contour universel** : `outline` (58,38,52), conservé. **Lumière** venant d'en haut à gauche, comme dans les décors existants.
- Tous les sprites de combattants sont **re-quantifiés** sur cette palette (§11.3), et les décors restent quantifiés à leur propre palette RD : on n'impose pas 64 couleurs aux décors, qui ont plus de nuances. Un **filtre de cohérence** s'applique (saturation et teinte ajustées au gabarit commun, contrôlé par planche contact).
- **Lisibilité** : les combattants sont plus saturés et plus contrastés que les fonds. Un **voile de 15 %** (dégradé vers la couleur du ciel) s'applique sur le plan lointain pour décoller les personnages.

### 10.3 Typographie
- **Logo et titres** : lettrage inspiré de l'**« euskal letra »** (le lettrage basque traditionnel des frontons et des linteaux, empattements triangulaires). Il est dessiné **à la main en grilles ASCII**, avec la méthode de `gen_louis.py`, pour un jeu de capitales A–Z, des chiffres et `!?'` en 12×16 px. Le résultat est une police bitmap Godot (`FontFile` construite depuis une image + `tools/gen_font.py`).
- **Petits textes** : Press Start 2P (8 px), conservée.
- **Logo** « MIARRITZE / BORROKA » : lettrage basque rouge à contour or, avec un **lauburu** en guise de « O » de BORROKA, et une vague d'écume dessous. Il est animé : le lauburu tourne et l'écume bouge sur 3 frames.

### 10.4 Sprites de combattants : spécification technique
- **Cellule** : 128×128 px. Personnage de **96 à 110 px** de haut (Mattin 118, Kaio 88 hors ailes, boss 140 dans une cellule de 160). **Pied au point (64, 120)** de la cellule. Il regarde **vers la droite** ; la gauche s'obtient par miroir.
- **Feuille par personnage** : une rangée par animation, une colonne par frame. Format **indexé** : une texture `R8` où chaque valeur est l'index de palette (0 = transparent), plus `palettes.png` (32 couleurs × 4 costumes).
- **Shader de swap de palette** (`fighter_palette.gdshader`) : `COLOR = texture(palette, vec2((idx+0.5)/32.0, (costume+0.5)/4.0))`. Il prend aussi en charge le **flash blanc** à l'impact (2 frames), la teinte rouge en garde brisée et la silhouette noire avec contour or pour l'insert du super.
- **Liste des animations** (frames indicatives ; celles d'origine RD sont ensuite adaptées) :

| Animation | Frames | Notes |
|---|---|---|
| intro | 8 | pose d'entrée (Maïa plante sa planche, Patxi lance sa ligne…) |
| idle | 8 | boucle, respiration bien visible |
| walk | 8 | marche arrière = lecture inverse |
| run | 6 | |
| crouch / crouch_idle | 3 / 4 | |
| jump_up / jump_fwd / fall | 4 / 6 / 2 | jump_fwd = salto pour certains |
| block / crouch_block | 2 / 2 | |
| punch_1/2/3 | 4 / 4 / 6 | auto-combo |
| kick / kick_high | 6 / 6 | |
| crouch_punch / sweep | 4 / 6 | |
| uppercut | 6 | grosse extension |
| jump_punch / jump_kick | 3 / 3 | |
| throw / thrown | 8 / 6 | |
| hit_high / hit_low / hit_air | 3 / 3 / 4 | |
| knockdown / getup | 6 / 6 | |
| dizzy | 6 | étoiles = vfx séparé |
| ko | 8 | chute comique |
| win | 8 | |
| sp_neutral / sp_forward / sp_down / sp_up | 6–10 | |
| super | 12 | |
| finisher | 12–16 | + vfx dédiés |

Soit environ **34 animations** et 180 à 220 frames par personnage, **toutes produites par le rig cut-out** (§11.3), sauf l'idle. Le coût en images RD ne dépend donc pas du nombre d'animations. La **Phase 3** livre d'abord un sous-ensemble jouable de 12 animations par personnage, puis on enrichit.

- **Projectiles et vfx** : cellules de 32, 48 ou 64 px, pas indexés (couleurs de palette directes). Ils sont additifs au besoin (Itsaso, faisceau du Phare).
- **Portraits** : `portrait.png` 96×96 (sélection, HUD en 40×40 réduit et retouché), `portrait_big.png` 160×200 (écran versus, insert du super), en **3 expressions** : neutre, combat, K.O.

### 10.5 Écrans (maquettes de principe)
- **Titre** : plan large de la baie (existant `bg_menu`, réanimé), logo, « Appuie pour commencer », goélands qui traversent, musique de titre.
- **Sélection des combattants** : grille **6×2** de portraits dans des cadres de planches peintes. Curseur J1 rouge, J2 vert, en ligne l'adversaire en bleu marine. À gauche (et à droite pour J2), le combattant en **grand**, en animation `idle` ×1 (sprite natif sur la scène, pas d'agrandissement non entier). Son nom en lettrage basque, son titre, son archétype en 3 icônes (puissance, vitesse, portée), son stage maison flouté en fond. Les flèches haut/bas changent de **costume** (verrous visibles).
- **Écran versus** : les deux grands portraits face à face, « VS » en lettrage basque qui claque, puis le nom du stage. Il dure 2 s et se passe d'un appui.
- **Pyramide** : le phare en coupe, les portraits sur chaque étage et une animation d'ascension entre les combats (le curseur monte d'un étage, le faisceau balaie).
- **HUD de combat** : en haut, les barres de vie en **cadres de planche** avec les portraits 40×40 aux extrémités. La vie passe du **vert basque à l'or puis au rouge**, avec une barre de « vie perdue » blanche qui descend en retard (lisibilité des dégâts). Le timer est au centre, dans une **bouée**. Les txapelas de rounds sont sous les barres. En bas, les jauges **Marée** (3 segments en vagues), et le compteur de combo (« 3 COUPS ! ») au bord de l'écran du côté de l'attaquant.
- **Annonces** : « ROUND 1 », « BORROKA ! » (= combat !), « K.O. » remplacé par **« PLOUF ! »**, « BUKATU ! », « TXAPELDUN ! », « PARFAIT ! ». Grandes lettres basques qui arrivent avec rebond et rotation pixel.
- **Salon en ligne** : une plage (fond `bg_beach`) où chaque copain en ligne est représenté par **son combattant miniature** qui se promène sur le sable avec sa carte au-dessus. On touche un copain pour le défier. C'est simple, vivant et sans texte libre.
- **Résultats** : le vainqueur en `win`, l'autre en `ko`, les stats du match. Boutons : « Revanche », « Changer de combattant », « Menu ».
- **Fins** : 3 images 320×180 (§11.5) en fondu, avec le texte en bas dans un cadre parchemin.
- Les transitions utilisent **l'iris pixelisé existant** (conservé), et un **balayage de vague** pour l'entrée en combat.

### 10.6 Stages : spécification technique
- **Largeur du monde** : 576 px. Vue de 384 px (jusqu'à environ 470 en expand). Hauteur de 216 px.
- **Calques** :
  1. `far.png` : **512×216**, parallaxe 0,25 (pour une vue de 470 et un monde de 576 : 470 + 0,25×106 ≈ 497 ≤ 512 ✔). C'est le décor i2i.
  2. `mid.png` (optionnel) : éléments au premier plan lointain (bateaux, parasols), parallaxe 0,6, transparent.
  3. `floor.png` : bande de sol **576×40**, parallaxe 1,0. Sable, planches de la passerelle, pavés, parquet de fronton… **tileable** si généré en tuile.
  4. `fg.png` (optionnel) : avant-plan (rambarde, herbes) à 1,15, très bas, ne masquant jamais les pieds.
- **Animations d'ambiance** : la méthode de `rd_post.py` (frames d'écume sur les pixels « eau ») est réutilisée, plus des sprites animés posés via `stage.json` (positions, fps).
- **`stage.json`** : `ground_y` (= 196), `walls` [16, 560], calques, parallaxes, animations, `music`, `ambient_sfx`, `impact_particles` ("sand"|"water"|"flour"|"wood").

### 10.7 Caméra
Elle est centrée sur le milieu des deux combattants. Le zoom est fixe (pas de zoom en pixel art). Elle est lissée sur 6 frames, bornée par le monde. Le **shake** est pixel-snappé. Pendant le super, un **léger décentrage vers l'attaquant** et l'assombrissement du fond.

---

## 11. Pipeline d'assets

### 11.1 Stratégie : RD pour l'identité, le code pour le mouvement
Avec un plafond de 50 $, on ne peut **pas** générer les ~34 animations × 13 personnages par RD (≈ 150 $). Le principe :
**RD produit peu d'images, mais celles qui portent l'identité** (une pose de base par personnage, les portraits, les décors). **Le mouvement est fabriqué en code** à partir de ces images, par un rig « cut-out » en pixel art (§11.3). C'est la technique de nombreux jeux de combat indés ; elle garantit en prime une cohérence parfaite entre les frames.

| Besoin | Source | Coût |
|---|---|---|
| Combattants : pose de base | Exploration en `rd_fast__default` / `rd_plus__default` (0,015–0,025 $), version finale en **`rd_pro__default`** 128×128, `remove_bg`, `input_palette` | ≈ 0,30 $/perso |
| Combattants : animations | **Rig cut-out procédural** (§11.3) pour toutes les animations. RD `rd_advanced_animation__idle` **seulement** pour l'idle (la respiration organique est ce qui se voit le plus) | ≈ 0,15 $/perso |
| Projectiles, vfx, impacts | **Procédural** (Fx + petits sprites en grilles ASCII) | 0 $ |
| Portraits | 1 portrait `rd_pro__default` 96×96 par perso ; le grand portrait et les expressions sont **dérivés en code** (agrandissement ×2 nearest + retouches, yeux et bouche repeints pour l'expression K.O.) | ≈ 0,20 $/perso |
| Stages | **i2i** depuis photos réelles (méthode existante `rd_i2i.py`, en v2) ; **réutiliser les 7 décors i2i existants** comme base quand c'est possible (extension latérale, §11.4) | ≈ 3 $ au total |
| Sols de stage | **Procéduraux** (tuiles en code, palette du stage) ; `rd_tile__single_tile` seulement si le résultat en code est trop pauvre | 0–1 $ |
| Fins | **1 image** par perso, `rd_plus__default` 320×180 (3 cases de BD obtenues par recadrage et zoom sur cette image) | ≈ 0,05 $/perso |
| UI (cadres, boutons, icônes, police, logo) | **Procédural, grilles ASCII** (méthode `gen_louis.py`) | 0 $ |
| **Placeholders** | **Mannequins procéduraux** (`tools/mannequin/`) | 0 $ |

### 11.2 Client RD v2 (`tools/rd/client.py`)
- `POST https://api.retrodiffusion.ai/v2/inferences` avec l'en-tête `X-RD-Token`. Réponse `{"status":"accepted","task_id":…}`, puis polling de `GET /v2/inferences/tasks/{task_id}` toutes les 2 s jusqu'à `succeeded` ou `failed`. Le résultat est dans `task["result"]["base64_images"]` (PNG, ou GIF pour les animations sauf avec `return_spritesheet: true`).
- **Avant tout** : vérifier les noms exacts de styles et de paramètres dans la doc à jour (https://github.com/Retro-Diffusion/api-examples). Les anciens scripts utilisent `/v1` (synchrone) ; on garde un adaptateur v1 au cas où.
- **Plafond dur de 50 $** (§0.3) :
  - `tools/rd/budget.json` : `{"cap_usd": 50.0, "start_balance": <lu au premier appel>}`, versionné. Le registre `tools/rd/ledger.jsonl` (versionné aussi) contient une ligne par requête facturée : date, style, taille, `balance_cost`, cumul.
  - Avant chaque requête : `check_cost: true` (gratuit). Si `cumul + coût > cap_usd`, le client **lève une erreur** et n'envoie rien. Aucun flag pour contourner le plafond : seul Julien peut modifier `cap_usd` à la main.
  - Contrôle croisé avec `GET /v2/inferences/credits` : si le solde réel a baissé plus que le registre ne l'indique, on s'arrête et on le signale.
  - `python3 tools/rd/client.py --status` affiche le dépensé, le restant et la projection des lots planifiés.
- **Tailles et styles au plus juste** : le coût de `rd_fast` et `rd_plus` dépend de la surface, donc on génère à la taille native exacte, jamais plus grand. L'exploration (choisir une direction) se fait toujours en `rd_fast`, et `rd_pro` est réservé aux images finales.
- **Cache** : `tools/rd/cache/<sha1(payload)>.png` + `manifest.jsonl` (payload, coût, date, task_id). On ne relance jamais une requête identique. Récupération des tâches perdues via `GET /v2/inferences/tasks?limit=20&status=running`.
- **Erreurs** : 429, on respecte `Retry-After`. Une animation en échec est relancée **une fois** avec des paramètres identiques (recommandation de la doc).
- **Sorties brutes** dans `tools/rd/out/` (gitignoré). Seuls les **assets post-traités et validés** entrent dans `assets/`.
- Les scripts écrivent dans le **dossier du projet**, et non dans les chemins `/private/tmp/claude-501/...` codés en dur dans les anciens scripts (à supprimer).

### 11.3 Combattants : procédure par personnage
1. **Fiche visuelle** : à partir du §5.1, écrire `tools/rd/prompts/fighters.yaml` (prompt de base, couleurs par rôle, accessoires, à éviter). Gabarit de prompt :
   `"full body fighting game character sprite, side view facing right, fighting stance, {description}, chibi proportions 1:4 head, bold readable silhouette, thick dark plum outline, sunny basque coast palette, kid friendly cartoon, no weapon blades, no blood, no text"`.
2. **Pose de base** (la seule image RD qui compte vraiment) :
   - **Exploration** : `rd_fast__default` 128×128, `num_images: 4` (≈ 0,06 $), éventuellement 2 tours. On choisit une direction sur planche contact.
   - **Finale** : `rd_pro__default` 128×128, `num_images: 1`, `remove_bg: true`, `input_palette` = palette du §10.2 (image 64×1), et la meilleure exploration en `reference_images`. 1 essai, 2 au maximum.
   - **Pose imposée** pour faciliter le rig : vue de profil vers la droite, garde de combat **ouverte** (bras avant tendu en garde, bras arrière plié près du torse, jambes écartées), avec le **moins de chevauchements possible** entre les membres. Ajouter au prompt : `"side view, open fighting stance, limbs clearly separated, arms not crossing the torso"`.
   - Critères de choix : silhouette, lisibilité à ×1, pied bien posé, regard vers la droite, membres séparables.
   - **Louis** : passer `assets/sprites/louis.png` (agrandi proprement) en `reference_images` pour garder sa filiation : blond, béret rouge, chemise blanche, ceinture rouge, espadrilles.
3. **Rig cut-out** (`tools/rig/`), qui remplace les animations RD :
   - **Découpage** : `assets/fighters/<id>/rig.json` décrit les pièces par **masques polygonaux** sur la pose de base (tête, torse, bassin, bras sup. ×2, avant-bras + main ×2, cuisse ×2, jambe + pied ×2, accessoire : béret, planche, chistera, pierre, canne, ailes, pinces…), le **pivot** de chaque pièce et l'ordre de dessin. Claude Code trace ces masques en regardant le sprite agrandi ×6 avec une grille, puis valide par une planche « pièces éclatées ».
   - **Zones cachées** : les pixels masqués par un autre membre (épaule derrière le bras, haut de cuisse) sont **reconstruits** en prolongeant la rampe de couleur de la pièce (remplissage par la couleur dominante du bord + ombrage), pour qu'aucun trou n'apparaisse quand le membre bouge.
   - **Poses-clés** : `tools/rig/poses/*.json` contient les angles par articulation et les décalages pour chaque frame de chaque animation du §10.4. Elles sont **communes à tout le roster** pour les coups normaux (avec un facteur d'amplitude par personnage) et **propres** pour les spéciaux, super et finishs.
   - **Rendu pixel-propre** : rotation des pièces par **RotSprite** (agrandissement Scale2x ×3 → rotation nearest → réduction avec vote majoritaire), jamais par rotation bilinéaire. Angles **quantifiés par pas de 7,5°**. Après composition : contour re-unifié en `outline`, suppression des pixels orphelins, re-quantification palette.
   - **Déformations simples** en plus des rotations : étirement de 1 à 2 px (anticipation, impact), aplatissement à l'atterrissage, et **smear frames** pour les coups rapides (une frame où le membre est étiré et traîné sur 2 à 3 positions, typique du pixel art de combat).
   - **Idle** : seule animation générée par RD (`rd_advanced_animation__idle`, `input_image` = pose de base sur toile 128×128 avec ≥ 12 px de marge, `frames_duration: 8`, `return_spritesheet: true`), car c'est la plus visible. Si le résultat dérive (taille, couleurs), on garde un idle de rig (respiration par décalage du torse et de la tête de 1 px).
   - Le rig est le **même code** que celui des mannequins placeholders (§11.7) : on développe le système une seule fois, sur les mannequins, puis on remplace les pièces dessinées en code par les pièces découpées dans les sprites RD.
4. **Post-traitement commun** (`tools/sprites/process_anim.py`), appliqué aussi à l'idle RD :
   - découper la planche en frames ;
   - **recaler le pied** : ligne la plus basse opaque → y=120. Recalage horizontal sur le **centre de masse des 20 rangées du bas** pour les animations « sur place », ou sur le pied arrière pour les attaques (paramétrable) ;
   - **re-quantifier** sur la palette du personnage (≤ 31 couleurs + transparent). Pas de tramage. Supprimer les pixels isolés (« orphelins ») ;
   - **unifier le contour** : tout pixel opaque en bord de silhouette passe à `outline` ;
   - vérifier les invariants de cohérence entre frames : variation de hauteur < 8 % pour idle et walk, couleur de peau stable, mêmes rôles de palette. En cas d'échec, l'animation est **marquée à revoir** ;
   - assembler `sheet.png` (indexée) et `palettes.png`, puis mettre à jour `data.json.anims`.
5. **Revue visuelle** : `tools/sprites/contact_sheet.py <id>` produit un PNG ×3 avec toutes les animations en grille + les GIF animés. **Regarde-les.** Les défauts se corrigent dans les poses ou le rig (gratuit), jamais en régénérant par RD.
6. **Costumes** : `tools/sprites/make_palettes.py` lit `palette_roles` et produit les palettes 2 à 4 par rotation de teinte des rampes « outfit » et « hat » seulement (jamais la peau). Contrôle par planche contact des 4 costumes côte à côte.

**Si la pose de base d'un personnage est impossible à découper proprement** (membres trop fusionnés) : une seule nouvelle génération `rd_pro` avec une pose plus ouverte. Sinon, on reconstruit les pièces fautives à la main en grilles ASCII, dans le style du sprite. Le jeu ne doit **jamais** bloquer sur une image.

### 11.4 Stages
- **Réutiliser d'abord l'existant** : les 7 décors i2i actuels (320×180, de bonne qualité) couvrent déjà Grande Plage, Côte des Basques, Port des Pêcheurs, Rocher de la Vierge, Port Vieux, Phare et la baie. Pour les élargir à 512×216 sans tout régénérer :
  - Agrandir **×1,2 en nearest** (384×216), ce qui fait des pixels de décor un peu plus gros que ceux des personnages, acceptable pour un plan lointain et même souhaitable pour la profondeur.
  - Combler les 64 px de chaque côté par une **extension i2i bon marché** (`rd_plus__default`, recadrage 160×216 du bord + bande vide, `strength` ≈ 0,55), puis raccord. Repli gratuit : prolonger le bord par miroir et tuilage du ciel et de la mer.
- **Nouveaux stages** (Halles, Fronton, Stade, Aquarium) : migrer `rd_i2i.py` en v2 et générer en `rd_plus__default` au plus juste. Tester d'abord `rd_pro__default` en 512×216 via `check_cost` ; on le prend si le lot entre dans le budget. Une variante soir ou crépuscule s'obtient **par recoloration en code** (LUT chaude ou bleutée sur la palette), sans nouvelle génération.
- **Prompt** : celui des scènes existantes, plus `"wide fighting game stage backdrop, horizon at 55% height, nothing in the bottom 20%"`. Le bas est libéré pour le sol.
- **Sol** : tuile 64×40 **générée en code** (palette et motif propres à chaque stage), tuilée sur 576. On ne passe à `rd_tile__single_tile` (0,10 $) que si le rendu en code est jugé trop pauvre sur planche contact. Une variante par stage : sable mouillé, planches de passerelle, pavés de quai, parquet de fronton, carrelage des Halles, pelouse du stade, sol de l'aquarium, pierre du Phare.
- **Ré-animation de l'eau** : reprendre l'algorithme de `rd_post.py` (`is_water`, étincelles d'écume par hash), étendu aux nouvelles dimensions.
- **Photos à fournir par Julien** : Les Halles, un fronton (Parc Mazon), l'Aquarium et le stade, à déposer dans `tools/rd/photos/`. En leur absence, txt2img avec un prompt descriptif détaillé, et le signaler dans `docs/DECISIONS.md`.

### 11.5 Portraits et fins
- **Portraits** : **un seul** `rd_pro__default` 96×96 par personnage (expression « combat »), avec la pose de base en `reference_images`. Prompt : « bust portrait, 3/4 view, determined expression, same character ». Quantifié sur la palette du personnage.
  - **Dérivés en code** : le grand portrait 160×200 est un agrandissement ×2 nearest, recadré et retouché (contour aminci, reflets ajoutés). L'expression **K.O.** s'obtient en repeignant yeux (spirales ou croix) et bouche ; l'expression neutre en adoucissant les sourcils. Le portrait HUD 40×40 est une réduction avec vote majoritaire, retouchée.
- **Fins** : **une seule image** de 320×180 par personnage (12 + boss = 13 images) en `rd_plus__default`, avec la pose de base en `input_image` ou en prompt détaillé. Ton « carte postale d'été ». Les 3 temps de la fin sont 3 cadrages (plan large, puis 2 zooms ×2 nearest avec un lent panoramique) de cette même image, avec le texte en overlay. **Aucun texte dans l'image.**

### 11.6 Hitboxes et hurtboxes automatiques
`tools/sprites/infer_boxes.py` :
- **Hurtbox** par frame : bbox opaque découpée en 3 boîtes (tête 25 %, torse 40 %, jambes 35 %), réduite de 2 px (tolérance enfant), pour un `push box` fixe par personnage.
- **Hitbox** des frames actives : masque **différence** entre la frame et la frame d'idle 0 (alignées au pied). On garde la plus grande composante connexe **du côté avant**, dont on prend la bbox, réduite de 1 px. Les frames actives sont désignées dans `data.json` (`startup` et `active`).
- Le résultat s'écrit dans `data.json`. Les **surcharges manuelles** (`hitbox_overrides`) priment toujours.
- **Visualiseur debug** en jeu (touche F3 en build debug) : hit en rouge, hurt en vert, push en bleu, plus la frame data affichée. Indispensable à l'équilibrage.

### 11.7 Mannequins placeholders (`tools/mannequin/`)
- Ce sont des combattants procéduraux dessinés en Python : squelette (tête, torse, bras ×2, jambes ×2) avec des capsules épaisses à contour `outline`, et 2 tons de couleur par personnage selon sa fiche. On y ajoute un attribut distinctif simple (béret, planche, chistera, pierre, ailes, pinces…).
- **Poses-clés** définies une seule fois pour tout le roster (angles des articulations par frame), puis rendues dans les mêmes cellules, au même format indexé et avec la même liste d'animations que §10.4.
- Ils servent dès la Phase 2, pour que le gameplay, le netcode et l'IA se développent **sans attendre** les images RD. Ils servent aussi de **secours** si RD échoue sur un personnage.
- **C'est le même moteur que le rig final** (§11.3) : mêmes poses-clés, même rendu RotSprite, même post-traitement. Seule la source des pièces change (capsules dessinées en code contre pièces découpées dans la pose RD). Les poses s'écrivent et se règlent donc **une seule fois**, en Phase 1–2, sur les mannequins.

### 11.8 Budget RD : plafond 50 $ (dur)
Estimation à partir des prix de la doc (à confirmer par `check_cost` ; les styles `rd_fast` et `rd_plus` sont facturés à la surface avec un minimum par image) :

| Poste | Volume | Prix unitaire | Total |
|---|---|---|---|
| Test du client (Phase 0) | 1–2 | 0,015 $ | 0,03 $ |
| Exploration des poses (`rd_fast`, 4 images × 2 tours × 13) | 104 | ≈ 0,015–0,02 $ | ≈ 2 $ |
| Poses de base finales (`rd_pro`, 13 × 1,5 essai) | 20 | 0,18 $ | 3,6 $ |
| Idle animé (`rd_advanced_animation__idle`, 13 × 1,3) | 17 | 0,14 $ | 2,4 $ |
| Portraits (`rd_pro`, 13 × 1,5) | 20 | 0,18 $ | 3,6 $ |
| Fins (`rd_plus` 320×180, 13 × 2) | 26 | ≈ 0,05 $ | 1,3 $ |
| Nouveaux stages (4 × 3 essais, `rd_pro` 512×216 au pire) | 12 | ≤ 0,18 $ | ≤ 2,2 $ |
| Extensions latérales des 7 stages existants (2 côtés × 7 × 1,5) | 21 | ≈ 0,03 $ | 0,6 $ |
| Réserve « ratés et retouches » | | | 5 $ |
| **Total prévu** | | | **≈ 21 $** |
| **Marge jusqu'au plafond** | | | **≈ 29 $** |

La marge sert à **rattraper** un personnage raté ou à ajouter, **si et seulement si** Julien le demande, quelques animations RD de prestige : super, finish d'un personnage (`rd_advanced_animation__custom_action`, 0,25 $ pièce). Le client refuse tout dépassement des 50 $.

**Point d'arrêt budgétaire** : à la fin de la Phase 3 (4 personnages), le registre doit afficher **≤ 8 $**. Au-delà, on s'arrête pour revoir la méthode avant de continuer.

---

## 12. Audio

- **Moteur** : `tools/gen_audio.py` conservé (synthèse chiptune maison → WAV → OGG via ffmpeg). Les morceaux restent des **arrangements originaux** d'airs **traditionnels basques du domaine public** (fandango, *Agur Jaunak*, *Boga boga*, *Maritxu nora zoaz*, airs de *zortziko* à 5/8…). On vérifie pour chaque air qu'il s'agit d'un traditionnel sans auteur identifié et on le documente dans `docs/MUSIC.md`.
- ⚠️ **Retirer *Hegoak*** de `gen_audio.py` et de `menu.mp3` (§2.2).
- **Morceaux** : titre, sélection, pyramide, 10 thèmes de stage, boss (plus sombre, en mineur), victoire (jingle), « TXAPELDUN ! » (fanfare), fins (doux, txistu simulé par onde triangle + vibrato).
- **SFX** : coups léger, moyen et lourd (bruit + pitch down), garde (« toc » de bois), projectile par personnage, sifflet (Txomin), pelote sur chistera, cri de goéland, pince, souffle de feu, vague, PLOUF, foule, tic du timer, sélection et validation dans les menus.
- **Voix** (option charmante, **[À trancher]** avec Julien) : faire enregistrer à Louis et ses copains les annonces (« Borroka ! », « Plouf ! », « Bukatu ! », « Txapeldun ! », les noms des 12 personnages). Les traiter en 8-bit (bitcrush 8 kHz) dans `gen_audio.py` (fonction `crunch_voice()`). Sinon, utiliser les annonces synthétiques ou du texte seul.
- **AudioManager** : bus `Music`, `SFX` et `Voice`, ducking de la musique (−8 dB) pendant les annonces et le super, déblocage web au premier geste (conservé). En rollback, il ne joue pas un son deux fois (§8.6).
- **Formats** : OGG Vorbis, 96 kbps pour la musique et 64 kbps pour les SFX (budget WASM).

---

## 13. IA (`src/fight/ai/ai_brain.gd`)

- L'IA **produit un `InputFrame` par tick** : la sim ne sait pas si elle affronte un humain. Elle tourne **dans** la sim déterministe (elle lit l'état et utilise le `XRng` de la sim). Les replays IA sont donc déterministes, ce qui permet les tests d'équilibrage (§14.4).
- **Décisions** toutes les N frames, N étant le *temps de réaction* (Facile 24, Normal 14, Expert 8, boss 7), selon la distance (contact, moyenne, longue), l'état de l'adversaire (en l'air, au sol, en récupération, en garde) et le profil `ai` du personnage :
  - anti-aérien si l'adversaire saute vers lui (probabilité `anti_air`) ;
  - punition après un coup bloqué (Expert) ;
  - zonage à longue distance (`zoning`), pression au contact (`aggression`) ;
  - garde : probabilité selon la difficulté (Facile 15 %, Normal 45 %, Expert 75 %), et garde basse sur balayette lue seulement en Expert ;
  - combos de 2 à 4 coups appris par personnage (`favorite_moves`).
- **Difficulté de la pyramide** : rampe progressive, réaction et garde interpolées de l'étage 1 à 8. Le boss est en Expert+.
- **Facile** : l'IA s'arrête parfois (« respire ») et ne fait jamais deux spéciaux de suite. Elle ne doit jamais humilier.
- **Règle d'adaptation** (anti-frustration) : en solo, après 2 défaites d'affilée au même étage, l'IA baisse d'un cran sur cet étage, sans le dire.

---

## 14. Qualité et tests

### 14.1 Tests de la sim (headless, en CI)
- **Godot headless** : `godot --headless --script res://tests/run_tests.gd`. Un mini-framework maison, sans dépendance externe ; GUT est accepté si l'export web n'est pas alourdi (dossier `tests/` exclu de l'export).
- Tests obligatoires :
  - **Déterminisme** : 2 sims, mêmes entrées aléatoires (graine fixe) sur 3600 frames → checksums identiques à chaque frame.
  - **Rollback** : sim A en direct, sim B avec rollbacks aléatoires (1 à 8 frames, entrées tardives) → état final identique.
  - **save/load** : aller-retour de l'état = identité binaire.
  - **Lint sim** : pas de `float`, `randf`, `Time`, `OS`, `Engine` dans `src/fight/sim/`.
  - **Frame data** : chaque coup sort à la frame annoncée, les hitboxes existent sur les frames actives, et tous les JSON sont validés par le schéma.
  - **Règles** : chip qui ne tue pas, combo forcé à 6, timer, égalités, Retour de vague une seule fois.

### 14.2 Captures visuelles (QaCapture étendu)
- `--scene=res://…`, `--autofight=<p1>,<p2>,<stage>,<seed>` (combat IA contre IA), `--frames=<liste>` (captures multiples), `--touchidx=random` (index tactiles aléatoires, régression iOS).
- Une **planche de non-régression** par stage et par personnage est générée en CI. **Regarde-la à chaque phase.**

### 14.3 Web et mobile
- **Playwright** (Chromium) : charger le build web servi avec COOP/COEP, jouer un combat IA contre IA de 30 s, vérifier l'absence d'erreurs console et capturer l'écran.
- **Test en ligne automatisé** : deux pages Playwright (deux contextes) + backend PHP local (`php -S`) → défi, signalisation, connexion WebRTC en loopback, 1 round complet, puis les deux rapports concordent et l'Elo est mis à jour.
- **Sur vrai iPhone** (par Julien, checklist dans `docs/TEST_IPHONE.md`) : paysage, encoche, multitouch joystick + 2 boutons simultanés, audio après le premier geste, 10 combats d'affilée sans crash mémoire, combat en ligne iPhone ↔ Mac sur Wi-Fi et en 4G.
- **Session longue** : 30 min de combats IA contre IA en boucle dans le navigateur. La mémoire doit rester stable (OOM WASM, leçon de l'ancien CLAUDE.md).

### 14.4 Équilibrage par simulation
`tests/balance_sim.gd` : tous les duels 13×13, 20 matchs chacun en IA Expert contre IA Expert (headless, accéléré). Il sort une matrice des taux de victoire en CSV et en PNG (heatmap). Objectif : 40–60 % par personnage (§5.2). On le relance après chaque modification de frame data.

---

## 15. Phases (ordre impératif)

> Comme dans l'ancien CLAUDE.md : **absorber le risque technique une seule fois, puis décliner.** Le risque n°1 est la sim déterministe et le netcode ; le n°2, la cohérence des animations RD. On les traite tôt.

**Phase 0 : Nettoyage et fondations**
- Branche `borroka`. Suppression des éléments du §2.2 (le git les conserve). Nouvelle arborescence §8.1.
- `DESIGN.md` et `CLAUDE.md` réécrits depuis cette spec. `docs/DECISIONS.md` créé.
- `project.godot` : résolution 384×216, mode viewport, 60 ticks de physique, nouveaux autoloads, actions d'entrée du §4.1.
- `tools/palette.py` étendu, `tools/rd/client.py` (v2, cache, check_cost, **registre et plafond de 50 $**, `--status`), `tools/rd/budget.json`, avec un test réel à 1 image bon marché (`rd_fast`, environ 0,015 $).
- Retrait d'*Hegoak*.
- ✅ *Sortie* : le projet s'ouvre et s'exporte en web, avec un écran titre provisoire sur iPhone en paysage. Le client RD a renvoyé une image.

**Phase 1 : La sim déterministe et un combat de mannequins**
- `sim/` complet pour les mouvements, coups normaux, garde, projection, rounds, timer et `save/load/checksum`. `InputHub` avec clavier et manette.
- `tools/mannequin/` : 2 mannequins (Louis, Maïa) avec toutes les animations de base.
- Vue minimale : stage plat, HUD basique, hitstop et shake. Versus local au clavier.
- Tests §14.1 au vert. Visualiseur de hitbox.
- ✅ *Sortie* : à deux sur un clavier, on se bat avec des mannequins. On sent l'uppercut. Tests de déterminisme et de rollback au vert.

**Phase 2 : Le contenu de gameplay en placeholder**
- Les 12 personnages et le boss en **mannequins**, avec leurs 4 spéciaux, projectiles, super et finish (vfx procéduraux), et le JSON complet de chaque personnage.
- IA (§13). Pyramide du Phare jouable de bout en bout (écrans provisoires). Entraînement + liste des coups.
- Équilibrage par simulation (§14.4), première passe.
- ✅ *Sortie* : Louis peut jouer la pyramide complète, avec n'importe quel personnage, sur ordinateur. La matrice d'équilibrage est dans la cible ±15 %.

**Phase 3 : Pipeline graphique, 4 personnages et 3 stages**
- `tools/sprites/*` (post-traitement, indexation, palettes, hitbox auto, planches contact) et `tools/rig/` (découpage, RotSprite, smear frames). Shader de palette.
- RD : Louis, Maïa, Patxi et Xabi (exploration, pose de base, idle, portrait). Rig des 12 animations prioritaires : walk, crouch, jump, block, punch, kick, uppercut, hit, ko, sp_neutral, sp_forward, plus l'idle.
- Stages Grande Plage, Côte des Basques et Port des Pêcheurs, élargis depuis les décors existants, avec sol et parallaxe.
- ✅ *Sortie* : planches contact validées **par Julien** (envoyer les PNG). Un combat Louis contre Maïa sur la Grande Plage, en vrais sprites, est capturé en GIF. Registre RD **≤ 8 $**. **Point d'arrêt : attendre le feu vert de Julien avant la Phase 4.**

**Phase 4 : Tactile iPhone**
- Manette virtuelle (§7.3) et mode gestes (§7.4), zones sûres, réglages de contrôle, tutoriel (§7.5).
- Tests d'index tactiles aléatoires, puis checklist iPhone.
- ✅ *Sortie* : Louis termine un combat sur iPhone sans aide et joue un super au pad.

**Phase 5 : Profils, menus et DA complète**
- Profils locaux (4 maximum), carte de joueur, costumes et déblocages, titres et stats.
- Tous les écrans du §10.5 en DA finale : police basque, logo, cadres en planche, annonces, transitions.
- Audio complet (§12).
- ✅ *Sortie* : parcours complet titre → profil → pyramide → fin, en DA finale, pour les 4 personnages finis.

**Phase 6 : En ligne**
- Backend §9 (migrations, routes, tests PHP), salon, présence, invitations, match rapide, choix de la map.
- `p2p_link.gd` et `rollback_session.gd` : **délai seul d'abord**, puis rollback. Checksums, rapports, Elo, classements.
- Test Playwright à 2 pages (§14.3), puis test réel iPhone ↔ Mac.
- ✅ *Sortie* : Louis défie un copain depuis deux maisons différentes, en 4G, et le combat est fluide. Le classement du groupe se met à jour.

**Phase 7 : Le reste du roster et des stages**
- Les 8 personnages restants et le boss (RD dans le plafond de 50 $), les 7 stages restants, les animations complètes par le rig (34 par personnage), les finishs et les fins illustrées.
- Seconde passe d'équilibrage.
- ✅ *Sortie* : 12 personnages + boss jouables avec leurs costumes, 10 stages, 13 fins.

**Phase 8 : Polissage après les tests de Louis**
- Game feel, difficulté, lisibilité, performance web (mémoire et taille du .pck < 40 Mo si possible), accessibilité (option « daltonisme » pour le HUD, vibrations).
- Déploiement en production. Itch.io en option.

---

## 16. Hypothèses à confirmer en playtest
- Timer de 60 s ou 90 s ? Meilleur des 3 rounds partout ?
- **Auto-combo** POING×3 : trop fort pour l'équilibre ? Il est indispensable aux enfants, on garde mais avec un réglage de dégâts.
- Le mode **Gestes** est-il réellement utilisé, ou la manette virtuelle suffit-elle ?
- Taille de la caméra : voit-on assez le jeu sur un iPhone mini ?
- Finishs : est-ce que ça fait rire Louis ? (C'est l'objectif principal.)
- Faut-il un serveur TURN ? Mesurer le taux d'échec des connexions via `/api/net/report`.
- Voix enregistrées par les enfants ou annonces synthétiques ?
- Faut-il ajouter le « code de salle » pour jouer avec un ami hors groupe ?

---

## 17. Hors périmètre v1 (pistes v2)
- Mode tag team 2 contre 2, tournoi à 8 du groupe (bracket), replays partagés (ils sont déjà possibles grâce au déterminisme : seed + entrées), spectateur en ligne.
- Personnages bonus : Foka le phoque de l'Aquarium, le Pottok (poney basque), la Sorgina (sorcière basque, mythologie).
- Dangers de stage (vague qui traverse la passerelle, mouette qui vole un objet).
- PWA installable (icône sur l'écran d'accueil de l'iPhone). `export_presets.cfg` prévoit déjà la PWA, il suffit de l'activer et de tester.
