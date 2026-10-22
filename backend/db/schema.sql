-- Miarritze Gordeka — schéma SQLite (docs/ONLINE_GORDEKA.md).
-- Appliqué à chaque connexion (idempotent). Les tables de l'ancien jeu de combat
-- (groups, players, profiles, presence, matches, signals, tower_scores, join_requests)
-- ne sont plus créées ; celles d'une base existante restent en place, inutilisées.
PRAGMA journal_mode = WAL;

-- ------------------------------------------------------------------ réseau
-- Échecs de connexion WebRTC (diagnostic, src/net/p2p_link.gd) et limitation de débit.
CREATE TABLE IF NOT EXISTS net_reports (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT NOT NULL,
  browser     TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  hits         INTEGER NOT NULL,
  PRIMARY KEY (key, window_start)
);

-- ------------------------------------------------------------------ Gordeka : salons
-- Miarritze Gordeka (SPEC-GORDEKA §6.2, §11). Les joueurs n'ont pas de groupe.
CREATE TABLE IF NOT EXISTS gk_players (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  pseudo      TEXT NOT NULL,
  secret      TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

-- state : attente | en_partie | ferme ; phase (posée par l'hôte) : '' | round | scores.
CREATE TABLE IF NOT EXISTS rooms (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  code              TEXT,
  is_public         INTEGER NOT NULL,
  name              TEXT NOT NULL,
  map               TEXT NOT NULL,
  places            INTEGER NOT NULL,
  state             TEXT NOT NULL,
  phase             TEXT NOT NULL DEFAULT '',
  round_current     INTEGER NOT NULL DEFAULT 0,
  round_total       INTEGER NOT NULL DEFAULT 0,
  settings_json     TEXT NOT NULL DEFAULT '{}',
  settings_version  INTEGER NOT NULL DEFAULT 1,
  game_json         TEXT NOT NULL DEFAULT '{}',
  admin_seq         INTEGER NOT NULL DEFAULT 0,
  admin_changed_at  INTEGER,
  created_at        INTEGER NOT NULL,
  last_game_at      INTEGER,
  closed_at         INTEGER
);
-- Code privé unique parmi les salons ouverts ; libéré à la fermeture.
CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_code_open ON rooms(code) WHERE state != 'ferme' AND code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rooms_state ON rooms(state, is_public);

-- status : joueur | spectateur. joined_at + rowid = ordre d'arrivée (passation d'admin).
CREATE TABLE IF NOT EXISTS room_members (
  room_id     INTEGER NOT NULL REFERENCES rooms(id),
  player_id   INTEGER NOT NULL REFERENCES gk_players(id),
  pseudo      TEXT NOT NULL,
  perso       TEXT NOT NULL,
  color       INTEGER NOT NULL,
  joined_at   INTEGER NOT NULL,
  is_admin    INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL,
  last_seen   INTEGER NOT NULL,
  PRIMARY KEY (room_id, player_id),
  UNIQUE (room_id, color)
);
CREATE INDEX IF NOT EXISTS idx_room_members_player ON room_members(player_id);
CREATE INDEX IF NOT EXISTS idx_room_members_seen ON room_members(last_seen);

CREATE TABLE IF NOT EXISTS room_bans (
  room_id     INTEGER NOT NULL REFERENCES rooms(id),
  player_id   INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (room_id, player_id)
);

-- Signalisation WebRTC en étoile (hôte ↔ chaque client), destinataire explicite.
CREATE TABLE IF NOT EXISTS room_signals (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  room_id     INTEGER NOT NULL REFERENCES rooms(id),
  from_player INTEGER NOT NULL,
  to_player   INTEGER NOT NULL,
  payload     TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_room_signals_to ON room_signals(to_player, room_id, id);
