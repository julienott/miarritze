<?php
declare(strict_types=1);

/**
 * Routeur unique de l'API Miarritze Borroka (SPEC-BORROKA §9.4).
 *
 * Sans auth : POST /group, POST /group/join, GET /net/config, POST /net/report,
 *             GET /leaderboard
 * Avec auth (player_id + secret) : /profile, /presence, /match/*, /signal,
 *             /tower/score
 * Le serveur ne fait pas de temps réel : présence, invitations, matchs et
 * signalisation WebRTC par polling. Le combat passe en pair-à-pair.
 */

require __DIR__ . '/../src/Db.php';
require __DIR__ . '/../src/Validation.php';
require __DIR__ . '/../src/Profanity.php';

const ONLINE_SECONDS = 15;
const INVITE_SECONDS = 20;
const SIGNAL_TTL = 600;
const MATCH_TTL = 3600;
const ELO_K = 32;

$configFile = __DIR__ . '/../config.php';
$config = is_file($configFile) ? require $configFile : [];

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
        $method === 'POST' && $route === '/group' => handleCreateGroup($pdo),
        $method === 'POST' && $route === '/group/join' => handleJoinGroup($pdo),
        $method === 'GET' && $route === '/net/config' => handleNetConfig($config),
        $method === 'POST' && $route === '/net/report' => handleNetReport($pdo),
        $method === 'GET' && $route === '/leaderboard' => handleLeaderboard($pdo),
        $method === 'GET' && $route === '/profile' => handleGetProfile($pdo),
        $method === 'POST' && $route === '/profile' => handlePostProfile($pdo),
        $method === 'POST' && $route === '/presence' => handlePresence($pdo),
        $method === 'POST' && $route === '/match/invite' => handleInvite($pdo),
        $method === 'POST' && $route === '/match/queue' => handleQueue($pdo),
        $method === 'POST' && $route === '/match/respond' => handleRespond($pdo),
        $method === 'POST' && $route === '/match/stage' => handleStage($pdo),
        $method === 'POST' && $route === '/match/cancel' => handleCancel($pdo),
        $method === 'POST' && $route === '/match/report' => handleReport($pdo),
        $method === 'POST' && $route === '/match/rematch' => handleRematch($pdo),
        $method === 'POST' && $route === '/signal' => handlePostSignal($pdo),
        $method === 'GET' && $route === '/signal' => handleGetSignal($pdo),
        $method === 'POST' && $route === '/tower/score' => handleTowerScore($pdo),
        default => fail(404, 'Route inconnue'),
    };
} catch (Throwable $e) {
    error_log('miarritze api: ' . $e->getMessage());
    fail(500, 'Erreur serveur');
}

// ------------------------------------------------------------------ groupes

function handleCreateGroup(PDO $pdo): void
{
    rateLimit($pdo, 'group:' . clientIp(), 10);
    $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
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
    try {
        $stmt = $pdo->prepare('INSERT INTO players (group_id, pseudo, secret, created_at) VALUES (?, ?, ?, ?)');
        $stmt->execute([(int) $group['id'], $pseudo, $secret, time()]);
    } catch (PDOException $e) {
        fail(409, 'Pseudo déjà pris dans ce groupe');
    }
    $playerId = (int) $pdo->lastInsertId();
    $pdo->prepare('INSERT INTO profiles (player_id, updated_at) VALUES (?, ?)')->execute([$playerId, time()]);
    ok(['player_id' => $playerId, 'secret' => $secret]);
}

// ------------------------------------------------------------------ profil

function handleGetProfile(PDO $pdo): void
{
    $me = auth($pdo, $_GET);
    ok(profileRow($pdo, (int) $me['id']));
}

function handlePostProfile(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'profile:p' . $me['id'], 30);
    $fighter = (string) ($body['fighter'] ?? 'louis');
    $costume = $body['costume'] ?? 0;
    $banner = $body['banner'] ?? 0;
    $emote = $body['emote'] ?? 0;
    $title = (string) ($body['title'] ?? '');
    $stats = $body['stats'] ?? [];
    if (!Validation::isFighter($fighter) || !is_int($costume) || !is_int($banner) || !is_int($emote)) {
        fail(400, 'Carte de joueur invalide');
    }
    if ($banner < 0 || $banner > 7 || $emote < 0 || $emote > 3 || !in_array($title, Validation::TITLES, true)) {
        fail(400, 'Carte de joueur invalide');
    }
    if (!is_array($stats)) {
        $stats = [];
    }
    $statsJson = json_encode($stats, JSON_UNESCAPED_UNICODE) ?: '{}';
    if (strlen($statsJson) > Validation::MAX_STATS_BYTES) {
        fail(400, 'Statistiques trop volumineuses');
    }
    if (!Validation::isPlausibleCostume($fighter, $costume, $stats)) {
        $costume = 0;   // costume non débloqué : on retombe sur le défaut, sans punir
    }
    $stmt = $pdo->prepare(
        'INSERT INTO profiles (player_id, fighter, costume, banner, title, emote, stats_json, updated_at)
         VALUES (:p, :f, :c, :b, :t, :e, :s, :u)
         ON CONFLICT(player_id) DO UPDATE SET fighter = :f, costume = :c, banner = :b, title = :t,
           emote = :e, stats_json = :s, updated_at = :u'
    );
    $stmt->execute([':p' => $me['id'], ':f' => $fighter, ':c' => $costume, ':b' => $banner, ':t' => $title,
        ':e' => $emote, ':s' => $statsJson, ':u' => time()]);
    ok(profileRow($pdo, (int) $me['id']));
}

function profileRow(PDO $pdo, int $playerId): array
{
    $stmt = $pdo->prepare(
        'SELECT p.id, p.pseudo, pr.fighter, pr.costume, pr.banner, pr.title, pr.emote, pr.rating, pr.wins, pr.losses
         FROM players p LEFT JOIN profiles pr ON pr.player_id = p.id WHERE p.id = ?'
    );
    $stmt->execute([$playerId]);
    $row = $stmt->fetch() ?: [];
    return [
        'player_id' => (int) ($row['id'] ?? 0), 'pseudo' => (string) ($row['pseudo'] ?? ''),
        'fighter' => (string) ($row['fighter'] ?? 'louis'), 'costume' => (int) ($row['costume'] ?? 0),
        'banner' => (int) ($row['banner'] ?? 0), 'title' => (string) ($row['title'] ?? ''),
        'emote' => (int) ($row['emote'] ?? 0), 'rating' => (int) ($row['rating'] ?? 1000),
        'wins' => (int) ($row['wins'] ?? 0), 'losses' => (int) ($row['losses'] ?? 0),
    ];
}

// ------------------------------------------------------------------ présence

function handlePresence(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'presence:p' . $me['id'], 20);
    rateLimit($pdo, 'presence:' . clientIp(), 60);
    $status = (string) ($body['status'] ?? 'lobby');
    if (!in_array($status, ['lobby', 'queue', 'busy'], true)) {
        $status = 'lobby';
    }
    $now = time();
    $pdo->prepare(
        'INSERT INTO presence (player_id, status, last_seen) VALUES (?, ?, ?)
         ON CONFLICT(player_id) DO UPDATE SET status = excluded.status, last_seen = excluded.last_seen'
    )->execute([$me['id'], $status, $now]);
    expireInvites($pdo);
    // Membres du groupe en ligne (heartbeat récent), avec leur carte.
    $stmt = $pdo->prepare(
        'SELECT p.id FROM players p JOIN presence s ON s.player_id = p.id
         WHERE p.group_id = ? AND s.last_seen >= ? ORDER BY p.pseudo'
    );
    $stmt->execute([$me['group_id'], $now - ONLINE_SECONDS]);
    $members = [];
    foreach ($stmt->fetchAll() as $row) {
        $card = profileRow($pdo, (int) $row['id']);
        $st = $pdo->prepare('SELECT status FROM presence WHERE player_id = ?');
        $st->execute([(int) $row['id']]);
        $card['status'] = (string) $st->fetchColumn();
        $card['me'] = (int) $row['id'] === (int) $me['id'];
        $members[] = $card;
    }
    $stmt = $pdo->prepare("SELECT id, p1 FROM matches WHERE p2 = ? AND state = 'invited' ORDER BY id DESC");
    $stmt->execute([$me['id']]);
    $invites = [];
    foreach ($stmt->fetchAll() as $row) {
        $invites[] = ['match_id' => (int) $row['id'], 'from' => profileRow($pdo, (int) $row['p1'])];
    }
    ok(['members' => $members, 'invites' => $invites, 'match' => currentMatch($pdo, (int) $me['id'])]);
}

function currentMatch(PDO $pdo, int $playerId): ?array
{
    $stmt = $pdo->prepare(
        "SELECT * FROM matches WHERE (p1 = :p OR p2 = :p)
         AND state IN ('invited', 'accepted', 'signaling', 'playing') ORDER BY id DESC LIMIT 1"
    );
    $stmt->execute([':p' => $playerId]);
    $m = $stmt->fetch();
    return $m === false ? null : matchView($pdo, $m, $playerId);
}

function matchView(PDO $pdo, array $m, int $me): array
{
    $other = (int) $m['p1'] === $me ? (int) $m['p2'] : (int) $m['p1'];
    return [
        'match_id' => (int) $m['id'], 'state' => (string) $m['state'],
        'host' => (int) $m['p1'] === $me, 'opponent' => profileRow($pdo, $other),
        'stage' => $m['stage'], 'seed' => (int) $m['seed'],
        'my_stage' => (int) $m['p1'] === $me ? $m['stage_p1'] : $m['stage_p2'],
    ];
}

// ------------------------------------------------------------------ matchs

function handleInvite(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $to = $body['to'] ?? 0;
    if (!is_int($to) || $to === (int) $me['id']) {
        fail(400, 'Adversaire invalide');
    }
    $stmt = $pdo->prepare('SELECT id FROM players WHERE id = ? AND group_id = ?');
    $stmt->execute([$to, $me['group_id']]);
    if ($stmt->fetch() === false) {
        fail(404, 'Ce joueur n\'est pas dans ton groupe');
    }
    cancelOpenMatches($pdo, (int) $me['id']);
    $matchId = createMatch($pdo, (int) $me['group_id'], (int) $me['id'], $to, 'invited');
    ok(['match_id' => $matchId]);
}

function handleQueue(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $now = time();
    $pdo->beginTransaction();
    $stmt = $pdo->prepare(
        "SELECT p.id FROM players p JOIN presence s ON s.player_id = p.id
         WHERE p.group_id = ? AND p.id != ? AND s.status = 'queue' AND s.last_seen >= ?
         ORDER BY s.last_seen DESC LIMIT 1"
    );
    $stmt->execute([$me['group_id'], $me['id'], $now - ONLINE_SECONDS]);
    $other = $stmt->fetchColumn();
    if ($other === false) {
        $pdo->prepare(
            "INSERT INTO presence (player_id, status, last_seen) VALUES (?, 'queue', ?)
             ON CONFLICT(player_id) DO UPDATE SET status = 'queue', last_seen = excluded.last_seen"
        )->execute([$me['id'], $now]);
        $pdo->commit();
        ok(['match' => null, 'waiting' => true]);
    }
    $a = min((int) $me['id'], (int) $other);
    $b = max((int) $me['id'], (int) $other);
    $matchId = createMatch($pdo, (int) $me['group_id'], $a, $b, 'accepted');
    $pdo->prepare("UPDATE presence SET status = 'busy' WHERE player_id IN (?, ?)")->execute([$a, $b]);
    $pdo->commit();
    $m = loadMatch($pdo, $matchId);
    ok(['match' => matchView($pdo, $m, (int) $me['id']), 'waiting' => false]);
}

function handleRespond(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $m = myMatch($pdo, $body, (int) $me['id']);
    if ((int) $m['p2'] !== (int) $me['id'] || $m['state'] !== 'invited') {
        fail(409, 'Invitation expirée');
    }
    $accept = (bool) ($body['accept'] ?? false);
    setState($pdo, (int) $m['id'], $accept ? 'accepted' : 'cancelled');
    if ($accept) {
        $pdo->prepare("UPDATE presence SET status = 'busy' WHERE player_id IN (?, ?)")->execute([$m['p1'], $m['p2']]);
    }
    ok(['match' => matchView($pdo, loadMatch($pdo, (int) $m['id']), (int) $me['id'])]);
}

/** Chacun propose une map ; identiques → celle-là, sinon tirage entre les deux. */
function handleStage(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $m = myMatch($pdo, $body, (int) $me['id']);
    $stage = (string) ($body['stage'] ?? '');
    if (!Validation::isStage($stage)) {
        fail(400, 'Map inconnue');
    }
    if (!in_array($m['state'], ['accepted', 'signaling'], true)) {
        fail(409, 'Match terminé');
    }
    $col = (int) $m['p1'] === (int) $me['id'] ? 'stage_p1' : 'stage_p2';
    $pdo->prepare("UPDATE matches SET $col = ?, updated_at = ? WHERE id = ?")->execute([$stage, time(), $m['id']]);
    $m = loadMatch($pdo, (int) $m['id']);
    if ($m['stage_p1'] !== null && $m['stage_p2'] !== null && $m['stage'] === null) {
        $pick = $m['stage_p1'] === $m['stage_p2'] ? $m['stage_p1'] : (random_int(0, 1) === 0 ? $m['stage_p1'] : $m['stage_p2']);
        // WHERE stage IS NULL : un seul des deux appels concurrents fixe la map.
        $pdo->prepare("UPDATE matches SET stage = ?, state = 'signaling', updated_at = ? WHERE id = ? AND stage IS NULL")
            ->execute([$pick, time(), $m['id']]);
        $m = loadMatch($pdo, (int) $m['id']);
    }
    ok(['match' => matchView($pdo, $m, (int) $me['id'])]);
}

function handleCancel(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $m = myMatch($pdo, $body, (int) $me['id']);
    // Un match déjà commencé ne s'annule pas (on n'esquive pas l'Elo).
    if (in_array($m['state'], ['invited', 'accepted', 'signaling'], true)) {
        setState($pdo, (int) $m['id'], 'cancelled');
    }
    $pdo->prepare("UPDATE presence SET status = 'lobby' WHERE player_id = ?")->execute([$me['id']]);
    ok(['ok' => true]);
}

/** Les deux clients rapportent vainqueur + checksum ; Elo seulement s'ils concordent. */
function handleReport(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $m = myMatch($pdo, $body, (int) $me['id']);
    $winner = $body['winner'] ?? null;
    $checksum = $body['checksum'] ?? null;
    if (!is_int($winner) || $winner < -1 || $winner > 1 || !is_int($checksum)) {
        fail(400, 'Rapport invalide');
    }
    if ($m['state'] === 'finished' || $m['state'] === 'cancelled') {
        // Second appel (le premier rapporteur revient chercher le verdict).
        $agreeDone = $m['winner_p1'] !== null && $m['winner_p2'] !== null
            && (int) $m['winner_p1'] === (int) $m['winner_p2'] && (int) $m['checksum_p1'] === (int) $m['checksum_p2'];
        ok(['state' => $m['state'], 'rated' => $agreeDone && (int) $m['winner_p1'] >= 0, 'agree' => $agreeDone,
            'rating' => rating($pdo, (int) $me['id'])]);
    }
    $isP1 = (int) $m['p1'] === (int) $me['id'];
    $sfx = $isP1 ? 'p1' : 'p2';
    $pdo->prepare("UPDATE matches SET winner_$sfx = ?, checksum_$sfx = ?, state = 'playing', updated_at = ? WHERE id = ?")
        ->execute([$winner, $checksum, time(), $m['id']]);
    $m = loadMatch($pdo, (int) $m['id']);
    if ($m['winner_p1'] === null || $m['winner_p2'] === null) {
        ok(['state' => 'waiting', 'rated' => false]);
    }
    $agree = (int) $m['winner_p1'] === (int) $m['winner_p2'] && (int) $m['checksum_p1'] === (int) $m['checksum_p2'];
    $pdo->beginTransaction();
    // Un seul rapport « clôture » le match : pas d'Elo appliqué deux fois.
    $close = $pdo->prepare("UPDATE matches SET state = 'finished', updated_at = ? WHERE id = ? AND state != 'finished'");
    $close->execute([time(), $m['id']]);
    if ($close->rowCount() !== 1) {
        $pdo->commit();
        ok(['state' => 'finished', 'rated' => $agree && (int) $m['winner_p1'] >= 0, 'agree' => $agree,
            'rating' => rating($pdo, (int) $me['id'])]);
    }
    $rated = false;
    $w = (int) $m['winner_p1'];
    if ($agree && $w >= 0) {
        $winnerId = $w === 0 ? (int) $m['p1'] : (int) $m['p2'];
        $loserId = $w === 0 ? (int) $m['p2'] : (int) $m['p1'];
        $ra = rating($pdo, $winnerId);
        $rb = rating($pdo, $loserId);
        $expected = 1.0 / (1.0 + 10 ** (($rb - $ra) / 400.0));
        $delta = (int) round(ELO_K * (1.0 - $expected));
        $pdo->prepare('UPDATE profiles SET rating = rating + ?, wins = wins + 1 WHERE player_id = ?')->execute([$delta, $winnerId]);
        $pdo->prepare('UPDATE profiles SET rating = MAX(100, rating - ?), losses = losses + 1 WHERE player_id = ?')->execute([$delta, $loserId]);
        $rated = true;
    }
    $pdo->prepare("UPDATE presence SET status = 'lobby' WHERE player_id IN (?, ?)")->execute([$m['p1'], $m['p2']]);
    $pdo->commit();
    ok(['state' => 'finished', 'rated' => $rated, 'agree' => $agree, 'rating' => rating($pdo, (int) $me['id'])]);
}

/**
 * Revanche : un NOUVEAU match (compté) entre les mêmes joueurs, même map,
 * nouvelle graine. Idempotent : le second appel récupère le même match.
 */
function handleRematch(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'match:p' . $me['id'], 30);
    $old = myMatch($pdo, $body, (int) $me['id']);
    $pdo->beginTransaction();
    $stmt = $pdo->prepare('SELECT id FROM matches WHERE rematch_of = ? ORDER BY id LIMIT 1');
    $stmt->execute([$old['id']]);
    $existing = $stmt->fetchColumn();
    if ($existing === false) {
        $id = createMatch($pdo, (int) $old['group_id'], (int) $old['p1'], (int) $old['p2'], 'playing');
        $pdo->prepare('UPDATE matches SET stage = ?, rematch_of = ? WHERE id = ?')->execute([$old['stage'], $old['id'], $id]);
        $existing = $id;
    }
    $pdo->commit();
    ok(['match' => matchView($pdo, loadMatch($pdo, (int) $existing), (int) $me['id'])]);
}


function rating(PDO $pdo, int $playerId): int
{
    $stmt = $pdo->prepare('SELECT rating FROM profiles WHERE player_id = ?');
    $stmt->execute([$playerId]);
    $r = $stmt->fetchColumn();
    return $r === false ? 1000 : (int) $r;
}

// ------------------------------------------------------------------ signalisation

function handlePostSignal(PDO $pdo): void
{
    $raw = file_get_contents('php://input') ?: '';
    if (strlen($raw) > Validation::MAX_SIGNAL_BYTES + 512) {
        fail(413, 'Message trop gros');
    }
    $body = json_decode($raw, true);
    $body = is_array($body) ? $body : [];
    $me = auth($pdo, $body);
    rateLimit($pdo, 'signal:p' . $me['id'], 240);
    rateLimit($pdo, 'signal:' . clientIp(), 480);
    $m = myMatch($pdo, $body, (int) $me['id']);
    $payload = $body['payload'] ?? null;
    if (!is_array($payload) || !in_array($payload['kind'] ?? '', ['offer', 'answer', 'ice', 'hello', 'bye'], true)) {
        fail(400, 'Message de signalisation invalide');
    }
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE) ?: '{}';
    if (strlen($json) > Validation::MAX_SIGNAL_BYTES) {
        fail(413, 'Message trop gros');
    }
    $to = (int) $m['p1'] === (int) $me['id'] ? (int) $m['p2'] : (int) $m['p1'];
    $pdo->prepare('INSERT INTO signals (match_id, to_player, payload, created_at) VALUES (?, ?, ?, ?)')
        ->execute([$m['id'], $to, $json, time()]);
    ok(['id' => (int) $pdo->lastInsertId()]);
}

function handleGetSignal(PDO $pdo): void
{
    $me = auth($pdo, $_GET);
    rateLimit($pdo, 'signal:p' . $me['id'], 240);
    $matchId = (int) ($_GET['match_id'] ?? 0);
    $after = (int) ($_GET['after'] ?? 0);
    $stmt = $pdo->prepare('SELECT id, payload FROM signals WHERE to_player = ? AND match_id = ? AND id > ? ORDER BY id LIMIT 100');
    $stmt->execute([$me['id'], $matchId, $after]);
    $out = [];
    foreach ($stmt->fetchAll() as $row) {
        $out[] = ['id' => (int) $row['id'], 'payload' => json_decode((string) $row['payload'], true)];
    }
    ok(['messages' => $out]);
}

// ------------------------------------------------------------------ réseau

function handleNetConfig(array $config): void
{
    $ice = [['urls' => ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']]];
    foreach (($config['turn_servers'] ?? []) as $turn) {
        $ice[] = $turn;   // TURN optionnels ajoutés sans recompiler le jeu (§9.2)
    }
    ok(['ice_servers' => $ice]);
}

function handleNetReport(PDO $pdo): void
{
    rateLimit($pdo, 'netreport:' . clientIp(), 10);
    $body = jsonBody();
    $kind = substr(preg_replace('/[^a-z_]/', '', (string) ($body['kind'] ?? 'inconnu')) ?? '', 0, 32);
    $browser = substr(preg_replace('/[^A-Za-z0-9 ._\/-]/', '', (string) ($body['browser'] ?? '')) ?? '', 0, 64);
    $pdo->prepare('INSERT INTO net_reports (kind, browser, created_at) VALUES (?, ?, ?)')->execute([$kind, $browser, time()]);
    ok(['ok' => true]);
}

// ------------------------------------------------------------------ pyramide, classements

function handleTowerScore(PDO $pdo): void
{
    $body = jsonBody();
    $me = auth($pdo, $body);
    rateLimit($pdo, 'tower:p' . $me['id'], 30);
    $fighter = (string) ($body['fighter'] ?? '');
    $difficulty = (string) ($body['difficulty'] ?? '');
    $score = $body['score'] ?? null;
    if (!Validation::isFighter($fighter) || !in_array($difficulty, Validation::DIFFICULTIES, true)) {
        fail(400, 'Pyramide inconnue');
    }
    if (!Validation::isPlausibleTowerScore($score)) {
        fail(400, 'Score refusé');
    }
    $pdo->prepare(
        'INSERT INTO tower_scores (player_id, fighter, difficulty, best_score, updated_at) VALUES (:p, :f, :d, :s, :t)
         ON CONFLICT(player_id, fighter, difficulty) DO UPDATE SET best_score = MAX(best_score, CAST(:s AS INTEGER)), updated_at = :t'
    )->execute([':p' => $me['id'], ':f' => $fighter, ':d' => $difficulty, ':s' => $score, ':t' => time()]);
    ok(['ok' => true]);
}

function handleLeaderboard(PDO $pdo): void
{
    $code = strtoupper(trim((string) ($_GET['code'] ?? '')));
    if (!Validation::isValidGroupCode($code)) {
        fail(400, 'Code de groupe invalide');
    }
    $stmt = $pdo->prepare('SELECT id FROM groups WHERE code = ?');
    $stmt->execute([$code]);
    $groupId = $stmt->fetchColumn();
    if ($groupId === false) {
        fail(404, 'Groupe introuvable');
    }
    if (($_GET['type'] ?? 'rating') === 'tower') {
        $stmt = $pdo->prepare(
            'SELECT p.pseudo, MAX(t.best_score) AS best, t.fighter FROM tower_scores t JOIN players p ON p.id = t.player_id
             WHERE p.group_id = ? GROUP BY p.id ORDER BY best DESC, p.pseudo LIMIT 100'
        );
        $stmt->execute([(int) $groupId]);
        ok(array_map(fn (array $r): array => ['pseudo' => $r['pseudo'], 'score' => (int) $r['best'],
            'fighter' => $r['fighter']], $stmt->fetchAll()));
    }
    $stmt = $pdo->prepare(
        'SELECT p.pseudo, pr.rating, pr.wins, pr.losses, pr.fighter FROM players p JOIN profiles pr ON pr.player_id = p.id
         WHERE p.group_id = ? ORDER BY pr.rating DESC, p.pseudo LIMIT 100'
    );
    $stmt->execute([(int) $groupId]);
    ok(array_map(fn (array $r): array => ['pseudo' => $r['pseudo'], 'rating' => (int) $r['rating'],
        'wins' => (int) $r['wins'], 'losses' => (int) $r['losses'], 'fighter' => $r['fighter']], $stmt->fetchAll()));
}

// ------------------------------------------------------------------ utilitaires

function auth(PDO $pdo, array $src): array
{
    $playerId = $src['player_id'] ?? 0;
    $playerId = is_string($playerId) && ctype_digit($playerId) ? (int) $playerId : $playerId;
    $secret = (string) ($src['secret'] ?? '');
    if (!is_int($playerId) || $playerId <= 0 || $secret === '') {
        fail(401, 'Identifiants manquants');
    }
    rateLimit($pdo, 'ip:' . clientIp(), 600);
    $stmt = $pdo->prepare('SELECT id, group_id, pseudo, secret FROM players WHERE id = ?');
    $stmt->execute([$playerId]);
    $player = $stmt->fetch();
    if ($player === false || !hash_equals((string) $player['secret'], $secret)) {
        fail(401, 'Joueur inconnu ou jeton invalide');
    }
    return $player;
}

function myMatch(PDO $pdo, array $body, int $me): array
{
    $matchId = (int) ($body['match_id'] ?? 0);
    $m = loadMatch($pdo, $matchId);
    if ($m === null || ((int) $m['p1'] !== $me && (int) $m['p2'] !== $me)) {
        fail(404, 'Match introuvable');
    }
    return $m;
}

function loadMatch(PDO $pdo, int $matchId): ?array
{
    $stmt = $pdo->prepare('SELECT * FROM matches WHERE id = ?');
    $stmt->execute([$matchId]);
    $m = $stmt->fetch();
    return $m === false ? null : $m;
}

function createMatch(PDO $pdo, int $groupId, int $p1, int $p2, string $state): int
{
    $now = time();
    $seed = random_int(1, 0x7FFFFFFF);
    $pdo->prepare('INSERT INTO matches (group_id, p1, p2, state, seed, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
        ->execute([$groupId, $p1, $p2, $state, $seed, $now, $now]);
    return (int) $pdo->lastInsertId();
}

function setState(PDO $pdo, int $matchId, string $state): void
{
    $pdo->prepare('UPDATE matches SET state = ?, updated_at = ? WHERE id = ?')->execute([$state, time(), $matchId]);
}

function cancelOpenMatches(PDO $pdo, int $playerId): void
{
    $pdo->prepare(
        "UPDATE matches SET state = 'cancelled', updated_at = ? WHERE (p1 = ? OR p2 = ?) AND state IN ('invited', 'accepted', 'signaling')"
    )->execute([time(), $playerId, $playerId]);
}

function expireInvites(PDO $pdo): void
{
    $pdo->prepare("UPDATE matches SET state = 'expired' WHERE state = 'invited' AND created_at < ?")
        ->execute([time() - INVITE_SECONDS]);
}

function purge(PDO $pdo): void
{
    $now = time();
    $pdo->prepare('DELETE FROM signals WHERE created_at < ?')->execute([$now - SIGNAL_TTL]);
    $pdo->prepare("UPDATE matches SET state = 'expired' WHERE state NOT IN ('finished', 'cancelled', 'expired') AND created_at < ?")
        ->execute([$now - MATCH_TTL]);
    $pdo->prepare('DELETE FROM rate_limits WHERE window_start < ?')->execute([intdiv($now, 60) - 2]);
    $pdo->prepare('DELETE FROM presence WHERE last_seen < ?')->execute([$now - 86400]);
    $pdo->prepare('DELETE FROM net_reports WHERE created_at < ?')->execute([$now - 30 * 86400]);
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

function fail(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}
