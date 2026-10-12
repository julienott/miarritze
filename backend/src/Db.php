<?php
declare(strict_types=1);

/**
 * Accès SQLite : PDO unique, WAL, schéma appliqué au premier appel.
 * Requêtes préparées partout — jamais de concaténation SQL.
 */
final class Db
{
    private static ?PDO $pdo = null;

    public static function get(array $config): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }
        // MIARRITZE_DB : base jetable pour les tests (php -S local).
        $path = getenv('MIARRITZE_DB') ?: ($config['db_path'] ?? __DIR__ . '/../db/miarritze.sqlite');
        $dir = dirname($path);
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        $pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        $pdo->exec('PRAGMA busy_timeout = 3000');
        $schema = file_get_contents(__DIR__ . '/../db/schema.sql');
        if ($schema !== false) {
            $pdo->exec($schema);
        }
        // Migrations additives (colonnes ajoutées après la création de la table).
        try {
            $pdo->exec('ALTER TABLE matches ADD COLUMN rematch_of INTEGER');
        } catch (PDOException $e) {
            // colonne déjà présente
        }
        self::$pdo = $pdo;
        return $pdo;
    }
}
