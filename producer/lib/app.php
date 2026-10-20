<?php
declare(strict_types=1);

/**
 * Service /producer : explorateur d'assets, commentaires versionnés, kanban.
 *
 * Deux façons de s'authentifier :
 * - Julien : mot de passe -> session PHP (cookie HttpOnly, Secure, SameSite=Strict),
 *   jeton CSRF exigé (en-tête X-CSRF-Token) sur toute écriture ;
 * - l'agent : Authorization: Bearer <jeton> (ou X-Producer-Token), sans session.
 * Échecs d'authentification limités par IP (AUTH_MAX_FAILURES / AUTH_WINDOW).
 * SQL : requêtes préparées uniquement. Fichiers : liste blanche de l'index.
 */

const AUTH_MAX_FAILURES = 5;
const AUTH_WINDOW = 900;            // 15 min
const SESSION_LIFETIME = 2592000;   // 30 jours
const MAX_TITLE = 200;
const MAX_TEXT = 8000;
const SCHEMA_VERSION = 3;
// Colonnes du kanban, dans l'ordre. « review » (ancienne colonne) = « qa ».
const CARD_STATUSES = ['backlog', 'todo', 'doing', 'qa', 'done'];
const STATUS_ALIASES = ['review' => 'qa'];
const CARD_TYPES = ['feature', 'bug', 'perso', 'animation', 'asset', 'gameplay', 'pixelforge'];
const MAX_DEPTH = 3;                // chapeau > sous-chapeau > carte
const MAX_EVENTS = 1000;
const PRIORITIES = ['', 'basse', 'normale', 'haute'];
const COMMENT_KINDS = ['amelioration', 'valide'];
const COMMENT_STATUSES = ['open', 'done'];
const MIME = [
    'png' => 'image/png',
    'gif' => 'image/gif',
    'ogg' => 'audio/ogg',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'json' => 'application/json',
];

final class HttpError extends Exception
{
}

final class App
{
    private array $config;
    private string $root;
    private ?PDO $pdo = null;
    private ?array $index = null;
    /** 'julien' (session web) | 'claude' (jeton API) | null */
    private ?string $actor = null;

    public function __construct(string $root)
    {
        $this->root = $root;
        $file = $root . '/config.php';
        $this->config = is_file($file) ? (array) require $file : [];
    }

    // ================================================================ entrée

    public function run(): void
    {
        $this->securityHeaders();
        $route = isset($_GET['r']) && is_string($_GET['r']) ? $_GET['r'] : '';
        if ($route === '') {
            $this->page();
            return;
        }
        try {
            $this->dispatch($route, $_SERVER['REQUEST_METHOD'] ?? 'GET');
        } catch (HttpError $e) {
            $this->json(['error' => $e->getMessage()], $e->getCode() ?: 400);
        } catch (Throwable $e) {
            error_log('producer: ' . $e->getMessage());
            $this->json(['error' => 'Erreur serveur'], 500);
        }
    }

    private function dispatch(string $route, string $method): void
    {
        // Routes publiques (sans être connecté).
        if ($route === 'session' && $method === 'GET') {
            $this->startSession();
            $this->json(['auth' => ($_SESSION['auth'] ?? false) === true, 'csrf' => $this->csrf()]);
            return;
        }
        if ($route === 'login' && $method === 'POST') {
            $this->login();
            return;
        }
        $this->authenticate($method);
        if ($route === 'file' && $method === 'GET') {
            $this->serveFile();
            return;
        }
        header('Cache-Control: no-store');
        match ("$method $route") {
            'POST logout' => $this->logout(),
            'GET index' => $this->json($this->index()),
            'GET comments' => $this->listComments(),
            'POST comment' => $this->addComment(),
            'POST comment_update' => $this->updateComment(),
            'POST comment_delete' => $this->deleteComment(),
            'GET cards' => $this->listCards(),
            'GET card' => $this->showCard(),
            'GET events' => $this->listEvents(),
            'POST card' => $this->addCard(),
            'POST card_update' => $this->updateCard(),
            'POST card_move' => $this->moveCard(),
            'POST card_comment', 'POST card_note' => $this->addNote(),
            'POST card_delete' => $this->deleteCard(),
            'POST card_accept' => $this->acceptCard(),
            'POST card_refuse' => $this->refuseCard(),
            default => throw new HttpError('Route inconnue', 404),
        };
    }

    // ========================================================== sécurité

    private function securityHeaders(): void
    {
        header("Content-Security-Policy: default-src 'self'; img-src 'self' data: blob:; media-src 'self';"
            . " script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self';"
            . " frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'");
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: no-referrer');
        header('X-Frame-Options: DENY');
        header('X-Robots-Tag: noindex, nofollow');
        header('Cross-Origin-Resource-Policy: same-origin');
    }

    private function dataDir(): string
    {
        $dir = (string) ($this->config['data_dir'] ?? ($this->root . '/data'));
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        // Ceinture et bretelles : le dossier n'est jamais servi par Apache.
        if (!is_file($dir . '/.htaccess')) {
            file_put_contents($dir . '/.htaccess', "Require all denied\n");
        }
        return $dir;
    }

    private function db(): PDO
    {
        if ($this->pdo === null) {
            $pdo = new PDO('sqlite:' . $this->dataDir() . '/producer.sqlite', null, null, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
            $pdo->exec('PRAGMA busy_timeout = 3000');
            $pdo->exec('PRAGMA journal_mode = WAL');
            $this->migrate($pdo);
            $pdo->exec('PRAGMA foreign_keys = ON');
            $this->pdo = $pdo;
        }
        return $this->pdo;
    }

    /**
     * Applique schema.sql et migre une base de version 1 (idempotent, sûr en
     * concurrence : BEGIN IMMEDIATE puis nouvelle lecture de user_version).
     * v1 -> v2 : colonnes todo/doing/review/done -> todo/doing/qa/done (+ backlog),
     * types libres, parent_id, origin, auteurs « agent » -> « claude »,
     * historique card_events amorcé (création + commentaires existants).
     * v2 -> v3 : colonnes cards.detail, cards.rework, card_notes.kind.
     */
    private function migrate(PDO $pdo): void
    {
        $schema = (string) file_get_contents(__DIR__ . '/schema.sql');
        $version = static fn (): int => (int) $pdo->query('PRAGMA user_version')->fetchColumn();
        if ($version() >= SCHEMA_VERSION) {
            $pdo->exec($schema);
            return;
        }
        $exists = static function (string $table) use ($pdo): bool {
            $st = $pdo->prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?");
            $st->execute([$table]);
            return $st->fetchColumn() !== false;
        };
        $pdo->exec('PRAGMA foreign_keys = OFF');   // sans effet dans une transaction
        $pdo->exec('BEGIN IMMEDIATE');
        try {
            if ($version() < SCHEMA_VERSION) {
                $old = $exists('cards') && !$exists('card_events');
                $seq = 0;
                if ($old) {
                    $seq = (int) $pdo->query("SELECT COALESCE(MAX(seq), 0) FROM sqlite_sequence WHERE name = 'cards'")->fetchColumn();
                    // L'index suivrait la table renommée et masquerait le nouveau.
                    $pdo->exec('DROP INDEX IF EXISTS card_notes_card');
                    $pdo->exec('ALTER TABLE card_notes RENAME TO card_notes_v1');
                    $pdo->exec('ALTER TABLE cards RENAME TO cards_v1');
                }
                $pdo->exec($schema);
                if ($old) {
                    $pdo->exec("INSERT INTO cards (id, type, title, description, priority, asset, status, position,"
                        . " parent_id, origin, created_at, updated_at)"
                        . " SELECT id, type, title, description, priority, asset,"
                        . " CASE status WHEN 'review' THEN 'qa' ELSE status END, position, NULL, 'julien', created_at, updated_at"
                        . " FROM cards_v1");
                    $pdo->exec("INSERT INTO card_notes (id, card_id, author, body, created_at)"
                        . " SELECT id, card_id, CASE author WHEN 'agent' THEN 'claude' ELSE 'julien' END, body, created_at"
                        . " FROM card_notes_v1 WHERE card_id IN (SELECT id FROM cards)");
                    $pdo->exec("INSERT INTO card_events (card_id, at, author, type, old, new)"
                        . " SELECT id, created_at, origin, 'creation', '', status FROM cards");
                    $pdo->exec("INSERT INTO card_events (card_id, at, author, type, old, new)"
                        . " SELECT card_id, created_at, author, 'commentaire', '', body FROM card_notes ORDER BY id");
                    $pdo->exec('DROP TABLE card_notes_v1');
                    $pdo->exec('DROP TABLE cards_v1');
                    // Les ids de cartes supprimées ne sont jamais réutilisés.
                    if ($seq > 0) {
                        $pdo->exec("INSERT INTO sqlite_sequence (name, seq) SELECT 'cards', 0"
                            . " WHERE NOT EXISTS (SELECT 1 FROM sqlite_sequence WHERE name = 'cards')");
                        $pdo->prepare("UPDATE sqlite_sequence SET seq = MAX(seq, ?) WHERE name = 'cards'")->execute([$seq]);
                    }
                }
                // v2 -> v3 : détail de l'asset, « à retraiter », type de commentaire.
                foreach ([['cards', 'detail', "TEXT NOT NULL DEFAULT ''"], ['cards', 'rework', 'INTEGER NOT NULL DEFAULT 0'],
                    ['card_notes', 'kind', "TEXT NOT NULL DEFAULT ''"]] as [$table, $col, $def]) {
                    $cols = array_column($pdo->query("PRAGMA table_info($table)")->fetchAll(), 'name');
                    if (!in_array($col, $cols, true)) {
                        $pdo->exec("ALTER TABLE $table ADD COLUMN $col $def");   // noms fixes ci-dessus
                    }
                }
                $pdo->exec('PRAGMA user_version = ' . SCHEMA_VERSION);
            }
            $pdo->exec('COMMIT');
        } catch (Throwable $e) {
            $pdo->exec('ROLLBACK');
            throw $e;
        } finally {
            $pdo->exec('PRAGMA foreign_keys = ON');
        }
    }

    private function clientIp(): string
    {
        // REMOTE_ADDR seulement : X-Forwarded-For est falsifiable.
        return (string) ($_SERVER['REMOTE_ADDR'] ?? '?');
    }

    private function checkThrottle(): void
    {
        $stmt = $this->db()->prepare('SELECT COUNT(*) FROM auth_failures WHERE ip = ? AND at > ?');
        $stmt->execute([$this->clientIp(), time() - AUTH_WINDOW]);
        if ((int) $stmt->fetchColumn() >= AUTH_MAX_FAILURES) {
            header('Retry-After: ' . AUTH_WINDOW);
            throw new HttpError('Trop de tentatives, réessaie dans 15 minutes', 429);
        }
    }

    private function recordFailure(): void
    {
        $db = $this->db();
        $db->prepare('DELETE FROM auth_failures WHERE at < ?')->execute([time() - AUTH_WINDOW]);
        $db->prepare('INSERT INTO auth_failures (ip, at) VALUES (?, ?)')->execute([$this->clientIp(), time()]);
    }

    private function startSession(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        $dir = $this->dataDir() . '/sessions';
        if (!is_dir($dir)) {
            mkdir($dir, 0770, true);
        }
        $path = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/') . '/';
        session_save_path($dir);
        session_name('producer_sid');
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        ini_set('session.gc_maxlifetime', (string) SESSION_LIFETIME);
        ini_set('session.gc_probability', '1');
        ini_set('session.gc_divisor', '100');
        session_set_cookie_params([
            'lifetime' => SESSION_LIFETIME,
            'path' => $path,
            'secure' => (bool) ($this->config['cookie_secure'] ?? true),
            'httponly' => true,
            'samesite' => 'Strict',
        ]);
        session_start();
    }

    private function csrf(): string
    {
        if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf'];
    }

    private function bearer(): string
    {
        foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $key) {
            $h = (string) ($_SERVER[$key] ?? '');
            if (stripos($h, 'Bearer ') === 0) {
                return trim(substr($h, 7));
            }
        }
        // Repli : certains hébergements Apache/CGI suppriment Authorization.
        return trim((string) ($_SERVER['HTTP_X_PRODUCER_TOKEN'] ?? ''));
    }

    private function authenticate(string $method): void
    {
        $token = $this->bearer();
        if ($token !== '') {
            $this->checkThrottle();
            $expected = (string) ($this->config['token_sha256'] ?? '');
            if ($expected === '' || !hash_equals($expected, hash('sha256', $token))) {
                $this->recordFailure();
                throw new HttpError('Jeton invalide', 401);
            }
            $this->actor = 'claude';
            return;    // pas de cookie, donc pas de CSRF possible
        }
        $this->startSession();
        if (($_SESSION['auth'] ?? false) !== true) {
            throw new HttpError('Non connecté', 401);
        }
        if ($method !== 'GET') {
            $sent = (string) ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
            if ($sent === '' || !hash_equals($this->csrf(), $sent)) {
                throw new HttpError('Jeton CSRF invalide', 403);
            }
        }
        // Libère le verrou de session (requêtes parallèles d'images, audio…).
        session_write_close();
        $this->actor = 'julien';
    }

    private function login(): void
    {
        $this->startSession();
        $sent = (string) ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
        if ($sent === '' || !hash_equals($this->csrf(), $sent)) {
            throw new HttpError('Jeton CSRF invalide', 403);
        }
        $this->checkThrottle();
        $body = $this->body();
        $password = is_string($body['password'] ?? null) ? $body['password'] : '';
        $hash = (string) ($this->config['password_hash'] ?? '');
        if ($hash === '' || $password === '' || !password_verify($password, $hash)) {
            $this->recordFailure();
            throw new HttpError('Mot de passe incorrect', 401);
        }
        $this->db()->prepare('DELETE FROM auth_failures WHERE ip = ?')->execute([$this->clientIp()]);
        session_regenerate_id(true);
        $_SESSION['auth'] = true;
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
        $this->json(['auth' => true, 'csrf' => $_SESSION['csrf']]);
    }

    private function logout(): void
    {
        if ($this->actor === 'julien') {
            $this->startSession();
            $_SESSION = [];
            $p = session_get_cookie_params();
            setcookie(session_name(), '', [
                'expires' => time() - 3600, 'path' => $p['path'], 'secure' => $p['secure'],
                'httponly' => true, 'samesite' => 'Strict',
            ]);
            session_destroy();
        }
        $this->json(['auth' => false]);
    }

    // ============================================================== utilitaires

    private function json(mixed $data, int $code = 200): void
    {
        http_response_code($code);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    private function body(): array
    {
        $raw = file_get_contents('php://input', false, null, 0, 65536);
        $data = json_decode($raw === false ? '' : $raw, true);
        if (!is_array($data)) {
            throw new HttpError('Corps JSON attendu', 400);
        }
        return $data;
    }

    private static function text(array $b, string $key, int $max, bool $required = false): ?string
    {
        if (!array_key_exists($key, $b)) {
            if ($required) {
                throw new HttpError("Champ manquant : $key", 400);
            }
            return null;
        }
        if (!is_string($b[$key])) {
            throw new HttpError("Champ invalide : $key", 400);
        }
        $v = trim($b[$key]);
        if ((function_exists('mb_strlen') ? mb_strlen($v) : strlen($v)) > $max) {
            throw new HttpError("Champ trop long : $key", 400);
        }
        if ($required && $v === '') {
            throw new HttpError("Champ vide : $key", 400);
        }
        return $v;
    }

    private static function oneOf(array $b, string $key, array $allowed, bool $required = false): ?string
    {
        $v = self::text($b, $key, 32, $required);
        if ($v !== null && !in_array($v, $allowed, true)) {
            throw new HttpError("Valeur invalide : $key", 400);
        }
        return $v;
    }

    private static function id(array $b): int
    {
        $id = $b['id'] ?? null;
        if (is_string($id) && ctype_digit($id)) {
            $id = (int) $id;
        }
        if (!is_int($id) || $id <= 0) {
            throw new HttpError('id invalide', 400);
        }
        return $id;
    }

    private function filesDir(): string
    {
        return $this->root . '/files';
    }

    private function index(): array
    {
        if ($this->index === null) {
            $raw = @file_get_contents($this->filesDir() . '/index.json');
            $data = $raw === false ? null : json_decode($raw, true);
            $this->index = is_array($data) ? $data : ['commit' => '', 'categories' => [], 'assets' => [], 'files' => []];
        }
        return $this->index;
    }

    /** Asset de l'index par id, ou null. */
    private function asset(string $id): ?array
    {
        foreach ($this->index()['assets'] as $a) {
            if (($a['id'] ?? null) === $id) {
                return $a;
            }
        }
        return null;
    }

    // ================================================================ fichiers

    private function serveFile(): void
    {
        $p = isset($_GET['p']) && is_string($_GET['p']) ? $_GET['p'] : '';
        // Liste blanche stricte : seul un chemin listé par l'index est servi.
        $allowed = array_flip($this->index()['files'] ?? []);
        if ($p === '' || !isset($allowed[$p]) || str_contains($p, '..') || str_contains($p, "\0")) {
            throw new HttpError('Fichier introuvable', 404);
        }
        $base = realpath($this->filesDir());
        $full = realpath($this->filesDir() . '/' . $p);
        if ($base === false || $full === false || !str_starts_with($full, $base . DIRECTORY_SEPARATOR) || !is_file($full)) {
            throw new HttpError('Fichier introuvable', 404);
        }
        $ext = strtolower(pathinfo($full, PATHINFO_EXTENSION));
        $mime = MIME[$ext] ?? null;
        if ($mime === null) {
            throw new HttpError('Type non servi', 404);
        }
        $size = (int) filesize($full);
        $etag = '"' . md5($p . '|' . $size . '|' . filemtime($full)) . '"';
        header('Content-Type: ' . $mime);
        header('ETag: ' . $etag);
        header('Accept-Ranges: bytes');
        header('Cache-Control: private, no-cache');
        if (($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
            http_response_code(304);
            return;
        }
        // Requêtes partielles (Safari les exige pour l'audio).
        $start = 0;
        $end = $size - 1;
        $range = (string) ($_SERVER['HTTP_RANGE'] ?? '');
        if ($range !== '' && $size > 0) {
            if (!preg_match('/^bytes=(\d*)-(\d*)$/', $range, $m) || ($m[1] === '' && $m[2] === '')) {
                http_response_code(416);
                header("Content-Range: bytes */$size");
                return;
            }
            if ($m[1] === '') {
                $start = max(0, $size - (int) $m[2]);
            } else {
                $start = (int) $m[1];
                $end = $m[2] === '' ? $size - 1 : min((int) $m[2], $size - 1);
            }
            if ($start > $end || $start >= $size) {
                http_response_code(416);
                header("Content-Range: bytes */$size");
                return;
            }
            http_response_code(206);
            header("Content-Range: bytes $start-$end/$size");
        }
        $length = $end - $start + 1;
        header('Content-Length: ' . $length);
        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'HEAD') {
            return;
        }
        $fh = fopen($full, 'rb');
        if ($fh === false) {
            throw new HttpError('Lecture impossible', 500);
        }
        fseek($fh, $start);
        $left = $length;
        while ($left > 0 && !feof($fh)) {
            $chunk = fread($fh, min(65536, $left));
            if ($chunk === false) {
                break;
            }
            echo $chunk;
            $left -= strlen($chunk);
        }
        fclose($fh);
    }

    // ============================================================ commentaires

    private function listComments(): void
    {
        $where = [];
        $args = [];
        $asset = isset($_GET['asset']) && is_string($_GET['asset']) ? $_GET['asset'] : '';
        if ($asset !== '') {
            $where[] = 'asset = ?';
            $args[] = $asset;
        }
        $status = isset($_GET['status']) && is_string($_GET['status']) ? $_GET['status'] : '';
        if ($status !== '') {
            if (!in_array($status, COMMENT_STATUSES, true)) {
                throw new HttpError('Statut invalide', 400);
            }
            $where[] = 'status = ?';
            $args[] = $status;
        }
        $sql = 'SELECT * FROM comments' . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . ' ORDER BY id DESC';
        $stmt = $this->db()->prepare($sql);
        $stmt->execute($args);
        $rows = $stmt->fetchAll();
        // Version courante de chaque asset, pour signaler « version précédente ».
        $current = [];
        foreach ($this->index()['assets'] as $a) {
            $current[$a['id']] = $a['version'];
        }
        foreach ($rows as &$r) {
            $r['id'] = (int) $r['id'];
            $r['current_version'] = $current[$r['asset']] ?? null;
            $r['outdated'] = $r['current_version'] !== null && $r['current_version'] !== $r['version'];
        }
        $this->json(['comments' => $rows, 'commit' => $this->index()['commit'] ?? '']);
    }

    private function addComment(): void
    {
        $b = $this->body();
        $assetId = (string) self::text($b, 'asset', 300, true);
        $asset = $this->asset($assetId);
        if ($asset === null) {
            throw new HttpError('Asset inconnu', 400);
        }
        $kind = (string) self::oneOf($b, 'kind', COMMENT_KINDS, true);
        $text = (string) (self::text($b, 'body', MAX_TEXT) ?? '');
        if ($kind === 'amelioration' && $text === '') {
            throw new HttpError('Décris l\'amélioration souhaitée', 400);
        }
        $context = (string) (self::text($b, 'context', 100) ?? '');
        $now = time();
        // La version enregistrée est celle de l'index servi (pas celle envoyée).
        $this->db()->prepare('INSERT INTO comments (asset, version, build, context, kind, body, created_at, updated_at)'
            . ' VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
            ->execute([$assetId, (string) $asset['version'], (string) ($this->index()['commit'] ?? ''),
                $context, $kind, $text, $now, $now]);
        $this->json(['id' => (int) $this->db()->lastInsertId()], 201);
    }

    private function updateComment(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $status = self::oneOf($b, 'status', COMMENT_STATUSES);
        $reply = self::text($b, 'reply', MAX_TEXT);
        $sets = [];
        $args = [];
        if ($status !== null) {
            $sets[] = 'status = ?';
            $args[] = $status;
        }
        if ($reply !== null) {
            $sets[] = 'reply = ?';
            $args[] = $reply;
        }
        if (!$sets) {
            throw new HttpError('Rien à modifier', 400);
        }
        $args[] = time();
        $args[] = $id;
        $stmt = $this->db()->prepare('UPDATE comments SET ' . implode(', ', $sets) . ', updated_at = ? WHERE id = ?');
        $stmt->execute($args);
        if ($stmt->rowCount() === 0) {
            throw new HttpError('Commentaire introuvable', 404);
        }
        $this->json(['ok' => true]);
    }

    private function deleteComment(): void
    {
        $id = self::id($this->body());
        $stmt = $this->db()->prepare('DELETE FROM comments WHERE id = ?');
        $stmt->execute([$id]);
        if ($stmt->rowCount() === 0) {
            throw new HttpError('Commentaire introuvable', 404);
        }
        $this->json(['ok' => true]);
    }

    // ================================================================== kanban

    /** Statut lu dans le corps (alias « review » -> « qa »). */
    private static function status(array $b, bool $required = false): ?string
    {
        $v = self::text($b, 'status', 32, $required);
        if ($v === null) {
            return null;
        }
        $v = STATUS_ALIASES[$v] ?? $v;
        if (!in_array($v, CARD_STATUSES, true)) {
            throw new HttpError('Statut invalide', 400);
        }
        return $v;
    }

    /** Parent lu dans le corps : absent -> null, 0/''/null -> 0 (aucun), sinon id. */
    private static function parentArg(array $b): ?int
    {
        if (!array_key_exists('parent', $b)) {
            return null;
        }
        $p = $b['parent'];
        if ($p === null || $p === '' || $p === 0 || $p === '0') {
            return 0;
        }
        if (is_string($p) && ctype_digit($p)) {
            $p = (int) $p;
        }
        if (!is_int($p) || $p < 0) {
            throw new HttpError('parent invalide', 400);
        }
        return $p;
    }

    /** Une carte par id, ou 404. */
    private function card(int $id): array
    {
        $stmt = $this->db()->prepare('SELECT * FROM cards WHERE id = ?');
        $stmt->execute([$id]);
        $c = $stmt->fetch();
        if ($c === false) {
            throw new HttpError('Carte introuvable', 404);
        }
        return $c;
    }

    /**
     * Vérifie qu'on peut accrocher la carte $id (0 = nouvelle) sous $parent :
     * parent existant, pas de boucle, au plus MAX_DEPTH niveaux.
     */
    private function checkParent(int $id, int $parent): void
    {
        if ($parent === 0) {
            return;
        }
        $db = $this->db();
        $up = $db->prepare('SELECT parent_id FROM cards WHERE id = ?');
        // Ancêtres du parent (le parent compris).
        $depth = 0;
        for ($cur = $parent; $cur !== 0; $depth++) {
            if ($cur === $id || $depth > MAX_DEPTH) {
                throw new HttpError('Parent invalide : boucle', 400);
            }
            $up->execute([$cur]);
            $row = $up->fetch();
            if ($row === false) {
                throw new HttpError('Carte parent introuvable', 400);
            }
            $cur = (int) ($row['parent_id'] ?? 0);
        }
        // Hauteur du sous-arbre de la carte déplacée.
        $height = 1;
        $down = $db->prepare('SELECT id FROM cards WHERE parent_id = ?');
        $level = $id > 0 ? [$id] : [];
        while ($level) {
            $next = [];
            foreach ($level as $cid) {
                $down->execute([$cid]);
                foreach ($down->fetchAll() as $r) {
                    $next[] = (int) $r['id'];
                }
            }
            if ($next) {
                $height++;
            }
            $level = $next;
        }
        if ($depth + $height > MAX_DEPTH) {
            throw new HttpError('Trop de niveaux de chapeaux (' . MAX_DEPTH . ' au plus)', 400);
        }
    }

    /** Écrit un événement d'historique (auteur = l'acteur authentifié). */
    private function event(int $cardId, string $type, string $old = '', string $new = '', ?int $at = null): void
    {
        $this->db()->prepare('INSERT INTO card_events (card_id, at, author, type, old, new) VALUES (?, ?, ?, ?, ?, ?)')
            ->execute([$cardId, $at ?? time(), $this->actor, $type, $old, $new]);
    }

    /** Typage JSON d'une ligne de carte. */
    private static function castCard(array $c): array
    {
        $c['id'] = (int) $c['id'];
        $c['position'] = (int) $c['position'];
        $c['parent_id'] = $c['parent_id'] === null ? null : (int) $c['parent_id'];
        $c['created_at'] = (int) $c['created_at'];
        $c['updated_at'] = (int) $c['updated_at'];
        $c['rework'] = (bool) (int) $c['rework'];
        return $c;
    }

    /**
     * Toutes les cartes, avec commentaires (`notes`) et avancement des enfants
     * (`children` : total, `children_done` : qa + done, descendants compris).
     */
    private function allCards(): array
    {
        $db = $this->db();
        $cards = [];
        foreach ($db->query('SELECT * FROM cards ORDER BY position, id')->fetchAll() as $c) {
            $c = self::castCard($c);
            $c['notes'] = [];
            $c['children'] = 0;
            $c['children_done'] = 0;
            $cards[$c['id']] = $c;
        }
        foreach ($db->query('SELECT * FROM card_notes ORDER BY id')->fetchAll() as $n) {
            $cid = (int) $n['card_id'];
            if (isset($cards[$cid])) {
                $cards[$cid]['notes'][] = [
                    'id' => (int) $n['id'], 'author' => $n['author'], 'body' => $n['body'], 'kind' => $n['kind'],
                    'created_at' => (int) $n['created_at'],
                ];
            }
        }
        foreach ($cards as $c) {
            $done = in_array($c['status'], ['qa', 'done'], true) ? 1 : 0;
            // Remonte la chaîne : chaque ancêtre compte ce descendant.
            for ($p = $c['parent_id'], $guard = 0; $p !== null && isset($cards[$p]) && $guard < 10; $guard++) {
                $cards[$p]['children']++;
                $cards[$p]['children_done'] += $done;
                $p = $cards[$p]['parent_id'];
            }
        }
        return array_values($cards);
    }

    private function listCards(): void
    {
        $status = isset($_GET['status']) && is_string($_GET['status']) ? $_GET['status'] : '';
        $status = STATUS_ALIASES[$status] ?? $status;
        if ($status !== '' && !in_array($status, CARD_STATUSES, true)) {
            throw new HttpError('Statut invalide', 400);
        }
        $parent = isset($_GET['parent']) && is_string($_GET['parent']) && ctype_digit($_GET['parent']) ? (int) $_GET['parent'] : 0;
        $cards = array_values(array_filter($this->allCards(), static fn (array $c): bool =>
            ($status === '' || $c['status'] === $status) && ($parent === 0 || $c['parent_id'] === $parent)));
        $this->json(['cards' => $cards]);
    }

    private function eventRows(string $where, array $args): array
    {
        $stmt = $this->db()->prepare('SELECT e.*, c.title AS card_title, c.status AS card_status FROM card_events e'
            . ' LEFT JOIN cards c ON c.id = e.card_id' . $where . ' ORDER BY e.at, e.id LIMIT ' . MAX_EVENTS);
        $stmt->execute($args);
        $rows = $stmt->fetchAll();
        foreach ($rows as &$r) {
            $r['id'] = (int) $r['id'];
            $r['card_id'] = (int) $r['card_id'];
            $r['at'] = (int) $r['at'];
        }
        return $rows;
    }

    /** Une carte, son historique (commentaires compris) et ses enfants. */
    private function showCard(): void
    {
        $id = self::id($_GET);
        $card = null;
        $children = [];
        foreach ($this->allCards() as $c) {
            if ($c['id'] === $id) {
                $card = $c;
            } elseif ($c['parent_id'] === $id) {
                $children[] = $c;
            }
        }
        if ($card === null) {
            throw new HttpError('Carte introuvable', 404);
        }
        $this->json(['card' => $card, 'children' => $children, 'events' => $this->eventRows(' WHERE e.card_id = ?', [$id])]);
    }

    /** Tous les événements du board depuis `since` (inclus), pour la boucle de l'agent. */
    private function listEvents(): void
    {
        $since = isset($_GET['since']) && is_string($_GET['since']) && ctype_digit($_GET['since']) ? (int) $_GET['since'] : 0;
        $where = ' WHERE e.at >= ?';
        $args = [$since];
        if (isset($_GET['card']) && is_string($_GET['card']) && ctype_digit($_GET['card'])) {
            $where .= ' AND e.card_id = ?';
            $args[] = (int) $_GET['card'];
        }
        $this->json(['events' => $this->eventRows($where, $args), 'now' => time()]);
    }

    private function addCard(): void
    {
        $b = $this->body();
        $type = (string) (self::oneOf($b, 'type', CARD_TYPES) ?: 'feature');
        $title = (string) self::text($b, 'title', MAX_TITLE, true);
        $desc = (string) (self::text($b, 'description', MAX_TEXT) ?? '');
        $prio = (string) (self::oneOf($b, 'priority', PRIORITIES) ?? '');
        $asset = (string) (self::text($b, 'asset', 300) ?? '');
        if ($asset !== '' && $this->asset($asset) === null) {
            throw new HttpError('Asset inconnu', 400);
        }
        $detail = (string) (self::text($b, 'detail', 100) ?? '');
        $status = (string) (self::status($b) ?? 'backlog');
        $parent = (int) self::parentArg($b);
        $this->checkParent(0, $parent);
        $db = $this->db();
        $db->beginTransaction();
        try {
            $stmt = $db->prepare('SELECT COALESCE(MAX(position), -1) + 1 FROM cards WHERE status = ?');
            $stmt->execute([$status]);
            $pos = (int) $stmt->fetchColumn();
            $now = time();
            $db->prepare('INSERT INTO cards (type, title, description, priority, asset, detail, status, position, parent_id, origin,'
                . ' created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
                ->execute([$type, $title, $desc, $prio, $asset, $detail, $status, $pos, $parent ?: null, $this->actor, $now, $now]);
            $id = (int) $db->lastInsertId();
            $this->event($id, 'creation', '', $status, $now);
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['id' => $id], 201);
    }

    private function updateCard(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $fields = [
            'type' => self::oneOf($b, 'type', CARD_TYPES),
            'title' => self::text($b, 'title', MAX_TITLE),
            'description' => self::text($b, 'description', MAX_TEXT),
            'priority' => self::oneOf($b, 'priority', PRIORITIES),
            'asset' => self::text($b, 'asset', 300),
            'detail' => self::text($b, 'detail', 100),
        ];
        $parent = self::parentArg($b);
        if ($fields['title'] === '') {
            throw new HttpError('Titre vide', 400);
        }
        if ($fields['type'] === '') {
            $fields['type'] = null;
        }
        if (($fields['asset'] ?? '') !== '' && $this->asset((string) $fields['asset']) === null) {
            throw new HttpError('Asset inconnu', 400);
        }
        if ($parent === null && !array_filter($fields, static fn ($v) => $v !== null)) {
            throw new HttpError('Rien à modifier', 400);
        }
        $db = $this->db();
        $db->beginTransaction();
        try {
            $cur = $this->card($id);
            // Nom de l'événement par colonne (« $col » vient de cette liste fixe).
            $names = ['type' => 'type', 'title' => 'titre', 'description' => 'description', 'priority' => 'priorite',
                'asset' => 'asset', 'detail' => 'detail'];
            $sets = [];
            $args = [];
            foreach ($fields as $col => $v) {
                if ($v !== null && $v !== (string) $cur[$col]) {
                    $sets[] = "$col = ?";
                    $args[] = $v;
                    $this->event($id, $names[$col], (string) $cur[$col], $v);
                }
            }
            $oldParent = (int) ($cur['parent_id'] ?? 0);
            if ($parent !== null && $parent !== $oldParent) {
                $this->checkParent($id, $parent);
                $sets[] = 'parent_id = ?';
                $args[] = $parent ?: null;
                $this->event($id, 'parent', $oldParent ? (string) $oldParent : '', $parent ? (string) $parent : '');
            }
            if ($sets) {
                $args[] = time();
                $args[] = $id;
                $db->prepare('UPDATE cards SET ' . implode(', ', $sets) . ', updated_at = ? WHERE id = ?')->execute($args);
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true, 'changed' => count($sets)]);
    }

    private function moveCard(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $status = (string) self::status($b, true);
        $index = $b['index'] ?? null;
        $db = $this->db();
        $db->beginTransaction();
        try {
            $old = (string) $this->card($id)['status'];
            $this->placeCard($id, $status, $index);
            // Le simple réordonnancement dans une colonne n'est pas historisé.
            if ($old !== $status) {
                $this->event($id, 'deplacement', $old, $status);
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true]);
    }

    /**
     * Range la carte $id dans la colonne $status à la position $index (fin par
     * défaut) et renumérote la colonne. Repasser en QA efface « à retraiter ».
     * À appeler dans une transaction.
     */
    private function placeCard(int $id, string $status, mixed $index = null): void
    {
        $db = $this->db();
        $stmt = $db->prepare('SELECT id FROM cards WHERE status = ? AND id != ? ORDER BY position, id');
        $stmt->execute([$status, $id]);
        $ids = array_map('intval', array_column($stmt->fetchAll(), 'id'));
        $at = is_int($index) ? max(0, min($index, count($ids))) : count($ids);
        array_splice($ids, $at, 0, [$id]);
        $upd = $db->prepare('UPDATE cards SET status = ?, position = ?, updated_at = CASE WHEN id = ? THEN ? ELSE updated_at END WHERE id = ?');
        foreach ($ids as $pos => $cid) {
            $upd->execute([$status, $pos, $id, time(), $cid]);
        }
        if ($status === 'qa') {
            $db->prepare('UPDATE cards SET rework = 0 WHERE id = ?')->execute([$id]);
        }
    }

    /**
     * QA : Julien accepte la carte -> Done (événement « accepte »). Un chapeau
     * accepte aussi ses descendants encore en QA. Renvoie les ids acceptés.
     */
    private function acceptCard(): void
    {
        $id = self::id($this->body());
        $db = $this->db();
        $db->beginTransaction();
        try {
            if ($this->card($id)['status'] !== 'qa') {
                throw new HttpError('Seule une carte en QA peut être acceptée', 400);
            }
            $accepted = [];
            $fam = $this->descendants($id);
            $st = $db->prepare('SELECT status FROM cards WHERE id = ?');
            foreach (array_merge([$id], $fam) as $cid) {
                $st->execute([$cid]);
                if ($st->fetchColumn() !== 'qa') {
                    continue;
                }
                $this->placeCard($cid, 'done');
                $this->event($cid, 'accepte', 'qa', 'done');
                $accepted[] = $cid;
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true, 'accepted' => $accepted]);
    }

    /** QA : refus avec commentaire obligatoire -> Doing, « à retraiter » (événement « refuse »). */
    private function refuseCard(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $text = (string) self::text($b, 'body', MAX_TEXT, true);
        $db = $this->db();
        $db->beginTransaction();
        try {
            if ($this->card($id)['status'] !== 'qa') {
                throw new HttpError('Seule une carte en QA peut être refusée', 400);
            }
            $now = time();
            $db->prepare("INSERT INTO card_notes (card_id, author, body, kind, created_at) VALUES (?, ?, ?, 'refus', ?)")
                ->execute([$id, $this->actor, $text, $now]);
            $this->placeCard($id, 'doing');
            $db->prepare('UPDATE cards SET rework = 1 WHERE id = ?')->execute([$id]);
            $this->event($id, 'refuse', 'qa', $text, $now);
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true]);
    }

    /** Ids des descendants d'une carte. */
    private function descendants(int $id): array
    {
        $down = $this->db()->prepare('SELECT id FROM cards WHERE parent_id = ? ORDER BY position, id');
        $out = [];
        $level = [$id];
        for ($guard = 0; $level && $guard < MAX_DEPTH + 1; $guard++) {
            $next = [];
            foreach ($level as $cid) {
                $down->execute([$cid]);
                foreach (array_column($down->fetchAll(), 'id') as $k) {
                    $next[] = (int) $k;
                }
            }
            $out = array_merge($out, $next);
            $level = $next;
        }
        return $out;
    }

    /** Commentaire sur une carte (route card_comment, alias historique card_note). */
    private function addNote(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $text = (string) self::text($b, 'body', MAX_TEXT, true);
        $db = $this->db();
        $db->beginTransaction();
        try {
            $this->card($id);
            $now = time();
            $db->prepare('INSERT INTO card_notes (card_id, author, body, created_at) VALUES (?, ?, ?, ?)')
                ->execute([$id, $this->actor, $text, $now]);
            $nid = (int) $db->lastInsertId();
            $db->prepare('UPDATE cards SET updated_at = ? WHERE id = ?')->execute([$now, $id]);
            $this->event($id, 'commentaire', '', $text, $now);
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['id' => $nid], 201);
    }

    private function deleteCard(): void
    {
        $id = self::id($this->body());
        $db = $this->db();
        $db->beginTransaction();
        try {
            $title = (string) $this->card($id)['title'];
            // Les enfants restent, détachés (ON DELETE SET NULL).
            $db->prepare('DELETE FROM cards WHERE id = ?')->execute([$id]);
            $this->event($id, 'suppression', $title, '');
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true]);
    }

    // =================================================================== page

    private function page(): void
    {
        header('Content-Type: text/html; charset=utf-8');
        header('Cache-Control: no-cache');
        // Coquille statique : aucune donnée dedans, tout passe par l'API.
        readfile(__DIR__ . '/page.html');
    }
}
