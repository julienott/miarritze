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

-- Rate limiting simple (fenêtre glissante par clé ip/player)
CREATE TABLE IF NOT EXISTS rate_limits (
  key         TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  hits        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (key, window_start)
);
