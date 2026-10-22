<?php
declare(strict_types=1);

/**
 * Routeur unique de l'API Miarritze Gordeka (docs/ONLINE.md).
 *
 * Réseau (sans auth) : GET /net/config (STUN/TURN), POST /net/report, GET /net/reports
 * Salons (GDD-BLACKOUT.md) : POST /gk/player, GET /rooms, POST /room/{create,join,presence,me,
 *             settings,launch,round,end,kick,leave,signal}, GET /room/signal — voir src/Rooms.php.
 * Le serveur ne fait pas de temps réel : présence et signalisation WebRTC par polling ; la partie
 * passe en pair-à-pair.
 */

require __DIR__ . '/../src/Db.php';
require __DIR__ . '/../src/Validation.php';
require __DIR__ . '/../src/Profanity.php';
require __DIR__ . '/../src/Rooms.php';   // salons de Gordeka (GDD-BLACKOUT.md, docs/ONLINE.md)

const SIGNAL_TTL = 600;   // messages de signalisation des salons gardés 10 min

$configFile = __DIR__ . '/../config.php';
$config = is_file($configFile) ? require $configFile : [];
// Relais TURN : fichier écrit au déploiement depuis les secrets GitHub (jamais dans le dépôt).
$turnFile = __DIR__ . '/../turn.php';
if (is_file($turnFile)) {
    $config = array_merge($config, require $turnFile);
}

header('Content-Type: application/json; charset=utf-8');

// CORS : même origine par défaut ; allowed_origin seulement pour le dev local.
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
    if (random_int(0, 49) === 0) {
        purge($pdo);
    }
    match (true) {
        $method === 'GET' && $route === '/net/config' => handleNetConfig($config),
        $method === 'POST' && $route === '/net/report' => handleNetReport($pdo),
        $method === 'GET' && $route === '/net/reports' => handleNetReports($pdo),
        $method === 'POST' && $route === '/gk/player' => handleGkPlayer($pdo),
        $method === 'GET' && $route === '/rooms' => handleRoomList($pdo),
        $method === 'POST' && $route === '/room/create' => handleRoomCreate($pdo),
        $method === 'POST' && $route === '/room/join' => handleRoomJoin($pdo),
        $method === 'POST' && $route === '/room/presence' => handleRoomPresence($pdo),
        $method === 'POST' && $route === '/room/me' => handleRoomMe($pdo),
        $method === 'POST' && $route === '/room/settings' => handleRoomSettings($pdo),
        $method === 'POST' && $route === '/room/launch' => handleRoomLaunch($pdo),
        $method === 'POST' && $route === '/room/round' => handleRoomRound($pdo),
        $method === 'POST' && $route === '/room/end' => handleRoomEnd($pdo),
        $method === 'POST' && $route === '/room/kick' => handleRoomKick($pdo),
        $method === 'POST' && $route === '/room/leave' => handleRoomLeave($pdo),
        $method === 'POST' && $route === '/room/signal' => handleRoomSignalPost($pdo),
        $method === 'GET' && $route === '/room/signal' => handleRoomSignalGet($pdo),
        default => fail(404, 'Route inconnue'),
    };
} catch (Throwable $e) {
    error_log('miarritze api: ' . $e->getMessage());
    fail(500, 'Erreur serveur');
}

// ------------------------------------------------------------------ réseau

function handleNetConfig(array $config): void
{
    $ice = [['urls' => ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']]];
    foreach (($config['turn_servers'] ?? []) as $turn) {
        $ice[] = $turn;   // TURN optionnels ajoutés sans recompiler le jeu (§9.2)
    }
    foreach (cloudflareTurn($config) as $turn) {
        $ice[] = $turn;
    }
    $relay = false;
    foreach ($ice as $s) {
        $relay = $relay || isset($s['credential']);
    }
    // relay : le client peut retenter en forçant le relais (4G, NAT strict).
    ok(['ice_servers' => $ice, 'relay' => $relay]);
}

/**
 * Relais TURN Cloudflare (gratuit jusqu'à 1 To/mois) : identifiants temporaires
 * générés côté serveur (la clé ne quitte jamais le serveur), mis en cache 1 h.
 */
function cloudflareTurn(array $config): array
{
    $cf = $config['cloudflare_turn'] ?? null;
    if (!is_array($cf) || ($cf['key_id'] ?? '') === '' || ($cf['api_token'] ?? '') === '') {
        return [];
    }
    $cache = __DIR__ . '/../db/turn_cache.json';
    if (is_file($cache)) {
        $c = json_decode((string) file_get_contents($cache), true);
        if (is_array($c) && (int) ($c['until'] ?? 0) > time() && is_array($c['servers'] ?? null)) {
            return $c['servers'];
        }
    }
    $ttl = 4 * 3600;
    $url = 'https://rtc.live.cloudflare.com/v1/turn/keys/' . rawurlencode((string) $cf['key_id']) . '/credentials/generate-ice-servers';
    $ctx = stream_context_create(['http' => [
        'method' => 'POST', 'timeout' => 4, 'ignore_errors' => true,
        'header' => "Authorization: Bearer {$cf['api_token']}\r\nContent-Type: application/json\r\n",
        'content' => json_encode(['ttl' => $ttl]),
    ]]);
    $raw = @file_get_contents($url, false, $ctx);
    $data = is_string($raw) ? json_decode($raw, true) : null;
    $list = $data['iceServers'] ?? [];
    if (isset($list['urls'])) {
        $list = [$list];   // ancienne forme de l'API : un seul objet
    }
    $servers = [];
    foreach ((array) $list as $s) {
        if (is_array($s) && isset($s['urls'], $s['username'], $s['credential'])) {
            // Ports 53/80/443 : passent les pare-feu d'école ; on garde turn: et turns:.
            $urls = array_values(array_filter((array) $s['urls'], fn($u) => str_starts_with((string) $u, 'turn')));
            $servers[] = ['urls' => $urls, 'username' => $s['username'], 'credential' => $s['credential']];
        }
    }
    if ($servers !== []) {
        @file_put_contents($cache, json_encode(['until' => time() + $ttl - 1800, 'servers' => $servers]));
    }
    return $servers;
}

/** Derniers échecs de connexion (diagnostic) : raison, navigateur, date. Rien de personnel. */
function handleNetReports(PDO $pdo): void
{
    rateLimit($pdo, 'netreports:' . clientIp(), 20);
    $rows = $pdo->query('SELECT kind, browser, created_at FROM net_reports ORDER BY id DESC LIMIT 30')->fetchAll();
    ok(array_map(fn($r) => ['kind' => $r['kind'], 'browser' => $r['browser'],
        'at' => gmdate('Y-m-d H:i', (int) $r['created_at'])], $rows));
}

function handleNetReport(PDO $pdo): void
{
    rateLimit($pdo, 'netreport:' . clientIp(), 10);
    $body = jsonBody();
    $kind = substr(preg_replace('/[^a-z0-9_]/', '', (string) ($body['kind'] ?? 'inconnu')) ?? '', 0, 40);
    $browser = substr(preg_replace('/[^A-Za-z0-9 ._\/-]/', '', (string) ($body['browser'] ?? '')) ?? '', 0, 64);
    $pdo->prepare('INSERT INTO net_reports (kind, browser, created_at) VALUES (?, ?, ?)')->execute([$kind, $browser, time()]);
    ok(['ok' => true]);
}

// ------------------------------------------------------------------ utilitaires

function purge(PDO $pdo): void
{
    $now = time();
    $pdo->prepare('DELETE FROM rate_limits WHERE window_start < ?')->execute([intdiv($now, 60) - 2]);
    $pdo->prepare('DELETE FROM net_reports WHERE created_at < ?')->execute([$now - 30 * 86400]);
    gkPurge($pdo);
}

/** Rate limiting fenêtre fixe de 60 s par clé. */
function rateLimit(PDO $pdo, string $key, int $maxPerMinute): void
{
    $window = intdiv(time(), 60);
    $pdo->prepare(
        'INSERT INTO rate_limits (key, window_start, hits) VALUES (?, ?, 1)
         ON CONFLICT(key, window_start) DO UPDATE SET hits = hits + 1'
    )->execute([$key, $window]);
    $stmt = $pdo->prepare('SELECT hits FROM rate_limits WHERE key = ? AND window_start = ?');
    $stmt->execute([$key, $window]);
    if ((int) $stmt->fetchColumn() > $maxPerMinute) {
        fail(429, 'Doucement ! Réessaie dans une minute');
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

/** $reason : code machine facultatif (routes Gordeka), le message reste pour l'affichage. */
function fail(int $status, string $message, string $reason = ''): never
{
    http_response_code($status);
    $out = ['error' => $message];
    if ($reason !== '') {
        $out['reason'] = $reason;
    }
    echo json_encode($out, JSON_UNESCAPED_UNICODE);
    exit;
}
