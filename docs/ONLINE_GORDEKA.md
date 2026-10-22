# En ligne Gordeka : API des salons

Serveur des salons de Miarritze Gordeka (SPEC-GORDEKA §2.2, §6.2, §11). Code : `backend/src/Rooms.php`,
tables dans `backend/db/schema.sql` (section « Gordeka : salons »). Tests :
`python3 tests/backend/rooms_test.py` (59 vérifications, `php -S` sur une base jetable, horloge simulée).

Le serveur ne fait tourner aucune partie. Il tient les salons, la présence par salon et la signalisation
WebRTC en étoile. **L'hôte est l'admin du salon** : il fait tourner la partie, gère les IA et publie l'état
des rounds. Tout passe par du polling JSON sur la même origine `/api`.

## Conventions

- JSON en entrée (`Content-Type: application/json`) et en sortie.
- Authentification : `player_id` + `secret` dans le corps (POST) ou la query (GET), obtenus par `POST /gk/player`.
  Le client les garde dans son profil local. Pas de groupe, pas de donnée personnelle.
- Erreur : statut HTTP + `{"error": "message à afficher", "reason": "code_machine"}`. Le client s'appuie sur
  `reason`, et peut afficher `error` tel quel (français, adapté aux enfants).
- Couleurs : un **indice 0–11** dans `data/gordeka/rules.json` → `colors` (0 Rouge … 11 Citron).
- Persos : les 12 ids de `rules.json` → `characters` (miroir dans `GK_CHARACTERS`). Un perso inconnu
  devient `louis` à l'entrée ; il est refusé (`bad_perso`) sur `/room/me`.
- Cartes : `port_pecheurs` seulement pour l'instant (`GK_MAPS`).
- Les horodatages sont en secondes Unix (horloge du serveur).

## Constantes (backend/src/Rooms.php)

| Constante | Valeur | Sens |
|---|---|---|
| `GK_MEMBER_TIMEOUT` | 60 s | membre non vu depuis 60 s → retiré, place libérée (coupure §2.2) |
| `GK_CONNECTED_SECONDS` | 15 s | `connected: false` au-delà (affichage « coupé ») |
| `GK_ROOM_IDLE` | 600 s | salon en `attente` sans partie lancée/finie depuis 10 min → fermé, code libéré |
| places | 4–8, défaut 6 | « plein » quand les humains (joueurs + spectateurs) occupent toutes les places |
| `GK_LAUNCH_MIN_HUMANS` | 2 | pour lancer |
| rounds | 0–12 | 0 = pas encore publié |
| réglages | objet JSON ≤ 2 Ko | libres (IA, rounds, options…), à la main du client |
| état de partie (`game`) | objet JSON ≤ 4 Ko | publié par l'hôte, repris par un nouvel hôte |

Battement de cœur conseillé : `/room/presence` toutes les **2 à 3 s** (limite : 90/min par joueur).

## Objet « vue du salon »

Renvoyé par `create`, `join`, `presence`, `me`, `settings`, `launch`, `round`, `end`, `kick` :

```json
{
  "room": {
    "room_id": 12, "name": "Salon de Léa", "is_public": false, "code": "KXBT",
    "map": "port_pecheurs", "places": 6, "humans": 3, "full": false,
    "state": "attente | en_partie", "phase": "'' | round | scores",
    "round": 2, "total": 6,
    "settings": {}, "settings_version": 3,
    "game": {},
    "admin_id": 5, "admin_pseudo": "Léa", "admin_seq": 1, "admin_changed_at": 1792526890,
    "created_at": 1792526000, "last_game_at": 1792526800
  },
  "members": [
    {"player_id": 5, "pseudo": "Léa", "perso": "maia", "color": 0, "status": "joueur | spectateur",
     "is_admin": true, "joined_at": 1792526000, "connected": true, "me": false}
  ],
  "me": 7
}
```

- `members` est trié par **ordre d'arrivée** (le premier est le plus ancien).
- `code` : présent pour un salon privé (les membres peuvent le montrer aux copains), `null` sinon.
- **Nouvel admin** : `admin_seq` augmente à chaque passation. Le client garde la dernière valeur vue ;
  si elle change, il affiche « `admin_pseudo` est maintenant admin ». Si `admin_id == me`, il devient hôte.
- **Réglages changés** : `settings_version` augmente à chaque `/room/settings` (« tout le monde voit ce qui a
  changé »).
- `phase` est posée par l'hôte (`/room/round`) ; `scores` autorise réglages et changements de perso/couleur.

## Routes

### `POST /gk/player` — créer un joueur ou changer son pseudo
Corps : `{"pseudo": "Léa"}` → `{"player_id", "secret", "pseudo"}`.
Avec `player_id` + `secret` en plus : change le pseudo (aussi dans les salons où il est membre).
Erreurs : `400 bad_pseudo` (2–15 lettres, chiffres, `_`, `-`), `400 pseudo_refused` (filtre anti-gros-mots),
`401 auth`. Limite : 30 créations/min par IP.

### `GET /rooms` — liste des salons publics
Sans auth. Salons publics non fermés, jamais les privés ni de code :
```json
{"rooms": [{"room_id": 12, "name": "Salon de Léa", "map": "port_pecheurs", "places": 6, "humans": 3,
  "full": false, "state": "en_partie", "round": 3, "total": 6,
  "avatars": [{"perso": "maia", "color": 0, "is_admin": true}]}]}
```
Les salons pleins viennent en dernier (à griser). 50 au plus, les plus récents d'abord. Limite 120/min par IP.

### `POST /room/create`
Corps : `{auth, "public": true, "places": 6, "map": "port_pecheurs", "settings": {}, "perso": "maia", "color": 3}`
(tout facultatif sauf l'auth). Le créateur est admin, couleur attribuée comme au `join`. Créer fait quitter
le salon où l'on était. Privé → `room.code` (4 lettres de `ABCDEFGHJKMNPQRSTUVWXYZ`, unique parmi les
salons ouverts). Erreurs : `400 bad_places`, `400 bad_map`, `400 bad_settings`, `429`.

### `POST /room/join`
Corps : `{auth, "room_id": 12}` (salon **public**) ou `{auth, "code": "KXBT"}` (minuscules acceptées), plus
`"perso"` et `"color"` (couleur préférée). Couleur : la préférée si libre, sinon la plus proche libre par
indice (à égalité, la suivante : pour 7 prise → 8, puis 6). Arrivée pendant une partie → `status:
"spectateur"` ; il devient `joueur` au round suivant publié par l'hôte (qui retire alors une IA).
Idempotent : un membre encore présent (reconnexion avant 60 s) garde sa place et sa couleur.
Rejoindre fait quitter l'autre salon.
Erreurs : `400 bad_code`, `404 not_found` (« Aucun salon avec ce code » / « Ce salon n'existe plus » ; un id
de salon privé donne aussi `not_found`), `403 banned` (exclu), `409 room_full` (« Salon plein »).

### `POST /room/presence` — battement de cœur
Corps : `{auth, "room_id"}` → vue du salon. Retire au passage les membres non vus depuis 60 s et ferme les
salons inactifs. Erreurs à gérer côté client :
- `403 banned` : « L'admin a libéré ta place » → retour à la liste ;
- `404 not_member` : coupé plus de 60 s (place perdue) → retenter `/room/join` ;
- `410 closed` : salon fermé → retour à la liste.

### `POST /room/me` — changer de perso ou de couleur
Corps : `{auth, "room_id", "perso"?, "color"?}`. Permis en `attente` ou pendant les `scores`.
Erreurs : `409 in_round`, `400 bad_perso`, `400 bad_color`, `409 color_taken` (couleur stricte ici :
le client propose les couleurs libres, d'après `members`).

### `POST /room/settings` — admin
Corps : `{auth, "room_id", "places"?, "map"?, "settings"?}` (`settings` remplace l'objet entier).
Permis en `attente` ou pendant les `scores` ; les changements valent au round suivant.
Erreurs : `403 not_admin`, `409 in_round`, `400 bad_places` (hors 4–8), `409 bad_places` (moins que les
humains présents), `400 bad_map`, `400 bad_settings`.

### `POST /room/launch` — admin
Corps : `{auth, "room_id", "total"?}` (nombre de rounds prévu, 0–12). Passe en `en_partie`, `phase: "round"`,
`round: 0`. L'hôte complète avec des IA (jusqu'à 4 joueurs au moins, `places` au plus).
Erreurs : `403 not_admin`, `409 already_playing`, `409 too_few` (moins de 2 humains), `400 bad_round`.

### `POST /room/round` — hôte (admin)
Corps : `{auth, "room_id", "round": k, "total": N, "phase": "round" | "scores", "game"?: {…}}`.
À appeler au début de chaque round (`phase: "round"`, k croissant) et à l'écran des scores
(`phase: "scores"`). Un **nouveau** round (k > précédent, phase `round`) fait passer tous les spectateurs en
joueurs. `game` (≤ 4 Ko, facultatif) : scores cumulés, sac du chasseur… ; renvoyé dans la vue, il permet
à un nouvel hôte de reprendre (§11). Erreurs : `403 not_admin`, `409 not_playing`, `400 bad_round`.

### `POST /room/end` — admin
Corps : `{auth, "room_id"}`. Fin de partie (après le podium) ou arrêt anticipé pendant les scores : retour
en `attente`, tout le monde `joueur`, `last_game_at` remis à maintenant (les 10 min d'inactivité repartent).

### `POST /room/kick` — admin
Corps : `{auth, "room_id", "target": player_id}`. Retire le joueur et l'exclut de ce salon pour toujours.
Erreurs : `403 not_admin`, `400 bad_target` (soi-même).

### `POST /room/leave`
Corps : `{auth, "room_id"}` → `{"ok": true}`. Si l'admin part, le plus ancien humain restant devient admin
(`admin_seq` +1, nom du salon « Salon de <nouvel admin> »). Plus personne → salon fermé, code libéré.
À appeler aussi en quittant la page si possible (sinon la coupure de 60 s s'en charge).

### Signalisation en étoile
- `POST /room/signal` : `{auth, "room_id", "to": player_id, "payload": {"kind": "offer|answer|ice|hello|bye", …}}`
  → `{"id"}`. L'un des deux bouts doit être l'admin (hôte ↔ client). Payload ≤ 16 Ko.
  Erreurs : `400 bad_signal`, `413 too_big`, `404 bad_target` (destinataire absent), `403 not_host`
  (client → client).
- `GET /room/signal?player_id&secret&room_id&after=<dernier id>` → `{"messages": [{"id", "from", "payload"}]}`
  (100 au plus, croissants). Le client garde le dernier `id` et repart de là.
- Messages effacés après 10 min, et à la fermeture du salon.
- Limites : 600/min par joueur, 3000/min par IP.

## Codes `reason`

`auth`, `bad_pseudo`, `pseudo_refused`, `bad_places`, `bad_map`, `bad_settings`, `bad_code`, `not_found`,
`closed`, `not_member`, `banned`, `room_full`, `not_admin`, `in_round`, `bad_perso`, `bad_color`,
`color_taken`, `already_playing`, `too_few`, `not_playing`, `bad_round`, `bad_target`, `bad_signal`,
`too_big`, `not_host`, `server`. Les `429` (limite de débit) n'ont pas de `reason` : attendre et réessayer.

## Ce que le client doit faire

1. Au premier passage en ligne : `POST /gk/player` avec le pseudo du profil, garder `player_id`/`secret`
   par profil local ; resynchroniser le pseudo s'il change.
2. Liste : `GET /rooms` toutes les 3–5 s ; « Créer un salon » ; « J'ai un code » (clavier de 23 lettres).
3. Dans le salon : `/room/presence` toutes les 2–3 s ; repérer `admin_seq` (bandeau), `settings_version`,
   `state`/`phase`, son propre `status`, et les erreurs `banned` / `not_member` / `closed`.
4. Hôte : relier chaque client par WebRTC (`/net/config` pour STUN/TURN, `/room/signal` avec `to`), publier
   `/room/round` à chaque round et aux scores, avec `game` (scores) pour la reprise ; `/room/end` à la fin.
   Remplacer une IA par chaque spectateur passé `joueur`.
5. Nouvel hôte (admin_id devient soi pendant une partie) : annuler le round en cours sans points, relire
   `game`, relancer la connexion des clients et reprendre au round suivant (§11).
6. Clients : quand `admin_id` change, fermer la liaison avec l'ancien hôte et attendre l'`offer` du nouveau.

## Déploiement

Migration **additive** : tables `gk_players`, `rooms`, `room_members`, `room_bans`, `room_signals` créées
par `CREATE TABLE IF NOT EXISTS` à la première requête. Aucune action manuelle sur le serveur. Les routes
et tables de l'ancien jeu de combat ont été retirées du code (tag `avant-suppression-borroka`) ; les tables
d'une base existante restent, inutilisées. `MIARRITZE_CLOCK_FILE` (horloge des tests) n'est jamais posée en prod.
