<?php
declare(strict_types=1);

/**
 * Validation côté serveur : pseudos, codes, épreuves, plausibilité des
 * scores. Les plafonds sont le miroir serveur de src/shared/config/balance.gd
 * — garder les deux en phase.
 */
final class Validation
{
    /** Épreuves connues (mêmes identifiants que challenges.gd). */
    public const CHALLENGES = [
        'beach_run', 'surf', 'fishing', 'rock_crossing', 'espadrille', 'lighthouse',
    ];

    /** Les 5 épreuves cœur (le cumul = somme de leurs best). */
    public const CORE = [
        'beach_run', 'surf', 'fishing', 'rock_crossing', 'espadrille',
    ];

    /** Plafond de plausibilité par épreuve (miroir de balance.gd). */
    public const MAX_SCORE = [
        'beach_run' => 100000,
        'surf' => 100000,
        'fishing' => 100000,
        'rock_crossing' => 100000,
        'espadrille' => 100000,
        'lighthouse' => 100000,
    ];

    public static function isValidPseudo(string $pseudo): bool
    {
        return (bool) preg_match('/^[\p{L}\p{N}_-]{2,15}$/u', $pseudo);
    }

    public static function isValidGroupCode(string $code): bool
    {
        return (bool) preg_match('/^[A-Z2-9]{4,8}$/', $code);
    }

    public static function isValidChallenge(string $challenge): bool
    {
        return in_array($challenge, self::CHALLENGES, true);
    }

    /** Score plausible : entier, positif, sous le plafond de l'épreuve. */
    public static function isPlausibleScore(string $challenge, mixed $score): bool
    {
        if (!is_int($score) || $score < 0) {
            return false;
        }
        return $score <= (self::MAX_SCORE[$challenge] ?? 0);
    }
}
