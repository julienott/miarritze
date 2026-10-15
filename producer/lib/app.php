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
const CARD_STATUSES = ['todo', 'doing', 'review', 'done'];
const CARD_TYPES = ['feature', 'bug'];
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
    /** 'julien' | 'agent' | null */
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
            'POST card' => $this->addCard(),
            'POST card_update' => $this->updateCard(),
            'POST card_move' => $this->moveCard(),
            'POST card_note' => $this->addNote(),
            'POST card_delete' => $this->deleteCard(),
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
            $pdo->exec('PRAGMA foreign_keys = ON');
            $pdo->exec((string) file_get_contents(__DIR__ . '/schema.sql'));
            $this->pdo = $pdo;
        }
        return $this->pdo;
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
            $this->actor = 'agent';
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

    private function listCards(): void
    {
        $status = isset($_GET['status']) && is_string($_GET['status']) ? $_GET['status'] : '';
        if ($status !== '' && !in_array($status, CARD_STATUSES, true)) {
            throw new HttpError('Statut invalide', 400);
        }
        $db = $this->db();
        if ($status !== '') {
            $stmt = $db->prepare('SELECT * FROM cards WHERE status = ? ORDER BY position, id');
            $stmt->execute([$status]);
        } else {
            $stmt = $db->query('SELECT * FROM cards ORDER BY position, id');
        }
        $cards = $stmt->fetchAll();
        $notes = [];
        foreach ($db->query('SELECT * FROM card_notes ORDER BY id')->fetchAll() as $n) {
            $notes[(int) $n['card_id']][] = [
                'id' => (int) $n['id'], 'author' => $n['author'], 'body' => $n['body'], 'created_at' => (int) $n['created_at'],
            ];
        }
        foreach ($cards as &$c) {
            $c['id'] = (int) $c['id'];
            $c['position'] = (int) $c['position'];
            $c['notes'] = $notes[$c['id']] ?? [];
        }
        $this->json(['cards' => $cards]);
    }

    private function addCard(): void
    {
        $b = $this->body();
        $type = (string) self::oneOf($b, 'type', CARD_TYPES, true);
        $title = (string) self::text($b, 'title', MAX_TITLE, true);
        $desc = (string) (self::text($b, 'description', MAX_TEXT) ?? '');
        $prio = (string) (self::oneOf($b, 'priority', PRIORITIES) ?? '');
        $asset = (string) (self::text($b, 'asset', 300) ?? '');
        if ($asset !== '' && $this->asset($asset) === null) {
            throw new HttpError('Asset inconnu', 400);
        }
        $status = (string) (self::oneOf($b, 'status', CARD_STATUSES) ?? 'todo');
        $db = $this->db();
        $stmt = $db->prepare('SELECT COALESCE(MAX(position), -1) + 1 FROM cards WHERE status = ?');
        $stmt->execute([$status]);
        $pos = (int) $stmt->fetchColumn();
        $now = time();
        $db->prepare('INSERT INTO cards (type, title, description, priority, asset, status, position, created_at, updated_at)'
            . ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
            ->execute([$type, $title, $desc, $prio, $asset, $status, $pos, $now, $now]);
        $this->json(['id' => (int) $db->lastInsertId()], 201);
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
        ];
        if ($fields['title'] === '') {
            throw new HttpError('Titre vide', 400);
        }
        if (($fields['asset'] ?? '') !== '' && $this->asset((string) $fields['asset']) === null) {
            throw new HttpError('Asset inconnu', 400);
        }
        $sets = [];
        $args = [];
        foreach ($fields as $col => $v) {
            if ($v !== null) {
                $sets[] = "$col = ?";   // $col vient de la liste fixe ci-dessus
                $args[] = $v;
            }
        }
        if (!$sets) {
            throw new HttpError('Rien à modifier', 400);
        }
        $args[] = time();
        $args[] = $id;
        $stmt = $this->db()->prepare('UPDATE cards SET ' . implode(', ', $sets) . ', updated_at = ? WHERE id = ?');
        $stmt->execute($args);
        if ($stmt->rowCount() === 0) {
            throw new HttpError('Carte introuvable', 404);
        }
        $this->json(['ok' => true]);
    }

    private function moveCard(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $status = (string) self::oneOf($b, 'status', CARD_STATUSES, true);
        $index = $b['index'] ?? null;
        $db = $this->db();
        $db->beginTransaction();
        try {
            $stmt = $db->prepare('SELECT id FROM cards WHERE id = ?');
            $stmt->execute([$id]);
            if ($stmt->fetch() === false) {
                throw new HttpError('Carte introuvable', 404);
            }
            $stmt = $db->prepare('SELECT id FROM cards WHERE status = ? AND id != ? ORDER BY position, id');
            $stmt->execute([$status, $id]);
            $ids = array_map('intval', array_column($stmt->fetchAll(), 'id'));
            $at = is_int($index) ? max(0, min($index, count($ids))) : count($ids);
            array_splice($ids, $at, 0, [$id]);
            $upd = $db->prepare('UPDATE cards SET status = ?, position = ?, updated_at = CASE WHEN id = ? THEN ? ELSE updated_at END WHERE id = ?');
            foreach ($ids as $pos => $cid) {
                $upd->execute([$status, $pos, $id, time(), $cid]);
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
        $this->json(['ok' => true]);
    }

    private function addNote(): void
    {
        $b = $this->body();
        $id = self::id($b);
        $text = (string) self::text($b, 'body', MAX_TEXT, true);
        $db = $this->db();
        $stmt = $db->prepare('SELECT id FROM cards WHERE id = ?');
        $stmt->execute([$id]);
        if ($stmt->fetch() === false) {
            throw new HttpError('Carte introuvable', 404);
        }
        $now = time();
        $db->prepare('INSERT INTO card_notes (card_id, author, body, created_at) VALUES (?, ?, ?, ?)')
            ->execute([$id, $this->actor, $text, $now]);
        $db->prepare('UPDATE cards SET updated_at = ? WHERE id = ?')->execute([$now, $id]);
        $this->json(['id' => (int) $db->lastInsertId()], 201);
    }

    private function deleteCard(): void
    {
        $id = self::id($this->body());
        $stmt = $this->db()->prepare('DELETE FROM cards WHERE id = ?');
        $stmt->execute([$id]);
        if ($stmt->rowCount() === 0) {
            throw new HttpError('Carte introuvable', 404);
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
