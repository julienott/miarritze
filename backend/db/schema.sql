-- Miarritze Borroka — schéma SQLite (SPEC-BORROKA §9.3).
-- Appliqué à chaque connexion (idempotent). Migration depuis l'ancien jeu :
-- la table `scores` des épreuves est supprimée (le jeu n'a jamais eu de public).
PRAGMA journal_mode = WAL;

DROP TABLE IF EXISTS scores;

CREATE TABLE IF NOT EXISTS groups (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT UNIQUE NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS players (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL REFERENCES groups(id),
  pseudo      TEXT NOT NULL,
  secret      TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  UNIQUE(group_id, pseudo)
);

CREATE TABLE IF NOT EXISTS profiles (
  player_id   INTEGER PRIMARY KEY REFERENCES players(id),
  fighter     TEXT NOT NULL DEFAULT 'louis',
  costume     INTEGER NOT NULL DEFAULT 0,
  banner      INTEGER NOT NULL DEFAULT 0,
  title       TEXT NOT NULL DEFAULT '',
  emote       INTEGER NOT NULL DEFAULT 0,
  stats_json  TEXT NOT NULL DEFAULT '{}',
  rating      INTEGER NOT NULL DEFAULT 1000,
  wins        INTEGER NOT NULL DEFAULT 0,
  losses      INTEGER NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS presence (
  player_id   INTEGER PRIMARY KEY REFERENCES players(id),
  status      TEXT NOT NULL,
  last_seen   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS matches (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL,
  p1          INTEGER NOT NULL,
  p2          INTEGER NOT NULL,
  state       TEXT NOT NULL,
  stage_p1    TEXT, stage_p2 TEXT, stage TEXT,
  seed        INTEGER NOT NULL,
  winner_p1   INTEGER, winner_p2 INTEGER,
  checksum_p1 INTEGER, checksum_p2 INTEGER,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_matches_p1 ON matches(p1, state);
CREATE INDEX IF NOT EXISTS idx_matches_p2 ON matches(p2, state);

CREATE TABLE IF NOT EXISTS signals (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  match_id    INTEGER NOT NULL REFERENCES matches(id),
  to_player   INTEGER NOT NULL,
  payload     TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_signals_to ON signals(to_player, id);

CREATE TABLE IF NOT EXISTS tower_scores (
  player_id   INTEGER NOT NULL REFERENCES players(id),
  fighter     TEXT NOT NULL,
  difficulty  TEXT NOT NULL,
  best_score  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (player_id, fighter, difficulty)
);

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

-- Demandes pour entrer dans un groupe vu dans « Salons actifs » : un membre
-- connecté accepte ou refuse ; le joueur n'est créé qu'à l'acceptation.
CREATE TABLE IF NOT EXISTS join_requests (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id    INTEGER NOT NULL REFERENCES groups(id),
  pseudo      TEXT NOT NULL,
  token       TEXT NOT NULL,
  state       TEXT NOT NULL,
  player_id   INTEGER,
  secret      TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_join_requests_group ON join_requests(group_id, state);

-- ------------------------------------------------------------------ Gordeka : salons
-- Miarritze Gordeka (SPEC-GORDEKA §6.2, §11). Tables additives : rien de Borroka
-- n'est modifié. Les joueurs Gordeka n'ont pas de groupe (table dédiée).
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
