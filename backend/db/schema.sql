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
