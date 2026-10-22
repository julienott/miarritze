<?php
declare(strict_types=1);

/**
 * Validation côté serveur : pseudos (miroir de Profiles.pseudo_ok côté jeu) et taille des messages
 * de signalisation des salons.
 */
final class Validation
{
    public const MAX_SIGNAL_BYTES = 16384;

    public static function isValidPseudo(string $pseudo): bool
    {
        return (bool) preg_match('/^[\p{L}\p{N}_-]{2,15}$/u', $pseudo);
    }
}
