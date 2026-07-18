# CLAUDE.md — Miarritze

Fichier de référence pour Claude Code. À lire au début de **chaque** session. Il fige la stack, l'arborescence, les conventions, l'architecture des scènes, le backend et l'ordre de construction. Le design (le *quoi/pourquoi*) est dans `DESIGN.md`.

---

## 0. Règles d'or

1. **Squelette d'abord.** Ne pas construire les six lieux en parallèle. Bâtir le tronc commun une seule fois (§7), puis décliner les épreuves à partir du même template.
2. **GDScript uniquement.** Le C# **ne s'exporte pas** vers le web sous Godot 4 → interdit ici.
3. **Web-first, tactile-first, paysage.** Toute mécanique doit être jouable au doigt, en paysage, sur un téléphone d'entrée de gamme.
4. **Budget WASM.** L'export web a un plafond mémoire. Assets légers, pas de fuite de scène (libérer les niveaux à la sortie), pas de dépendances lourdes.
5. **Un enfant de 9 ans est le juge.** Lisibilité > richesse. Feedback immédiat, échec jamais opaque, tolérance généreuse.
6. **Pas de données personnelles.** Pseudo seul. Jamais de nom réel, email, ni compte.
7. **Tout paramètre de gameplay est une donnée**, pas un nombre magique enfoui (voir `@export` et `src/shared/config/`).

---

## 1. Stack

| Élément | Choix | Notes |
|---|---|---|
| Moteur | **Godot 4.7** (stable) | WASM SIMD par défaut, option wasm64 |
| Langage | **GDScript** typé | Pas de C# (incompatible web) |
| Renderer | **Compatibility** (WebGL 2.0) | Forward+/Mobile/WebGPU non supportés en web |
| Cible | Export **Web (HTML5)** | + desktop/clavier en bonus |
| Backend | **PHP + SQLite** | API REST leaderboard |
| Hébergement | Serveur propre (LAMP) | Sert le jeu statique **et** l'API |
| Dev/test navigateur | Chromium ou Firefox | Safari a des soucis WebGL 2.0 connus |

---

## 2. Arborescence du projet

```
miarritze/
├── project.godot
├── export_presets.cfg
├── DESIGN.md
├── CLAUDE.md
├── .gitignore                      # ignore backend/db/*.sqlite, /web/build, config.php
├── assets/
│   ├── sprites/                    # atlas + spritesheets par lieu
│   ├── audio/
│   │   ├── music/                  # chiptune, un thème par épreuve
│   │   └── sfx/
│   ├── fonts/
│   └── ui/
├── src/
│   ├── autoload/                   # singletons (voir §4)
│   │   ├── game_state.gd
│   │   ├── score_manager.gd
│   │   ├── audio_manager.gd
│   │   ├── leaderboard_client.gd
│   │   └── scene_router.gd
│   ├── shared/
│   │   ├── config/
│   │   │   ├── challenges.gd        # enum + métadonnées des épreuves
│   │   │   └── balance.gd           # constantes de barème/seuils (tunables)
│   │   ├── input/
│   │   │   └── touch_input.gd       # abstraction tap / drag / clavier
│   │   ├── fsm/
│   │   │   ├── state_machine.gd      # FSM générique réutilisable
│   │   │   └── state.gd
│   │   └── components/              # composants réutilisables (parallaxe, spawner…)
│   ├── hub/
│   │   ├── hub.tscn                 # carte de Biarritz (sélection de lieu)
│   │   └── hub.gd
│   ├── challenges/
│   │   ├── base/
│   │   │   ├── challenge_base.gd     # classe abstraite (cycle de vie commun)
│   │   │   └── challenge_base.tscn
│   │   ├── beach_run/               # Grande Plage
│   │   ├── surf/                    # Côte des Basques
│   │   ├── fishing/                 # Port des Pêcheurs
│   │   ├── rock_crossing/           # Rocher de la Vierge
│   │   ├── espadrille/              # Port Vieux
│   │   └── lighthouse/              # Phare (débloquable)
│   └── ui/
│       ├── boot/                    # écran de démarrage
│       ├── orientation_gate/        # "tourne ton appareil"
│       ├── pseudo_entry/            # saisie pseudo + code de groupe
│       ├── results/                 # écran de score fin d'épreuve
│       └── leaderboard/             # tableaux (par épreuve + cumulé)
├── backend/                        # PHP + SQLite (déployé côté serveur)
│   ├── public/
│   │   └── index.php                # routeur unique de l'API
│   ├── src/
│   │   ├── Db.php
│   │   ├── Validation.php
│   │   └── Profanity.php
│   ├── db/
│   │   ├── schema.sql
│   │   └── miarritze.sqlite          # généré, gitignoré
│   └── config.sample.php
└── web/
    └── .htaccess                    # en-têtes COOP/COEP + MIME wasm
```

**Principe :** *une feature = un dossier* contenant sa `.tscn` et son `.gd` de même nom. Une épreuve ne connaît que `challenge_base` et les autoloads — jamais les autres épreuves.

---

## 3. Conventions de code

**GDScript**
- `class_name` en **PascalCase** ; fichiers et dossiers en **snake_case**.
- Variables et fonctions en **snake_case** ; constantes en **UPPER_SNAKE_CASE**.
- **Typage statique partout** (`var speed: float = 0.0`, retours typés). Améliore la perf web et la maintenabilité.
- Signaux au passé (`finished`, `score_submitted`, `hit_obstacle`).
- Membres privés préfixés `_` (`_state`, `_on_area_entered`).
- `@export` pour tout ce qu'on veut régler depuis l'éditeur ou au playtest (vitesses, fenêtres de timing, seuils). Aucun nombre magique dans la logique.
- Composition > héritage profond. Une seule hiérarchie autorisée : `challenge_base` → épreuve concrète.

**Scènes**
- Une scène racine par feature, un script attaché du même nom.
- Nœuds nommés en PascalCase explicite (`WaveSpawner`, `TensionGauge`, `AimIndicator`).
- Pas de logique dans `_process` si un signal ou un timer suffit (budget web).

**Git**
- Commits atomiques par phase (§7). Branche `main` toujours exportable.
- `.sqlite`, `config.php`, `/web/build` jamais versionnés.

---

## 4. Autoloads (singletons)

Déclarés dans `project.godot`. Ordre de chargement : `GameState → ScoreManager → AudioManager → LeaderboardClient → SceneRouter`.

| Autoload | Responsabilité | API publique (extrait) |
|---|---|---|
| **GameState** | Session courante : pseudo, `group_code`, `player_id`, `player_secret`, état de déblocage du Phare | `set_identity(pseudo, code)`, `is_lighthouse_unlocked()` |
| **ScoreManager** | Meilleurs scores locaux par épreuve, calcul du cumul, logique de déblocage | `submit_local(challenge, score) -> bool`, `best(challenge) -> int`, `cumulative() -> int` |
| **AudioManager** | Musique par épreuve, SFX, volumes | `play_music(challenge)`, `sfx(name)` |
| **LeaderboardClient** | Appels HTTP à l'API PHP (async via `HTTPRequest`) | `join_group`, `post_score`, `fetch_leaderboard` (signaux de retour) |
| **SceneRouter** | Transitions de scène, chargement/déchargement propre (anti-fuite WASM) | `goto_hub()`, `goto_challenge(id)`, `goto_leaderboard()` |

`ScoreManager` est la **source de vérité locale** ; il pousse vers `LeaderboardClient` quand un nouveau best est établi. Le cumul = somme des best des 5 épreuves cœur (constante `Challenges.CORE`).

---

## 5. Architecture des épreuves

### 5.1 Classe de base
`challenge_base.gd` définit le **cycle de vie commun** à toutes les épreuves ; chaque épreuve l'étend et implémente les hooks.

```gdscript
class_name ChallengeBase
extends Node2D

signal finished(score: int)

@export var challenge_id: StringName      # "beach_run", "surf", ...
@export var time_limit: float = 0.0        # 0 = sans limite

var _score: int = 0
var _running: bool = false

func begin() -> void:                       # appelé par SceneRouter
    _score = 0
    _running = true
    AudioManager.play_music(challenge_id)
    _on_begin()

func _on_begin() -> void: pass              # hook à surcharger
func _on_finish() -> void: pass             # hook à surcharger

func add_score(points: int) -> void:
    _score += points

func end() -> void:
    if not _running: return
    _running = false
    _on_finish()
    var is_best := ScoreManager.submit_local(challenge_id, _score)
    if is_best:
        LeaderboardClient.post_score(challenge_id, _score)
    finished.emit(_score)                    # → écran results
```

### 5.2 FSM générique
Les épreuves à personnage mobile (course, surf, Rocher, Phare) utilisent `state_machine.gd` + `state.gd`. Chaque épreuve définit **ses** états (pas de FSM joueur universelle, les mécaniques diffèrent trop).

| Épreuve | États principaux | Contrôle |
|---|---|---|
| `beach_run` | `Run`, `Jump`, `Fall`, `Hit` | tap = jump |
| `surf` | `Ride`, `Launch`, `Trick`, `Land`, `Wipeout` | tap = launch/trick (timing) |
| `fishing` | `Cast`, `Bite`, `Reel`, `Slack`, `Snap`, `Landed` | tap = reel / release = slack |
| `rock_crossing` | `Wait`, `Step`, `Swept` | tap = advance (fenêtre de vague) |
| `espadrille` | `Aim`, `Charge`, `Throw`, `Resolve` | drag = aim/charge, release = throw |
| `lighthouse` | `Climb`, `Jump`, `Fall`, `Reach` | tap = jump |

### 5.3 Entrée tactile
`touch_input.gd` abstrait trois gestes et unifie tactile + clavier (bonus desktop) :
- **tap** → `InputEventScreenTouch` pressé (ou Espace/clic).
- **drag** → `InputEventScreenDrag` (ou souris maintenue) : expose vecteur + magnitude pour l'espadrille.
- Émet des signaux (`tap`, `drag_start`, `drag_update`, `drag_end`) que les épreuves consomment. **Aucune épreuve ne lit les InputEvent bruts directement.**

---

## 6. Backend — PHP + SQLite

Le jeu Godot exporté est **statique** ; le seul besoin dynamique est le leaderboard. Une petite API REST, un routeur PHP unique, base SQLite mono-fichier.

### 6.1 Schéma (`db/schema.sql`)
```sql
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS groups (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT UNIQUE NOT NULL,          -- code de groupe partageable
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS players (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL REFERENCES groups(id),
  pseudo      TEXT NOT NULL,
  secret      TEXT NOT NULL,                 -- jeton par joueur (auth des posts)
  created_at  INTEGER NOT NULL,
  UNIQUE(group_id, pseudo)
);

CREATE TABLE IF NOT EXISTS scores (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id   INTEGER NOT NULL REFERENCES players(id),
  challenge   TEXT NOT NULL,                 -- 'beach_run' | 'surf' | ... | 'lighthouse'
  best_score  INTEGER NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL,
  UNIQUE(player_id, challenge)
);

CREATE INDEX IF NOT EXISTS idx_scores_challenge ON scores(challenge, best_score DESC);
```

### 6.2 Contrat d'API (JSON, préfixe `/api`)

| Méthode | Route | Corps / params | Réponse | Notes |
|---|---|---|---|---|
| `POST` | `/api/group` | — | `{ code }` | Crée un groupe, renvoie un code court |
| `POST` | `/api/group/join` | `{ code, pseudo }` | `{ player_id, secret }` | Crée le joueur si pseudo neuf dans le groupe ; **filtre anti-gros-mots** sur `pseudo` |
| `POST` | `/api/score` | `{ player_id, secret, challenge, score }` | `{ best_score, cumulative }` | Met à jour si meilleur ; **valide `secret`** et **plafond de plausibilité** par épreuve |
| `GET` | `/api/leaderboard` | `?code=XXX&challenge=surf` | `[{ pseudo, best_score }]` | Classement par épreuve (tri desc) |
| `GET` | `/api/leaderboard` | `?code=XXX&type=cumulative` | `[{ pseudo, total }]` | Somme des best des 5 épreuves cœur, par joueur |

### 6.3 Sécurité / hygiène
- **Auth score** : `secret` par joueur, obtenu au `join`, envoyé à chaque `post`. Pas de compte, mais empêche l'usurpation de pseudo.
- **Anti-triche léger** : `Validation.php` refuse tout score au-delà d'un plafond par épreuve (constantes serveur miroir de `balance.gd`) + rejette les valeurs négatives/non entières.
- **Pseudos** : `Profanity.php`, liste FR/EN, appliqué au `join`.
- **CORS** : autoriser l'origine du jeu uniquement. **Ne pas** ouvrir `*` en prod.
- **Rate limiting** simple (par IP + par `player_id`) sur `/api/score`.
- SQLite en `WAL`, requêtes **préparées** partout (jamais de concaténation SQL).

---

## 7. Ordre de construction (impératif)

> Objectif : absorber tout le risque technique **une fois**, puis décliner.

**Phase 0 — Pipeline.**
Projet Godot + preset export Web. Une scène vide s'exporte, tourne sur téléphone en **paysage**, avec `.htaccess` COOP/COEP en place (sinon écran noir). Valider Chromium + un vrai mobile. *Livrable : « ça tourne en ligne sur le tel ».*

**Phase 1 — Squelette (le tronc commun, construit une seule fois).**
- Autoloads (§4).
- `orientation_gate` + `pseudo_entry` (pseudo + code de groupe).
- `hub.tscn` : carte de Biarritz avec 6 zones cliquables (placeholders).
- `challenge_base` + **une** épreuve placeholder (rectangle qui monte un score bidon et appelle `end()`).
- `results` (affiche score + best) et `leaderboard` (lit l'API).
- Backend PHP/SQLite déployé : schéma + les 5 routes, testées end-to-end.
- **Critère de sortie : la chaîne complète tourne** — jouer → scorer → poster → voir le classement du groupe en ligne, sur mobile.

**Phase 2 — Les 5 épreuves cœur.**
Décliner `beach_run`, `surf`, `fishing`, `rock_crossing`, `espadrille` en étendant `challenge_base`, chacune avec sa FSM et son entrée (tap/drag). Assets provisoires acceptés. Réutiliser au maximum les composants partagés (parallaxe, spawner, jauge).

**Phase 3 — Le Phare.**
Logique de déblocage (seuil de cumul dans `balance.gd`), ascension `lighthouse`, salle des trophées = vue leaderboard au sommet.

**Phase 4 — Polissage itératif (après tests de Louis).**
Passe art (pixel art def, palette, animations), passe audio (chiptune par épreuve + SFX), réglage du game feel épreuve par épreuve selon les retours. C'est ici que se règlent les *hypothèses à confirmer* de `DESIGN.md` §10.

---

## 8. Contraintes web — rappels critiques

- **COOP/COEP** obligatoires pour le build threadé (sinon écran noir). Via `.htaccess` :
  `Cross-Origin-Opener-Policy: same-origin` et `Cross-Origin-Embedder-Policy: require-corp`. Vérifier aussi le **MIME `application/wasm`**.
- **Renderer Compatibility** uniquement (WebGL 2.0). Ne rien utiliser qui exige Forward+/Mobile.
- **Budget mémoire WASM** : décharger chaque niveau à la sortie (`SceneRouter`), atlas compressés, audio léger. Tester une **session longue** (l'OOM apparaît sur la durée, pas au lancement).
- **Tactile en paysage** : cibles tactiles généreuses, zones de tap larges, rien d'essentiel dans les coins masqués par les pouces.
- **Desktop** : le mapping clavier (Espace = tap, souris = drag) doit rester gratuit via `touch_input.gd`.

---

## 9. Définition de « fini » (v1)

Jouable en ligne sur tablette et téléphone en paysard, 5 épreuves + hub + Phare débloquable, high scores par épreuve + cumul, leaderboard privé par code fonctionnel (pseudo seul, filtré), pixel art et chiptune en place, aucune donnée personnelle collectée, session longue sans crash WASM. Louis peut envoyer un lien à un copain, ils jouent et se comparent.
