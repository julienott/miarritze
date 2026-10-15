<?php
declare(strict_types=1);

/**
 * Modèle de producer/config.php (JAMAIS versionné).
 *
 * En prod, config.php est généré au déploiement par
 * tools/producer/make_config.php depuis les secrets GitHub PRODUCER_PASSWORD
 * et PRODUCER_TOKEN : seuls leurs hachages sont écrits. Sans config.php,
 * toute connexion est refusée.
 */
return [
    // password_hash() du mot de passe de Julien.
    'password_hash' => '',
    // sha256 (hex) du jeton de l'agent (Authorization: Bearer <jeton>).
    'token_sha256' => '',
    // Cookie de session « Secure » (false seulement pour un test local en http).
    'cookie_secure' => true,
    // Dossier des données (SQLite + sessions), jamais écrasé au déploiement.
    'data_dir' => __DIR__ . '/data',
];
