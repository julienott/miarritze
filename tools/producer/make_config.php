<?php
declare(strict_types=1);

/**
 * Génère producer/config.php depuis l'environnement (étape de déploiement).
 *
 *   PRODUCER_PASSWORD=… PRODUCER_TOKEN=… php make_config.php <chemin/config.php>
 *
 * N'écrit que des hachages (password_hash pour le mot de passe, sha256 pour le
 * jeton, aléatoire et long). N'affiche jamais les secrets.
 * PRODUCER_INSECURE_COOKIE=1 : cookie sans « Secure » (test local en http).
 * PRODUCER_DATA_DIR : dossier de données (défaut : data/ à côté de config.php).
 * PRODUCER_TAILSCALE=1 : service local derrière `tailscale serve` ; écrit 'tailscale_auth' => true
 *   (connexion sans mot de passe par l'en-tête Tailscale-User-Login) ; PRODUCER_PASSWORD devient
 *   facultatif (sans lui, pas de password_hash : la connexion par mot de passe est fermée).
 */

if ($argc !== 2) {
    fwrite(STDERR, "usage : make_config.php <chemin/config.php>\n");
    exit(2);
}
$password = (string) getenv('PRODUCER_PASSWORD');
$token = (string) getenv('PRODUCER_TOKEN');
$tailscale = getenv('PRODUCER_TAILSCALE') === '1';
if (($password === '' && !$tailscale) || strlen($token) < 24) {
    fwrite(STDERR, "PRODUCER_PASSWORD vide (sans PRODUCER_TAILSCALE=1) ou PRODUCER_TOKEN absent/trop court (24 caractères min.)\n");
    exit(1);
}
$dataDir = (string) getenv('PRODUCER_DATA_DIR');
$config = [];
if ($password !== '') {
    $config['password_hash'] = password_hash($password, PASSWORD_DEFAULT);
}
$config['token_sha256'] = hash('sha256', $token);
$config['cookie_secure'] = getenv('PRODUCER_INSECURE_COOKIE') !== '1';
if ($tailscale) {
    $config['tailscale_auth'] = true;
}
$dataLine = $dataDir !== ''
    ? "    'data_dir' => " . var_export($dataDir, true) . ",\n"
    : "    'data_dir' => __DIR__ . '/data',\n";
$php = "<?php\n// Généré au déploiement par tools/producer/make_config.php — ne pas versionner.\nreturn [\n";
foreach ($config as $k => $v) {
    $php .= '    ' . var_export($k, true) . ' => ' . var_export($v, true) . ",\n";
}
$php .= $dataLine . "];\n";
if (file_put_contents($argv[1], $php) === false) {
    fwrite(STDERR, "écriture impossible\n");
    exit(1);
}
echo "config producer écrite\n";
