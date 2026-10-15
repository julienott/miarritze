-- Schéma du service /producer (commentaires d'assets + kanban).
-- Appliqué à chaque connexion : uniquement des CREATE ... IF NOT EXISTS.
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS comments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    asset       TEXT    NOT NULL,              -- id de l'asset (chemin relatif à assets/)
    version     TEXT    NOT NULL,              -- hash court de la source vue
    build       TEXT    NOT NULL DEFAULT '',   -- commit git du build vu
    context     TEXT    NOT NULL DEFAULT '',   -- ex. nom de l'animation affichée
    kind        TEXT    NOT NULL CHECK (kind IN ('amelioration', 'valide')),
    body        TEXT    NOT NULL DEFAULT '',
    status      TEXT    NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done')),
    reply       TEXT    NOT NULL DEFAULT '',
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS comments_asset ON comments (asset);

CREATE TABLE IF NOT EXISTS cards (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    type        TEXT    NOT NULL CHECK (type IN ('feature', 'bug')),
    title       TEXT    NOT NULL,
    description TEXT    NOT NULL DEFAULT '',
    priority    TEXT    NOT NULL DEFAULT '' CHECK (priority IN ('', 'basse', 'normale', 'haute')),
    asset       TEXT    NOT NULL DEFAULT '',
    status      TEXT    NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'doing', 'review', 'done')),
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS card_notes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id     INTEGER NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    author      TEXT    NOT NULL CHECK (author IN ('julien', 'agent')),
    body        TEXT    NOT NULL,
    created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS card_notes_card ON card_notes (card_id);

CREATE TABLE IF NOT EXISTS auth_failures (
    ip          TEXT    NOT NULL,
    at          INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_failures_ip ON auth_failures (ip, at);
