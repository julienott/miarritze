<?php
declare(strict_types=1);

/**
 * Validation côté serveur (SPEC-BORROKA §9.4–9.5) : pseudos, codes, roster,
 * stages, cartes de joueur, plausibilité des scores de pyramide.
 * Miroir de src/fight/data/roster.gd et src/autoload/profiles.gd.
 */
final class Validation
{
    public const FIGHTERS = [
        'louis', 'maia', 'patxi', 'xabi', 'mattin', 'amaia', 'txomin', 'kaio',
        'karramarro', 'ramuntxo', 'itsaso', 'peio', 'itsasargi',
    ];
    public const STAGES = [
        'grande_plage', 'cote_basques', 'port_pecheurs', 'rocher_vierge', 'port_vieux',
        'halles', 'fronton', 'stade', 'aquarium', 'phare_sommet',
    ];
    public const DIFFICULTIES = ['facile', 'normal', 'expert'];
    public const TITLES = ['', 'debutant', 'txapeldun', 'expert', 'cote_basques', 'fronton', 'finisher', 'parfait', 'collection'];
    /** 9 étages × (victoire + vie + temps) ×2 (Parfait) + finish : ≈ 45 000. */
    public const MAX_TOWER_SCORE = 60000;
    public const MAX_STATS_BYTES = 4096;
    public const MAX_SIGNAL_BYTES = 16384;

    public static function isValidPseudo(string $pseudo): bool
    {
        return (bool) preg_match('/^[\p{L}\p{N}_-]{2,15}$/u', $pseudo);
    }

    public static function isValidGroupCode(string $code): bool
    {
        return (bool) preg_match('/^[A-Z2-9]{4,8}$/', $code);
    }

    public static function isFighter(string $id): bool
    {
        return in_array($id, self::FIGHTERS, true);
    }

    public static function isStage(string $id): bool
    {
        return in_array($id, self::STAGES, true);
    }

    public static function isPlausibleTowerScore(mixed $score): bool
    {
        return is_int($score) && $score >= 0 && $score <= self::MAX_TOWER_SCORE;
    }

    /**
     * Costume débloqué de façon plausible d'après les stats déclarées (§5.4) :
     * 2 → 5 victoires avec le perso, 3 → une pyramide, 4 → la pyramide en Expert.
     */
    public static function isPlausibleCostume(string $fighter, int $costume, array $stats): bool
    {
        if ($costume === 0) {
            return true;
        }
        if ($costume < 0 || $costume > 3) {
            return false;
        }
        $wins = (int) (($stats['wins_by'] ?? [])[$fighter] ?? 0);
        $towers = (int) (($stats['towers'] ?? [])[$fighter] ?? 0);
        $expert = !empty(($stats['txapelas'] ?? [])[$fighter . '_expert']);
        return match ($costume) {
            1 => $wins >= 5 || $towers > 0,
            2 => $towers > 0,
            3 => $expert,
            default => false,
        };
    }
}
