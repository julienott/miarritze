<?php
declare(strict_types=1);

/**
 * Routeur du service local (php -S, voir studio_installe.sh ; GDD §14.2, docs/PRODUCER.md) :
 *   /producer/…  le board (index.php ; statiques servis tels quels ; data/, lib/ et config.php refusés)
 *   /jeu/…       le jeu de QA (export web), avec COOP/COEP comme en prod (web/.htaccess)
 *   /            renvoie vers le board
 * Racine : .studio/site. Joignable de l'extérieur seulement par tailscale serve (proxy vers 127.0.0.1).
 */

$racine = realpath(__DIR__ . '/../../.studio/site');
$chemin = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));

if ($chemin === '/' || $chemin === '') {
    header('Location: /producer/');
    return true;
}
if ($chemin === '/jeu') {
    header('Location: /jeu/');
    return true;
}

if (str_starts_with($chemin, '/producer/')) {
    $rel = substr($chemin, strlen('/producer/'));
    if (preg_match('#^(data|lib|files)(/|$)|^config\.php$|\.\.#', $rel)) {
        http_response_code(403);
        return true;
    }
    if ($rel === '' || $rel === 'index.php') {
        chdir($racine . '/producer');
        $_SERVER['SCRIPT_NAME'] = '/producer/index.php';
        require $racine . '/producer/index.php';
        return true;
    }
    return false;          // statiques (static/…) servis par php -S
}

if (str_starts_with($chemin, '/jeu/')) {
    $rel = substr($chemin, strlen('/jeu/'));
    $fichier = realpath($racine . '/jeu/' . ($rel === '' ? 'index.html' : $rel));
    if ($fichier === false || !str_starts_with($fichier, $racine . '/jeu/') || !is_file($fichier)) {
        http_response_code(404);
        echo "Pas encore de build de QA.\n";
        return true;
    }
    $types = ['html' => 'text/html; charset=utf-8', 'js' => 'application/javascript', 'wasm' => 'application/wasm',
        'pck' => 'application/octet-stream', 'png' => 'image/png', 'svg' => 'image/svg+xml', 'json' => 'application/json',
        'ico' => 'image/x-icon', 'webmanifest' => 'application/manifest+json'];
    $ext = strtolower(pathinfo($fichier, PATHINFO_EXTENSION));
    header('Content-Type: ' . ($types[$ext] ?? 'application/octet-stream'));
    header('Cross-Origin-Opener-Policy: same-origin');
    header('Cross-Origin-Embedder-Policy: require-corp');
    header('Cross-Origin-Resource-Policy: same-origin');
    header('Cache-Control: no-cache');
    header('Content-Length: ' . filesize($fichier));
    readfile($fichier);
    return true;
}

http_response_code(404);
return true;
