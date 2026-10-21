<?php
declare(strict_types=1);

/**
 * Salons en ligne de Miarritze Gordeka (SPEC-GORDEKA §2.2, §6.2, §11).
 *
 * Le serveur ne fait tourner aucune partie : il tient les salons (public/privé,
 * code, places, admin, ordre d'arrivée, exclusions), la présence par salon et la
 * signalisation WebRTC en étoile. L'hôte (= admin) gère les IA et publie l'état
 * des rounds. Tout passe par du polling JSON, comme le reste de l'API.
 *
 * Utilise les utilitaires de public/index.php : ok(), fail(), jsonBody(),
 * rateLimit(), clientIp(). Documentation : docs/ONLINE_GORDEKA.md.
 */

const GK_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ';   // ni I, L, O, ni chiffres
const GK_CODE_LENGTH = 4;
const GK_MEMBER_TIMEOUT = 60;      // un joueur coupé garde sa place 60 s
const GK_CONNECTED_SECONDS = 15;   // « connecté » affiché si vu il y a moins de 15 s
const GK_ROOM_IDLE = 600;          // salon sans partie lancée depuis 10 min → fermé
const GK_CLOSED_TTL = 86400;       // salons fermés effacés après un jour
const GK_PLACES_MIN = 4;
const GK_PLACES_MAX = 8;
const GK_PLACES_DEFAULT = 6;
const GK_LAUNCH_MIN_HUMANS = 2;
const GK_COLOR_COUNT = 12;         // data/gordeka/rules.json « colors »
const GK_ROUNDS_MAX = 12;
const GK_MAX_SETTINGS_BYTES = 2048;
const GK_MAX_GAME_BYTES = 4096;
/** Miroir de data/gordeka/rules.json « characters » (le backend est déployé sans data/). */
const GK_CHARACTERS = ['louis', 'maia', 'patxi', 'xabi', 'mattin', 'amaia', 'txomin', 'kaio',
    'karramarro', 'ramuntxo', 'itsaso', 'peio'];
const GK_MAPS = ['port_pecheurs', 'parc_mazon'];

/**
 * Horloge des salons. Les tests peuvent l'avancer (purge 10 min, coupure 60 s)
 * avec un fichier d'offset désigné par MIARRITZE_CLOCK_FILE, variable
 * d'environnement jamais posée en prod.
 */
function gkNow(): int
{
    $file = getenv('MIARRITZE_CLOCK_FILE');
    if (is_string($file) && $file !== '' && is_file($file)) {
        return time() + (int) trim((string) file_get_contents($file));
    }
    return time();
}

// ------------------------------------------------------------------ joueurs

/**
 * Crée un joueur Gordeka (pseudo + secret, sans groupe ni donnée personnelle),
 * ou change le pseudo d'un joueur existant si player_id + secret sont fournis.
 */
function handleGkPlayer(PDO $pdo): void
{
    $body = jsonBody();
    $pseudo = trim((string) ($body['pseudo'] ?? ''));
    if (!Validation::isValidPseudo($pseudo)) {
        fail(400, 'Pseudo invalide (2 à 15 lettres ou chiffres)', 'bad_pseudo');
    }
    if (!Profanity::isClean($pseudo)) {
        fail(400, 'Ce pseudo n\'est pas accepté, choisis-en un autre', 'pseudo_refused');
    }
    if (isset($body['player_id'])) {
        $me = gkAuth($pdo, $body);
        $pdo->prepare('UPDATE gk_players SET pseudo = ? WHERE id = ?')->execute([$pseudo, $me['id']]);
        $pdo->prepare('UPDATE room_members SET pseudo = ? WHERE player_id = ?')->execute([$pseudo, $me['id']]);
        ok(['player_id' => (int) $me['id'], 'secret' => (string) $me['secret'], 'pseudo' => $pseudo]);
    }
    rateLimit($pdo, 'gkplayer:' . clientIp(), 30);
    $secret = bin2hex(random_bytes(16));
    $pdo->prepare('INSERT INTO gk_players (pseudo, secret, created_at) VALUES (?, ?, ?)')
        ->execute([$pseudo, $secret, time()]);
    ok(['player_id' => (int) $pdo->lastInsertId(), 'secret' => $secret, 'pseudo' => $pseudo]);
}

function gkAuth(PDO $pdo, array $src): array
{
    $playerId = $src['player_id'] ?? 0;
    $playerId = is_string($playerId) && ctype_digit($playerId) ? (int) $playerId : $playerId;
    $secret = (string) ($src['secret'] ?? '');
    if (!is_int($playerId) || $playerId <= 0 || $secret === '') {
        fail(401, 'Identifiants manquants', 'auth');
    }
    // Une classe partage une IP : 8 joueurs × (présence + signalisation).
    rateLimit($pdo, 'gkip:' . clientIp(), 1800);
    $stmt = $pdo->prepare('SELECT id, pseudo, secret FROM gk_players WHERE id = ?');
    $stmt->execute([$playerId]);
    $player = $stmt->fetch();
    if ($player === false || !hash_equals((string) $player['secret'], $secret)) {
        fail(401, 'Joueur inconnu ou jeton invalide', 'auth');
    }
    return $player;
}

// ------------------------------------------------------------------ entretien

/**
 * Appelé par chaque route de salon : retire les membres non vus depuis 60 s
 * (passation d'admin, fermeture sans humain) et ferme les salons inactifs.
 */
function gkMaintain(PDO $pdo): void
{
    $now = gkNow();
    $stmt = $pdo->prepare(
        "SELECT m.room_id, m.player_id FROM room_members m JOIN rooms r ON r.id = m.room_id
         WHERE r.state != 'ferme' AND m.last_seen < ? ORDER BY m.room_id, m.joined_at"
    );
    $stmt->execute([$now - GK_MEMBER_TIMEOUT]);
    foreach ($stmt->fetchAll() as $row) {
        gkRemoveMember($pdo, (int) $row['room_id'], (int) $row['player_id']);
    }
    $stmt = $pdo->prepare("SELECT id FROM rooms WHERE state = 'attente' AND COALESCE(last_game_at, created_at) < CAST(? AS INTEGER)");
    $stmt->execute([$now - GK_ROOM_IDLE]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $id) {
        gkCloseRoom($pdo, (int) $id);
    }
}

/** Purge lente (appelée par purge() de index.php) : vieux salons fermés et signaux. */
function gkPurge(PDO $pdo): void
{
    $now = gkNow();
    $pdo->prepare('DELETE FROM room_signals WHERE created_at < ?')->execute([$now - SIGNAL_TTL]);
    $old = $pdo->prepare("SELECT id FROM rooms WHERE state = 'ferme' AND closed_at < ?");
    $old->execute([$now - GK_CLOSED_TTL]);
    foreach ($old->fetchAll(PDO::FETCH_COLUMN) as $id) {
        $pdo->prepare('DELETE FROM room_bans WHERE room_id = ?')->execute([(int) $id]);
        $pdo->prepare('DELETE FROM rooms WHERE id = ?')->execute([(int) $id]);
    }
}

function gkCloseRoom(PDO $pdo, int $roomId): void
{
    $pdo->prepare("UPDATE rooms SET state = 'ferme', phase = '', closed_at = ? WHERE id = ? AND state != 'ferme'")
        ->execute([gkNow(), $roomId]);
    $pdo->prepare('DELETE FROM room_members WHERE room_id = ?')->execute([$roomId]);
    $pdo->prepare('DELETE FROM room_signals WHERE room_id = ?')->execute([$roomId]);
}

/**
 * Retire un membre. Si c'était l'admin, le plus ancien humain restant le
 * devient (admin_seq incrémenté : événement « nouvel admin »). Plus personne →
 * salon fermé.
 */
function gkRemoveMember(PDO $pdo, int $roomId, int $playerId): void
{
    $stmt = $pdo->prepare('SELECT is_admin FROM room_members WHERE room_id = ? AND player_id = ?');
    $stmt->execute([$roomId, $playerId]);
    $wasAdmin = $stmt->fetchColumn();
    if ($wasAdmin === false) {
        return;
    }
    $pdo->prepare('DELETE FROM room_members WHERE room_id = ? AND player_id = ?')->execute([$roomId, $playerId]);
    $stmt = $pdo->prepare('SELECT player_id, pseudo FROM room_members WHERE room_id = ? ORDER BY joined_at, rowid LIMIT 1');
    $stmt->execute([$roomId]);
    $next = $stmt->fetch();
    if ($next === false) {
        gkCloseRoom($pdo, $roomId);
        return;
    }
    if ((int) $wasAdmin === 1) {
        $pdo->prepare('UPDATE room_members SET is_admin = 1 WHERE room_id = ? AND player_id = ?')
            ->execute([$roomId, (int) $next['player_id']]);
        $pdo->prepare('UPDATE rooms SET admin_seq = admin_seq + 1, admin_changed_at = ?, name = ? WHERE id = ?')
            ->execute([gkNow(), gkRoomName((string) $next['pseudo']), $roomId]);
    }
}

/** Un joueur n'est que dans un salon à la fois : rejoindre ailleurs le fait quitter. */
function gkLeaveOtherRooms(PDO $pdo, int $playerId, int $exceptRoom): void
{
    $stmt = $pdo->prepare('SELECT room_id FROM room_members WHERE player_id = ? AND room_id != ?');
    $stmt->execute([$playerId, $exceptRoom]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $roomId) {
        gkRemoveMember($pdo, (int) $roomId, $playerId);
    }
}

// ------------------------------------------------------------------ outils

function gkRoomName(string $pseudo): string
{
    return 'Salon de ' . $pseudo;
}

function gkBegin(PDO $pdo): void
{
    // IMMEDIATE : verrou d'écriture dès le début (places, couleurs, codes sans course).
    $pdo->exec('BEGIN IMMEDIATE');
}

function gkCommit(PDO $pdo): void
{
    $pdo->exec('COMMIT');
}

function gkLoadRoom(PDO $pdo, int $roomId): ?array
{
    $stmt = $pdo->prepare('SELECT * FROM rooms WHERE id = ?');
    $stmt->execute([$roomId]);
    $r = $stmt->fetch();
    return $r === false ? null : $r;
}

function gkHumans(PDO $pdo, int $roomId): int
{
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM room_members WHERE room_id = ?');
    $stmt->execute([$roomId]);
    return (int) $stmt->fetchColumn();
}

function gkIsBanned(PDO $pdo, int $roomId, int $playerId): bool
{
    $stmt = $pdo->prepare('SELECT 1 FROM room_bans WHERE room_id = ? AND player_id = ?');
    $stmt->execute([$roomId, $playerId]);
    return $stmt->fetchColumn() !== false;
}

/**
 * Couleur attribuée : la préférée si libre, sinon la plus proche libre dans
 * l'ordre des 12 couleurs (distance d'indice, à égalité la suivante d'abord).
 */
function gkPickColor(PDO $pdo, int $roomId, int $pref, int $exceptPlayer = 0): int
{
    $stmt = $pdo->prepare('SELECT color FROM room_members WHERE room_id = ? AND player_id != ?');
    $stmt->execute([$roomId, $exceptPlayer]);
    $taken = array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    if ($pref < 0 || $pref >= GK_COLOR_COUNT) {
        $pref = 0;
    }
    for ($d = 0; $d < GK_COLOR_COUNT; $d++) {
        foreach ([$pref + $d, $pref - $d] as $c) {
            if ($c >= 0 && $c < GK_COLOR_COUNT && !in_array($c, $taken, true)) {
                return $c;
            }
        }
    }
    return -1;   // impossible avec 8 places au plus
}

function gkPerso(mixed $perso): string
{
    return is_string($perso) && in_array($perso, GK_CHARACTERS, true) ? $perso : GK_CHARACTERS[0];
}

/** Réglages libres de l'admin : un objet JSON (IA, rounds, options), taille bornée. */
function gkSettingsJson(mixed $settings, int $max): string
{
    if ($settings === null || $settings === []) {
        return '{}';
    }
    if (!is_array($settings) || array_is_list($settings)) {
        fail(400, 'Réglages invalides', 'bad_settings');
    }
    $json = json_encode($settings, JSON_UNESCAPED_UNICODE) ?: '{}';
    if (strlen($json) > $max) {
        fail(400, 'Réglages trop volumineux', 'bad_settings');
    }
    return $json;
}

function gkIntIn(mixed $v, int $min, int $max): bool
{
    return is_int($v) && $v >= $min && $v <= $max;
}

/**
 * Charge le salon et le membre courant ; refuse fermé (410), exclu (403),
 * non-membre (404). Toute action d'un membre compte comme « vu ».
 */
function gkRequireMember(PDO $pdo, array $body, int $playerId): array
{
    $roomId = (int) ($body['room_id'] ?? 0);
    $room = gkLoadRoom($pdo, $roomId);
    if ($room === null) {
        fail(404, 'Ce salon n\'existe pas', 'not_found');
    }
    if ($room['state'] === 'ferme') {
        fail(410, 'Ce salon est fermé', 'closed');
    }
    if (gkIsBanned($pdo, $roomId, $playerId)) {
        fail(403, 'L\'admin a libéré ta place', 'banned');
    }
    $stmt = $pdo->prepare('SELECT * FROM room_members WHERE room_id = ? AND player_id = ?');
    $stmt->execute([$roomId, $playerId]);
    $member = $stmt->fetch();
    if ($member === false) {
        fail(404, 'Tu n\'es plus dans ce salon', 'not_member');
    }
    $pdo->prepare('UPDATE room_members SET last_seen = ? WHERE room_id = ? AND player_id = ?')
        ->execute([gkNow(), $roomId, $playerId]);
    return [$room, $member];
}

function gkRequireAdmin(PDO $pdo, array $body, int $playerId): array
{
    [$room, $member] = gkRequireMember($pdo, $body, $playerId);
    if ((int) $member['is_admin'] !== 1) {
        fail(403, 'Seul l\'admin du salon peut faire ça', 'not_admin');
    }
    return [$room, $member];
}

/** Réglages modifiables avant le lancement et entre deux rounds (phase « scores »). */
function gkCanEditBetweenRounds(array $room): bool
{
    return $room['state'] === 'attente' || ($room['state'] === 'en_partie' && $room['phase'] === 'scores');
}

/** Vue complète d'un salon pour ses membres. */
function gkRoomView(PDO $pdo, int $roomId, int $me): array
{
    $r = gkLoadRoom($pdo, $roomId) ?? [];
    $stmt = $pdo->prepare('SELECT * FROM room_members WHERE room_id = ? ORDER BY joined_at, rowid');
    $stmt->execute([$roomId]);
    $now = gkNow();
    $members = [];
    $adminId = 0;
    $adminPseudo = '';
    foreach ($stmt->fetchAll() as $m) {
        if ((int) $m['is_admin'] === 1) {
            $adminId = (int) $m['player_id'];
            $adminPseudo = (string) $m['pseudo'];
        }
        $members[] = [
            'player_id' => (int) $m['player_id'], 'pseudo' => (string) $m['pseudo'],
            'perso' => (string) $m['perso'], 'color' => (int) $m['color'],
            'status' => (string) $m['status'], 'is_admin' => (int) $m['is_admin'] === 1,
            'joined_at' => (int) $m['joined_at'],
            'connected' => (int) $m['last_seen'] >= $now - GK_CONNECTED_SECONDS,
            'me' => (int) $m['player_id'] === $me,
        ];
    }
    return [
        'room' => [
            'room_id' => (int) $r['id'], 'name' => (string) $r['name'], 'is_public' => (int) $r['is_public'] === 1,
            'code' => $r['code'], 'map' => (string) $r['map'], 'places' => (int) $r['places'],
            'humans' => count($members), 'full' => count($members) >= (int) $r['places'],
            'state' => (string) $r['state'], 'phase' => (string) $r['phase'],
            'round' => (int) $r['round_current'], 'total' => (int) $r['round_total'],
            'settings' => json_decode((string) $r['settings_json'], true) ?: new stdClass(),
            'settings_version' => (int) $r['settings_version'],
            'game' => json_decode((string) $r['game_json'], true) ?: new stdClass(),
            'admin_id' => $adminId, 'admin_pseudo' => $adminPseudo,
            'admin_seq' => (int) $r['admin_seq'], 'admin_changed_at' => $r['admin_changed_at'] === null ? null : (int) $r['admin_changed_at'],
            'created_at' => (int) $r['created_at'],
            'last_game_at' => $r['last_game_at'] === null ? null : (int) $r['last_game_at'],
        ],
        'members' => $members,
        'me' => $me,
    ];
}

// ------------------------------------------------------------------ routes

/** POST /room/create : public ou privé (→ code de 4 lettres), places, carte, réglages. */
function handleRoomCreate(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomcreate:' . clientIp(), 20);
    rateLimit($pdo, 'roomcreate:p' . $me['id'], 5);
    $public = (bool) ($body['public'] ?? true);
    $places = $body['places'] ?? GK_PLACES_DEFAULT;
    $map = $body['map'] ?? GK_MAPS[0];
    if (!gkIntIn($places, GK_PLACES_MIN, GK_PLACES_MAX)) {
        fail(400, 'Places : de 4 à 8', 'bad_places');
    }
    if (!is_string($map) || !in_array($map, GK_MAPS, true)) {
        fail(400, 'Carte inconnue', 'bad_map');
    }
    $settings = gkSettingsJson($body['settings'] ?? null, GK_MAX_SETTINGS_BYTES);
    $color = is_int($body['color'] ?? null) ? $body['color'] : 0;
    $perso = gkPerso($body['perso'] ?? null);
    gkMaintain($pdo);
    $now = gkNow();
    gkBegin($pdo);
    gkLeaveOtherRooms($pdo, (int) $me['id'], 0);
    $roomId = 0;
    for ($attempt = 0; $attempt < 20 && $roomId === 0; $attempt++) {
        $code = null;
        if (!$public) {
            $code = '';
            for ($i = 0; $i < GK_CODE_LENGTH; $i++) {
                $code .= GK_CODE_ALPHABET[random_int(0, strlen(GK_CODE_ALPHABET) - 1)];
            }
        }
        try {
            $pdo->prepare(
                "INSERT INTO rooms (code, is_public, name, map, places, state, settings_json, created_at)
                 VALUES (?, ?, ?, ?, ?, 'attente', ?, ?)"
            )->execute([$code, $public ? 1 : 0, gkRoomName((string) $me['pseudo']), $map, $places, $settings, $now]);
            $roomId = (int) $pdo->lastInsertId();
        } catch (PDOException $e) {
            // code déjà pris par un salon ouvert : on en tire un autre
        }
    }
    if ($roomId === 0) {
        fail(500, 'Impossible de générer un code', 'server');
    }
    $color = gkPickColor($pdo, $roomId, $color);
    $pdo->prepare(
        "INSERT INTO room_members (room_id, player_id, pseudo, perso, color, joined_at, is_admin, status, last_seen)
         VALUES (?, ?, ?, ?, ?, ?, 1, 'joueur', ?)"
    )->execute([$roomId, $me['id'], $me['pseudo'], $perso, $color, $now, $now]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, $roomId, (int) $me['id']));
}

/** GET /rooms : salons publics ouverts, jamais les privés ni leurs codes. */
function handleRoomList(PDO $pdo): void
{
    rateLimit($pdo, 'rooms:' . clientIp(), 120);
    gkMaintain($pdo);
    $rooms = $pdo->query(
        "SELECT * FROM rooms WHERE is_public = 1 AND state != 'ferme' ORDER BY created_at DESC, id DESC LIMIT 50"
    )->fetchAll();
    $out = [];
    $avatars = $pdo->prepare('SELECT perso, color, is_admin FROM room_members WHERE room_id = ? ORDER BY joined_at, rowid');
    foreach ($rooms as $r) {
        $avatars->execute([(int) $r['id']]);
        $list = array_map(fn(array $m): array => ['perso' => (string) $m['perso'], 'color' => (int) $m['color'],
            'is_admin' => (int) $m['is_admin'] === 1], $avatars->fetchAll());
        $out[] = [
            'room_id' => (int) $r['id'], 'name' => (string) $r['name'], 'map' => (string) $r['map'],
            'places' => (int) $r['places'], 'humans' => count($list), 'full' => count($list) >= (int) $r['places'],
            'state' => (string) $r['state'], 'round' => (int) $r['round_current'], 'total' => (int) $r['round_total'],
            'avatars' => $list,
        ];
    }
    // Salons avec de la place d'abord (les pleins sont grisés en bas).
    usort($out, fn(array $a, array $b): int => (int) $a['full'] <=> (int) $b['full']);
    ok(['rooms' => $out]);
}

/**
 * POST /room/join : par room_id (salon public) ou par code (salon privé).
 * Refus si plein ou exclu. Arrivée en cours de partie → spectateur.
 * Idempotent : un membre déjà présent (reconnexion < 60 s) garde sa place.
 */
function handleRoomJoin(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomjoin:' . clientIp(), 60);
    rateLimit($pdo, 'roomjoin:p' . $me['id'], 20);
    $pid = (int) $me['id'];
    gkMaintain($pdo);
    $code = strtoupper(trim((string) ($body['code'] ?? '')));
    if ($code !== '') {
        if (!preg_match('/^[' . GK_CODE_ALPHABET . ']{' . GK_CODE_LENGTH . '}$/', $code)) {
            fail(400, 'Code invalide (4 lettres)', 'bad_code');
        }
        $stmt = $pdo->prepare("SELECT id FROM rooms WHERE code = ? AND state != 'ferme'");
        $stmt->execute([$code]);
    } else {
        $stmt = $pdo->prepare("SELECT id FROM rooms WHERE id = ? AND is_public = 1 AND state != 'ferme'");
        $stmt->execute([(int) ($body['room_id'] ?? 0)]);
    }
    $roomId = $stmt->fetchColumn();
    if ($roomId === false) {
        fail(404, $code !== '' ? 'Aucun salon avec ce code' : 'Ce salon n\'existe plus', 'not_found');
    }
    $roomId = (int) $roomId;
    gkBegin($pdo);
    $room = gkLoadRoom($pdo, $roomId);
    if (gkIsBanned($pdo, $roomId, $pid)) {
        fail(403, 'L\'admin a libéré ta place', 'banned');
    }
    $now = gkNow();
    $stmt = $pdo->prepare('SELECT 1 FROM room_members WHERE room_id = ? AND player_id = ?');
    $stmt->execute([$roomId, $pid]);
    if ($stmt->fetchColumn() !== false) {
        $pdo->prepare('UPDATE room_members SET last_seen = ? WHERE room_id = ? AND player_id = ?')->execute([$now, $roomId, $pid]);
        gkCommit($pdo);
        ok(gkRoomView($pdo, $roomId, $pid));
    }
    if (gkHumans($pdo, $roomId) >= (int) $room['places']) {
        fail(409, 'Salon plein', 'room_full');
    }
    gkLeaveOtherRooms($pdo, $pid, $roomId);
    $color = gkPickColor($pdo, $roomId, is_int($body['color'] ?? null) ? $body['color'] : 0);
    $status = $room['state'] === 'en_partie' ? 'spectateur' : 'joueur';
    $pdo->prepare(
        'INSERT INTO room_members (room_id, player_id, pseudo, perso, color, joined_at, is_admin, status, last_seen)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)'
    )->execute([$roomId, $pid, $me['pseudo'], gkPerso($body['perso'] ?? null), $color, $now, $status, $now]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, $roomId, $pid));
}

/** POST /room/presence : battement de cœur (toutes les 2 à 5 s) → état complet du salon. */
function handleRoomPresence(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roompresence:p' . $me['id'], 90);
    gkMaintain($pdo);
    gkRequireMember($pdo, $body, (int) $me['id']);
    ok(gkRoomView($pdo, (int) $body['room_id'], (int) $me['id']));
}

/** POST /room/me : changer son perso et/ou sa couleur (unique dans le salon). */
function handleRoomMe(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireMember($pdo, $body, (int) $me['id']);
    if (!gkCanEditBetweenRounds($room)) {
        fail(409, 'Pas pendant un round', 'in_round');
    }
    if (array_key_exists('perso', $body)) {
        if (!is_string($body['perso']) || !in_array($body['perso'], GK_CHARACTERS, true)) {
            fail(400, 'Personnage inconnu', 'bad_perso');
        }
        $pdo->prepare('UPDATE room_members SET perso = ? WHERE room_id = ? AND player_id = ?')
            ->execute([$body['perso'], $room['id'], $me['id']]);
    }
    if (array_key_exists('color', $body)) {
        if (!gkIntIn($body['color'], 0, GK_COLOR_COUNT - 1)) {
            fail(400, 'Couleur inconnue', 'bad_color');
        }
        $stmt = $pdo->prepare('SELECT 1 FROM room_members WHERE room_id = ? AND color = ? AND player_id != ?');
        $stmt->execute([$room['id'], $body['color'], $me['id']]);
        if ($stmt->fetchColumn() !== false) {
            fail(409, 'Cette couleur est déjà prise', 'color_taken');
        }
        $pdo->prepare('UPDATE room_members SET color = ? WHERE room_id = ? AND player_id = ?')
            ->execute([$body['color'], $room['id'], $me['id']]);
    }
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/** POST /room/settings (admin) : places, carte, réglages libres. Avant le lancement ou pendant les scores. */
function handleRoomSettings(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireAdmin($pdo, $body, (int) $me['id']);
    if (!gkCanEditBetweenRounds($room)) {
        fail(409, 'Les réglages se changent avant le lancement ou entre deux rounds', 'in_round');
    }
    $places = (int) $room['places'];
    if (array_key_exists('places', $body)) {
        if (!gkIntIn($body['places'], GK_PLACES_MIN, GK_PLACES_MAX)) {
            fail(400, 'Places : de 4 à 8', 'bad_places');
        }
        if ($body['places'] < gkHumans($pdo, (int) $room['id'])) {
            fail(409, 'Il y a déjà plus de joueurs que ça', 'bad_places');
        }
        $places = $body['places'];
    }
    $map = (string) $room['map'];
    if (array_key_exists('map', $body)) {
        if (!is_string($body['map']) || !in_array($body['map'], GK_MAPS, true)) {
            fail(400, 'Carte inconnue', 'bad_map');
        }
        $map = $body['map'];
    }
    $settings = array_key_exists('settings', $body)
        ? gkSettingsJson($body['settings'], GK_MAX_SETTINGS_BYTES) : (string) $room['settings_json'];
    $pdo->prepare('UPDATE rooms SET places = ?, map = ?, settings_json = ?, settings_version = settings_version + 1 WHERE id = ?')
        ->execute([$places, $map, $settings, $room['id']]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/** POST /room/launch (admin) : au moins 2 humains ; l'hôte complète avec des IA. */
function handleRoomLaunch(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireAdmin($pdo, $body, (int) $me['id']);
    if ($room['state'] !== 'attente') {
        fail(409, 'La partie est déjà lancée', 'already_playing');
    }
    if (gkHumans($pdo, (int) $room['id']) < GK_LAUNCH_MIN_HUMANS) {
        fail(409, 'Il faut au moins 2 joueurs', 'too_few');
    }
    $total = $body['total'] ?? 0;
    if (!gkIntIn($total, 0, GK_ROUNDS_MAX)) {
        fail(400, 'Nombre de rounds invalide', 'bad_round');
    }
    $pdo->prepare(
        "UPDATE rooms SET state = 'en_partie', phase = 'round', round_current = 0, round_total = ?,
           game_json = '{}', last_game_at = ? WHERE id = ?"
    )->execute([$total, gkNow(), $room['id']]);
    $pdo->prepare("UPDATE room_members SET status = 'joueur' WHERE room_id = ?")->execute([$room['id']]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/**
 * POST /room/round (hôte = admin) : publie round k/N et la phase (round | scores),
 * plus un état de partie facultatif (scores…) repris par un nouvel hôte.
 * Un nouveau round fait passer les spectateurs en joueurs (ils remplacent une IA).
 */
function handleRoomRound(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireAdmin($pdo, $body, (int) $me['id']);
    if ($room['state'] !== 'en_partie') {
        fail(409, 'Aucune partie en cours', 'not_playing');
    }
    $round = $body['round'] ?? null;
    $total = $body['total'] ?? (int) $room['round_total'];
    $phase = $body['phase'] ?? null;
    if (!gkIntIn($round, 0, GK_ROUNDS_MAX) || !gkIntIn($total, 0, GK_ROUNDS_MAX) || !in_array($phase, ['round', 'scores'], true)) {
        fail(400, 'État de round invalide', 'bad_round');
    }
    $game = array_key_exists('game', $body)
        ? gkSettingsJson($body['game'], GK_MAX_GAME_BYTES) : (string) $room['game_json'];
    if ($phase === 'round' && $round > (int) $room['round_current']) {
        $pdo->prepare("UPDATE room_members SET status = 'joueur' WHERE room_id = ? AND status = 'spectateur'")
            ->execute([$room['id']]);
    }
    $pdo->prepare('UPDATE rooms SET round_current = ?, round_total = ?, phase = ?, game_json = ?, last_game_at = ? WHERE id = ?')
        ->execute([$round, $total, $phase, $game, gkNow(), $room['id']]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/** POST /room/end (admin) : fin de partie (podium) ou arrêt anticipé → retour au salon. */
function handleRoomEnd(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireAdmin($pdo, $body, (int) $me['id']);
    $pdo->prepare("UPDATE rooms SET state = 'attente', phase = '', round_current = 0, last_game_at = ? WHERE id = ?")
        ->execute([gkNow(), $room['id']]);
    $pdo->prepare("UPDATE room_members SET status = 'joueur' WHERE room_id = ?")->execute([$room['id']]);
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/** POST /room/kick (admin) : exclut un joueur, qui ne peut plus revenir dans ce salon. */
function handleRoomKick(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkMaintain($pdo);
    gkBegin($pdo);
    [$room] = gkRequireAdmin($pdo, $body, (int) $me['id']);
    $target = $body['target'] ?? 0;
    if (!is_int($target) || $target === (int) $me['id']) {
        fail(400, 'Joueur invalide', 'bad_target');
    }
    $pdo->prepare('INSERT OR IGNORE INTO room_bans (room_id, player_id, created_at) VALUES (?, ?, ?)')
        ->execute([$room['id'], $target, gkNow()]);
    gkRemoveMember($pdo, (int) $room['id'], $target);
    gkCommit($pdo);
    ok(gkRoomView($pdo, (int) $room['id'], (int) $me['id']));
}

/** POST /room/leave : quitter (passation d'admin, fermeture s'il ne reste personne). */
function handleRoomLeave(PDO $pdo): void
{
    $body = jsonBody();
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomact:p' . $me['id'], 60);
    gkBegin($pdo);
    gkRemoveMember($pdo, (int) ($body['room_id'] ?? 0), (int) $me['id']);
    gkCommit($pdo);
    ok(['ok' => true]);
}

// ------------------------------------------------------------------ signalisation en étoile

/** POST /room/signal : message WebRTC vers un membre ; l'un des deux bouts doit être l'hôte (admin). */
function handleRoomSignalPost(PDO $pdo): void
{
    $raw = file_get_contents('php://input') ?: '';
    if (strlen($raw) > Validation::MAX_SIGNAL_BYTES + 512) {
        fail(413, 'Message trop gros', 'too_big');
    }
    $body = json_decode($raw, true);
    $body = is_array($body) ? $body : [];
    $me = gkAuth($pdo, $body);
    rateLimit($pdo, 'roomsignal:p' . $me['id'], 600);
    rateLimit($pdo, 'roomsignal:' . clientIp(), 3000);
    [$room, $member] = gkRequireMember($pdo, $body, (int) $me['id']);
    $payload = $body['payload'] ?? null;
    if (!is_array($payload) || !in_array($payload['kind'] ?? '', ['offer', 'answer', 'ice', 'hello', 'bye'], true)) {
        fail(400, 'Message de signalisation invalide', 'bad_signal');
    }
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE) ?: '{}';
    if (strlen($json) > Validation::MAX_SIGNAL_BYTES) {
        fail(413, 'Message trop gros', 'too_big');
    }
    $to = $body['to'] ?? 0;
    $stmt = $pdo->prepare('SELECT is_admin FROM room_members WHERE room_id = ? AND player_id = ?');
    $stmt->execute([$room['id'], $to]);
    $toAdmin = $stmt->fetchColumn();
    if (!is_int($to) || $to === (int) $me['id'] || $toAdmin === false) {
        fail(404, 'Destinataire absent du salon', 'bad_target');
    }
    if ((int) $member['is_admin'] !== 1 && (int) $toAdmin !== 1) {
        fail(403, 'Les messages passent par l\'hôte', 'not_host');
    }
    $pdo->prepare('INSERT INTO room_signals (room_id, from_player, to_player, payload, created_at) VALUES (?, ?, ?, ?, ?)')
        ->execute([$room['id'], $me['id'], $to, $json, gkNow()]);
    ok(['id' => (int) $pdo->lastInsertId()]);
}

/** GET /room/signal?room_id&after : messages reçus dans ce salon, après l'id donné. */
function handleRoomSignalGet(PDO $pdo): void
{
    $me = gkAuth($pdo, $_GET);
    rateLimit($pdo, 'roomsignal:p' . $me['id'], 600);
    [$room] = gkRequireMember($pdo, $_GET, (int) $me['id']);
    $stmt = $pdo->prepare(
        'SELECT id, from_player, payload FROM room_signals WHERE to_player = ? AND room_id = ? AND id > ? ORDER BY id LIMIT 100'
    );
    $stmt->execute([$me['id'], $room['id'], (int) ($_GET['after'] ?? 0)]);
    $out = [];
    foreach ($stmt->fetchAll() as $row) {
        $out[] = ['id' => (int) $row['id'], 'from' => (int) $row['from_player'],
            'payload' => json_decode((string) $row['payload'], true)];
    }
    ok(['messages' => $out]);
}
