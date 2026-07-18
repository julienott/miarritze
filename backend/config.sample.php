<?php
declare(strict_types=1);

/**
 * Copier vers config.php (gitignoré) pour surcharger les défauts.
 * Sans config.php, l'API fonctionne avec ces valeurs par défaut.
 */
return [
    // Chemin du fichier SQLite (créé automatiquement au premier appel).
    'db_path' => __DIR__ . '/db/miarritze.sqlite',

    // Origine autorisée en CORS. Vide = aucune (le jeu est sur la même
    // origine en prod). À renseigner uniquement pour le dev depuis
    // l'éditeur Godot, ex. 'http://localhost:8080'. Jamais '*' en prod.
    'allowed_origin' => '',
];
