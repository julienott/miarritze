<?php
declare(strict_types=1);

/**
 * Routeur unique de l'API Miarritze (contrat : CLAUDE.md §6.2).
 *
 *   POST /api/group              → { code }
 *   POST /api/group/join         → { player_id, secret }
 *   POST /api/score              → { best_score, cumulative }
 *   GET  /api/leaderboard        → [{ pseudo, best_score }] ou [{ pseudo, total }]
 */

require __DIR__ . '/../src/Db.php';
require __DIR__ . '/../src/Validation.php';
require __DIR__ . '/../src/Profanity.php';

$configFile = __DIR__ . '/../config.php';
$config = is_file($configFile) ? require $configFile : [];

header('Content-Type: application/json; charset=utf-8');

// CORS : le jeu est servi sur la même origine → rien à ouvrir par défaut.
// allowed_origin dans config.php sert uniquement au dev depuis l'éditeur Godot.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$allowedOrigin = $config['allowed_origin'] ?? '';
if ($allowedOrigin !== '' && $origin === $allowedOrigin) {
    header('Access-Control-Allow-Origin: ' . $allowedOrigin);
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
}
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$apiPos = strpos($path, '/api');
$route = $apiPos === false ? $path : substr($path, $apiPos + 4);
$route = '/' . trim($route, '/');

try {
    $pdo = Db::get($config);
    match (true) {
        $method === 'POST' && $route === '/group' => handleCreateGroup($pdo),
        $method === 'POST' && $route === '/group/join' => handleJoinGroup($pdo),
        $method === 'POST' && $route === '/score' => handlePostScore($pdo, $config),
        $method === 'GET' && $route === '/leaderboard' => handleLeaderboard($pdo),
        default => fail(404, 'Route inconnue'),
    };
} catch (Throwable $e) {
    error_log('miarritze api: ' . $e->getMessage());
    fail(500, 'Erreur serveur');
}

// ---------------------------------------------------------------------------

function handleCreateGroup(PDO $pdo): void
{
    rateLimit($pdo, 'group:' . clientIp(), 10);
    $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sans 0/O/1/I/L ambigus
    for ($attempt = 0; $attempt < 10; $attempt++) {
        $code = '';
        for ($i = 0; $i < 6; $i++) {
            $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        $stmt = $pdo->prepare('INSERT OR IGNORE INTO groups (code, created_at) VALUES (?, ?)');
        $stmt->execute([$code, time()]);
        if ($stmt->rowCount() === 1) {
            ok(['code' => $code]);
        }
    }
    fail(500, 'Impossible de générer un code');
}

function handleJoinGroup(PDO $pdo): void
{
    rateLimit($pdo, 'join:' . clientIp(), 20);
    $body = jsonBody();
    $code = strtoupper(trim((string) ($body['code'] ?? '')));
    $pseudo = trim((string) ($body['pseudo'] ?? ''));

    if (!Validation::isValidGroupCode($code)) {
        fail(400, 'Code de groupe invalide');
    }
    if (!Validation::isValidPseudo($pseudo)) {
        fail(400, 'Pseudo invalide (2 à 15 lettres ou chiffres)');
    }
    if (!Profanity::isClean($pseudo)) {
        fail(400, 'Ce pseudo n\'est pas accepté, choisis-en un autre');
    }

    $stmt = $pdo->prepare('SELECT id FROM groups WHERE code = ?');
    $stmt->execute([$code]);
    $group = $stmt->fetch();
    if ($group === false) {
        fail(404, 'Groupe introuvable — vérifie le code');
    }

    $secret = bin2hex(random_bytes(16));
    $stmt = $pdo->prepare(
        'INSERT INTO players (group_id, pseudo, secret, created_at) VALUES (?, ?, ?, ?)'
    );
    try {
        $stmt->execute([(int) $group['id'], $pseudo, $secret, time()]);
    } catch (PDOException $e) {
        fail(409, 'Pseudo déjà pris dans ce groupe');
    }
    ok(['player_id' => (int) $pdo->lastInsertId(), 'secret' => $secret]);
}

function handlePostScore(PDO $pdo, array $config): void
{
    $body = jsonBody();
    $playerId = $body['player_id'] ?? 0;
    $secret = (string) ($body['secret'] ?? '');
    $challenge = (string) ($body['challenge'] ?? '');
    $score = $body['score'] ?? null;

    if (!is_int($playerId) || $playerId <= 0 || $secret === '') {
        fail(401, 'Identifiants manquants');
    }
    rateLimit($pdo, 'score:' . clientIp(), 60);
    rateLimit($pdo, 'score:p' . $playerId, 30);
    if (!Validation::isValidChallenge($challenge)) {
        fail(400, 'Épreuve inconnue');
    }
    if (!Validation::isPlausibleScore($challenge, $score)) {
        fail(400, 'Score refusé');
    }

    $stmt = $pdo->prepare('SELECT id, secret FROM players WHERE id = ?');
    $stmt->execute([$playerId]);
    $player = $stmt->fetch();
    if ($player === false || !hash_equals((string) $player['secret'], $secret)) {
        fail(401, 'Joueur inconnu ou jeton invalide');
    }

    $stmt = $pdo->prepare(
        'INSERT INTO scores (player_id, challenge, best_score, updated_at)
         VALUES (:p, :c, :s, :t)
         ON CONFLICT(player_id, challenge)
         -- CAST requis : PDO binde en TEXT et en SQLite un texte est toujours
         -- supérieur à un entier, ce qui casserait le MAX.
         DO UPDATE SET best_score = MAX(best_score, CAST(:s AS INTEGER)), updated_at = :t'
    );
    $stmt->execute([':p' => $playerId, ':c' => $challenge, ':s' => $score, ':t' => time()]);

    $stmt = $pdo->prepare('SELECT best_score FROM scores WHERE player_id = ? AND challenge = ?');
    $stmt->execute([$playerId, $challenge]);
    $best = (int) $stmt->fetchColumn();

    $core = implode(',', array_fill(0, count(Validation::CORE), '?'));
    $stmt = $pdo->prepare(
        "SELECT COALESCE(SUM(best_score), 0) FROM scores WHERE player_id = ? AND challenge IN ($core)"
    );
    $stmt->execute([$playerId, ...Validation::CORE]);
    $cumulative = (int) $stmt->fetchColumn();

    ok(['best_score' => $best, 'cumulative' => $cumulative]);
}

function handleLeaderboard(PDO $pdo): void
{
    $code = strtoupper(trim((string) ($_GET['code'] ?? '')));
    if (!Validation::isValidGroupCode($code)) {
        fail(400, 'Code de groupe invalide');
    }
    $stmt = $pdo->prepare('SELECT id FROM groups WHERE code = ?');
    $stmt->execute([$code]);
    $group = $stmt->fetch();
    if ($group === false) {
        fail(404, 'Groupe introuvable');
    }
    $groupId = (int) $group['id'];

    if (($_GET['type'] ?? '') === 'cumulative') {
        $core = implode(',', array_fill(0, count(Validation::CORE), '?'));
        $stmt = $pdo->prepare(
            "SELECT p.pseudo, COALESCE(SUM(s.best_score), 0) AS total
             FROM players p
             LEFT JOIN scores s ON s.player_id = p.id AND s.challenge IN ($core)
             WHERE p.group_id = ?
             GROUP BY p.id
             ORDER BY total DESC, p.pseudo ASC
             LIMIT 100"
        );
        $stmt->execute([...Validation::CORE, $groupId]);
        ok(array_map(
            fn (array $row): array => ['pseudo' => $row['pseudo'], 'total' => (int) $row['total']],
            $stmt->fetchAll()
        ));
    }

    $challenge = (string) ($_GET['challenge'] ?? '');
    if (!Validation::isValidChallenge($challenge)) {
        fail(400, 'Épreuve inconnue');
    }
    $stmt = $pdo->prepare(
        'SELECT p.pseudo, s.best_score
         FROM scores s
         JOIN players p ON p.id = s.player_id
         WHERE p.group_id = ? AND s.challenge = ?
         ORDER BY s.best_score DESC, p.pseudo ASC
         LIMIT 100'
    );
    $stmt->execute([$groupId, $challenge]);
    ok(array_map(
        fn (array $row): array => ['pseudo' => $row['pseudo'], 'best_score' => (int) $row['best_score']],
        $stmt->fetchAll()
    ));
}

// ---------------------------------------------------------------------------

/** Rate limiting fenêtre fixe de 60 s par clé. Refuse au-delà de $maxPerMinute. */
function rateLimit(PDO $pdo, string $key, int $maxPerMinute): void
{
    $window = intdiv(time(), 60);
    $stmt = $pdo->prepare(
        'INSERT INTO rate_limits (key, window_start, hits) VALUES (?, ?, 1)
         ON CONFLICT(key, window_start) DO UPDATE SET hits = hits + 1'
    );
    $stmt->execute([$key, $window]);
    $stmt = $pdo->prepare('SELECT hits FROM rate_limits WHERE key = ? AND window_start = ?');
    $stmt->execute([$key, $window]);
    if ((int) $stmt->fetchColumn() > $maxPerMinute) {
        fail(429, 'Doucement ! Réessaie dans une minute');
    }
    // Purge opportuniste des fenêtres passées (1 requête sur ~50)
    if (random_int(0, 49) === 0) {
        $stmt = $pdo->prepare('DELETE FROM rate_limits WHERE window_start < ?');
        $stmt->execute([$window - 2]);
    }
}

function clientIp(): string
{
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

function jsonBody(): array
{
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function ok(mixed $data): never
{
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}
