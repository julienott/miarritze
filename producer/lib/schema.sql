-- Schéma du service /producer (commentaires d'assets, kanban, jalons), version 6.
-- Appliqué à chaque connexion : uniquement des CREATE ... IF NOT EXISTS.
-- Une base de version 1 (colonnes todo/doing/review/done, notes d'« agent »)
-- est migrée d'abord par App::migrate() (PRAGMA user_version) ; les colonnes
-- ajoutées depuis (v3, v4, v5, v6) le sont par ALTER TABLE dans migrate() : aucun
-- index ici ne doit porter sur elles (il serait créé avant la colonne).
-- v6 : la table cards est reconstruite par migrate() pour que sa contrainte CHECK
-- accepte 'valide' ; migrate() relit la définition de cards ci-dessous (en début de
-- ligne, close par « ); » seul sur sa ligne : garder cette forme).

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
    card_id     INTEGER,                       -- v5 : carte où le commentaire a été reporté (sans clé étrangère)
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS comments_asset ON comments (asset);

-- Jalons de la roadmap (v5). Une carte (souvent un chapeau) appartient à un
-- jalon au plus ; ses descendants comptent dans l'avancement du jalon.
CREATE TABLE IF NOT EXISTS milestones (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT    NOT NULL DEFAULT '',
    due         TEXT    NOT NULL DEFAULT '',     -- échéance AAAA-MM-JJ, ou ''
    position    INTEGER NOT NULL DEFAULT 0,
    closed      INTEGER NOT NULL DEFAULT 0,      -- 1 = jalon clos (atteint ou abandonné)
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

-- Kanban. Le type est validé côté PHP (CARD_TYPES) : en ajouter un ne
-- demande pas de migration.
CREATE TABLE IF NOT EXISTS cards (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    type        TEXT    NOT NULL DEFAULT 'feature',
    title       TEXT    NOT NULL,
    description TEXT    NOT NULL DEFAULT '',
    priority    TEXT    NOT NULL DEFAULT '' CHECK (priority IN ('', 'basse', 'normale', 'haute')),
    asset       TEXT    NOT NULL DEFAULT '',
    detail      TEXT    NOT NULL DEFAULT '',     -- précise l'asset : nom de l'animation (ex. walk)
    -- valide (v6) : accepté en QA, part en prod au prochain déploiement ; done = en prod.
    status      TEXT    NOT NULL DEFAULT 'backlog' CHECK (status IN ('backlog', 'todo', 'doing', 'qa', 'valide', 'done')),
    position    INTEGER NOT NULL DEFAULT 0,
    parent_id   INTEGER REFERENCES cards (id) ON DELETE SET NULL,   -- carte chapeau
    origin      TEXT    NOT NULL DEFAULT 'julien' CHECK (origin IN ('julien', 'claude')),
    rework      INTEGER NOT NULL DEFAULT 0,      -- 1 = refusée en QA, « à retraiter »
    night       INTEGER NOT NULL DEFAULT 0,      -- 1 = night shift : traitée la nuit (1 h – 8 h, Paris)
    milestone_id INTEGER REFERENCES milestones (id) ON DELETE SET NULL,   -- v5 : jalon de la roadmap
    due         TEXT    NOT NULL DEFAULT '',     -- v5 : échéance AAAA-MM-JJ, ou ''
    jobs        TEXT    NOT NULL DEFAULT '',     -- v6 : tâches pixelforge (liste JSON écrite par le watcher), ou ''
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS cards_parent ON cards (parent_id);

-- Commentaires des cartes (ex-« notes »).
CREATE TABLE IF NOT EXISTS card_notes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id     INTEGER NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
    author      TEXT    NOT NULL CHECK (author IN ('julien', 'claude')),
    body        TEXT    NOT NULL,
    kind        TEXT    NOT NULL DEFAULT '',     -- '' | 'refus'
    created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS card_notes_card ON card_notes (card_id);

-- Historique des cartes. Pas de clé étrangère : l'événement « suppression »
-- survit à la carte, pour que le fil `events` reste complet.
-- type : creation | deplacement | titre | description | priorite | type | asset
--        | detail | parent | night | jalon | echeance | jobs | commentaire | accepte | refuse
--        | suppression
CREATE TABLE IF NOT EXISTS card_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id     INTEGER NOT NULL,
    at          INTEGER NOT NULL,
    author      TEXT    NOT NULL CHECK (author IN ('julien', 'claude')),
    type        TEXT    NOT NULL,
    old         TEXT    NOT NULL DEFAULT '',
    new         TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS card_events_card ON card_events (card_id, at);
CREATE INDEX IF NOT EXISTS card_events_at ON card_events (at);

CREATE TABLE IF NOT EXISTS auth_failures (
    ip          TEXT    NOT NULL,
    at          INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS auth_failures_ip ON auth_failures (ip, at);
